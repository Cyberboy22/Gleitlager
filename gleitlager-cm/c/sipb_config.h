/* automatisch erzeugt von vergleich_python_c.py - nicht von Hand aendern */
#ifndef SIPB_CONFIG_H
#define SIPB_CONFIG_H
#include "sipb_features.h"

static const float SIPB_PHI[SIPB_N] = {9.750000000e+01f, 1.050000000e+02f, 1.125000000e+02f, 1.200000000e+02f, 1.275000000e+02f, 1.350000000e+02f, 1.425000000e+02f, 1.500000000e+02f, 1.575000000e+02f, 1.650000000e+02f, 1.725000000e+02f, 1.800000000e+02f, 1.875000000e+02f, 1.950000000e+02f, 2.025000000e+02f, 2.100000000e+02f, 2.175000000e+02f, 2.250000000e+02f, 2.325000000e+02f, 2.400000000e+02f, 2.475000000e+02f, 2.550000000e+02f, 2.625000000e+02f, 2.700000000e+02f};
static const float SIPB_OFFSET[SIPB_N] = {-8.125000000e-03f, 2.271875000e-01f, 2.552083333e-01f, 9.500000000e-02f, 1.113541667e-01f, -2.385416667e-02f, -9.031250000e-02f, -8.552083333e-02f, -1.020833333e-01f, 1.847916667e-01f, 4.229166667e-02f, 6.697916667e-02f, -4.760416667e-02f, -1.118750000e-01f, -1.303125000e-01f, -7.864583333e-02f, 1.368750000e-01f, 5.166666667e-02f, -2.000000000e-02f, 8.125000000e-03f, -1.645833333e-01f, 2.320833333e-01f, -1.344791667e-01f, 5.520833333e-02f};
static const float SIPB_GUEMBEL[5] = {-1.452402436e-03f, 1.973567207e-03f, -2.120063968e-02f, -1.234796508e-01f, 8.651280794e-01f};

static inline void sipb_config_apply(sipb_state *s) {
    for (int i = 0; i < SIPB_N; i++) { s->phi[i] = SIPB_PHI[i]; s->offset[i] = SIPB_OFFSET[i]; }
    for (int i = 0; i < 5; i++) s->guembel[i] = SIPB_GUEMBEL[i];
    s->phi_lo = 1.995171407e+02f;
    s->phi_hi = 2.243415854e+02f;
    s->clearance_um = 7.000200000e+01f;
    s->Ts = 7.142857143e+00f;
    s->th_rate = 8.048750000e-01f;
    s->th_h_um = 4.000000000e+00f;
    s->th_drift = 3.086067616e-03f;
    s->min_prom = 1.5f;
    s->jump = 1.500000000e+00f;
    s->ratio = 2.500000000e-01f;
    s->m_rate = 1;
    s->m_qs = 8;
    s->n_drift = 84;
    s->n_persist = 1;
}
#endif
