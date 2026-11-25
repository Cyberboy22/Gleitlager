/*
 * sipb_features.h - Merkmale und Alarmlogik fuer ein temperaturfeldbasiertes
 * sensorintegrierendes Gleitlager, ausgelegt fuer einen Mikrocontroller.
 *
 * - nur float (single precision, passt zu Cortex-M4F)
 * - kein malloc, fester Speicher (sizeof(sipb_state) siehe test_main)
 * - pro Messung ein Aufruf von sipb_update()
 *
 * Gleiche Rechenschritte wie sipb/features.py, wird gegen Python getestet.
 */
#ifndef SIPB_FEATURES_H
#define SIPB_FEATURES_H

#include <stdint.h>

#define SIPB_N 24          /* Anzahl Temperatursensoren */
#define SIPB_MAX_HIST 128  /* max. Laenge der Ringpuffer (600 s bei 0,2 Hz) */

typedef struct {
    /* Konfiguration (aus Kalibrierung, siehe sipb_config.h) */
    float phi[SIPB_N];       /* Sensorwinkel [deg] */
    float offset[SIPB_N];    /* Sensor-Offsets [K] */
    float guembel[5];        /* eps(phi) = g0*phi^4 + ... + g4 */
    float phi_lo, phi_hi;    /* Gueltigkeitsbereich des Polynoms [deg] */
    float clearance_um;      /* radiales Lagerspiel psi*R [um] */
    float Ts;                /* Abtastzeit [s] */
    float th_rate, th_h_um, th_drift, min_prom;
    float jump, ratio;       /* Plausibilitaetspruefung */

    /* abgeleitete Fensterlaengen in Messungen */
    uint16_t m_rate, m_qs, n_drift, n_persist;

    /* Zustand */
    float prev[SIPB_N];
    uint8_t has_prev;
    uint8_t bad[SIPB_N];
    float tmax_hist[SIPB_MAX_HIST];
    float tmean_hist[SIPB_MAX_HIST];
    uint8_t cond_hist[SIPB_MAX_HIST];
    uint32_t k;              /* Anzahl bisheriger Messungen */
    uint8_t alarm_latched;
} sipb_state;

typedef struct {
    float Tmax, Tmin, Tmean, Tmed, dTglob, prom;
    float phi_hot, h_est_um;
    float rate_max;          /* K/s, NAN solange Historie fehlt */
    float drift;             /* K/s, NAN solange Historie fehlt */
    uint8_t hot_ok, quasi_stat, guembel_ok;
    uint8_t n_bad;
    uint8_t k3, k4, k5;      /* Einzelkriterien in dieser Messung */
    uint8_t alarm;           /* Kombi-Alarm (mit Haltezeit) */
} sipb_features;

void sipb_init(sipb_state *s);
void sipb_update(sipb_state *s, const float T_raw[SIPB_N], sipb_features *out);

#endif
