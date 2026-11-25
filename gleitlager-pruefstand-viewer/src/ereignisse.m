function ev = ereignisse(aktion, datei, ev)
%EREIGNISSE Markierte Ereignisse (Zeitpunkt + Text) laden und speichern.
%   ev = ereignisse('laden', datei)          leeres struct-Array, wenn es
%                                           die Datei noch nicht gibt
%   ereignisse('speichern', datei, ev)
%   ev ist ein struct-Array mit den Feldern t (Zeit [s]) und text.
%   Format: CSV mit Kopfzeile "zeit_s,text", Text in Anfuehrungszeichen.

switch aktion
    case 'laden'
        ev = struct('t', {}, 'text', {});
        if ~exist(datei, 'file')
            return
        end
        zeilen = strsplit(strrep(fileread(datei), sprintf('\r'), ''), sprintf('\n'));
        for k = 2:numel(zeilen)
            z = strtrim(zeilen{k});
            if isempty(z)
                continue
            end
            tok = regexp(z, '^([^,]+),"?(.*?)"?$', 'tokens', 'once');
            if isempty(tok)
                continue
            end
            ev(end+1).t = str2double(tok{1}); %#ok<AGROW>
            ev(end).text = strrep(tok{2}, '""', '"');
        end
    case 'speichern'
        [~, o] = sort([ev.t]);
        ev = ev(o);
        fid = fopen(datei, 'w');
        if fid < 0
            error('ereignisse:schreiben', 'Kann %s nicht schreiben.', datei);
        end
        fprintf(fid, 'zeit_s,text\n');
        for k = 1:numel(ev)
            fprintf(fid, '%.2f,"%s"\n', ev(k).t, strrep(ev(k).text, '"', '""'));
        end
        fclose(fid);
    otherwise
        error('ereignisse:aktion', 'Unbekannte Aktion %s', aktion);
end
end
