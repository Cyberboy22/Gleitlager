function tab = ladeCsv(datei)
%LADECSV Liest eine CSV-Datei mit Kopfzeile robust ein.
%   tab = ladeCsv(datei)
%   Erkennt automatisch:
%     - Trennzeichen Komma oder Semikolon (deutsches Excel)
%     - Dezimalkomma (bei Semikolon-Dateien)
%     - UTF-8-BOM und Windows-Zeilenenden
%   Rueckgabe:
%     tab.namen  1xN Zellarray der Spaltennamen
%     tab.daten  MxN double, leere oder ungueltige Felder = NaN
%     tab.texte  1xN Zellarray; bei reinen Textspalten die Texte, sonst []
%     tab.datei  Pfad

if ~exist(datei, 'file')
    error('ladeCsv:keineDatei', 'Datei nicht gefunden: %s', datei);
end
txt = fileread(datei);
txt = strrep(txt, sprintf('\r'), '');
% BOM entfernen (je nach Dekodierung als 1 oder 3 Zeichen)
if ~isempty(txt) && double(txt(1)) == 65279
    txt = txt(2:end);
elseif numel(txt) >= 3 && isequal(double(txt(1:3)), [239 187 191])
    txt = txt(4:end);
end

nl = find(txt == sprintf('\n'), 1);
if isempty(nl)
    error('ladeCsv:leer', 'Datei hat keine Datenzeilen: %s', datei);
end
kopf = txt(1:nl-1);
rumpf = txt(nl+1:end);

if sum(kopf == ';') > sum(kopf == ',')
    trenn = ';';
    rumpf = strrep(rumpf, ',', '.');   % Dezimalkomma -> Punkt
else
    trenn = ',';
end

namen = strtrim(strsplit(kopf, trenn));
namen = regexprep(namen, '^"|"$', '');
n = numel(namen);

% schneller Weg: alles numerisch
C = textscan(rumpf, repmat('%f', 1, n), 'Delimiter', trenn, ...
             'CollectOutput', true, 'EmptyValue', NaN);
daten = C{1};
if size(daten, 2) < n
    daten(:, end+1:n) = NaN;
end
texte = cell(1, n);
% textscan bricht bei der ersten Textzelle ab -> dann robust Feld fuer Feld
if size(daten, 1) < anzahlZeilen(rumpf)
    C = textscan(rumpf, repmat('%s', 1, n), 'Delimiter', trenn, 'ReturnOnError', false);
    m = min(cellfun(@numel, C));
    daten = nan(m, n);
    for j = 1:n
        spalte = strtrim(C{j}(1:m));
        daten(:, j) = str2double(spalte);
        if all(isnan(daten(:, j))) && any(~cellfun(@isempty, spalte))
            texte{j} = regexprep(spalte, '^"|"$', '');  % reine Textspalte behalten
        end
    end
end

tab.namen = namen;
tab.daten = daten;
tab.texte = texte;
tab.datei = datei;
tab.trennzeichen = trenn;
end

function n = anzahlZeilen(txt)
% nicht-leere Datenzeilen
z = regexp(txt, '[^\n]*', 'match');
n = sum(~cellfun(@isempty, regexp(z, '\S', 'once')));
end
