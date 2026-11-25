function [seg, code] = segmentiere(t, v, p, cfg)
%SEGMENTIERE Zerlegt einen Versuch in Betriebsphasen.
%   [seg, code] = segmentiere(t, v, p, cfg)
%     t  Zeit [s], v Gleitgeschwindigkeit [m/s], p spez. Last [MPa] (darf
%     leer oder NaN sein), cfg aus konfiguration().
%
%   Phasen (code):
%     1 Stillstand    v < cfg.seg.v_still
%     2 Hochfahren    dv/dt >  a_rel * v_ref
%     3 Konstant      sonst
%     4 Runterfahren  dv/dt < -a_rel * v_ref
%     5 Lastwechsel   konstante Geschwindigkeit, aber |dp/dt| > dp_rel * p_ref
%   v_ref, p_ref = 95%-Quantil (robust gegen Ausreisser).
%
%   Kurze Abschnitte (< cfg.seg.t_min_s) werden dem Nachbarn zugeschlagen.
%
%   seg ist ein struct-Array mit nr, phase, code, zyklus, i_start, i_ende,
%   t_start, t_ende, dauer. code ist die Phase je Zeitpunkt.

if nargin < 4 || isempty(cfg)
    cfg = konfiguration();
end
t = t(:);
v = v(:);
if isempty(p)
    p = nan(size(t));
end
p = p(:);
n = numel(t);
if n < 2
    error('segmentiere:zuKurz', 'Zu wenige Messpunkte.');
end

dt = median(diff(t));
ng = max(1, round(cfg.seg.glaettung_s / dt));
vg = gleitMittel(v, ng);
pg = gleitMittel(p, ng);
% Ableitung ueber +-ng Messungen (statt Nachbarwerte): viel weniger Rauschen
dv = ableitung(vg, t, ng);
dp = ableitung(pg, t, ng);

v_ref = quantil(vg, 0.95);
p_ref = quantil(pg, 0.95);
a_thr = cfg.seg.a_rel * max(v_ref, eps);

code = 3 * ones(n, 1);
code(dv > a_thr) = 2;
code(dv < -a_thr) = 4;
if isfinite(p_ref) && p_ref > 0
    code(code == 3 & abs(dp) > cfg.seg.dp_rel * p_ref) = 5;
end
code(vg < cfg.seg.v_still | ~isfinite(vg)) = 1;

% kurze Abschnitte zusammenlegen, bis sich nichts mehr aendert
n_min = max(1, round(cfg.seg.t_min_s / dt));
for durchlauf = 1:50
    [a, e] = laeufe(code);
    kurz = find((e - a + 1) < n_min);
    if isempty(kurz) || numel(a) == 1
        break
    end
    % kuerzesten zuerst dem laengeren Nachbarn zuschlagen
    [~, o] = min(e(kurz) - a(kurz));
    j = kurz(o);
    if j == 1
        neu = code(a(2));
    elseif j == numel(a)
        neu = code(a(j - 1));
    elseif (e(j-1) - a(j-1)) >= (e(j+1) - a(j+1))
        neu = code(a(j - 1));
    else
        neu = code(a(j + 1));
    end
    code(a(j):e(j)) = neu;
end

namen = {'Stillstand', 'Hochfahren', 'Konstant', 'Runterfahren', 'Lastwechsel'};
[a, e] = laeufe(code);
zyklus = 0;
seg = struct('nr', {}, 'phase', {}, 'code', {}, 'zyklus', {}, 'i_start', {}, ...
             'i_ende', {}, 't_start', {}, 't_ende', {}, 'dauer', {});
for k = 1:numel(a)
    c = code(a(k));
    if c == 2 && (k == 1 || code(a(k-1)) == 1)
        zyklus = zyklus + 1;  % neuer Start-Stopp-Zyklus beginnt aus dem Stillstand
    end
    seg(k).nr = k;
    seg(k).phase = namen{c};
    seg(k).code = c;
    seg(k).zyklus = zyklus;
    seg(k).i_start = a(k);
    seg(k).i_ende = e(k);
    seg(k).t_start = t(a(k));
    seg(k).t_ende = t(e(k));
    seg(k).dauer = t(e(k)) - t(a(k));
end
end

% ========================================================================
function d = ableitung(y, t, h)
% Differenzenquotient ueber +-h Messungen, am Rand einseitig
n = numel(y);
i = (1:n)';
a = max(1, i - h);
b = min(n, i + h);
d = (y(b) - y(a)) ./ (t(b) - t(a));
d(b == a) = NaN;
end

function q = quantil(x, p)
x = sort(x(isfinite(x)));
if isempty(x)
    q = NaN;
    return
end
q = x(max(1, min(numel(x), round(p * numel(x)))));
end

function [a, e] = laeufe(code)
w = [true; diff(code) ~= 0];
a = find(w);
e = [a(2:end) - 1; numel(code)];
end
