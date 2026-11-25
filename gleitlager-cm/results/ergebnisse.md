# Ergebnisse

Alle Zahlen stammen aus **synthetischen** Daten (siehe README). Bewertet werden 10 frische Validierungsläufe je Szenario, die bei der Entwicklung der Regeln nicht verwendet wurden.

## Gümbel-Kalibrierung

70 quasistationäre Betriebspunkte (v = 0,4–2,5 m/s, p = 4–12 MPa, Öl 20/40/60 °C). Fehler der Spalthöhe nach Polynom 4. Ordnung: RMSE = 0.24 µm.

## Schwellen (aus gesunden Läufen, 0,14 Hz)

| Kriterium | Schwelle |
|---|---|
| K1 T_max | 74.9 °C |
| K2 globaler Gradient | 13.4 K |
| K3 Temperaturrate | 0.80 K/s |
| K4 Gümbel-Spalthöhe | 4.0 µm |
| K5 Drift | 0.19 K/min |

## Vergleich der Kriterien (0,14 Hz)

| Kriterium | Fehlalarme | erkannt | vor kritischem Zustand | Median Verzug ab Fehlerbeginn [s] | Median Vorwarnzeit [s] |
|---|---|---|---|---|---|
| K1_Tmax | 0 / 60 | 40 / 60 | 30 | 198 | 96 |
| K2_dTglob | 0 / 60 | 30 / 60 | 16 | 185 | 1 |
| K3_Rate | 0 / 60 | 30 / 60 | 0 | 201 | -12 |
| K4_Guembel | 0 / 60 | 30 / 60 | 20 | 123 | 45 |
| K5_Drift | 0 / 60 | 50 / 60 | 30 | 201 | 59 |
| Kombi | 0 / 60 | 60 / 60 | 40 | 127 | 62 |

Kombi = K3 oder K4 oder K5, mit Sensor-Plausibilitätsprüfung. Vorwarnzeit = Zeit vom Alarm bis zum kritischen Zustand (Reibmoment +50 % oder Mischreibung); negativ = Alarm kam zu spät.

## Kombi je Szenario

| Szenario | Läufe | Alarm | Fehlalarm | Median Vorwarnzeit [s] | Diagnose im Alarmmoment | Sensorfehler erkannt |
|---|---|---|---|---|---|---|
| abrasiv_20 | 10 | 10 | 0 | – | abrasiver Verschleiß: 10 | 0 |
| abrasiv_60 | 10 | 10 | 0 | 512 | abrasiver Verschleiß: 10 | 0 |
| lastwechsel_20 | 10 | 0 | 0 | – | – | 0 |
| mangel_20 | 10 | 10 | 0 | 102 | Schmierstoffmangel: 10 | 0 |
| mangel_60 | 10 | 10 | 0 | 62 | Schmierstoffmangel: 10 | 0 |
| sensorfehler_60 | 10 | 0 | 0 | – | – | 10 |
| start_stopp_20 | 10 | 0 | 0 | – | – | 0 |
| start_stopp_60 | 10 | 0 | 0 | – | – | 0 |
| start_stopp_mangel_60 | 10 | 10 | 0 | 45 | Schmierstoffmangel: 10 | 0 |
| stationaer_20 | 10 | 0 | 0 | – | – | 0 |
| stationaer_60 | 10 | 0 | 0 | – | – | 0 |
| ueberlast_60 | 10 | 10 | 0 | -8 | Mischreibung (Betriebszustand): 10 | 0 |

## Einfluss der Abtastrate (Kombi)

Schwellen werden je Abtastrate neu aus den gesunden Läufen bestimmt.

| Abtastrate [Hz] | Fehlalarme | Vorwarnzeit Mangel 60 [s] | Vorwarnzeit Start-Stopp+Mangel [s] | Vorwarnzeit Überlast [s] |
|---|---|---|---|---|
| 0.14 | 0 | 62 | 45 | -8 |
| 0.5 | 0 | 57 | 31 | -10 |
| 1.0 | 0 | 59 | 40 | -8 |
| 2.0 | 0 | 59 | 36 | -8 |
| 8.92 | 0 | 59 | 32 | -9 |

## Einfluss der Sensoranzahl (0,14 Hz)

Gümbel-Polynom auf der Hälfte der Kalibrierpunkte angepasst, auf der anderen Hälfte getestet.

| Sensoren | Abstand [°] | RMSE Spalthöhe Kalibrierpunkte [µm] | RMSE Spalthöhe in Fehlerläufen [µm] | Fehlalarme | Vorwarnzeit Mangel 60 [s] | Vorwarnzeit Überlast [s] |
|---|---|---|---|---|---|---|
| 24 | 7.5 | 0.27 | 0.44 | 0 | 64 | -8 |
| 12 | 15.0 | 0.16 | 0.29 | 0 | 59 | -8 |
| 8 | 22.5 | 0.13 | 0.38 | 0 | 66 | -8 |
| 6 | 30.0 | 0.13 | 0.43 | 0 | 65 | -8 |
| 4 | 45.0 | 0.15 | 0.33 | 0 | 99 | -6 |
