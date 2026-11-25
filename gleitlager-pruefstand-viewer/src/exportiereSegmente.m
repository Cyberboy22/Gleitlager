function dateien = exportiereSegmente(versuch, seg, m, zielordner, auswahl, deutsch)
%EXPORTIERESEGMENTE Schreibt die Abschnitte eines Versuchs als CSV und MAT.
%   dateien = exportiereSegmente(versuch, seg, m, zielordner)
%   dateien = exportiereSegmente(..., auswahl)   nur diese Abschnittsnummern
%   dateien = exportiereSegmente(..., auswahl, true)  deutsches Excel-Format
%                                                     (Semikolon, Dezimalkomma)
%   Erzeugt in zielordner:
%     segmente.csv              eine Zeile je Abschnitt mit allen Kennwerten
%     segmente/NNN_Phase.csv    Messwerte je Abschnitt (Temperaturen +
%                               Pruefstand auf Temperaturzeitpunkten + Merkmale)
%     versuch.mat               versuch, seg, m (nur beim Gesamtexport)

if nargin < 5 || isempty(auswahl)
    auswahl = [seg.nr];
    gesamt = true;
else
    gesamt = false;
end
if nargin < 6
    deutsch = false;
end
if ~isfield(versuch, 'P_aufT')
    versuch = synchronisiere(versuch);
end
if ~exist(zielordner, 'dir')
    mkdir(zielordner);
end
sub = fullfile(zielordner, 'segmente');
if ~exist(sub, 'dir')
    mkdir(sub);
end
if deutsch
    tr = ';';
else
    tr = ',';
end
dateien = {};

% ---------------------------------------------------------- Uebersicht
spalten = {'nr', 'phase', 'zyklus', 't_start_s', 't_ende_s', 'dauer_s', 'n_T', ...
           'Tmax_max_degC', 'Tmax_mittel_degC', 'dTglob_mittel_K', 'phi_hot_median_deg', ...
           'v_mittel_mps', 'p_mittel_MPa', 'M_mittel_Nm', 'M_max_Nm', 'T_oel_mittel_degC'};
felder = {'zyklus', 't_start', 't_ende', 'dauer', 'n_T', 'Tmax_max', 'Tmax_mittel', ...
          'dTglob_mittel', 'phi_hot_median', 'v_mittel', 'p_mittel', 'M_mittel', ...
          'M_max', 'T_oel_mittel'};
if gesamt
    datei = fullfile(zielordner, 'segmente.csv');
    fid = oeffne(datei);
    fprintf(fid, '%s\n', strjoin(spalten, tr));
    for k = 1:numel(seg)
        werte = cellfun(@(f) seg(k).(f), felder);
        zeile = [sprintf('%d', seg(k).nr), tr, seg(k).phase, tr, zahlen(werte, tr, deutsch)];
        fprintf(fid, '%s\n', zeile);
    end
    fclose(fid);
    dateien{end+1} = datei;
end

% ---------------------------------------------------------- je Abschnitt
nT = size(versuch.T, 2);
kopf = [{'zeit_s'}, arrayfun(@(i) sprintf('T%02d_degC', versuch.sensor_nr(i)), 1:nT, ...
        'UniformOutput', false), {'v_mps', 'p_MPa', 'M_Nm', 'T_oel_degC', ...
        'Tmax_degC', 'dTglob_K', 'phi_hot_deg', 'hotspot_ok'}];
for k = auswahl(:)'
    s = seg([seg.nr] == k);
    in = versuch.t_T >= s.t_start & versuch.t_T <= s.t_ende;
    X = [versuch.t_T(in), versuch.T(in, :), versuch.P_aufT.v(in), versuch.P_aufT.p(in), ...
         versuch.P_aufT.M(in), versuch.P_aufT.T_oel(in), m.Tmax(in), m.dTglob(in), ...
         m.phi_hot(in), double(m.hot_ok(in))];
    datei = fullfile(sub, sprintf('%03d_%s.csv', s.nr, regexprep(s.phase, '[^A-Za-z0-9]+', '_')));
    fid = oeffne(datei);
    fprintf(fid, '%s\n', strjoin(kopf, tr));
    for r = 1:size(X, 1)
        fprintf(fid, '%s\n', zahlen(X(r, :), tr, deutsch));
    end
    fclose(fid);
    dateien{end+1} = datei; %#ok<AGROW>
end

if gesamt
    datei = fullfile(zielordner, 'versuch.mat');
    save(datei, 'versuch', 'seg', 'm', '-v7');
    dateien{end+1} = datei;
end
end

% ========================================================================
function fid = oeffne(datei)
fid = fopen(datei, 'w');
if fid < 0
    error('exportiereSegmente:schreiben', 'Kann %s nicht schreiben.', datei);
end
end

function s = zahlen(x, tr, deutsch)
c = arrayfun(@(v) sprintf('%.6g', v), x, 'UniformOutput', false);
c(~isfinite(x)) = {''};
s = strjoin(c, tr);
if deutsch
    s = strrep(s, '.', ',');
end
end
