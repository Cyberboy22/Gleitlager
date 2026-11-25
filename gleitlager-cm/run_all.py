"""Komplette Auswertung: Kalibrierung, Validierung, Abtastrate, Sensoranzahl.

Aufruf:  python run_all.py          (ca. 5-10 min, Simulationen werden gecacht)
Ergebnis: results/ergebnisse.md, results/*.png, results/*.json, results/*.csv
"""
import json
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from sipb.experiments import (CRITERIA, calibrate_guembel, calibrate_thresholds,
                              critical_time, evaluate_run, features_for,
                              guembel_calibration_scenarios, healthy_scenarios,
                              per_scenario, run_many, summarize, test_scenarios)
from sipb.features import sample_indices
from sipb.simulate import PHI

OUT = os.path.join(os.path.dirname(__file__), "results")
os.makedirs(OUT, exist_ok=True)

CAL_SEEDS = [100, 101, 102]          # gesunde Laeufe fuer Schwellen
VAL_SEEDS = list(range(20, 30))      # frische Laeufe, NICHT zur Entwicklung genutzt
FS_MAIN = 0.14                       # Abtastrate wie im Paper [Hz]

# Farben (Referenzpalette, siehe README)
SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
BLUE, ORANGE, AQUA, CRITICAL = "#2a78d6", "#eb6834", "#1baf7a", "#d03b3b"
plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "text.color": INK, "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.spines.top": False, "axes.spines.right": False, "font.size": 10,
    "axes.titlesize": 11, "axes.titleweight": "bold", "axes.titlelocation": "left",
})


def fmt(x, nd=0):
    return "–" if x is None or not np.isfinite(x) else f"{x:.{nd}f}"


def main():
    md = ["# Ergebnisse\n",
          "Alle Zahlen stammen aus **synthetischen** Daten (siehe README). "
          f"Bewertet werden {len(VAL_SEEDS)} frische Validierungsläufe je Szenario, "
          "die bei der Entwicklung der Regeln nicht verwendet wurden.\n"]

    # ------------------------------------------------------------- 1. Guembel
    print("1/5 Guembel-Kalibrierung ...")
    kal = run_many(guembel_calibration_scenarios())
    gmap, phi_m, eps_t, h_t = calibrate_guembel(kal)
    h_rmse = np.sqrt(np.mean((gmap.h_min(phi_m) - h_t) ** 2)) * 1e6
    json.dump({"koeffizienten_eps_von_phi": gmap.coeffs.tolist(), "phi_bereich": gmap.phi_range},
              open(os.path.join(OUT, "guembel_polynom.json"), "w"), indent=2)
    md.append(f"## Gümbel-Kalibrierung\n\n{len(phi_m)} quasistationäre Betriebspunkte "
              f"(v = 0,4–2,5 m/s, p = 4–12 MPa, Öl 20/40/60 °C). "
              f"Fehler der Spalthöhe nach Polynom 4. Ordnung: RMSE = {h_rmse:.2f} µm.\n")

    fig, ax = plt.subplots(figsize=(6.4, 3.6))
    ax.scatter(phi_m, h_t * 1e6, s=28, color=BLUE, edgecolor=SURFACE, linewidth=1.2, zorder=3)
    xx = np.linspace(*gmap.phi_range, 200)
    ax.plot(xx, gmap.h_min(xx) * 1e6, color=INK2, lw=2)
    ax.axhline(3.0, color=CRITICAL, lw=1, ls="--")
    ax.text(gmap.phi_range[1], 3.4, "Grenze Mischreibung (3 µm)", color=INK2, fontsize=9, ha="right")
    ax.set_title("Hotspot-Winkel verrät die Spalthöhe (Gümbel-Methode)")
    ax.set_xlabel("gemessener Winkel des Temperaturmaximums [°]")
    ax.set_ylabel("minimale Spalthöhe [µm]")
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "fig5_guembel.png"), dpi=160)
    plt.close(fig)

    # ------------------------------------------------------------- 2. Schwellen + Validierung
    print("2/5 Schwellen kalibrieren und validieren ...")
    cal = run_many(healthy_scenarios(CAL_SEEDS))
    th = calibrate_thresholds([features_for(r, FS_MAIN, gmap) for r in cal])
    json.dump(th, open(os.path.join(OUT, "schwellen_0p14Hz.json"), "w"), indent=2)
    val = run_many(test_scenarios(VAL_SEEDS))
    feats = [features_for(r, FS_MAIN, gmap) for r in val]
    rows = [evaluate_run(r, f, th, 1 / FS_MAIN) for r, f in zip(val, feats)]
    summ = summarize(rows)

    md.append("## Schwellen (aus gesunden Läufen, 0,14 Hz)\n")
    md.append("| Kriterium | Schwelle |\n|---|---|")
    md.append(f"| K1 T_max | {th['K1_Tmax']:.1f} °C |")
    md.append(f"| K2 globaler Gradient | {th['K2_dTglob']:.1f} K |")
    md.append(f"| K3 Temperaturrate | {th['K3_Rate']:.2f} K/s |")
    md.append(f"| K4 Gümbel-Spalthöhe | {th['K4_Guembel']*1e6:.1f} µm |")
    md.append(f"| K5 Drift | {th['K5_Drift']*60:.2f} K/min |\n")

    md.append("## Vergleich der Kriterien (0,14 Hz)\n")
    md.append("| Kriterium | Fehlalarme | erkannt | vor kritischem Zustand | Median Verzug ab Fehlerbeginn [s] | Median Vorwarnzeit [s] |")
    md.append("|---|---|---|---|---|---|")
    for c, s in summ.items():
        md.append(f"| {c} | {s['fehlalarme']} / {s['laeufe_ohne_schaden']} | {s['erkannt']} / {s['fehlerlaeufe']} | "
                  f"{s['vor_kritisch']} | {fmt(s['median_verzug_s'])} | {fmt(s['median_vorwarnzeit_s'])} |")
    md.append("\nKombi = K3 oder K4 oder K5, mit Sensor-Plausibilitätsprüfung. "
              "Vorwarnzeit = Zeit vom Alarm bis zum kritischen Zustand (Reibmoment +50 % oder "
              "Mischreibung); negativ = Alarm kam zu spät.\n")

    md.append("## Kombi je Szenario\n")
    md.append("| Szenario | Läufe | Alarm | Fehlalarm | Median Vorwarnzeit [s] | Diagnose im Alarmmoment | Sensorfehler erkannt |")
    md.append("|---|---|---|---|---|---|---|")
    for name, s in per_scenario(rows).items():
        kl = ", ".join(f"{k}: {v}" for k, v in s["klassen"].items()) or "–"
        md.append(f"| {name} | {s['laeufe']} | {s['alarm']} | {s['fehlalarm']} | "
                  f"{fmt(s['median_vorwarnzeit_s'])} | {kl} | {s['sensorfehler_erkannt']} |")

    # Abbildung: Kriterienvergleich (Fehlalarme sind ueberall 0 -> steht im Titel statt als leeres Diagramm)
    names = list(summ.keys())
    labels = ["K1 T_max", "K2 glob. Gradient", "K3 Rate", "K4 Gümbel", "K5 Drift", "Kombi"]
    n_f = summ["Kombi"]["fehlerlaeufe"]
    n_h = summ["Kombi"]["laeufe_ohne_schaden"]
    fa_total = sum(summ[c]["fehlalarme"] for c in names)
    det = [summ[c]["erkannt"] for c in names]
    early = [summ[c]["vor_kritisch"] for c in names]
    fig, ax = plt.subplots(figsize=(8.0, 3.8))
    y = np.arange(len(names))[::-1]
    ax.set_axisbelow(True)
    ax.barh(y + 0.19, det, height=0.36, color="#86b6ef", edgecolor=SURFACE, linewidth=2, label="erkannt (irgendwann)")
    ax.barh(y - 0.19, early, height=0.36, color=BLUE, edgecolor=SURFACE, linewidth=2, label="vor dem kritischen Zustand erkannt")
    for yi, a, b in zip(y, det, early):
        ax.text(a + 0.6, yi + 0.19, str(a), va="center", color=INK2, fontsize=9)
        ax.text(b + 0.6, yi - 0.19, str(b), va="center", color=INK2, fontsize=9)
    ax.set_yticks(y, labels)
    ax.set_xlim(0, n_f * 1.1)
    ax.set_xlabel(f"Anzahl Schadensläufe (von {n_f})")
    ax.grid(axis="y", visible=False)
    fa_txt = "keine Fehlalarme" if fa_total == 0 else f"{fa_total} Fehlalarme"
    ax.set_title(f"Nur die Kombination erkennt alle Schäden\n({fa_txt} in {n_h} Läufen ohne Schaden)")
    ax.legend(frameon=False, fontsize=9, loc="upper center", bbox_to_anchor=(0.5, -0.17), ncol=2)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "fig2_kriterien.png"), dpi=160)
    plt.close(fig)

    # Abbildung: Temperaturfeld eines Start-Stopp-Laufs mit Schmierstoffmangel
    i_ex = next(i for i, r in enumerate(val) if r["scenario"].name == "start_stopp_mangel_60")
    r, f, row = val[i_ex], feats[i_ex], rows[i_ex]
    t0, t_al, t_cr = r["scenario"].t0, row["Kombi"], row["t_crit"]
    lo = max(0.0, t0 - 600)
    hi = min(r["t"][-1], (t_cr if np.isfinite(t_cr) else t0) + 20)
    m = (f["t"] >= lo) & (f["t"] <= hi)
    idx = f["idx"][m]
    fig = plt.figure(figsize=(9.6, 5.8))
    gs = fig.add_gridspec(2, 2, height_ratios=[2.2, 1], width_ratios=[40, 1], hspace=0.12, wspace=0.03)
    a1 = fig.add_subplot(gs[0, 0])
    a2 = fig.add_subplot(gs[1, 0], sharex=a1)
    cax = fig.add_subplot(gs[0, 1])
    pre = r["T"][idx][r["t"][idx] < (t_al if np.isfinite(t_al) else t0)]
    im = a1.pcolormesh(r["t"][idx] - t0, PHI, r["T"][idx].T, cmap="Blues", shading="nearest",
                       vmin=np.nanpercentile(pre, 1), vmax=np.nanmax(pre) + 4)
    cb = fig.colorbar(im, cax=cax, extend="max")
    cb.set_label("Temperatur [°C]", color=INK2)
    a1.set_ylabel("Umfangswinkel [°]")
    a1.set_title("Gemessenes Temperaturfeld (24 Sensoren, 0,14 Hz) – Start-Stopp mit Schmierstoffmangel")
    a1.grid(False)
    plt.setp(a1.get_xticklabels(), visible=False)
    ok = f["hot_ok"][m] & (f["prom"][m] > 1.0)
    a2.plot(r["t"][idx] - t0, r["h_min"][idx] * 1e6, color=INK2, lw=1.2, label="wahre Spalthöhe (nur in Simulation bekannt)")
    a2.plot((r["t"][idx] - t0)[ok], (f["h_est"][m] * 1e6)[ok], "o", ms=3.5, color=ORANGE,
            label="geschätzt aus Temperaturfeld (Gümbel)")
    a2.axhline(3.0, color=CRITICAL, lw=1, ls="--")
    a2.set_ylim(0, 14)
    a2.set_ylabel("h_min [µm]")
    a2.set_xlabel("Zeit relativ zum Fehlerbeginn [s]")
    a2.legend(loc="upper left", frameon=False, fontsize=9, ncol=2)
    for ax in (a1, a2):
        ax.axvline(0, color=INK2, lw=1.2, ls=":")
        if np.isfinite(t_al):
            ax.axvline(t_al - t0, color=BLUE, lw=2)
        if np.isfinite(t_cr):
            ax.axvline(t_cr - t0, color=CRITICAL, lw=2)
    ymax = a2.get_ylim()[1]
    a1.text(3, PHI[-1] - 6, "Fehlerbeginn", color=INK, fontsize=9)
    if np.isfinite(t_al):
        a1.text(t_al - t0 - 3, PHI[0] + 4, f"Alarm: {row['Kombi_klasse']}", color=INK, fontsize=9,
                ha="right", bbox=dict(fc=SURFACE, ec="none", pad=1.5))
    if np.isfinite(t_cr):
        a1.text(t_cr - t0 - 3, PHI[-1] - 6, "kritisch", color=INK, fontsize=9, ha="right",
                bbox=dict(fc=SURFACE, ec="none", pad=1.5))
    fig.subplots_adjust(left=0.08, right=0.92, top=0.93, bottom=0.1)
    fig.savefig(os.path.join(OUT, "fig1_temperaturfeld.png"), dpi=160)
    plt.close(fig)

    # Beispieldaten wie ein Pruefstands-Export (auch fuer den C-Test)
    full_idx = sample_indices(r, FS_MAIN)
    header = "zeit_s," + ",".join(f"T{i+1:02d}_degC" for i in range(24)) + \
             ",v_mps,p_MPa,reibmoment_Nm,h_min_um_sim"
    data = np.column_stack([r["t"][full_idx], r["T"][full_idx], r["v"][full_idx],
                            r["p"][full_idx] / 1e6, r["M_friction"][full_idx], r["h_min"][full_idx] * 1e6])
    np.savetxt(os.path.join(OUT, "beispiel_pruefstand.csv"), data, delimiter=",", header=header,
               comments="", fmt="%.5f")

    # ------------------------------------------------------------- 3. Abtastrate
    print("3/5 Abtastrate ...")
    fs_list = [0.14, 0.5, 1.0, 2.0, 8.92]
    sub = ("mangel_60", "start_stopp_mangel_60", "ueberlast_60", "stationaer_60", "stationaer_20",
           "start_stopp_60", "start_stopp_20", "lastwechsel_20")
    val_sub = [r for r in val if r["scenario"].name in sub]
    rate_res = {}
    for fs in fs_list:
        th_fs = calibrate_thresholds([features_for(r, fs, gmap) for r in cal])
        rr = [evaluate_run(r, features_for(r, fs, gmap), th_fs, 1 / fs) for r in val_sub]
        ps = per_scenario(rr)
        rate_res[fs] = {"fehlalarme": sum(ps[n]["fehlalarm"] for n in ps),
                        **{n: ps[n]["median_vorwarnzeit_s"] for n in ("mangel_60", "start_stopp_mangel_60", "ueberlast_60")}}
        print("   ", fs, rate_res[fs])
    md.append("\n## Einfluss der Abtastrate (Kombi)\n")
    md.append("Schwellen werden je Abtastrate neu aus den gesunden Läufen bestimmt.\n")
    md.append("| Abtastrate [Hz] | Fehlalarme | Vorwarnzeit Mangel 60 [s] | Vorwarnzeit Start-Stopp+Mangel [s] | Vorwarnzeit Überlast [s] |")
    md.append("|---|---|---|---|---|")
    for fs, v in rate_res.items():
        md.append(f"| {fs} | {v['fehlalarme']} | {fmt(v['mangel_60'])} | {fmt(v['start_stopp_mangel_60'])} | {fmt(v['ueberlast_60'])} |")

    fig, ax = plt.subplots(figsize=(6.8, 3.6))
    series = (("mangel_60", "Schmierstoffmangel", BLUE), ("start_stopp_mangel_60", "Start-Stopp + Mangel", ORANGE),
              ("ueberlast_60", "Überlast (Mischreibung)", AQUA))
    for key, lab, col in series:
        yv = [rate_res[fs][key] for fs in fs_list]
        ax.plot(fs_list, yv, "-o", color=col, lw=2, ms=6, mec=SURFACE, mew=1.5, label=lab)
        ax.text(fs_list[-1] * 1.08, yv[-1], lab, color=INK2, fontsize=9, va="center")
    ax.axhline(0, color=INK2, lw=1)
    ax.set_xscale("log")
    ax.set_xticks(fs_list, [str(x) for x in fs_list])
    ax.minorticks_off()
    ax.set_xlim(0.11, 40)
    ax.set_xlabel("Abtastrate [Hz] (log)")
    ax.set_ylabel("Median Vorwarnzeit [s]")
    ax.set_title("Mehr Abtastrate bringt kaum mehr Vorwarnzeit", pad=26)
    ax.legend(frameon=False, fontsize=9, loc="lower left", bbox_to_anchor=(0, 1.0), ncol=3,
              borderaxespad=0.2, handlelength=1.5)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "fig3_abtastrate.png"), dpi=160)
    plt.close(fig)

    # ------------------------------------------------------------- 4. Sensoranzahl
    print("4/5 Sensoranzahl ...")
    layouts = {24: np.arange(24), 12: np.arange(0, 24, 2), 8: np.arange(0, 24, 3),
               6: np.arange(0, 24, 4), 4: np.arange(0, 24, 6)}
    kal_even, kal_odd = kal[0::2], kal[1::2]
    sens_res = {}
    for n, s_idx in layouts.items():
        gm_n, *_ = calibrate_guembel(kal_even, sensors=s_idx)
        _, pm_o, _, h_o = calibrate_guembel(kal_odd, sensors=s_idx)
        rmse = np.sqrt(np.mean((gm_n.h_min(pm_o) - h_o) ** 2)) * 1e6
        th_n = calibrate_thresholds([features_for(r, FS_MAIN, gm_n, s_idx) for r in cal])
        fv = [features_for(r, FS_MAIN, gm_n, s_idx) for r in val_sub]
        rr = [evaluate_run(r, f_, th_n, 1 / FS_MAIN) for r, f_ in zip(val_sub, fv)]
        ps = per_scenario(rr)
        # haerterer Test: Spalthoehe in Fehlerlaeufen, wo sich die Hotspot-Form aendert
        err = np.concatenate([(f_["h_est"] - r["h_min"][f_["idx"]])[f_["guembel_ok"]]
                              for r, f_ in zip(val_sub, fv) if r["scenario"].fault in ("mangel", "ueberlast")])
        sens_res[n] = {"h_rmse_um": rmse, "h_rmse_fehler_um": float(np.sqrt(np.mean(err**2)) * 1e6),
                       "fehlalarme": sum(ps[k]["fehlalarm"] for k in ps),
                       "ueberlast_vorwarnzeit": ps["ueberlast_60"]["median_vorwarnzeit_s"],
                       "mangel_vorwarnzeit": ps["mangel_60"]["median_vorwarnzeit_s"],
                       "abstand_deg": float(PHI[s_idx[1]] - PHI[s_idx[0]])}
        print("   ", n, sens_res[n])
    md.append("\n## Einfluss der Sensoranzahl (0,14 Hz)\n")
    md.append("Gümbel-Polynom auf der Hälfte der Kalibrierpunkte angepasst, auf der anderen Hälfte getestet.\n")
    md.append("| Sensoren | Abstand [°] | RMSE Spalthöhe Kalibrierpunkte [µm] | RMSE Spalthöhe in Fehlerläufen [µm] | Fehlalarme | Vorwarnzeit Mangel 60 [s] | Vorwarnzeit Überlast [s] |")
    md.append("|---|---|---|---|---|---|---|")
    for n, v in sens_res.items():
        md.append(f"| {n} | {v['abstand_deg']:.1f} | {v['h_rmse_um']:.2f} | {v['h_rmse_fehler_um']:.2f} | {v['fehlalarme']} | "
                  f"{fmt(v['mangel_vorwarnzeit'])} | {fmt(v['ueberlast_vorwarnzeit'])} |")

    fig, ax = plt.subplots(figsize=(6.8, 3.6))
    ns = list(sens_res.keys())
    xs = np.arange(len(ns))
    v1 = [sens_res[n]["h_rmse_um"] for n in ns]
    v2 = [sens_res[n]["h_rmse_fehler_um"] for n in ns]
    top = max(v1 + v2)
    for off, vals, col, lab in ((-0.19, v1, BLUE, "Kalibrierpunkte (stationär)"),
                                (0.19, v2, ORANGE, "Fehlerläufe (Hotspot-Form ändert sich)")):
        ax.bar(xs + off, vals, width=0.36, color=col, edgecolor=SURFACE, linewidth=2, label=lab)
        for x, v in zip(xs + off, vals):
            ax.text(x, v + top * 0.02, f"{v:.2f}", ha="center", color=INK2, fontsize=8)
    ax.legend(frameon=False, fontsize=9, loc="lower left", bbox_to_anchor=(0, 1.0), ncol=2,
              borderaxespad=0.2)
    ax.set_ylim(0, top * 1.12)
    ax.set_xticks(xs, [f"{n}\n({sens_res[n]['abstand_deg']:.1f}°)" for n in ns])
    ax.set_xlabel("Anzahl Sensoren (Abstand)")
    ax.set_ylabel("Fehler Spalthöhe, RMSE [µm]")
    ax.set_title("Wie viele Sensoren braucht die Gümbel-Methode?", pad=26)
    ax.grid(axis="x", visible=False)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "fig4_sensoranzahl.png"), dpi=160)
    plt.close(fig)

    # ------------------------------------------------------------- 5. speichern
    print("5/5 schreiben ...")
    with open(os.path.join(OUT, "ergebnisse.md"), "w") as fh:
        fh.write("\n".join(md) + "\n")
    print(open(os.path.join(OUT, "ergebnisse.md")).read())


if __name__ == "__main__":
    main()
