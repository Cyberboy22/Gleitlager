"""Erzeugt sipb_config.h aus der Python-Kalibrierung, kompiliert den C-Code,
laesst ihn auf dem Beispiel-Export laufen und vergleicht mit Python.

Aufruf (aus dem Projektordner, nach run_all.py):  python c/vergleich_python_c.py
"""
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

from run_all import VAL_SEEDS  # noqa: E402
from sipb.experiments import criterion_masks, first_alarm, run, test_scenarios  # noqa: E402
from sipb.features import (GuembelMap, PlausibilityCheck, estimate_offsets,  # noqa: E402
                           extract, sample_indices)
from sipb.simulate import PHI, Scenario, calibration_soak  # noqa: E402

RES = os.path.join(ROOT, "results")
FS = 0.14
TS = 1 / FS


def cf(v):
    """float-Literal fuer C, immer mit Exponent (105f waere ungueltig)."""
    return f"{float(v):.9e}f"


def carr(x):
    return "{" + ", ".join(cf(v) for v in x) + "}"


def main():
    g = json.load(open(os.path.join(RES, "guembel_polynom.json")))
    th = json.load(open(os.path.join(RES, "schwellen_0p14Hz.json")))
    gmap = GuembelMap(g["koeffizienten_eps_von_phi"], tuple(g["phi_bereich"]))
    sc = next(s for s in test_scenarios(VAL_SEEDS) if s.name == "start_stopp_mangel_60")
    offsets = estimate_offsets(calibration_soak(sc.seed))
    b = Scenario("x").bearing
    pc = PlausibilityCheck(24)
    m_rate = max(1, int(round(10.0 / TS)))
    m_qs = max(1, int(round(60.0 / TS)))
    n_drift = max(3, int(round(600.0 / TS)))
    n_persist = max(1, int(np.ceil(5.0 / TS)))
    assert max(m_rate, m_qs, n_drift, n_persist) < 128, "SIPB_MAX_HIST zu klein"

    hdr = f"""/* automatisch erzeugt von vergleich_python_c.py - nicht von Hand aendern */
#ifndef SIPB_CONFIG_H
#define SIPB_CONFIG_H
#include "sipb_features.h"

static const float SIPB_PHI[SIPB_N] = {carr(PHI)};
static const float SIPB_OFFSET[SIPB_N] = {carr(offsets)};
static const float SIPB_GUEMBEL[5] = {carr(gmap.coeffs)};

static inline void sipb_config_apply(sipb_state *s) {{
    for (int i = 0; i < SIPB_N; i++) {{ s->phi[i] = SIPB_PHI[i]; s->offset[i] = SIPB_OFFSET[i]; }}
    for (int i = 0; i < 5; i++) s->guembel[i] = SIPB_GUEMBEL[i];
    s->phi_lo = {cf(gmap.phi_range[0])};
    s->phi_hi = {cf(gmap.phi_range[1])};
    s->clearance_um = {cf(b.psi * b.R * 1e6)};
    s->Ts = {cf(TS)};
    s->th_rate = {cf(th['K3_Rate'])};
    s->th_h_um = {cf(th['K4_Guembel'] * 1e6)};
    s->th_drift = {cf(th['K5_Drift'])};
    s->min_prom = 1.5f;
    s->jump = {cf(pc.jump)};
    s->ratio = {cf(pc.ratio)};
    s->m_rate = {m_rate};
    s->m_qs = {m_qs};
    s->n_drift = {n_drift};
    s->n_persist = {n_persist};
}}
#endif
"""
    open(os.path.join(HERE, "sipb_config.h"), "w").write(hdr)

    exe = os.path.join(HERE, "sipb_test")
    subprocess.run(["gcc", "-O2", "-std=c99", "-Wall", "-Wextra", "-Werror", "-o", exe,
                    os.path.join(HERE, "test_main.c"), os.path.join(HERE, "sipb_features.c"), "-lm"],
                   check=True)
    all_ok = True
    for name in ("start_stopp_mangel_60", "sensorfehler_60"):
        sc_i = next(x for x in test_scenarios(VAL_SEEDS) if x.name == name and x.seed == sc.seed)
        csv = os.path.join(RES, f"pruefstand_{name}.csv")
        write_csv(run(sc_i), csv)
        print(f"\n--- {name} (seed {sc_i.seed}) ---")
        all_ok &= compare(exe, csv, gmap, th, offsets)
    print("\nERGEBNIS:", "OK - C und Python stimmen ueberein" if all_ok else "ABWEICHUNG")
    return 0 if all_ok else 1


def write_csv(r, path):
    idx = sample_indices(r, FS)
    header = "zeit_s," + ",".join(f"T{i+1:02d}_degC" for i in range(24))
    np.savetxt(path, np.column_stack([r["t"][idx], r["T"][idx]]), delimiter=",",
               header=header, comments="", fmt="%.5f")


def compare(exe, csv, gmap, th, offsets):
    out = subprocess.run([exe, csv], check=True, capture_output=True, text=True)
    print(out.stderr.strip())
    c = np.genfromtxt(out.stdout.splitlines(), delimiter=",", names=True)
    data = np.loadtxt(csv, delimiter=",", skiprows=1)
    t, T = data[:, 0], data[:, 1:25]
    f = extract(T, TS, PHI, gmap, offsets)
    masks = criterion_masks(f, th)
    t_alarm_py = min(first_alarm(masks[k], t, TS)[0] for k in ("K3_Rate", "K4_Guembel", "K5_Drift"))
    t_alarm_c = t[np.argmax(c["alarm"] > 0)] if (c["alarm"] > 0).any() else np.inf

    def maxdiff(a, b):
        ok = np.isfinite(a) & np.isfinite(b)
        assert np.array_equal(np.isfinite(a), np.isfinite(b)), "NaN-Muster unterschiedlich"
        return float(np.max(np.abs(a[ok] - b[ok])))

    checks = {
        "Tmax [K]": maxdiff(c["Tmax"], f["Tmax"]),
        "dTglob [K]": maxdiff(c["dTglob"], f["dTglob"]),
        "phi_hot [deg]": maxdiff(c["phi_hot"], f["phi_hot"]),
        "h_est [um]": maxdiff(c["h_est_um"], f["h_est"] * 1e6),
        "rate_max [K/s]": maxdiff(c["rate_max"], f["rate_max"]),
        "drift [K/s]": maxdiff(c["drift"], f["drift"]),
    }
    print(f"{len(t)} Messungen verglichen, max. Abweichung C (float32) vs. Python (float64):")
    for k, v in checks.items():
        print(f"  {k:16s} {v:.2e}")
    same_ok = np.array_equal(c["guembel_ok"].astype(bool), f["guembel_ok"])
    same_bad = np.array_equal(c["n_bad"].astype(int), f["n_bad"])
    print(f"  guembel_ok identisch: {same_ok},  Sensorfehler-Flags identisch: {same_bad} "
          f"(defekte Sensoren am Ende: {int(c['n_bad'][-1])})")
    print(f"  erster Alarm: Python t = {t_alarm_py:.1f} s, C t = {t_alarm_c:.1f} s")
    tol = {"Tmax [K]": 1e-3, "dTglob [K]": 1e-3, "phi_hot [deg]": 1e-2, "h_est [um]": 1e-2,
           "rate_max [K/s]": 1e-4, "drift [K/s]": 1e-5}
    return all(checks[k] < tol[k] for k in tol) and same_ok and same_bad and t_alarm_py == t_alarm_c


if __name__ == "__main__":
    sys.exit(main())
