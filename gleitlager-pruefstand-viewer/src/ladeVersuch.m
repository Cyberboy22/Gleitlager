function versuch = ladeVersuch(quelle, cfg)
%LADEVERSUCH Laedt einen Versuch: Lagertemperaturen (SiPB) + Pruefstandsdaten.
%   versuch = ladeVersuch(ordner)        sucht sipb*.csv und pruefstand*.csv
%   versuch = ladeVersuch({sipb, pruef}) explizite Dateien (pruef darf '' sein)
%   versuch = ladeVersuch(..., cfg)      eigene Einstellungen (konfiguration)
%
%   Die beiden Quellen haben eigene Zeitachsen und Abtastraten (z.B. 0,14 Hz
%   und 10 Hz). Sie werden NICHT umgetastet; versuch.t_T und versuch.t_P
%   bleiben getrennt. synchronisiere() bringt sie auf eine gemeinsame Achse.
%
%   Felder:
%     name, quellen
%     t_T [s] (nx1), T [degC] (nxS), phi [deg] (1xS)       Lagertemperaturen
%     t_P [s] (mx1), P.v [m/s], P.p [MPa], P.M [Nm], P.T_oel [degC]
%     einheiten_hinweis  welche Umrechnungen gemacht wurden
%
%   Liegt im Versuchsordner eine Datei einstellungen.txt, ueberschreibt sie
%   Felder von cfg.import, eine Zeile je Wert, # fuer Kommentare:
%       # SiPB-Uhr geht 12 s vor
%       zeitversatz_s = -12

if nargin < 2 || isempty(cfg)
    cfg = konfiguration();
end

[datei_T, datei_P, name] = dateienFinden(quelle, cfg);
% optionale Einstellungen je Versuch, z.B. "zeitversatz_s = -12"
if ischar(quelle) && exist(fullfile(quelle, 'einstellungen.txt'), 'file')
    cfg = leseEinstellungen(fullfile(quelle, 'einstellungen.txt'), cfg);
end
versuch.name = name;
versuch.quellen = {datei_T, datei_P};
versuch.einheiten_hinweis = {};

% ---------------------------------------------------------------- Temperaturen
tabT = ladeCsv(datei_T);
iz = findeSpalte(tabT.namen, cfg.spalten.zeit);
if iz == 0
    iz = 1;  % erste Spalte als Zeit annehmen
end
[iT, nr] = temperaturSpalten(tabT.namen, cfg.spalten.temperatur);
if isempty(iT)
    error('ladeVersuch:keineTemperaturen', ...
          'Keine Temperaturspalten (T01, T02, ...) in %s gefunden.', datei_T);
end
versuch.t_T = tabT.daten(:, iz) + cfg.import.zeitversatz_s;
versuch.T = tabT.daten(:, iT);
versuch.sensor_nr = nr;
phi = cfg.lager.phi(:)';
if numel(phi) >= max(nr)
    versuch.phi = phi(nr);
else
    versuch.phi = linspace(phi(1), phi(end), numel(nr));
end
if ~isempty(cfg.import.offsets)
    versuch.T = versuch.T - repmat(cfg.import.offsets(nr), size(versuch.T, 1), 1);
    versuch.einheiten_hinweis{end+1} = 'Sensor-Offsets abgezogen';
end
gueltig = isfinite(versuch.t_T);
versuch.t_T = versuch.t_T(gueltig);
versuch.T = versuch.T(gueltig, :);

% ---------------------------------------------------------------- Pruefstand
leer = nan(0, 1);
versuch.t_P = leer;
versuch.P = struct('v', leer, 'p', leer, 'M', leer, 'T_oel', leer);
if ~isempty(datei_P)
    tabP = ladeCsv(datei_P);
    iz = findeSpalte(tabP.namen, cfg.spalten.zeit);
    if iz == 0
        iz = 1;
    end
    t = tabP.daten(:, iz);
    m = numel(t);
    P = struct('v', nan(m, 1), 'p', nan(m, 1), 'M', nan(m, 1), 'T_oel', nan(m, 1));

    k = findeSpalte(tabP.namen, cfg.spalten.v);
    if k > 0
        P.v = tabP.daten(:, k);
    else
        k = findeSpalte(tabP.namen, cfg.spalten.n);
        if k > 0  % Drehzahl [1/min] -> Gleitgeschwindigkeit [m/s]
            P.v = pi * cfg.lager.D * tabP.daten(:, k) / 60;
            versuch.einheiten_hinweis{end+1} = sprintf( ...
                'v aus Drehzahl berechnet (D = %.0f mm)', cfg.lager.D * 1e3);
        end
    end

    k = findeSpalte(tabP.namen, cfg.spalten.p);
    if k > 0
        P.p = tabP.daten(:, k);
    else
        k = findeSpalte(tabP.namen, cfg.spalten.F);
        if k > 0  % Kraft -> spezifische Lagerlast p = F / (B*D)
            F = tabP.daten(:, k);
            if ~isempty(regexpi(tabP.namen{k}, 'kn', 'once'))
                F = F * 1e3;
            end
            P.p = F / (cfg.lager.B * cfg.lager.D) / 1e6;
            versuch.einheiten_hinweis{end+1} = 'p aus Radialkraft berechnet (p = F / (B*D))';
        end
    end

    k = findeSpalte(tabP.namen, cfg.spalten.M);
    if k > 0
        P.M = tabP.daten(:, k);
    end
    k = findeSpalte(tabP.namen, cfg.spalten.T_oel);
    if k > 0
        P.T_oel = tabP.daten(:, k);
    end
    gueltig = isfinite(t);
    versuch.t_P = t(gueltig);
    felder = fieldnames(P);
    for f = 1:numel(felder)
        versuch.P.(felder{f}) = P.(felder{f})(gueltig);
    end
end
end

% ========================================================================
function cfg = leseEinstellungen(datei, cfg)
zeilen = strsplit(strrep(fileread(datei), sprintf('\r'), ''), sprintf('\n'));
for k = 1:numel(zeilen)
    z = strtrim(regexprep(zeilen{k}, '[#%].*$', ''));
    tok = regexp(z, '^(\w+)\s*=\s*(.+)$', 'tokens', 'once');
    if isempty(tok)
        continue
    end
    wert = str2num(tok{2}); %#ok<ST2NM>  erlaubt auch Vektoren wie [0.1 -0.2 ...]
    if isempty(wert)
        warning('ladeVersuch:einstellung', 'Wert fuer %s in %s nicht lesbar.', tok{1}, datei);
    else
        cfg.import.(tok{1}) = wert;
    end
end
end

function [datei_T, datei_P, name] = dateienFinden(quelle, cfg)
if iscell(quelle)
    datei_T = quelle{1};
    datei_P = '';
    if numel(quelle) > 1
        datei_P = quelle{2};
    end
    [~, name] = fileparts(datei_T);
    return
end
if exist(quelle, 'dir')
    datei_T = ersteDatei(quelle, cfg.import.datei_sipb);
    datei_P = ersteDatei(quelle, cfg.import.datei_pruefstand);
    if isempty(datei_T)
        error('ladeVersuch:keineDatei', 'Keine Datei %s in %s.', cfg.import.datei_sipb, quelle);
    end
    [~, name] = fileparts(regexprep(quelle, '[\\/]+$', ''));
else
    datei_T = quelle;  % eine Datei, die alles enthaelt
    datei_P = quelle;
    [~, name] = fileparts(quelle);
end
end

function datei = ersteDatei(ordner, muster)
d = dir(fullfile(ordner, muster));
if isempty(d)
    datei = '';
else
    datei = fullfile(ordner, d(1).name);
end
end

function [idx, nr] = temperaturSpalten(namen, muster)
idx = [];
nr = [];
for k = 1:numel(namen)
    tok = regexpi(strtrim(namen{k}), muster, 'tokens', 'once');
    if ~isempty(tok)
        idx(end+1) = k;               %#ok<AGROW>
        nr(end+1) = str2double(tok{end}); %#ok<AGROW>
    end
end
[nr, o] = sort(nr);
idx = idx(o);
end
