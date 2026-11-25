"""Vereinfachte Gleitlager-Physik (hydrodynamisches Radialgleitlager).

Alles hier ist bewusst einfach gehalten, damit man es nachvollziehen kann:
- Viskositaet von ISO VG 320 nach Walther (ASTM D341)
- Sommerfeldzahl nach DIN 31652: So = p * psi^2 / (eta * omega)
- Exzentrizitaet und Verlagerungswinkel nach der Kurzlagertheorie (Ocvirk)
- Reibungszahl: Petroff mit Exzentrizitaetskorrektur + Mischreibungsanteil

Die Geometrie entspricht dem Pruefstandslager aus
Baszenski et al. (2025), Forschung im Ingenieurwesen 89:140:
D = 120 mm, B = 30 mm, relatives Lagerspiel 1,1667 promille.
"""
from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class Bearing:
    D: float = 0.120          # Innendurchmesser [m]
    B: float = 0.030          # Breite [m]
    psi: float = 1.1667e-3    # relatives Lagerspiel [-]
    h_lim: float = 3.0e-6     # Uebergang in Mischreibung (aus Rauheit) [m]
    mu_boundary: float = 0.12  # Reibungszahl bei Festkoerperkontakt [-]

    @property
    def R(self) -> float:
        return self.D / 2

    @property
    def area(self) -> float:
        return self.B * self.D


# --- Oel: ISO VG 320, Walther-Gleichung durch nu40 = 320 cSt, nu100 = 35 cSt ---
_T40, _T100 = 313.15, 373.15
_LL40 = np.log10(np.log10(320.0 + 0.7))
_LL100 = np.log10(np.log10(35.0 + 0.7))
_WB = (_LL40 - _LL100) / (np.log10(_T100) - np.log10(_T40))
_WA = _LL40 + _WB * np.log10(_T40)
OIL_DENSITY = 850.0  # kg/m^3


def viscosity(T_celsius):
    """Dynamische Viskositaet [Pa s] von ISO VG 320 bei T [degC]."""
    T_K = np.asarray(T_celsius, dtype=float) + 273.15
    nu_cst = 10 ** (10 ** (_WA - _WB * np.log10(T_K))) - 0.7
    return nu_cst * 1e-6 * OIL_DENSITY


# --- Kurzlagertheorie: So(eps) und Verlagerungswinkel beta(eps) ---
def sommerfeld_short_bearing(eps, B_over_D):
    eps = np.asarray(eps, dtype=float)
    g = eps / (1 - eps**2) ** 2 * np.sqrt(np.pi**2 * (1 - eps**2) + 16 * eps**2)
    return 0.5 * B_over_D**2 * g


def attitude_angle_deg(eps):
    """Verlagerungswinkel beta [deg] (Kurzlager): tan(beta) = pi*sqrt(1-eps^2)/(4 eps)."""
    eps = np.clip(np.asarray(eps, dtype=float), 1e-4, 0.9999)
    return np.degrees(np.arctan(np.pi * np.sqrt(1 - eps**2) / (4 * eps)))


_EPS_GRID = np.linspace(1e-3, 0.995, 4000)
_LOG_SO_CACHE = {}


def eccentricity_from_sommerfeld(So, B_over_D):
    """Numerische Umkehrung So(eps) -> eps ueber eine Tabelle."""
    if B_over_D not in _LOG_SO_CACHE:
        _LOG_SO_CACHE[B_over_D] = np.log(sommerfeld_short_bearing(_EPS_GRID, B_over_D))
    So = np.asarray(So, dtype=float)
    return np.interp(np.log(np.maximum(So, 1e-9)), _LOG_SO_CACHE[B_over_D], _EPS_GRID)


def operating_point(bearing: Bearing, v, p, T_eff, starvation=0.0, psi_factor=1.0):
    """Berechnet den hydrodynamischen Zustand fuer einen Zeitpunkt.

    v: Gleitgeschwindigkeit [m/s], p: spez. Lagerlast [Pa], T_eff: effektive
    Schmierfilmtemperatur [degC].
    starvation in [0, 1): Schmierstoffmangel. Der unvollstaendig gefuellte
    Spalt traegt weniger (hoehere Exzentrizitaet), die Scherreibung im
    benetzten Bereich bleibt aber erhalten.
    psi_factor > 1: Verschleiss (Spielvergroesserung).

    Rueckgabe: dict mit So, eps, beta_deg, h_min [m], mu_hydro, mu_mixed
    """
    psi = bearing.psi * psi_factor
    eta = viscosity(T_eff)
    omega = 2 * v / bearing.D
    if v < 1e-4:
        # Stillstand: kein Schmierfilm aufgebaut, aber auch keine Reibleistung
        eps = 0.995
        So = np.inf
    else:
        So = p * psi**2 / (eta * omega)
        So_eff = So / max(1.0 - starvation, 1e-3)  # Tragfaehigkeit sinkt
        eps = float(eccentricity_from_sommerfeld(So_eff, bearing.B / bearing.D))
    beta = float(attitude_angle_deg(eps))
    h_min = psi * bearing.R * (1 - eps)
    if np.isfinite(So):
        mu_hydro = psi * (np.pi / (So * np.sqrt(1 - eps**2)) + 0.5 * eps * np.sin(np.radians(beta)))
    else:
        mu_hydro = 0.0
    mixed_frac = float(np.clip((bearing.h_lim - h_min) / bearing.h_lim, 0.0, 1.0))
    mu_mixed = bearing.mu_boundary * mixed_frac**1.5
    return {
        "So": So,
        "eps": eps,
        "beta_deg": beta,
        "h_min": h_min,
        "mu_hydro": float(mu_hydro),
        "mu_mixed": mu_mixed,
        "mixed_frac": mixed_frac,
    }
