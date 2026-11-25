function seg = segmentStatistik(versuch, seg, m)
%SEGMENTSTATISTIK Kennwerte je Abschnitt aus Temperatur- und Pruefstandsdaten.
%   seg = segmentStatistik(versuch, seg, m) ergaenzt jedes Element von seg um
%     n_T            Anzahl Temperaturmessungen im Abschnitt
%     Tmax_max       hoechste Lagertemperatur [degC]
%     Tmax_mittel    mittlere Maximaltemperatur [degC]
%     dTglob_mittel  mittlerer globaler Gradient [K]
%     phi_hot_median Hotspot-Winkel, nur deutliche Hotspots [deg]
%     v_mittel, p_mittel, M_mittel, M_max, T_oel_mittel (Pruefstand)
%   Fehlt etwas, steht NaN.

for k = 1:numel(seg)
    ta = seg(k).t_start;
    te = seg(k).t_ende;
    inT = versuch.t_T >= ta & versuch.t_T <= te;
    seg(k).n_T = sum(inT);
    seg(k).Tmax_max = maxNaN(m.Tmax(inT));
    seg(k).Tmax_mittel = mittelNaN(m.Tmax(inT));
    seg(k).dTglob_mittel = mittelNaN(m.dTglob(inT));
    seg(k).phi_hot_median = medianNaN(m.phi_hot(inT & m.hot_ok));

    inP = versuch.t_P >= ta & versuch.t_P <= te;
    seg(k).v_mittel = mittelNaN(versuch.P.v(inP));
    seg(k).p_mittel = mittelNaN(versuch.P.p(inP));
    seg(k).M_mittel = mittelNaN(versuch.P.M(inP));
    seg(k).M_max = maxNaN(versuch.P.M(inP));
    seg(k).T_oel_mittel = mittelNaN(versuch.P.T_oel(inP));
end
end

function y = mittelNaN(x)
x = x(isfinite(x));
if isempty(x), y = NaN; else, y = mean(x); end
end

function y = maxNaN(x)
x = x(isfinite(x));
if isempty(x), y = NaN; else, y = max(x); end
end

function y = medianNaN(x)
x = x(isfinite(x));
if isempty(x), y = NaN; else, y = median(x); end
end
