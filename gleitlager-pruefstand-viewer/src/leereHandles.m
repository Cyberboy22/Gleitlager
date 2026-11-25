function h = leereHandles(n)
%LEEREHANDLES Leeres Array fuer Grafik-Handles (MATLAB: gobjects, Octave: Zahlen).
if exist('gobjects') > 0 %#ok<EXIST>
    h = gobjects(1, n);
else
    h = zeros(1, n);
end
end
