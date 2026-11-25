function cfg = konfiguration()
%KONFIGURATION Standardeinstellungen fuer Import, Segmentierung und Viewer.
%   cfg = konfiguration() liefert ein struct, das man vor dem Aufruf von
%   ladeVersuch / segmentiere anpassen kann, z.B.
%       cfg = konfiguration();
%       cfg.import.zeitversatz_s = -12;   % SiPB-Uhr geht 12 s vor
%       versuch = ladeVersuch('beispieldaten/V03_...', cfg);

% --- Lager (Pruefstandslager aus Baszenski et al. 2025) -----------------
cfg.lager.D = 0.120;                       % Innendurchmesser [m]
cfg.lager.B = 0.030;                       % Breite [m]
cfg.lager.phi = linspace(97.5, 270, 24);   % Sensorwinkel [deg]

% --- Import ---------------------------------------------------------------
cfg.import.datei_sipb = 'sipb*.csv';             % Lagertemperaturen
cfg.import.datei_pruefstand = 'pruefstand*.csv'; % Pruefstandsdaten
cfg.import.zeitversatz_s = 0;   % wird auf die SiPB-Zeit addiert
cfg.import.offsets = [];        % Sensor-Offsets [K] (1x24), leer = keine

% Spaltenerkennung ueber regulaere Ausdruecke (Gross/Klein egal).
% Erste passende Spalte gewinnt. Bei eigenen Exporten hier anpassen.
cfg.spalten.zeit = '^((zeit|time).*|t(\s*\[s\]|_s)?)$';
cfg.spalten.temperatur = '^(t|temp|temperatur)[\s_]*0*(\d+)';  % T01, T1, Temp_01
cfg.spalten.v = '^(v|gleitgeschw|geschw|speed)([\s_\[]|$)';
cfg.spalten.n = '(drehzahl|rpm|^n([\s_\[]|$))';
cfg.spalten.p = '^(p|spez|flaechenpressung|pressure)([\s_\[]|$)';
cfg.spalten.F = '(kraft|force|^f([\s_\[]|$))';
cfg.spalten.M = '(reib|torque|moment|^m([\s_\[]|$))';
cfg.spalten.T_oel = '(oel|oil|zulauf|ltemp)';

% --- Segmentierung der Betriebsphasen -----------------------------------
cfg.seg.glaettung_s = 1.0;   % gleitender Mittelwert vor der Ableitung [s]
cfg.seg.v_still = 0.05;      % darunter: Stillstand [m/s]
cfg.seg.a_rel = 0.01;        % Beschleunigungsschwelle relativ zu v_ref [1/s]
cfg.seg.dp_rel = 0.002;      % Lastaenderungsschwelle relativ zu p_ref [1/s]
cfg.seg.t_min_s = 3.0;       % kuerzere Abschnitte werden zusammengelegt [s]

% --- Merkmale -------------------------------------------------------------
cfg.merkmale.min_prominenz = 1.0;  % Hotspot muss so deutlich sein [K]

% --- Export ---------------------------------------------------------------
cfg.export.ordner = 'export';
end
