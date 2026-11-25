"""Kleine Plausibilitaetstests:  python -m pytest tests"""
import numpy as np

from sipb.features import GuembelMap, PlausibilityCheck, hotspot
from sipb.physics import Bearing, operating_point, sommerfeld_short_bearing, viscosity
from sipb.simulate import PHI


def test_viskositaet_iso_vg_320():
    nu40 = viscosity(40.0) / 850 * 1e6
    nu100 = viscosity(100.0) / 850 * 1e6
    assert abs(nu40 - 320) < 1 and abs(nu100 - 35) < 0.5


def test_sommerfeld_steigt_mit_exzentrizitaet():
    eps = np.linspace(0.1, 0.95, 50)
    assert np.all(np.diff(sommerfeld_short_bearing(eps, 0.25)) > 0)


def test_mehr_last_kleinerer_spalt():
    b = Bearing()
    h1 = operating_point(b, 2.5, 5e6, 60)["h_min"]
    h2 = operating_point(b, 2.5, 10e6, 60)["h_min"]
    assert h2 < h1


def test_parabel_findet_exaktes_maximum():
    T = -0.01 * (PHI - 203.0) ** 2 + 80
    phi_hot, _, ok = hotspot(T, PHI)
    assert ok and abs(phi_hot - 203.0) < 1e-9


def test_hotspot_am_rand_ungueltig():
    _, _, ok = hotspot(PHI.copy(), PHI)  # Maximum beim letzten Sensor
    assert not ok


def test_plausibilitaet_einzelner_sprung_ist_sensorfehler():
    pc = PlausibilityCheck(24)
    T = np.full(24, 70.0)
    pc.update(T)
    T2 = T.copy()
    T2[10] -= 4.0
    assert pc.update(T2)[10]


def test_plausibilitaet_echte_erwaermung_ist_kein_sensorfehler():
    pc = PlausibilityCheck(24)
    T = np.full(24, 70.0)
    pc.update(T)
    heat = 6.0 * np.exp(-0.5 * ((PHI - 200) / 15) ** 2)  # raeumlich glatter Hotspot
    assert not pc.update(T + heat).any()


def test_guembel_polynom_rundreise():
    phi = np.linspace(200, 225, 30)
    eps = 0.95 - 0.004 * (phi - 200)
    g = GuembelMap.fit(phi, eps)
    assert np.max(np.abs(g.eps(phi) - eps)) < 1e-6
