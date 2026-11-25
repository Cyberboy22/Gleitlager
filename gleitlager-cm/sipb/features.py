"""Merkmalsextraktion aus dem Temperaturfeld.

Alle Merkmale nutzen nur die Lagertemperaturen, also genau das, was das
energieautarke Sensorsystem selbst kennt (keine Drehzahl, keine Last).
Die Rechenschritte sind so gewaehlt, dass sie auch auf einem
Mikrocontroller laufen koennen (siehe c/sipb_features.c).
"""
import numpy as np

from .physics import Bearing


# ------------------------------------------------------------------ Vorverarbeitung
def estimate_offsets(soak: np.ndarray) -> np.ndarray:
    """Sensor-Offsets aus einer isothermen Kalibriermessung (n x S)."""
    m = soak.mean(axis=0)
    return m - np.median(m)


def sample_indices(res: dict, fs: float) -> np.ndarray:
    """Indizes der Simulationsschritte, die ein Sensorsystem mit fs [Hz] sieht."""
    Ts = 1.0 / fs
    tk = np.arange(0.0, res["t"][-1] + 1e-9, Ts)
    idx = np.round(tk / res["dt"]).astype(int)
    return np.unique(idx[idx < len(res["t"])])


class PlausibilityCheck:
    """Erkennt defekte Sensoren: ein Sensor springt, seine Nachbarn nicht.

    Ein echtes thermisches Ereignis ist raeumlich glatt (Waermeleitung), d.h.
    benachbarte Sensoren bewegen sich in dieselbe Richtung. Springt ein Sensor
    allein, ist das ein Sensorfehler und kein Lagerschaden.
    """

    def __init__(self, n_sensors: int, jump: float = 1.5, ratio: float = 0.25):
        self.n = n_sensors
        self.jump = jump
        self.ratio = ratio
        self.prev = None
        self.bad = np.zeros(n_sensors, dtype=bool)

    def update(self, T: np.ndarray) -> np.ndarray:
        if self.prev is not None:
            d = T - self.prev
            # nur Sensoren pruefen, die ueberhaupt stark springen (selten)
            for i in np.flatnonzero(~self.bad & (np.abs(d) > self.jump)):
                nb = [j for j in (i - 2, i - 1, i + 1, i + 2)
                      if 0 <= j < self.n and not self.bad[j]]
                if nb and abs(np.median(d[nb])) < self.ratio * abs(d[i]):
                    self.bad[i] = True
        self.prev = T.copy()
        return self.bad.copy()


def repair(T: np.ndarray, bad: np.ndarray, phi: np.ndarray) -> np.ndarray:
    """Ersetzt defekte Sensoren durch lineare Interpolation der guten."""
    if not bad.any():
        return T
    good = ~bad
    out = T.copy()
    out[bad] = np.interp(phi[bad], phi[good], T[good])
    return out


# ------------------------------------------------------------------ Hotspot
def hotspot(T: np.ndarray, phi: np.ndarray):
    """Winkel und Temperatur des Maximums mit Parabel durch 3 Punkte.

    Rueckgabe: (phi_hot, T_hot, gueltig). Ungueltig, wenn das Maximum am Rand
    liegt (dann ist der Hotspot evtl. ausserhalb des Messbereichs).
    """
    i = int(np.argmax(T))
    if i == 0 or i == len(T) - 1:
        return float(phi[i]), float(T[i]), False
    y0, y1, y2 = T[i - 1], T[i], T[i + 1]
    denom = y0 - 2 * y1 + y2
    if denom >= 0:
        return float(phi[i]), float(y1), False
    delta = 0.5 * (y0 - y2) / denom
    spacing = phi[i + 1] - phi[i]
    return float(phi[i] + delta * spacing), float(y1 - 0.25 * (y0 - y2) * delta), True


# ------------------------------------------------------------------ Guembel
class GuembelMap:
    """Polynom 4. Ordnung: gemessener Hotspot-Winkel -> Exzentrizitaet.

    Entspricht Gl. (2) im Paper. Kalibriert wird mit quasistationaeren
    Laeufen, bei denen die Spalthoehe bekannt ist (am Pruefstand z.B. ueber
    Wegsensoren).

    Der Winkel wird vorher auf x = (phi - Mitte) / Halbbreite normiert. Ohne
    Normierung waere phi^4 ~ 1,6e9 und das Polynom in 32-bit float auf dem
    Mikrocontroller numerisch unbrauchbar.
    """

    def __init__(self, coeffs, phi_range):
        self.coeffs = np.asarray(coeffs)
        self.phi_range = phi_range
        self.center = 0.5 * (phi_range[0] + phi_range[1])
        self.scale = 0.5 * (phi_range[1] - phi_range[0])

    @classmethod
    def fit(cls, phi_meas, eps_true):
        rng = (float(np.min(phi_meas)), float(np.max(phi_meas)))
        tmp = cls(np.zeros(5), rng)
        coeffs = np.polyfit(tmp._norm(phi_meas), eps_true, 4)
        return cls(coeffs, rng)

    def _norm(self, phi):
        return (np.clip(phi, *self.phi_range) - self.center) / self.scale

    def eps(self, phi_hot):
        return np.clip(np.polyval(self.coeffs, self._norm(phi_hot)), 0.0, 0.999)

    def h_min(self, phi_hot, bearing: Bearing = Bearing()):
        return bearing.psi * bearing.R * (1 - self.eps(phi_hot))


# ------------------------------------------------------------------ Merkmale
def _lagged_rate(x: np.ndarray, Ts: float, window: float) -> np.ndarray:
    m = max(1, int(round(window / Ts)))
    r = np.full_like(x, np.nan)
    r[m:] = (x[m:] - x[:-m]) / (m * Ts)
    return r


def _rolling_slope(x: np.ndarray, Ts: float, window: float) -> np.ndarray:
    """Steigung einer Ausgleichsgeraden ueber das letzte Zeitfenster [K/s]."""
    n = max(3, int(round(window / Ts)))
    out = np.full_like(x, np.nan)
    if len(x) < n:
        return out
    t = np.arange(n) * Ts
    t = t - t.mean()
    w = t / np.sum(t**2)
    out[n - 1:] = np.convolve(x, w[::-1], mode="valid")
    return out


def extract(T: np.ndarray, Ts: float, phi: np.ndarray, gmap: GuembelMap = None,
            offsets: np.ndarray = None, rate_window: float = 10.0,
            drift_window: float = 600.0, use_plausibility: bool = True,
            min_prominence: float = 1.5) -> dict:
    """Berechnet alle Merkmale fuer eine Messreihe T (n x S), Abtastzeit Ts."""
    n, S = T.shape
    Tc = T - offsets if offsets is not None else T.copy()
    check = PlausibilityCheck(S)
    f = {k: np.full(n, np.nan) for k in
         ("Tmax", "Tmin", "Tmean", "Tmed", "dTglob", "prom", "phi_hot", "h_est")}
    f["hot_ok"] = np.zeros(n, dtype=bool)
    f["n_bad"] = np.zeros(n, dtype=int)
    f["bad_first"] = -1
    for k in range(n):
        x = Tc[k]
        if use_plausibility:
            bad = check.update(x)
            if bad.any() and f["bad_first"] < 0:
                f["bad_first"] = k
            f["n_bad"][k] = bad.sum()
            x = repair(x, bad, phi)
        f["Tmax"][k], f["Tmin"][k] = x.max(), x.min()
        f["Tmean"][k], f["Tmed"][k] = x.mean(), np.median(x)
        phi_hot, _, ok = hotspot(x, phi)
        f["phi_hot"][k], f["hot_ok"][k] = phi_hot, ok
    f["dTglob"] = f["Tmax"] - f["Tmin"]          # globaler Gradient (Paper)
    f["prom"] = f["Tmax"] - f["Tmed"]            # wie ausgepraegt ist der Hotspot?
    f["rate_max"] = _lagged_rate(f["Tmax"], Ts, rate_window)     # lokaler Gradient
    f["rate_mean"] = _lagged_rate(f["Tmean"], Ts, rate_window)
    f["drift"] = _rolling_slope(f["Tmean"], Ts, drift_window)    # langsame Erwaermung
    f["quasi_stat"] = np.abs(_lagged_rate(f["Tmean"], Ts, 60.0)) < 0.03
    if gmap is not None:
        f["h_est"] = gmap.h_min(f["phi_hot"])
    # Guembel nur, wenn der Hotspot deutlich ausgepraegt und der Zustand quasistationaer ist
    f["guembel_ok"] = f["hot_ok"] & (f["prom"] > min_prominence) & f["quasi_stat"]
    return f
