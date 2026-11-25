% START_DEMO  Beispielversuch laden, auswerten und im Viewer oeffnen.
%   In MATLAB: diesen Ordner als aktuellen Ordner waehlen und
%       start_demo
%   eingeben. Fuer eigene Daten siehe README.md.

wurzel = fileparts(mfilename('fullpath'));
addpath(fullfile(wurzel, 'src'));

ordner = fullfile(wurzel, 'beispieldaten', 'V01_start_stopp_schmierstoffmangel_60C');
fprintf('Lade %s ...\n', ordner);
pruefstandViewer(ordner);

% Weitere Beispiele:
%   pruefstandViewer(fullfile(wurzel, 'beispieldaten', 'V02_ueberlast_60C_deutsches_format'));
%   stapelExport(fullfile(wurzel, 'beispieldaten'));   % alle Versuche exportieren
