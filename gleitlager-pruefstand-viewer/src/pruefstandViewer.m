function fig = pruefstandViewer(varargin)
%PRUEFSTANDVIEWER Interaktive Ansicht eines Gleitlager-Versuchs.
%   pruefstandViewer('beispieldaten/V01_...')        Ordner laden und anzeigen
%   pruefstandViewer(ordner, cfg)                     mit eigener Konfiguration
%   pruefstandViewer(versuch, seg, m)                 bereits analysierter Versuch
%   pruefstandViewer(versuch, seg, m, cfg)
%   ... , 'ereignisDatei', datei, 'exportOrdner', ordner, 'sichtbar', false
%
%   Links:  Temperaturfeld (Zeit x Umfangswinkel), Gleitgeschwindigkeit
%           (eingefaerbt nach Betriebsphase), Last, Reibmoment, Hotspot-Winkel.
%   Rechts: Temperaturprofil am Cursor, aktuelle Werte, Abschnittstabelle,
%           Knoepfe fuer Ereignisse, Export und Bild.
%   Bedienung:
%     Klick in ein Diagramm oder Schieberegler -> Cursor setzen
%     Pfeiltasten links/rechts                  -> vorherige/naechste Messung
%     Zeile in der Tabelle anklicken             -> auf den Abschnitt zoomen

cfg = konfiguration();
if ischar(varargin{1})
    ordner = varargin{1};
    rest = varargin(2:end);
    if ~isempty(rest) && isstruct(rest{1})
        cfg = rest{1};
        rest = rest(2:end);
    end
    versuch = ladeVersuch(ordner, cfg);
    [versuch, seg, m] = analysiereVersuch(versuch, cfg);
    optionen = struct('ereignisDatei', fullfile(ordner, 'ereignisse.csv'), ...
                      'exportOrdner', fullfile(ordner, cfg.export.ordner), 'sichtbar', true);
else
    versuch = varargin{1};
    seg = varargin{2};
    m = varargin{3};
    rest = varargin(4:end);
    if ~isempty(rest) && isstruct(rest{1})
        cfg = rest{1};
        rest = rest(2:end);
    end
    optionen = struct('ereignisDatei', 'ereignisse.csv', ...
                      'exportOrdner', cfg.export.ordner, 'sichtbar', true);
end
for k = 1:2:numel(rest)
    optionen.(rest{k}) = rest{k + 1};
end
if ~isfield(versuch, 'P_aufT')
    versuch = synchronisiere(versuch);
end

F = farben();
S.versuch = versuch;
S.seg = seg;
S.m = m;
S.cfg = cfg;
S.opt = optionen;
S.ev = ereignisse('laden', optionen.ereignisDatei);
S.k = 1;   % Index der aktuellen Temperaturmessung

if optionen.sichtbar
    sicht = 'on';
else
    sicht = 'off';
end
fig = figure('Name', ['Prüfstands-Viewer - ', strrep(versuch.name, '_', ' ')], ...
             'NumberTitle', 'off', 'Color', F.surface, 'Units', 'pixels', ...
             'Position', [60 60 1480 860], 'Visible', sicht, 'KeyPressFcn', @taste);

% ------------------------------------------------------------ Zeitachsen links
links = 0.055; breite = 0.585;
pos = {[links 0.600 breite 0.355], [links 0.475 breite 0.105], [links 0.360 breite 0.105], ...
       [links 0.245 breite 0.105], [links 0.130 breite 0.105]};
ax = leereHandles(5);
for i = 1:5
    ax(i) = axes('Parent', fig, 'Position', pos{i}, 'Color', F.surface, 'XColor', F.ink2, ...
                 'YColor', F.ink2, 'Box', 'off', 'TickDir', 'out', 'FontSize', 9, ...
                 'ButtonDownFcn', @klickZeit);
    hold(ax(i), 'on');
    if i > 1
        grid(ax(i), 'on');
        set(ax(i), 'GridColor', F.grid, 'GridAlpha', 1);
    end
    if i < 5
        set(ax(i), 'XTickLabel', {});
    end
end
t = versuch.t_T;
tP = versuch.t_P;

% Temperaturfeld
% imagesc braucht gleichmaessige Zeitschritte; bei Luecken fuer die Anzeige
% auf ein gleichmaessiges Raster legen (naechster Messwert, Luecken bleiben leer)
[tBild, TBild] = gleichmaessig(t, versuch.T);
hImg = imagesc(tBild, versuch.phi, TBild', 'Parent', ax(1));
set(hImg, 'ButtonDownFcn', @klickZeit);
set(ax(1), 'YDir', 'normal', 'Layer', 'top');
colormap(ax(1), F.sequenziell);
alleT = sort(versuch.T(isfinite(versuch.T)));
if numel(alleT) > 1
    clim = [alleT(1), alleT(max(1, round(0.98 * numel(alleT))))];
    if clim(2) > clim(1)
        set(ax(1), 'CLim', clim);
    end
end
cb = colorbar(ax(1));
set(cb, 'Color', F.ink2);
% Farbskala neben die Achse legen, damit alle Zeitachsen gleich breit bleiben
set(ax(1), 'Position', pos{1});
set(cb, 'Position', [links + breite + 0.008, pos{1}(2), 0.012, pos{1}(4)]);
set(ax(1), 'Position', pos{1});
ylabel(cb, 'Temperatur [\circC]');
ylabel(ax(1), 'Umfangswinkel [\circ]');
title(ax(1), ['Temperaturfeld: ', strrep(versuch.name, '_', ' ')], 'Color', F.ink, ...
      'FontWeight', 'bold', 'Interpreter', 'none');
ylim(ax(1), [versuch.phi(1) - 4, versuch.phi(end) + 4]);
% Hotspot-Winkel im Feld (nur deutliche Hotspots)
ok = m.hot_ok;
plot(ax(1), t(ok), m.phi_hot(ok), '.', 'Color', F.ink, 'MarkerSize', 5, 'HitTest', 'off');

% Gleitgeschwindigkeit, eingefaerbt nach Phase
namen = {'Stillstand', 'Hochfahren', 'Konstant', 'Runterfahren', 'Lastwechsel'};
hLeg = leereHandles(0);
legText = {};
if ~isempty(tP) && any(isfinite(versuch.P.v))
    for k = 1:numel(seg)
        in = tP >= seg(k).t_start & tP <= seg(k).t_ende;
        c = F.phase(max(1, seg(k).code), :);
        h = plot(ax(2), tP(in), versuch.P.v(in), '-', 'Color', c, 'LineWidth', 1.5, 'HitTest', 'off');
        if seg(k).code >= 1 && ~any(strcmp(legText, namen{seg(k).code}))
            hLeg(end + 1) = h; %#ok<AGROW>
            legText{end + 1} = namen{seg(k).code}; %#ok<AGROW>
        end
    end
    [~, o] = sort(cellfun(@(s) find(strcmp(namen, s)), legText));
    lg = legend(ax(2), hLeg(o), legText(o), 'Orientation', 'horizontal', 'Location', 'northwest');
    set(lg, 'AutoUpdate', 'off');  % Cursor- und Ereignislinien nicht in die Legende
    vmax = max(versuch.P.v(isfinite(versuch.P.v)));
    if vmax > 0, ylim(ax(2), [0, 1.45 * vmax]); end
    set(lg, 'Box', 'off', 'TextColor', F.ink2, 'FontSize', 8);
    plot(ax(3), tP, versuch.P.p, '-', 'Color', F.blau, 'LineWidth', 1.2, 'HitTest', 'off');
    plot(ax(4), tP, versuch.P.M, '-', 'Color', F.blau, 'LineWidth', 1.2, 'HitTest', 'off');
else
    text(0.5, 0.5, 'keine Prüfstandsdaten', 'Parent', ax(2), 'Units', 'normalized', ...
         'HorizontalAlignment', 'center', 'Color', F.ink2);
end
ylabel(ax(2), 'v [m/s]');
ylabel(ax(3), 'p [MPa]');
ylabel(ax(4), 'M_R [Nm]');
plot(ax(5), t(ok), m.phi_hot(ok), 'o', 'Color', F.blau, 'MarkerFaceColor', F.blau, ...
     'MarkerSize', 3, 'HitTest', 'off');
ylabel(ax(5), '\phi_{hot} [\circ]');
xlabel(ax(5), 'Zeit [s]');
tmin = min([t; tP]);
tmax = max([t; tP]);
linkaxes(ax, 'x');
xlim(ax(1), [tmin, tmax]);

% Cursor-Linien und Ereignisse
hCur = leereHandles(5);
for i = 1:5
    yl = get(ax(i), 'YLim');
    hCur(i) = plot(ax(i), [t(1) t(1)], yl, '-', 'Color', F.ink, 'LineWidth', 1, 'HitTest', 'off');
end
S.hEv = leereHandles(0);

% Schieberegler
hSl = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
                'Position', [links 0.035 breite 0.025], 'Min', 1, 'Max', max(2, numel(t)), ...
                'Value', 1, 'SliderStep', [1, 10] / max(1, numel(t) - 1), 'Callback', @schieber);

% ------------------------------------------------------------ rechte Seite
r0 = 0.70; rb = 0.28;
axP = axes('Parent', fig, 'Position', [r0 + 0.03 0.635 rb - 0.03 0.30], 'Color', F.surface, ...
           'XColor', F.ink2, 'YColor', F.ink2, 'Box', 'off', 'FontSize', 9);
hold(axP, 'on');
grid(axP, 'on');
set(axP, 'GridColor', F.grid, 'GridAlpha', 1);
xlabel(axP, 'Umfangswinkel [\circ]');
ylabel(axP, 'T [\circC]');
% feste y-Achse (gleiche Skala wie das Farbfeld), damit man Profile vergleichen kann;
% sie waechst nur, wenn ein Profil darueber hinausgeht (z.B. kurz vor einem Fresser)
S.yProfil = get(ax(1), 'CLim') + [-0.5 0.5];
set(axP, 'XLim', [versuch.phi(1) - 5, versuch.phi(end) + 5], 'YLim', S.yProfil);
yr = S.yProfil;
hProfil = plot(axP, versuch.phi, versuch.T(1, :), '-o', 'Color', F.blau, ...
               'MarkerFaceColor', F.blau, 'MarkerSize', 4, 'LineWidth', 1.5);
hHot = plot(axP, [NaN NaN], yr, '--', 'Color', F.orange, 'LineWidth', 1.2);
hTitelP = title(axP, '', 'Color', F.ink, 'FontWeight', 'bold');

hInfo = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', 'Position', [r0 0.505 rb 0.085], ...
                  'BackgroundColor', F.surface, 'ForegroundColor', F.ink, 'FontSize', 9, ...
                  'HorizontalAlignment', 'left', 'String', '');

daten = tabellenDaten(seg);
hTab = uitable(fig, 'Units', 'normalized', 'Position', [r0 0.195 rb 0.30], 'Data', daten, ...
               'ColumnName', {'Nr', 'Phase', 'Zyklus', 'Start [s]', 'Dauer [s]', 'Tmax [°C]', 'M [Nm]'}, ...
               'ColumnWidth', {32, 92, 46, 62, 60, 62, 52}, ...
               'RowName', [], 'CellSelectionCallback', @tabelleGewaehlt, 'FontSize', 9);

bw = (rb - 0.02) / 3;
knopf = @(txt, x, y, cb) uicontrol(fig, 'Style', 'pushbutton', 'String', txt, 'Units', 'normalized', ...
                                   'Position', [x y bw 0.045], 'Callback', cb, 'FontSize', 9);
knopf('Ganzer Versuch', r0, 0.13, @(h, e) zoomen(tmin, tmax));
knopf('Ereignis markieren', r0 + bw + 0.01, 0.13, @ereignisMarkieren);
knopf('Bild speichern', r0 + 2 * (bw + 0.01), 0.13, @bildSpeichern);
knopf('Abschnitt exportieren', r0, 0.075, @abschnittExport);
knopf('Alles exportieren', r0 + bw + 0.01, 0.075, @allesExport);
knopf('Excel-Format (DE)', r0 + 2 * (bw + 0.01), 0.075, @(h, e) allesExport(h, e, true));
hStatus = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', 'Position', [r0 0.02 rb 0.045], ...
                    'BackgroundColor', F.surface, 'ForegroundColor', F.ink2, 'FontSize', 8, ...
                    'HorizontalAlignment', 'left', 'String', hinweisText());

S.ax = ax; S.axP = axP; S.hCur = hCur; S.hSl = hSl; S.hProfil = hProfil; S.hHot = hHot;
S.hTitelP = hTitelP; S.hInfo = hInfo; S.hTab = hTab; S.hStatus = hStatus; S.F = F;
guidata(fig, S);
zeichneEreignisse();
setzeCursor(1);

% ======================================================== verschachtelte Funktionen
    function setzeCursor(k)
        S = guidata(fig);
        k = max(1, min(numel(S.versuch.t_T), round(k)));
        S.k = k;
        tk = S.versuch.t_T(k);
        for j = 1:5
            yl = get(S.ax(j), 'YLim');
            set(S.hCur(j), 'XData', [tk tk], 'YData', yl);
        end
        set(S.hSl, 'Value', k);
        set(S.hProfil, 'YData', S.versuch.T(k, :));
        yl = S.yProfil;
        yl(2) = max(yl(2), max(S.versuch.T(k, :)) + 0.5);
        set(S.axP, 'YLim', yl);
        if S.m.hot_ok(k)
            set(S.hHot, 'XData', [1 1] * S.m.phi_hot(k), 'YData', get(S.axP, 'YLim'));
        else
            set(S.hHot, 'XData', [NaN NaN]);
        end
        sk = abschnittBei(tk);
        if isempty(sk)
            ph = '-';
        else
            ph = sprintf('%s (Abschnitt %d)', S.seg(sk).phase, S.seg(sk).nr);
        end
        set(S.hTitelP, 'String', sprintf('Profil bei t = %.1f s', tk));
        P = S.versuch.P_aufT;
        set(S.hInfo, 'String', { ...
            sprintf('Phase: %s', ph), ...
            sprintf('v = %.2f m/s    p = %.2f MPa    M_R = %.1f Nm    T_Öl = %.1f °C', ...
                    P.v(k), P.p(k), P.M(k), P.T_oel(k)), ...
            sprintf('T_max = %.1f °C    T_max - T_min = %.1f K    Hotspot = %s', ...
                    S.m.Tmax(k), S.m.dTglob(k), hotText(k))});
        guidata(fig, S);
    end

    function s = hotText(k)
        if S.m.hot_ok(k)
            s = sprintf('%.1f°', S.m.phi_hot(k));
        else
            s = 'nicht deutlich';
        end
    end

    function sk = abschnittBei(tk)
        sk = find([S.seg.t_start] <= tk & [S.seg.t_ende] >= tk, 1);
        if isempty(sk)  % zwischen zwei Abschnitten (Abtastluecke): naechsten nehmen
            [~, sk] = min(abs([S.seg.t_start] - tk));
        end
    end

    function klickZeit(h, ~)
        a = ancestor(h, 'axes');
        cp = get(a, 'CurrentPoint');
        [~, k] = min(abs(S.versuch.t_T - cp(1, 1)));
        setzeCursor(k);
    end

    function schieber(h, ~)
        setzeCursor(get(h, 'Value'));
    end

    function taste(~, e)
        S = guidata(fig);
        switch e.Key
            case 'rightarrow', setzeCursor(S.k + 1);
            case 'leftarrow',  setzeCursor(S.k - 1);
        end
    end

    function tabelleGewaehlt(~, e)
        if isempty(e.Indices)
            return
        end
        zeile = e.Indices(1, 1);
        s = S.seg(zeile);
        rand = max(5, 0.1 * s.dauer);
        zoomen(s.t_start - rand, s.t_ende + rand);
        [~, k] = min(abs(S.versuch.t_T - s.t_start));
        setzeCursor(k);
    end

    function zoomen(a, b)
        if b <= a, b = a + 1; end
        xlim(S.ax(1), [a b]);
    end

    function ereignisMarkieren(~, ~)
        S = guidata(fig);
        tk = S.versuch.t_T(S.k);
        antwort = inputdlg(sprintf('Beschreibung des Ereignisses bei t = %.1f s:', tk), ...
                           'Ereignis markieren', 1, {''});
        if isempty(antwort) || isempty(strtrim(antwort{1}))
            return
        end
        S.ev(end + 1).t = tk;
        S.ev(end).text = strtrim(antwort{1});
        ereignisse('speichern', S.opt.ereignisDatei, S.ev);
        guidata(fig, S);
        zeichneEreignisse();
        status(sprintf('Ereignis gespeichert in %s', S.opt.ereignisDatei));
    end

    function zeichneEreignisse()
        S = guidata(fig);
        delete(S.hEv(ishandle(S.hEv)));
        S.hEv = leereHandles(0);
        for q = 1:numel(S.ev)
            for j = 1:5
                yl = get(S.ax(j), 'YLim');
                S.hEv(end + 1) = plot(S.ax(j), [1 1] * S.ev(q).t, yl, '--', ...
                                      'Color', S.F.ink2, 'LineWidth', 1, 'HitTest', 'off');
            end
            S.hEv(end + 1) = text(S.ev(q).t, S.versuch.phi(end) - 3, [' ', S.ev(q).text], ...
                                  'Parent', S.ax(1), 'Color', S.F.ink, 'FontSize', 8, ...
                                  'VerticalAlignment', 'top', 'BackgroundColor', S.F.surface, ...
                                  'HitTest', 'off');
        end
        guidata(fig, S);
    end

    function abschnittExport(~, ~)
        S = guidata(fig);
        sk = abschnittBei(S.versuch.t_T(S.k));
        d = exportiereSegmente(S.versuch, S.seg, S.m, S.opt.exportOrdner, S.seg(sk).nr);
        status(sprintf('Abschnitt %d exportiert: %s', S.seg(sk).nr, d{end}));
    end

    function allesExport(~, ~, deutsch)
        if nargin < 3, deutsch = false; end
        S = guidata(fig);
        d = exportiereSegmente(S.versuch, S.seg, S.m, S.opt.exportOrdner, [], deutsch);
        status(sprintf('%d Dateien exportiert nach %s', numel(d), S.opt.exportOrdner));
    end

    function bildSpeichern(~, ~)
        S = guidata(fig);
        if ~exist(S.opt.exportOrdner, 'dir'), mkdir(S.opt.exportOrdner); end
        datei = fullfile(S.opt.exportOrdner, sprintf('ansicht_t%06.0f.png', S.versuch.t_T(S.k)));
        print(fig, '-dpng', '-r110', datei);
        status(sprintf('Bild gespeichert: %s', datei));
    end

    function status(txt)
        set(S.hStatus, 'String', txt);
        drawnow;
    end
end

% ========================================================================
function [tq, Tq] = gleichmaessig(t, T)
dt = diff(t);
if numel(t) < 3 || std(dt) <= 0.05 * median(dt)
    tq = t;
    Tq = T;
    return
end
tq = (t(1):median(dt):t(end))';
idx = interp1(t, (1:numel(t))', tq, 'nearest');
Tq = T(idx, :);
luecke = abs(t(idx) - tq) > 1.5 * median(dt);
Tq(luecke, :) = NaN;
end

function d = tabellenDaten(seg)
d = cell(numel(seg), 7);
for k = 1:numel(seg)
    d(k, :) = {seg(k).nr, seg(k).phase, seg(k).zyklus, zahl(seg(k).t_start), ...
               zahl(seg(k).dauer), zahl(seg(k).Tmax_max), zahl(seg(k).M_mittel)};
end
end

function s = zahl(x)
if isfinite(x)
    s = sprintf('%.1f', x);
else
    s = '-';
end
end

function s = hinweisText()
s = 'Klick ins Diagramm / Schieberegler: Cursor setzen  |  Pfeiltasten: nächste Messung  |  Tabellenzeile: Abschnitt zoomen';
end

function F = farben()
hex = @(h) double([hex2dec(h(2:3)), hex2dec(h(4:5)), hex2dec(h(6:7))]) / 255;
F.surface = hex('#fcfcfb');
F.ink = hex('#0b0b0b');
F.ink2 = hex('#52514e');
F.grid = hex('#e4e3df');
F.blau = hex('#2a78d6');
F.orange = hex('#eb6834');
% Phasen: Stillstand neutral grau, dann feste Reihenfolge der Kategorienfarben
F.phase = [hex('#a3a29d'); hex('#2a78d6'); hex('#1baf7a'); hex('#eb6834'); hex('#eda100')];
% sequenzielle Blau-Rampe (hell = kalt, dunkel = warm)
stufen = {'#cde2fb', '#9ec5f4', '#6da7ec', '#3987e5', '#256abf', '#184f95', '#0d366b'};
st = cell2mat(cellfun(hex, stufen', 'UniformOutput', false));
x = linspace(0, 1, size(st, 1));
xi = linspace(0, 1, 256);
F.sequenziell = [interp1(x, st(:, 1), xi)', interp1(x, st(:, 2), xi)', interp1(x, st(:, 3), xi)'];
end
