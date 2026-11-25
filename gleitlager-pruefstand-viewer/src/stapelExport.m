function ueb = stapelExport(wurzel, cfg, ziel)
%STAPELEXPORT Alle Versuche eines Ordners auswerten und exportieren.
%   ueb = stapelExport(wurzel)            Export nach <Versuch>/export
%   ueb = stapelExport(wurzel, cfg, ziel) Export nach ziel/<Versuch>
%   Jeder Unterordner mit einer SiPB-Datei (cfg.import.datei_sipb) zaehlt als
%   Versuch. Zusaetzlich entsteht uebersicht.csv mit einer Zeile je Versuch.
%   Fehlerhafte Versuche werden uebersprungen und gemeldet, nicht abgebrochen.

if nargin < 2 || isempty(cfg)
    cfg = konfiguration();
end
if nargin < 3
    ziel = '';
end
d = dir(wurzel);
d = d([d.isdir] & ~strncmp({d.name}, '.', 1));
ueb = struct('name', {}, 'dauer_s', {}, 'n_abschnitte', {}, 'n_zyklen', {}, ...
             'Tmax_max', {}, 'M_max', {}, 'phi_hot_min', {}, 'phi_hot_max', {});
for k = 1:numel(d)
    ordner = fullfile(wurzel, d(k).name);
    if isempty(dir(fullfile(ordner, cfg.import.datei_sipb)))
        continue
    end
    try
        v = ladeVersuch(ordner, cfg);
        [v, seg, m] = analysiereVersuch(v, cfg);
        if isempty(ziel)
            z = fullfile(ordner, cfg.export.ordner);
        else
            z = fullfile(ziel, d(k).name);
        end
        exportiereSegmente(v, seg, m, z);
        i = numel(ueb) + 1;
        ueb(i).name = d(k).name;
        ueb(i).dauer_s = v.t_T(end) - v.t_T(1);
        ueb(i).n_abschnitte = numel(seg);
        ueb(i).n_zyklen = max([seg.zyklus]);
        ueb(i).Tmax_max = max(m.Tmax);
        ueb(i).M_max = max([seg.M_max]);
        ueb(i).phi_hot_min = min(m.phi_hot(m.hot_ok));
        ueb(i).phi_hot_max = max(m.phi_hot(m.hot_ok));
        fprintf('  %-45s %3d Abschnitte, %2d Zyklen\n', d(k).name, numel(seg), ueb(i).n_zyklen);
    catch e
        fprintf('  %-45s FEHLER: %s\n', d(k).name, e.message);
    end
end
if isempty(ziel)
    datei = fullfile(wurzel, 'uebersicht.csv');
else
    if ~exist(ziel, 'dir'), mkdir(ziel); end
    datei = fullfile(ziel, 'uebersicht.csv');
end
fid = fopen(datei, 'w');
fprintf(fid, 'versuch,dauer_s,abschnitte,zyklen,Tmax_max_degC,M_max_Nm,phi_hot_min_deg,phi_hot_max_deg\n');
for i = 1:numel(ueb)
    fprintf(fid, '%s,%.1f,%d,%d,%.2f,%.2f,%.1f,%.1f\n', ueb(i).name, ueb(i).dauer_s, ...
            ueb(i).n_abschnitte, ueb(i).n_zyklen, ueb(i).Tmax_max, ueb(i).M_max, ...
            ueb(i).phi_hot_min, ueb(i).phi_hot_max);
end
fclose(fid);
end
