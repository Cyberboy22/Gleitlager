function [versuch, seg, m] = analysiereVersuch(versuch, cfg)
%ANALYSIEREVERSUCH Komplette Aufbereitung eines geladenen Versuchs.
%   [versuch, seg, m] = analysiereVersuch(versuch, cfg)
%     1. Pruefstandsdaten auf die Temperaturzeitpunkte legen (synchronisiere)
%     2. Temperaturmerkmale je Messung (temperaturMerkmale)
%     3. Betriebsphasen aus Geschwindigkeit und Last (segmentiere)
%     4. Kennwerte je Abschnitt (segmentStatistik)
%   Ohne Geschwindigkeitssignal wird der ganze Versuch ein Abschnitt.

if nargin < 2 || isempty(cfg)
    cfg = konfiguration();
end
versuch = synchronisiere(versuch);
m = temperaturMerkmale(versuch.T, versuch.phi, cfg);

if numel(versuch.t_P) >= 2 && any(isfinite(versuch.P.v))
    seg = segmentiere(versuch.t_P, versuch.P.v, versuch.P.p, cfg);
    versuch.seg_zeitbasis = 'pruefstand';
else
    t = versuch.t_T;
    seg = struct('nr', 1, 'phase', 'Gesamt (ohne Pruefstandsdaten)', 'code', 0, ...
                 'zyklus', 0, 'i_start', 1, 'i_ende', numel(t), 't_start', t(1), ...
                 't_ende', t(end), 'dauer', t(end) - t(1));
    versuch.seg_zeitbasis = 'temperatur';
end
seg = segmentStatistik(versuch, seg, m);
end
