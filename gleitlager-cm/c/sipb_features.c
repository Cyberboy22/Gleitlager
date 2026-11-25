/*
 * sipb_features.c - siehe sipb_features.h
 */
#include "sipb_features.h"

#include <math.h>
#include <string.h>

static void sort_small(float *a, int n) {
    for (int i = 1; i < n; i++) {
        float x = a[i];
        int j = i - 1;
        while (j >= 0 && a[j] > x) { a[j + 1] = a[j]; j--; }
        a[j + 1] = x;
    }
}

static float median_small(const float *v, int n) {
    float a[SIPB_N];
    memcpy(a, v, (size_t)n * sizeof(float));
    sort_small(a, n);
    return (n % 2) ? a[n / 2] : 0.5f * (a[n / 2 - 1] + a[n / 2]);
}

static float hist_get(const float *h, uint32_t k) { return h[k % SIPB_MAX_HIST]; }

void sipb_init(sipb_state *s) {
    s->has_prev = 0;
    s->k = 0;
    s->alarm_latched = 0;
    memset(s->bad, 0, sizeof(s->bad));
}

/* Sensor springt allein, Nachbarn nicht -> Sensorfehler (kein Lagerschaden) */
static void plausibility(sipb_state *s, const float *T) {
    if (s->has_prev) {
        float d[SIPB_N];
        uint8_t cand[SIPB_N];
        for (int i = 0; i < SIPB_N; i++) {
            d[i] = T[i] - s->prev[i];
            cand[i] = !s->bad[i] && fabsf(d[i]) > s->jump;
        }
        for (int i = 0; i < SIPB_N; i++) {
            if (!cand[i]) continue;
            float nb[4];
            int n = 0;
            for (int o = -2; o <= 2; o++) {
                int j = i + o;
                if (o == 0 || j < 0 || j >= SIPB_N || s->bad[j]) continue;
                nb[n++] = d[j];
            }
            if (n > 0 && fabsf(median_small(nb, n)) < s->ratio * fabsf(d[i])) s->bad[i] = 1;
        }
    }
    memcpy(s->prev, T, sizeof(s->prev));
    s->has_prev = 1;
}

/* defekte Sensoren linear aus den guten interpolieren (am Rand konstant) */
static void repair(const sipb_state *s, float *T) {
    for (int i = 0; i < SIPB_N; i++) {
        if (!s->bad[i]) continue;
        int lo = -1, hi = -1;
        for (int j = i - 1; j >= 0; j--) if (!s->bad[j]) { lo = j; break; }
        for (int j = i + 1; j < SIPB_N; j++) if (!s->bad[j]) { hi = j; break; }
        if (lo < 0 && hi < 0) continue;
        if (lo < 0) { T[i] = T[hi]; continue; }
        if (hi < 0) { T[i] = T[lo]; continue; }
        float w = (s->phi[i] - s->phi[lo]) / (s->phi[hi] - s->phi[lo]);
        T[i] = T[lo] + w * (T[hi] - T[lo]);
    }
}

static float guembel_h_um(const sipb_state *s, float phi_hot) {
    float c = 0.5f * (s->phi_lo + s->phi_hi), sc = 0.5f * (s->phi_hi - s->phi_lo);
    float p = phi_hot < s->phi_lo ? s->phi_lo : (phi_hot > s->phi_hi ? s->phi_hi : phi_hot);
    float x = (p - c) / sc;
    float eps = s->guembel[0];
    for (int i = 1; i < 5; i++) eps = eps * x + s->guembel[i];  /* Horner */
    if (eps < 0.0f) eps = 0.0f;
    if (eps > 0.999f) eps = 0.999f;
    return s->clearance_um * (1.0f - eps);
}

void sipb_update(sipb_state *s, const float T_raw[SIPB_N], sipb_features *f) {
    float T[SIPB_N];
    for (int i = 0; i < SIPB_N; i++) T[i] = T_raw[i] - s->offset[i];

    plausibility(s, T);
    f->n_bad = 0;
    for (int i = 0; i < SIPB_N; i++) f->n_bad += s->bad[i];
    repair(s, T);

    /* Statistik des Feldes */
    int imax = 0;
    float tmin = T[0], sum = 0.0f;
    for (int i = 0; i < SIPB_N; i++) {
        if (T[i] > T[imax]) imax = i;
        if (T[i] < tmin) tmin = T[i];
        sum += T[i];
    }
    f->Tmax = T[imax];
    f->Tmin = tmin;
    f->Tmean = sum / SIPB_N;
    f->Tmed = median_small(T, SIPB_N);
    f->dTglob = f->Tmax - f->Tmin;
    f->prom = f->Tmax - f->Tmed;

    /* Hotspot per Parabel durch 3 Punkte */
    f->phi_hot = s->phi[imax];
    f->hot_ok = 0;
    if (imax > 0 && imax < SIPB_N - 1) {
        float y0 = T[imax - 1], y1 = T[imax], y2 = T[imax + 1];
        float den = y0 - 2.0f * y1 + y2;
        if (den < 0.0f) {
            float delta = 0.5f * (y0 - y2) / den;
            f->phi_hot = s->phi[imax] + delta * (s->phi[imax + 1] - s->phi[imax]);
            f->hot_ok = 1;
        }
    }
    f->h_est_um = guembel_h_um(s, f->phi_hot);

    /* Historie */
    uint32_t k = s->k;
    s->tmax_hist[k % SIPB_MAX_HIST] = f->Tmax;
    s->tmean_hist[k % SIPB_MAX_HIST] = f->Tmean;

    f->rate_max = NAN;
    if (k >= s->m_rate)
        f->rate_max = (f->Tmax - hist_get(s->tmax_hist, k - s->m_rate)) / (s->m_rate * s->Ts);

    f->quasi_stat = 0;
    if (k >= s->m_qs)
        f->quasi_stat = fabsf((f->Tmean - hist_get(s->tmean_hist, k - s->m_qs)) / (s->m_qs * s->Ts)) < 0.03f;

    /* Steigung der Ausgleichsgeraden ueber n_drift Messungen */
    f->drift = NAN;
    uint16_t n = s->n_drift;
    if (k + 1 >= n) {
        float cmid = 0.5f * (float)(n - 1), st2 = 0.0f, acc = 0.0f;
        for (uint16_t j = 0; j < n; j++) {
            float t = ((float)j - cmid) * s->Ts;
            st2 += t * t;
            acc += t * hist_get(s->tmean_hist, k - n + 1 + j);
        }
        f->drift = acc / st2;
    }

    f->guembel_ok = f->hot_ok && f->prom > s->min_prom && f->quasi_stat;

    /* Einzelkriterien (NAN-Vergleiche sind immer falsch) */
    f->k3 = f->rate_max > s->th_rate;
    f->k4 = f->guembel_ok && f->h_est_um < s->th_h_um;
    f->k5 = f->drift > s->th_drift;
    s->cond_hist[k % SIPB_MAX_HIST] = (uint8_t)(f->k3 | (f->k4 << 1) | (f->k5 << 2));

    /* Haltezeit: Kriterium in >= 80 % der letzten n_persist Messungen */
    f->alarm = s->alarm_latched;
    if (!s->alarm_latched && k + 1 >= s->n_persist) {
        for (int b = 0; b < 3; b++) {
            if (!((s->cond_hist[k % SIPB_MAX_HIST] >> b) & 1)) continue;
            int hits = 0;
            for (uint16_t j = 0; j < s->n_persist; j++)
                hits += (s->cond_hist[(k - j) % SIPB_MAX_HIST] >> b) & 1;
            if (hits >= 0.8f * s->n_persist) { s->alarm_latched = 1; f->alarm = 1; }
        }
    }
    s->k = k + 1;
}
