function n_fehler = run_alle_tests(mitGui)
%RUN_ALLE_TESTS Alle Tests ausfuehren (MATLAB und GNU Octave).
%   run_alle_tests          ohne Oberflaechentest
%   run_alle_tests(true)    zusaetzlich die Oberflaeche unsichtbar oeffnen und
%                           alle Knoepfe einmal ausloesen
%   Rueckgabe: Anzahl fehlgeschlagener Tests (0 = alles gut).

if nargin < 1
    mitGui = false;
end
wurzel = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(wurzel, 'src'));
tmp = fullfile(tempdir, sprintf('pruefstand_tests_%d', round(rand * 1e6)));
mkdir(tmp);

tests = {@test_csv_komma, @test_csv_semikolon_dezimalkomma, @test_csv_bom_crlf_luecken, ...
         @test_spaltenerkennung, @test_versuch_einheiten_und_versatz, ...
         @test_temperaturspalten_sortiert, @test_synchronisation, ...
         @test_segmentierung_start_stopp, @test_segmentierung_kurze_stoerung, ...
         @test_segmentierung_lastwechsel, @test_hotspot_parabel, @test_hotspot_rand_und_schwach, ...
         @test_export_und_ereignisse, @test_beispieldaten, @test_stapelexport, ...
         @test_luecken_in_zeitachse};
if mitGui
    tests{end + 1} = @test_oberflaeche;
end

n_fehler = 0;
fprintf('\n');
for k = 1:numel(tests)
    name = func2str(tests{k});
    try
        tests{k}(tmp, wurzel);
        fprintf('  OK      %s\n', name);
    catch e
        n_fehler = n_fehler + 1;
        fprintf('  FEHLER  %s\n          %s\n', name, e.message);
    end
end
fprintf('\n%d von %d Tests bestanden.\n', numel(tests) - n_fehler, numel(tests));
end

% ======================================================================= Hilfen
function schreibe(datei, txt)
fid = fopen(datei, 'w');
fwrite(fid, txt);
fclose(fid);
end

function istGleich(a, b, tol, was)
if nargin < 3, tol = 1e-9; end
if nargin < 4, was = ''; end
a = double(a); b = double(b);
if ~isequal(size(a), size(b)) || any(abs(a(:) - b(:)) > tol | isnan(a(:)) ~= isnan(b(:)))
    error('%s: erwartet [%s], erhalten [%s]', was, num2str(b(:)'), num2str(a(:)'));
end
end

function pruefe(bedingung, text)
if ~bedingung
    error(text);
end
end

% ======================================================================= Import
function test_csv_komma(tmp, ~)
d = fullfile(tmp, 'a.csv');
schreibe(d, sprintf('zeit_s,T01,T02\n0,20.5,21\n1,20.75,21.25\n'));
tab = ladeCsv(d);
pruefe(isequal(tab.namen, {'zeit_s', 'T01', 'T02'}), 'Spaltennamen');
istGleich(tab.daten, [0 20.5 21; 1 20.75 21.25], 1e-12, 'Daten');
end

function test_csv_semikolon_dezimalkomma(tmp, ~)
d = fullfile(tmp, 'b.csv');
schreibe(d, sprintf('Zeit [s];Drehzahl [1/min];Radialkraft [kN]\n0,10;397,19;36,022\n0,20;1,5;2\n'));
tab = ladeCsv(d);
pruefe(strcmp(tab.trennzeichen, ';'), 'Semikolon nicht erkannt');
istGleich(tab.daten, [0.1 397.19 36.022; 0.2 1.5 2], 1e-12, 'Dezimalkomma');
end

function test_csv_bom_crlf_luecken(tmp, ~)
d = fullfile(tmp, 'c.csv');
schreibe(d, [char([239 187 191]), sprintf('zeit_s,T01,T02\r\n0,1,\r\n1,,3\r\n')]);
tab = ladeCsv(d);
pruefe(strcmp(tab.namen{1}, 'zeit_s'), 'BOM nicht entfernt');
istGleich(tab.daten, [0 1 NaN; 1 NaN 3], 1e-12, 'Luecken als NaN');
end

function test_spaltenerkennung(~, ~)
cfg = konfiguration();
namen = {'Zeit [s]', 'Drehzahl [1/min]', 'Radialkraft [kN]', 'Reibmoment [Nm]', ...
         ['Ö', 'ltemperatur Zulauf [°C]'], 'T_oel_degC', 'v_mps', 'p_MPa'};
istGleich(findeSpalte(namen, cfg.spalten.zeit), 1, 0, 'Zeit');
istGleich(findeSpalte(namen, cfg.spalten.n), 2, 0, 'Drehzahl');
istGleich(findeSpalte(namen, cfg.spalten.F), 3, 0, 'Kraft');
istGleich(findeSpalte(namen, cfg.spalten.M), 4, 0, 'Reibmoment');
istGleich(findeSpalte(namen, cfg.spalten.T_oel), 5, 0, 'Oeltemperatur');
istGleich(findeSpalte(namen, cfg.spalten.v), 7, 0, 'Geschwindigkeit');
istGleich(findeSpalte(namen, cfg.spalten.p), 8, 0, 'Last');
istGleich(findeSpalte({'T_oel_degC', 'zeit_s'}, cfg.spalten.zeit), 2, 0, 'T_oel ist keine Zeit');
end

function test_versuch_einheiten_und_versatz(tmp, ~)
ordner = fullfile(tmp, 'versuch_de');
mkdir(ordner);
schreibe(fullfile(ordner, 'sipb.csv'), sprintf('zeit_s,T01,T02,T03\n12,60,61,60\n19,60,62,60\n'));
schreibe(fullfile(ordner, 'pruefstand.csv'), ...
         sprintf('Zeit [s];Drehzahl [1/min];Radialkraft [kN];Reibmoment [Nm]\n0;600;36;5\n10;600;36;5\n'));
cfg = konfiguration();
cfg.import.zeitversatz_s = -12;
v = ladeVersuch(ordner, cfg);
istGleich(v.t_T, [0; 7], 1e-12, 'Zeitversatz');
istGleich(v.P.v, pi * 0.12 * 600 / 60 * [1; 1], 1e-9, 'v aus Drehzahl');
istGleich(v.P.p, 36e3 / (0.03 * 0.12) / 1e6 * [1; 1], 1e-9, 'p aus kN');
istGleich(v.P.M, [5; 5], 1e-12, 'Reibmoment');
pruefe(numel(v.einheiten_hinweis) == 2, 'Hinweise auf Umrechnung fehlen');
end

function test_temperaturspalten_sortiert(tmp, ~)
ordner = fullfile(tmp, 'versuch_sort');
mkdir(ordner);
schreibe(fullfile(ordner, 'sipb.csv'), sprintf('zeit_s,T10,T2,T1\n0,10,2,1\n'));
v = ladeVersuch(ordner);
istGleich(v.sensor_nr, [1 2 10], 0, 'Sensornummern');
istGleich(v.T, [1 2 10], 0, 'Reihenfolge');
cfg = konfiguration();
istGleich(v.phi, cfg.lager.phi([1 2 10]), 1e-12, 'Winkel passend zur Nummer');
pruefe(isempty(v.t_P), 'ohne Pruefstandsdatei sollte t_P leer sein');
end

function test_synchronisation(~, ~)
v.t_T = [-1; 0; 0.5; 2; 5];
v.t_P = [0; 1; 2];
v.P = struct('v', [0; 2; 4], 'p', [1; 1; 1], 'M', [NaN; 3; 5], 'T_oel', [NaN; NaN; NaN]);
v = synchronisiere(v);
istGleich(v.P_aufT.v, [NaN; 0; 1; 4; NaN], 1e-12, 'v interpoliert');
% M hat gueltige Werte nur bei t = 1 und 2 -> davor/danach NaN (keine Extrapolation)
istGleich(v.P_aufT.M, [NaN; NaN; NaN; 5; NaN], 1e-12, 'M ohne NaN-Stuetzstellen');
pruefe(all(isnan(v.P_aufT.T_oel)), 'leeres Signal bleibt NaN');
end

% ======================================================================= Segmentierung
function [t, v, p] = startStoppProfil(n_zyklen, dt)
t = (0:dt:99 * n_zyklen - dt)';
tc = mod(t, 99);
v = 2.5 * ones(size(t));
v(tc < 20) = 2.5 * tc(tc < 20) / 20;
r = tc >= 69 & tc < 89;
v(r) = 2.5 * (89 - tc(r)) / 20;
v(tc >= 89) = 0;
p = 0.5 + 9.5 * v / 2.5;
end

function test_segmentierung_start_stopp(~, ~)
[t, v, p] = startStoppProfil(5, 0.1);
v = v + 0.002 * sin(37 * t) + 0.002 * cos(91 * t);  % deterministisches Messrauschen
seg = segmentiere(t, v, p);
istGleich(numel(seg), 20, 0, 'Anzahl Abschnitte');
istGleich(max([seg.zyklus]), 5, 0, 'Anzahl Zyklen');
erwartet = {'Hochfahren', 'Konstant', 'Runterfahren', 'Stillstand'};
for k = 1:numel(seg)
    pruefe(strcmp(seg(k).phase, erwartet{mod(k - 1, 4) + 1}), sprintf('Phase %d', k));
end
% Grenzen auf +-1 s genau
grenzen = [0 20 69 89; 20 69 89 99];
for k = 1:numel(seg)
    j = mod(k - 1, 4) + 1;
    z = floor((k - 1) / 4) * 99;
    pruefe(abs(seg(k).t_start - (z + grenzen(1, j))) <= 1.0, sprintf('Start Abschnitt %d', k));
end
end

function test_segmentierung_kurze_stoerung(~, ~)
t = (0:0.1:100)';
v = 2.5 * ones(size(t));
v(t > 50 & t < 50.8) = 0;   % 0,8 s Aussetzer im Signal
seg = segmentiere(t, v, []);
istGleich(numel(seg), 1, 0, 'Stoerung sollte zusammengelegt werden');
pruefe(strcmp(seg(1).phase, 'Konstant'), 'Phase');
end

function test_segmentierung_lastwechsel(~, ~)
t = (0:0.1:200)';
v = 2.5 * ones(size(t));
p = 10 * ones(size(t));
r = t >= 100 & t < 130;
p(r) = 10 + 2 * (t(r) - 100) / 30;
p(t >= 130) = 12;
seg = segmentiere(t, v, p);
phasen = {seg.phase};
pruefe(isequal(phasen, {'Konstant', 'Lastwechsel', 'Konstant'}), ...
       ['Phasen: ', strjoin(phasen, ', ')]);
pruefe(abs(seg(2).t_start - 100) <= 1.5 && abs(seg(2).t_ende - 130) <= 1.5, 'Grenzen Lastwechsel');
end

% ======================================================================= Merkmale
function test_hotspot_parabel(~, ~)
phi = linspace(97.5, 270, 24);
T = -0.01 * (phi - 203.3) .^ 2 + 80;
m = temperaturMerkmale(T, phi);
istGleich(m.phi_hot, 203.3, 1e-9, 'Parabel-Hotspot');
pruefe(m.hot_ok, 'Hotspot sollte gueltig sein');
istGleich(m.dTglob, max(T) - min(T), 1e-12, 'globaler Gradient');
end

function test_hotspot_rand_und_schwach(~, ~)
phi = linspace(97.5, 270, 24);
T = [phi / 10; 60 + 0.2 * cos((phi - 200) / 30)];  % Max am Rand / Hotspot zu flach
m = temperaturMerkmale(T, phi);
pruefe(~m.hot_ok(1), 'Maximum am Rand darf nicht gueltig sein');
pruefe(~m.hot_ok(2), 'zu flacher Hotspot darf nicht gueltig sein');
end

% ======================================================================= Export
function test_export_und_ereignisse(tmp, ~)
[t, v, p] = startStoppProfil(2, 0.1);
ver.name = 'test';
ver.t_P = t;
ver.P = struct('v', v, 'p', p, 'M', 5 + 0 * t, 'T_oel', 60 + 0 * t);
ver.t_T = (0:7:197)';
phi = linspace(97.5, 270, 24);
ver.phi = phi;
ver.sensor_nr = 1:24;
ver.T = repmat(60 - 0.001 * (phi - 205) .^ 2, numel(ver.t_T), 1);
[ver, seg, m] = analysiereVersuch(ver);
ziel = fullfile(tmp, 'export');
d = exportiereSegmente(ver, seg, m, ziel);
istGleich(numel(d), numel(seg) + 2, 0, 'Anzahl Dateien');
tab = ladeCsv(fullfile(ziel, 'segmente.csv'));
istGleich(size(tab.daten, 1), numel(seg), 0, 'Zeilen Uebersicht');
istGleich(tab.daten(:, 1), (1:numel(seg))', 0, 'Nummern');
pruefe(strcmp(tab.texte{2}{1}, seg(1).phase), 'Textspalte phase wieder eingelesen');
d2 = exportiereSegmente(ver, seg, m, fullfile(tmp, 'export_de'), [], true);
txt = fileread(d2{1});
pruefe(~isempty(strfind(txt, ';')) && ~isempty(regexp(txt, '\d,\d', 'once')), 'deutsches Format');
tabDe = ladeCsv(d2{1});
istGleich(tabDe.daten, tab.daten, 1e-9, 'deutsch und englisch gleich');
% Ereignisse mit Komma und Anfuehrungszeichen im Text
ev = struct('t', {12.5, 3}, 'text', {'Hotspot wandert, T steigt', 'Sensor "7" springt'});
datei = fullfile(tmp, 'ev.csv');
ereignisse('speichern', datei, ev);
ev2 = ereignisse('laden', datei);
istGleich([ev2.t], [3 12.5], 1e-9, 'Ereigniszeiten sortiert');
pruefe(strcmp(ev2(1).text, 'Sensor "7" springt') && strcmp(ev2(2).text, 'Hotspot wandert, T steigt'), ...
       'Ereignistexte');
pruefe(isempty(ereignisse('laden', fullfile(tmp, 'gibtsnicht.csv'))), 'fehlende Datei');
end

% ======================================================================= Beispieldaten
function test_beispieldaten(~, wurzel)
b = fullfile(wurzel, 'beispieldaten');
cfg = konfiguration();
v = ladeVersuch(fullfile(b, 'V01_start_stopp_schmierstoffmangel_60C'), cfg);
[v, seg] = analysiereVersuch(v, cfg);
istGleich(max([seg.zyklus]), 16, 0, 'V01 Zyklen');
pruefe(size(v.T, 2) == 24, 'V01 24 Sensoren');
pruefe(max(v.P.M) > 100, 'V01 Reibmoment-Anstieg am Ende');

v = ladeVersuch(fullfile(b, 'V02_ueberlast_60C_deutsches_format'), cfg);
[v, seg] = analysiereVersuch(v, cfg);
istGleich(numel(seg), 3, 0, 'V02 Abschnitte');
istGleich(seg(1).v_mittel, 2.5, 0.02, 'V02 v aus Drehzahl');
istGleich(seg(1).p_mittel, 10, 0.05, 'V02 p aus Kraft');
pruefe(seg(3).M_mittel > 5 * seg(1).M_mittel, 'V02 Mischreibung: Reibmoment steigt stark');
pruefe(seg(3).phi_hot_median < seg(1).phi_hot_median - 2, 'V02 Hotspot wandert Richtung Lastzone');

% V03: SiPB-Uhr geht 12 s vor, korrigiert ueber einstellungen.txt im Ordner
v = ladeVersuch(fullfile(b, 'V03_start_stopp_gesund_20C'), cfg);
[v, seg] = analysiereVersuch(v, cfg);
istGleich(v.t_T(1), 0, 1e-9, 'V03 Zeitversatz aus einstellungen.txt');
istGleich(max([seg.zyklus]), 13, 0, 'V03 Zyklen');
end

function test_stapelexport(tmp, wurzel)
ziel = fullfile(tmp, 'stapel');
ueb = stapelExport(fullfile(wurzel, 'beispieldaten'), [], ziel);
istGleich(numel(ueb), 3, 0, 'Anzahl Versuche');
pruefe(exist(fullfile(ziel, 'uebersicht.csv'), 'file') == 2, 'uebersicht.csv fehlt');
pruefe(exist(fullfile(ziel, ueb(2).name, 'segmente.csv'), 'file') == 2, 'Export je Versuch fehlt');
tab = ladeCsv(fullfile(ziel, 'uebersicht.csv'));
istGleich(size(tab.daten, 1), 3, 0, 'Zeilen Uebersicht');
end

function test_luecken_in_zeitachse(tmp, ~)
% Messausfall: 60 s ohne Temperaturdaten mitten im Versuch
phi = linspace(97.5, 270, 24);
ver.name = 'luecke';
ver.t_T = [(0:7:300)'; (370:7:600)'];
ver.T = repmat(60 - 0.001 * (phi - 205) .^ 2, numel(ver.t_T), 1);
ver.phi = phi;
ver.sensor_nr = 1:24;
ver.t_P = (0:0.1:600)';
ver.P = struct('v', 2.5 + 0 * ver.t_P, 'p', 10 + 0 * ver.t_P, 'M', 5 + 0 * ver.t_P, 'T_oel', 60 + 0 * ver.t_P);
[ver, seg, m] = analysiereVersuch(ver);
istGleich(numel(seg), 1, 0, 'ein Abschnitt');
istGleich(seg(1).n_T, numel(ver.t_T), 0, 'alle Temperaturmessungen im Abschnitt');
if kannGuiOeffnen()
    fig = pruefstandViewer(ver, seg, m, 'sichtbar', false, 'ereignisDatei', fullfile(tmp, 'e.csv'));
    close(fig);
end
end

function ok = kannGuiOeffnen()
if exist('OCTAVE_VERSION', 'builtin') == 0
    ok = true;  % MATLAB oeffnet unsichtbare Fenster auch ohne Bildschirm
else
    ok = ~isempty(getenv('DISPLAY')) && any(strcmp(available_graphics_toolkits(), 'qt'));
end
end

% ======================================================================= Oberflaeche
function test_oberflaeche(tmp, wurzel)
ordner = fullfile(wurzel, 'beispieldaten', 'V02_ueberlast_60C_deutsches_format');
fig = pruefstandViewer(ordner, 'sichtbar', false, 'ereignisDatei', fullfile(tmp, 'ev_gui.csv'), ...
                       'exportOrdner', fullfile(tmp, 'gui_export'));
aufraeumen = onCleanup(@() close(fig));
S = guidata(fig);
set(S.hSl, 'Value', 200);
feval(get(S.hSl, 'Callback'), S.hSl, []);
S = guidata(fig);
istGleich(S.k, 200, 0, 'Schieberegler');
feval(get(fig, 'KeyPressFcn'), fig, struct('Key', 'rightarrow'));
S = guidata(fig);
istGleich(S.k, 201, 0, 'Pfeiltaste');
feval(get(S.hTab, 'CellSelectionCallback'), S.hTab, struct('Indices', [2 1]));
xl = get(S.ax(1), 'XLim');
pruefe(xl(1) < S.seg(2).t_start && xl(2) > S.seg(2).t_ende, 'Zoom auf Abschnitt');
for name = {'Ganzer Versuch', 'Abschnitt exportieren', 'Alles exportieren', 'Excel-Format (DE)', 'Bild speichern'}
    h = findobj(fig, 'Style', 'pushbutton', 'String', name{1});
    cb = get(h, 'Callback');
    feval(cb, h, []);
end
pruefe(exist(fullfile(tmp, 'gui_export', 'segmente.csv'), 'file') == 2, 'Export aus der Oberflaeche');
end
