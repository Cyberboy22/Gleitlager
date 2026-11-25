/*
 * test_main.c - liest einen Pruefstands-Export (CSV) und gibt die Merkmale
 * aus, die der Mikrocontroller berechnen wuerde. Wird von
 * vergleich_python_c.py gegen die Python-Implementierung geprueft.
 *
 *   gcc -O2 -std=c99 -Wall -Wextra -o sipb_test test_main.c sipb_features.c -lm
 *   ./sipb_test ../results/beispiel_pruefstand.csv > c_features.csv
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sipb_config.h"
#include "sipb_features.h"

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Aufruf: %s datei.csv\n", argv[0]);
        return 1;
    }
    FILE *fp = fopen(argv[1], "r");
    if (!fp) { perror(argv[1]); return 1; }

    static sipb_state s;
    sipb_config_apply(&s);
    sipb_init(&s);
    fprintf(stderr, "sizeof(sipb_state) = %zu Byte RAM\n", sizeof(sipb_state));

    char line[4096];
    if (!fgets(line, sizeof line, fp)) return 1;  /* Kopfzeile */
    printf("zeit_s,Tmax,dTglob,prom,phi_hot,h_est_um,rate_max,drift,guembel_ok,n_bad,alarm\n");
    while (fgets(line, sizeof line, fp)) {
        float T[SIPB_N];
        char *p = line;
        double t = strtod(p, &p);
        for (int i = 0; i < SIPB_N; i++) { p++; T[i] = (float)strtod(p, &p); }
        sipb_features f;
        sipb_update(&s, T, &f);
        printf("%.2f,%.5f,%.5f,%.5f,%.5f,%.5f,%.6f,%.7f,%d,%d,%d\n", t, f.Tmax, f.dTglob, f.prom,
               f.phi_hot, f.h_est_um, f.rate_max, f.drift, f.guembel_ok, f.n_bad, f.alarm);
    }
    fclose(fp);
    return 0;
}
