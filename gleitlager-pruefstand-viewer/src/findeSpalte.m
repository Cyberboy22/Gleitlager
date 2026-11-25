function idx = findeSpalte(namen, muster)
%FINDESPALTE Index der ersten Spalte, deren Name zum regulaeren Ausdruck passt.
%   idx = findeSpalte(namen, muster), 0 wenn keine Spalte passt.
%   Gross-/Kleinschreibung wird ignoriert; Umlaute werden vorher
%   umgeschrieben (Oel statt Öl), damit die Muster einfach bleiben.
idx = 0;
for k = 1:numel(namen)
    if ~isempty(regexpi(normiereName(namen{k}), muster, 'once'))
        idx = k;
        return
    end
end
end

function s = normiereName(s)
s = lower(strtrim(s));
s = strrep(s, char(246), 'oe');  % ö
s = strrep(s, char(228), 'ae');  % ä
s = strrep(s, char(252), 'ue');  % ü
s = strrep(s, char(223), 'ss');  % ß
% UTF-8-Bytes, falls die Datei als Latin-1 gelesen wurde
s = strrep(s, char([195 182]), 'oe');
s = strrep(s, char([195 164]), 'ae');
s = strrep(s, char([195 188]), 'ue');
s = strrep(s, char([195 150]), 'oe');  % Ö
end
