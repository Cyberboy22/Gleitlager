"""Erzeugt die Beispieldaten in ../beispieldaten aus dem Simulator des
Projekts gleitlager-cm im selben Repository (synthetische Daten!).

Aufruf:  python erzeuge_beispieldaten.py <pfad/zu/gleitlager-cm>

Pro Versuch zwei Dateien, wie an einem echten Pruefstand:
  sipb.csv        Lagertemperaturen vom Sensorsystem (24 Kanaele, 0,14 Hz)
  pruefstand.csv  Pruefstandsdaten (10 Hz): Geschwindigkeit/Drehzahl, Last,
                  Reibmoment, Oeltemperatur
V02 ist absichtlich im deutschen Excel-Format (Semikolon, Dezimalkomma,
Drehzahl in 1/min, Kraft in kN), um den Import zu testen.
"""
import os
import sys

import numpy as np

sys.path.insert(0, sys.argv[1] if len(sys.argv) > 1 else "../../gleitlager-cm")
from sipb.experiments import run  # noqa: E402
from sipb.features import sample_indices  # noqa: E402
from sipb.simulate import Scenario  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "beispieldaten")
D, B = 0.120, 0.030


def write(path, header, cols, fmt, delim=",", dec="."):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(delim.join(header) + "\n")
        for row in zip(*cols):
            s = delim.join(f % v for f, v in zip(fmt, row))
            fh.write(s.replace(".", dec) if dec != "." else s)
            fh.write("\n")


def export(name, sc, german=False, rig_dt=0.1, sipb_clock_offset=0.0):
    rng = np.random.default_rng(sc.seed + 77)
    r = run(sc)
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    # --- SiPB: 0,14 Hz, eigene Uhr (optional versetzt)
    idx = sample_indices(r, 0.14)
    t_s = r["t"][idx] + sipb_clock_offset
    hdr = ["zeit_s"] + [f"T{i+1:02d}_degC" for i in range(24)]
    cols = [t_s] + [r["T"][idx, i] for i in range(24)]
    write(os.path.join(d, "sipb.csv"), hdr, cols, ["%.2f"] + ["%.5f"] * 24)
    # --- Pruefstand: 10 Hz mit Messrauschen
    step = int(round(rig_dt / r["dt"]))
    j = np.arange(0, len(r["t"]), step)
    v = r["v"][j] + rng.normal(0, 0.004, len(j))
    p = r["p"][j] / 1e6 + rng.normal(0, 0.03, len(j))
    M = r["M_friction"][j] + rng.normal(0, 0.15, len(j))
    T_oil = sc.T_oil + rng.normal(0, 0.1, len(j))
    if german:
        n_rpm = np.maximum(v, 0) * 60 / (np.pi * D)
        F_kN = p * 1e6 * B * D / 1e3
        hdr = ["Zeit [s]", "Drehzahl [1/min]", "Radialkraft [kN]", "Reibmoment [Nm]", "Öltemperatur Zulauf [°C]"]
        write(os.path.join(d, "pruefstand.csv"), hdr, [r["t"][j], n_rpm, F_kN, M, T_oil],
              ["%.2f", "%.2f", "%.3f", "%.3f", "%.2f"], delim=";", dec=",")
    else:
        hdr = ["zeit_s", "v_mps", "p_MPa", "reibmoment_Nm", "T_oel_degC"]
        write(os.path.join(d, "pruefstand.csv"), hdr, [r["t"][j], v, p, M, T_oil],
              ["%.2f", "%.4f", "%.4f", "%.3f", "%.2f"])
    print(name, "fertig:", len(idx), "SiPB-Messungen,", len(j), "Pruefstandswerte")


if __name__ == "__main__":
    export("V01_start_stopp_schmierstoffmangel_60C",
           Scenario("start_stopp_mangel_60", 60.0, "start_stopp", fault="mangel", t0=1278.0, seed=20))
    export("V02_ueberlast_60C_deutsches_format",
           Scenario("ueberlast_60", 60.0, fault="ueberlast", t0=1100.0, seed=21), german=True)
    export("V03_start_stopp_gesund_20C",
           Scenario("start_stopp_20", 20.0, "start_stopp", seed=22, duration=1200.0),
           sipb_clock_offset=12.0)
