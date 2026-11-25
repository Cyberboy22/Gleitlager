function versuch = synchronisiere(versuch)
%SYNCHRONISIERE Pruefstandsdaten auf die Zeitpunkte der Temperaturmessung legen.
%   versuch = synchronisiere(versuch) ergaenzt versuch.P_aufT mit den Feldern
%   v, p, M, T_oel, linear interpoliert auf versuch.t_T. Ausserhalb des
%   Pruefstands-Zeitbereichs: NaN (kein Extrapolieren).
%
%   Hinweis: Die SiPB-Uhr und die Pruefstandsuhr koennen versetzt sein.
%   Den Versatz vorher mit cfg.import.zeitversatz_s in ladeVersuch korrigieren.

felder = fieldnames(versuch.P);
for f = 1:numel(felder)
    y = versuch.P.(felder{f});
    if numel(versuch.t_P) >= 2 && any(isfinite(y))
        ok = isfinite(y);
        versuch.P_aufT.(felder{f}) = interp1(versuch.t_P(ok), y(ok), versuch.t_T, 'linear', NaN);
    else
        versuch.P_aufT.(felder{f}) = nan(size(versuch.t_T));
    end
end
end
