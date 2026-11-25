"""Versuchsplan, Schwellenkalibrierung und Auswertung der Erkennungskriterien."""
import hashlib
import os
import pickle
from concurrent.futures import ProcessPoolExecutor
from dataclasses import replace

import numpy as np

from .features import GuembelMap, estimate_offsets, extract, sample_indices
from .simulate import PHI, Scenario, calibration_soak, simulate

CACHE = os.path.join(os.path.dirname(__file__), "..", "results", "cache")
H_LIM = Scenario("x").bearing.h_lim


# ------------------------------------------------------------------ Simulation mit Cache
def _key(sc: Scenario, dt: float) -> str:
    return hashlib.md5(repr((sc, dt)).encode()).hexdigest()[:16]


def run(sc: Scenario, dt: float = 0.1) -> dict:
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, _key(sc, dt) + ".pkl")
    if os.path.exists(path):
        with open(path, "rb") as fh:
            return pickle.load(fh)
    res = simulate(sc, dt=dt)
    with open(path, "wb") as fh:
        pickle.dump(res, fh)
    return res


def run_many(scs, dt=0.1, workers=None):
    with ProcessPoolExecutor(max_workers=workers) as ex:
        return list(ex.map(run, scs, [dt] * len(scs)))


# ------------------------------------------------------------------ Versuchsplan
def healthy_scenarios(seeds):
    out = []
    for s in seeds:
        out += [Scenario("stationaer_60", 60.0, seed=s),
                Scenario("stationaer_20", 20.0, seed=s),
                Scenario("start_stopp_60", 60.0, "start_stopp", seed=s),
                Scenario("start_stopp_20", 20.0, "start_stopp", seed=s)]
    return out


def test_scenarios(seeds):
    out = []
    for s in seeds:
        rng = np.random.default_rng(1000 + s)
        t0 = float(rng.uniform(900, 1500))
        t0_ss = 99.0 * int(rng.integers(9, 15)) + 20.0 + float(rng.uniform(5, 40))  # in Haltephase
        t0_ab = float(rng.uniform(200, 500))
        out += [
            # gesunde Laeufe -> duerfen keinen Alarm ausloesen
            Scenario("stationaer_60", 60.0, seed=s),
            Scenario("stationaer_20", 20.0, seed=s),
            Scenario("start_stopp_60", 60.0, "start_stopp", seed=s),
            Scenario("start_stopp_20", 20.0, "start_stopp", seed=s),
            Scenario("lastwechsel_20", 20.0, fault="ueberlast", t0=t0, seed=s),  # bleibt unkritisch
            # Fehlerfaelle
            Scenario("mangel_60", 60.0, fault="mangel", t0=t0, seed=s),
            Scenario("mangel_20", 20.0, fault="mangel", t0=t0, seed=s),
            Scenario("start_stopp_mangel_60", 60.0, "start_stopp", fault="mangel", t0=t0_ss, seed=s),
            Scenario("abrasiv_60", 60.0, fault="abrasiv", t0=t0_ab, seed=s),
            Scenario("abrasiv_20", 20.0, fault="abrasiv", t0=t0_ab, seed=s),
            Scenario("ueberlast_60", 60.0, fault="ueberlast", t0=t0, seed=s),
            Scenario("sensorfehler_60", 60.0, fault="sensor", t0=t0, seed=s),
        ]
    return out


def guembel_calibration_scenarios():
    out, s = [], 500
    for T_oil in (20.0, 40.0, 60.0):
        for v in (0.4, 0.6, 1.0, 1.5, 2.0, 2.5):
            for p in (4e6, 7e6, 10e6, 12e6):
                out.append(Scenario(f"kal_{T_oil:.0f}_{v}_{p/1e6:.0f}", T_oil,
                                    duration=120.0, v_nom=v, p_nom=p, seed=s))
                s += 1
    return out


# ------------------------------------------------------------------ Guembel-Kalibrierung
def calibrate_guembel(results, sensors=None, fs=1.0):
    sensors = np.arange(24) if sensors is None else np.asarray(sensors)
    phi_m, eps_t, h_t = [], [], []
    for r in results:
        idx = sample_indices(r, fs)
        idx = idx[r["t"][idx] >= 60.0]
        off = estimate_offsets(calibration_soak(r["scenario"].seed))[sensors]
        f = extract(r["T"][idx][:, sensors], 1 / fs, PHI[sensors], None, off,
                    use_plausibility=False)
        ok = f["hot_ok"] & (f["prom"] > 0.5)
        if ok.sum() < 5:
            continue
        phi_m.append(np.mean(f["phi_hot"][ok]))
        eps_t.append(np.mean(r["eps"][idx][ok]))
        h_t.append(np.mean(r["h_min"][idx][ok]))
    phi_m, eps_t, h_t = map(np.array, (phi_m, eps_t, h_t))
    return GuembelMap.fit(phi_m, eps_t), phi_m, eps_t, h_t


# ------------------------------------------------------------------ Bewertung
def features_for(r, fs, gmap, sensors=None):
    sensors = np.arange(24) if sensors is None else np.asarray(sensors)
    idx = sample_indices(r, fs)
    off = estimate_offsets(calibration_soak(r["scenario"].seed))[sensors]
    f = extract(r["T"][idx][:, sensors], 1 / fs, PHI[sensors], gmap, off)
    f["t"] = r["t"][idx]
    f["idx"] = idx
    return f


def critical_time(r) -> float:
    """Wann wird es kritisch? Reibmoment +50 % gegenueber vor Fehlerbeginn
    oder Mischreibung (h_min < h_lim), jeweils nur bei v > 0,2 m/s.
    Das entspricht dem Vorschlag im Paper, Grenzwerte ueber das Reibmoment
    am Pruefstand festzulegen."""
    sc = r["scenario"]
    if not np.isfinite(sc.t0) or sc.fault in ("sensor",):
        return np.inf
    t, v, M, h = r["t"], r["v"], r["M_friction"], r["h_min"]
    moving = v > 0.2
    before = np.where((t < sc.t0) & moving)[0]
    M_ref = M[before[-1]]
    crit = moving & (t >= sc.t0) & ((M > 1.5 * M_ref) | (h < H_LIM))
    if sc.name.startswith("lastwechsel"):
        crit = moving & (t >= sc.t0) & (h < H_LIM)  # Lastwechsel allein ist kein Schaden
    if not crit.any():
        return r["seizure_t"]
    return float(t[np.argmax(crit)])


CRITERIA = ("K1_Tmax", "K2_dTglob", "K3_Rate", "K4_Guembel", "K5_Drift")


def criterion_masks(f, th):
    with np.errstate(invalid="ignore"):
        return {
            "K1_Tmax": f["Tmax"] > th["K1_Tmax"],
            "K2_dTglob": f["dTglob"] > th["K2_dTglob"],
            "K3_Rate": f["rate_max"] > th["K3_Rate"],
            "K4_Guembel": f["guembel_ok"] & (f["h_est"] < th["K4_Guembel"]),
            "K5_Drift": f["drift"] > th["K5_Drift"],
        }


def first_alarm(mask, t, Ts, persist=5.0, share=0.8):
    """Erster Zeitpunkt, an dem die Bedingung in >= 80 % der Messungen der
    letzten persist Sekunden erfuellt ist (bei 0,14 Hz: eine Messung).
    Ein einzelner verrauschter Messpunkt setzt die Zaehlung so nicht zurueck."""
    n_p = max(1, int(np.ceil(persist / Ts)))
    m = np.asarray(mask, dtype=float)
    hits = np.convolve(m, np.ones(n_p), mode="full")[:len(m)]
    ok = np.flatnonzero((hits >= share * n_p) & (np.arange(len(m)) >= n_p - 1) & (m > 0))
    if ok.size == 0:
        return np.inf, -1
    k = int(ok[0])
    return float(t[k]), k


def calibrate_thresholds(feature_list, h_warn=H_LIM + 1e-6):
    """Schwellen = hoechster Wert in gesunden Laeufen + Sicherheitsabstand."""
    cat = {k: np.concatenate([f[k] for f in feature_list]) for k in
           ("Tmax", "dTglob", "rate_max", "drift")}
    return {
        "K1_Tmax": float(np.nanmax(cat["Tmax"]) + 2.0),
        "K2_dTglob": float(np.nanmax(cat["dTglob"]) + 1.0),
        "K3_Rate": float(1.3 * np.nanmax(cat["rate_max"]) + 0.02),
        "K4_Guembel": float(h_warn),
        "K5_Drift": float(1.5 * np.nanmax(cat["drift"]) + 1e-3),
    }


def classify(f, k, which, Ts):
    """Einfache Regeln zur Schadensunterscheidung im Alarmmoment.

    - Hotspot wandert Richtung Lastzone (Spalt wird kleiner)
        + Temperatur steigt     -> Schmierstoffmangel (schnell, lokal)
        + Temperatur steigt kaum -> Mischreibung durch Betriebszustand
    - Hotspot bleibt, Temperatur steigt langsam und gleichmaessig
                                -> abrasiver Verschleiss
    """
    def window(t_from, t_to):
        return (f["t"] >= f["t"][k] - t_from) & (f["t"] <= f["t"][k] - t_to)

    def med_phi(t_from, t_to):
        m = window(t_from, t_to) & f["hot_ok"] & (f["prom"] > 1.0)
        return np.median(f["phi_hot"][m]) if m.any() else np.nan

    # Hotspot-Wanderung: letzte ~20 s gegen 2-4 min vorher. Wegen der
    # thermischen Traegheit wandert das Maximum erst spaet; hat das
    # Guembel-Kriterium ausgeloest, ist die Wanderung bereits belegt.
    d_phi = med_phi(20, 0) - med_phi(240, 120)
    moved = which == "K4_Guembel" or d_phi < -2.0
    # Temperaturanstieg der Einhuellenden (robust gegen Start-Stopp-Zyklen):
    # Maximum der letzten 2 min gegen Maximum 2-4 min vorher
    d_T = np.max(f["Tmax"][window(120, 0)]) - np.max(f["Tmax"][window(240, 120)])
    if moved:
        return "Schmierstoffmangel" if d_T > 1.5 else "Mischreibung (Betriebszustand)"
    if which == "K3_Rate" or d_T > 3.0:
        return "Schmierstoffmangel"
    return "abrasiver Verschleiß"


EXPECTED_CLASS = {"mangel": "Schmierstoffmangel", "abrasiv": "abrasiver Verschleiß",
                  "ueberlast": "Mischreibung (Betriebszustand)"}


def evaluate_run(r, f, th, Ts, combo=("K3_Rate", "K4_Guembel", "K5_Drift")):
    sc = r["scenario"]
    masks = criterion_masks(f, th)
    t_end = r["t"][-1]
    t_crit = critical_time(r)
    row = {"szenario": sc.name, "seed": sc.seed, "t0": sc.t0, "t_crit": t_crit,
           "t_fresser": r["seizure_t"], "t_end": t_end,
           "sensorfehler_erkannt": f["bad_first"] >= 0}
    alarms = {}
    for c in CRITERIA:
        alarms[c] = first_alarm(masks[c], f["t"], Ts)
        row[c] = alarms[c][0]
    first = min(combo, key=lambda c: alarms[c][0])
    row["Kombi"] = alarms[first][0]
    row["Kombi_ausloeser"] = first if np.isfinite(alarms[first][0]) else ""
    row["Kombi_klasse"] = (classify(f, alarms[first][1], first, Ts)
                           if np.isfinite(alarms[first][0]) else "")
    return row


DAMAGE_PREFIXES = ("mangel", "start_stopp_mangel", "abrasiv", "ueberlast")


def is_damage(name: str) -> bool:
    """Laeufe mit echtem Lagerschaden. Alle anderen (gesund, Lastwechsel,
    Sensorfehler) duerfen keinen Schadensalarm ausloesen."""
    return name.startswith(DAMAGE_PREFIXES)


def summarize(rows, criteria=CRITERIA + ("Kombi",)):
    """Kennzahlen je Kriterium: Fehlalarme, Erkennungsrate, Vorwarnzeit."""
    healthy = [r for r in rows if not is_damage(r["szenario"])]
    faults = [r for r in rows if is_damage(r["szenario"])]
    out = {}
    for c in criteria:
        fa_healthy = sum(np.isfinite(r[c]) for r in healthy)
        fa_early = sum(r[c] < r["t0"] for r in faults)
        detected = [r for r in faults if r["t0"] <= r[c] <= min(r["t_end"], r["t_fresser"])]
        warn = [r["t_crit"] - r[c] for r in detected if np.isfinite(r["t_crit"])]
        delay = [r[c] - r["t0"] for r in detected]
        out[c] = {
            "fehlalarme": fa_healthy + fa_early,
            "laeufe_ohne_schaden": len(healthy),
            "erkannt": len(detected),
            "fehlerlaeufe": len(faults),
            "vor_kritisch": sum(w > 0 for w in warn),
            "median_verzug_s": float(np.median(delay)) if delay else np.nan,
            "median_vorwarnzeit_s": float(np.median(warn)) if warn else np.nan,
        }
    return out


def per_scenario(rows, c="Kombi"):
    out = {}
    for name in sorted({r["szenario"] for r in rows}):
        rs = [r for r in rows if r["szenario"] == name]
        dmg = is_damage(name)
        det = [r for r in rs if dmg and np.isfinite(r[c]) and r[c] >= r["t0"]]
        warn = [r["t_crit"] - r[c] for r in det if np.isfinite(r["t_crit"])]
        cls = [r["Kombi_klasse"] for r in det] if c == "Kombi" else []
        out[name] = {
            "laeufe": len(rs),
            "alarm": len(det),
            "fehlalarm": sum(np.isfinite(r[c]) and (not dmg or r[c] < r["t0"]) for r in rs),
            "median_vorwarnzeit_s": float(np.median(warn)) if warn else np.nan,
            "klassen": {k: cls.count(k) for k in sorted(set(cls))},
            "sensorfehler_erkannt": sum(r["sensorfehler_erkannt"] for r in rs),
        }
    return out
