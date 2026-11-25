"""Synthetische Pruefstandsdaten eines temperaturfeldbasierten sensorintegrierenden
Gleitlagers (SiPB).

Sensoranordnung wie im IMSE-Prototyp (Baszenski et al. 2025):
24 Temperatursensoren von 97,5 deg bis 270 deg (Lastzone), 1,5 mm unter der
Laufflaeche, Oelzufuhr bei 0 deg.

Das thermische Modell ist ein grobes Ersatzmodell mit drei Zeitkonstanten:
- lokaler Hotspot nahe der Laufflaeche (Sekunden)
- Temperaturanstieg entlang des Umfangs (Minute)
- Lagerkoerper/Gehaeuse (20 min)
Es soll die *qualitativen* Effekte aus dem Paper abbilden, nicht die echten
Messdaten ersetzen.
"""
from dataclasses import dataclass, field

import numpy as np

from .physics import Bearing, operating_point

PHI = np.linspace(97.5, 270.0, 24)   # Sensorwinkel [deg]
PHI_LOAD = 180.0                      # Lastrichtung [deg]
HOTSPOT_OFFSET = 8.0                  # Hotspot liegt etwas hinter h_min [deg]

# Thermische Ersatzparameter
TAU_PEAK = 4.0       # s
TAU_RAMP = 60.0      # s
TAU_BULK = 1200.0    # s
TAU_SENSOR = 0.43    # s  (0,0051 J/K * 85 K/W aus dem Paper)
K_PEAK = 0.10        # K / W^0.7
K_RAMP = 0.033       # K / W^0.7
K_UNIFORM = 0.02     # K / W  (gleichmaessige Erwaermung, z.B. Verschleiss)
R_BULK = 0.03        # K / W
W_UP, W_DOWN = 40.0, 22.0  # Breite des Hotspots vor/nach dem Maximum [deg]

NOISE_STD = 0.03     # K
QUANT = 0.03125      # K  (Aufloesung LM73)
T_SEIZURE = 180.0    # K  ab hier: Fresser, Simulation endet


@dataclass
class Scenario:
    name: str
    T_oil: float = 60.0            # Oeleintrittstemperatur [degC]
    operation: str = "stationaer"  # "stationaer" | "start_stopp"
    fault: str = "keiner"          # "keiner" | "mangel" | "abrasiv" | "ueberlast" | "sensor"
    t0: float = np.inf             # Fehlerbeginn [s]
    duration: float = 2400.0       # [s]
    faulty_sensor: int = 14
    seed: int = 0
    v_nom: float = 2.5             # Gleitgeschwindigkeit im stationaeren Betrieb [m/s]
    p_nom: float = 10e6            # spez. Lagerlast im stationaeren Betrieb [Pa]
    bearing: Bearing = field(default_factory=Bearing)


# ---------------------------------------------------------------- Betrieb
def nominal_operation(sc: Scenario, t: float):
    """Drehzahl/Last-Profil ohne Fehler -> (v [m/s], p [Pa])."""
    if sc.operation == "stationaer":
        v = sc.v_nom
    elif sc.operation == "start_stopp":
        # 99-s-Zyklus wie im Paper: hochfahren, halten, runterfahren, Stillstand
        tc = t % 99.0
        if tc < 20:
            v = 2.5 * tc / 20
        elif tc < 69:
            v = 2.5
        elif tc < 89:
            v = 2.5 * (89 - tc) / 20
        else:
            v = 0.0
    else:
        raise ValueError(sc.operation)
    p = (0.5 + 9.5 * v / 2.5) * 1e6 if sc.operation == "start_stopp" else sc.p_nom
    return v, p


def fault_state(sc: Scenario, t: float):
    """Fehlereinfluss zum Zeitpunkt t."""
    st = {"starvation": 0.0, "mu_add": 0.0, "psi_factor": 1.0, "v_factor": 1.0, "p_factor": 1.0}
    if t < sc.t0:
        return st
    dt = t - sc.t0
    if sc.fault == "mangel":
        # Oelversorgung bricht innerhalb von 4 min auf 5 % ein (z.B. Filter setzt sich zu)
        st["starvation"] = 0.95 * min(dt / 240.0, 1.0)
    elif sc.fault == "abrasiv":
        # Partikel im Oel: Reibung waechst langsam, Spiel vergroessert sich
        st["mu_add"] = 1.2e-6 * dt
        st["psi_factor"] = 1.0 + 0.03 * dt / 1800.0
    elif sc.fault == "ueberlast":
        # Drehzahl sinkt auf 16 %, Last steigt um 20 % -> Mischreibung
        r = min(dt / 60.0, 1.0)
        st["v_factor"] = 1.0 - 0.84 * r
        st["p_factor"] = 1.0 + 0.2 * r
    return st


# ---------------------------------------------------------------- Temperaturfeld
def peak_shape(phi_hot, sharpen=0.0):
    w_up = W_UP * (1 - 0.4 * sharpen)
    w_down = W_DOWN * (1 - 0.4 * sharpen)
    w = np.where(PHI < phi_hot, w_up, w_down)
    return np.exp(-0.5 * ((PHI - phi_hot) / w) ** 2)


def ramp_shape(phi_hot):
    return np.clip((PHI - PHI[0]) / max(phi_hot - PHI[0], 1.0), 0.0, 1.0)


def simulate(sc: Scenario, dt: float = 0.1, warmup: float = 4000.0):
    """Simuliert ein Szenario. Rueckgabe: dict mit Zeitreihen.

    Messwerte:  t [s], T [N x 24] in degC (mit Offset, Rauschen, Quantisierung)
    Wahrheit:   v, p, T_oil, eps, h_min, mu, M_friction, mixed_frac, T_true_max
    """
    rng = np.random.default_rng(sc.seed)
    b = sc.bearing
    offsets = rng.normal(0.0, 0.15, size=24)  # Kalibrierfehler je Sensor

    # Zustand
    T_bulk = sc.T_oil + 8.0
    T_peak = np.zeros(24)
    T_ramp = np.zeros(24)
    T_sens = None

    def step(t, h, record_fault):
        nonlocal T_bulk, T_peak, T_ramp
        v, p = nominal_operation(sc, t)
        fs = fault_state(sc, t) if record_fault else fault_state(Scenario("x"), t)
        v *= fs["v_factor"]
        p *= fs["p_factor"]
        s = fs["starvation"]
        T_true_prev = T_bulk + T_peak + T_ramp
        T_eff = 0.5 * (sc.T_oil + T_true_prev.max())
        op = operating_point(b, v, p, T_eff, starvation=s,
                             psi_factor=fs["psi_factor"])
        F = p * b.area
        mu_loc = op["mu_hydro"] + op["mu_mixed"]
        P_loc = mu_loc * F * v
        P_uni = fs["mu_add"] * F * v
        P_tot = P_loc + P_uni
        phi_hot = PHI_LOAD + op["beta_deg"] + HOTSPOT_OFFSET
        sharpen = max(s, op["mixed_frac"])

        # weniger Oel -> weniger Waermeabfuhr, lokal und im Lagerkoerper
        target_peak = K_PEAK * (1 + 2 * s) * P_loc**0.7 * peak_shape(phi_hot, sharpen)
        target_ramp = K_RAMP * P_tot**0.7 * ramp_shape(phi_hot) + K_UNIFORM * P_uni
        R_b = R_BULK * (1 + 4 * s)
        T_peak = T_peak + h / TAU_PEAK * (target_peak - T_peak)
        T_ramp = T_ramp + h / TAU_RAMP * (target_ramp - T_ramp)
        T_bulk = T_bulk + h / TAU_BULK * (sc.T_oil + R_b * P_tot - T_bulk)
        return v, p, op, mu_loc + fs["mu_add"], F

    # Einlaufen ins thermische Gleichgewicht (ohne Fehler, nicht aufgezeichnet)
    hw = 0.5
    for k in range(int(warmup / hw)):
        step(-warmup + k * hw, hw, record_fault=False)

    n = int(round(sc.duration / dt))
    out = {k: np.full(n, np.nan) for k in
           ("v", "p", "eps", "h_min", "mu", "M_friction", "mixed_frac", "T_true_max", "phi_hot_true")}
    T_meas = np.full((n, 24), np.nan)
    t_arr = np.arange(n) * dt
    seizure_t = np.inf
    for k in range(n):
        t = t_arr[k]
        v, p, op, mu, F = step(t, dt, record_fault=True)
        T_true = T_bulk + T_peak + T_ramp
        # Sensor: Offset + thermische Traegheit
        x = T_true + offsets
        T_sens = x if T_sens is None else T_sens + dt / TAU_SENSOR * (x - T_sens)
        y = T_sens + rng.normal(0.0, NOISE_STD, 24)
        if sc.fault == "sensor" and t >= sc.t0:
            # Waermeleitpaste geloest / Wackelkontakt: Sprung + starkes Rauschen
            y[sc.faulty_sensor] += -4.0 + rng.normal(0.0, 4 * NOISE_STD)
        T_meas[k] = np.round(y / QUANT) * QUANT
        out["v"][k], out["p"][k] = v, p
        out["eps"][k], out["h_min"][k] = op["eps"], op["h_min"]
        out["mu"][k], out["M_friction"][k] = mu, mu * F * b.R
        out["mixed_frac"][k] = op["mixed_frac"]
        out["T_true_max"][k] = T_true.max()
        out["phi_hot_true"][k] = PHI_LOAD + op["beta_deg"] + HOTSPOT_OFFSET
        if T_true.max() > T_SEIZURE:
            seizure_t = t
            n = k + 1
            break

    res = {key: val[:n] for key, val in out.items()}
    res.update(t=t_arr[:n], T=T_meas[:n], offsets=offsets, seizure_t=seizure_t,
               scenario=sc, dt=dt)
    return res


def calibration_soak(seed: int, T_level: float = 40.0, n: int = 300):
    """Isotherme Kalibriermessung (Lager steht, Oel umgewaelzt): liefert
    Messwerte, aus denen sich die Sensor-Offsets schaetzen lassen."""
    rng = np.random.default_rng(seed)
    offsets = rng.normal(0.0, 0.15, size=24)  # gleiche Offsets wie in simulate()
    y = T_level + offsets + rng.normal(0.0, NOISE_STD, (n, 24))
    return np.round(y / QUANT) * QUANT
