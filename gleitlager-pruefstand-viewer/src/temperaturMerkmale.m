function m = temperaturMerkmale(T, phi, cfg)
%TEMPERATURMERKMALE Kennwerte des Temperaturfelds je Messung.
%   m = temperaturMerkmale(T, phi, cfg)
%     T    n x S Temperaturen [degC], phi 1 x S Sensorwinkel [deg]
%   Felder (je n x 1):
%     Tmax, Tmin, Tmean, Tmed
%     dTglob   globaler Gradient T_max - T_min [K]
%     prom     Auspraegung des Hotspots T_max - Median [K]
%     phi_hot  Winkel des Maximums, Parabel durch 3 Punkte [deg]
%     hot_ok   Hotspot liegt nicht am Rand und ist deutlich (>= min_prominenz)
%
%   Der Hotspot-Winkel ist die Eingangsgroesse der Guembel-Methode
%   (Winkel des Temperaturmaximums -> Verlagerungswinkel -> Spalthoehe).

if nargin < 3 || isempty(cfg)
    cfg = konfiguration();
end
phi = phi(:)';
[n, S] = size(T);
[m.Tmax, imax] = max(T, [], 2);
m.Tmin = min(T, [], 2);
m.Tmean = mean(T, 2);
m.Tmed = median(T, 2);
m.dTglob = m.Tmax - m.Tmin;
m.prom = m.Tmax - m.Tmed;
m.phi_hot = phi(imax)';
m.hot_ok = false(n, 1);

innen = imax > 1 & imax < S;
idx = find(innen);
if ~isempty(idx)
    i = imax(idx);
    lin = @(r, c) r + (c - 1) * n;
    y0 = T(lin(idx, i - 1));
    y1 = T(lin(idx, i));
    y2 = T(lin(idx, i + 1));
    nenner = y0 - 2 * y1 + y2;
    ok = nenner < 0;
    delta = zeros(size(idx));
    delta(ok) = 0.5 * (y0(ok) - y2(ok)) ./ nenner(ok);
    abstand = phi(i + 1)' - phi(i)';
    m.phi_hot(idx(ok)) = phi(i(ok))' + delta(ok) .* abstand(ok);
    m.hot_ok(idx(ok)) = true;
end
m.hot_ok = m.hot_ok & m.prom >= cfg.merkmale.min_prominenz & all(isfinite(T), 2);
end
