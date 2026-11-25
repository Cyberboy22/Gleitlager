function y = gleitMittel(x, n)
%GLEITMITTEL Zentrierter gleitender Mittelwert ueber n Werte, NaN-tolerant.
%   y = gleitMittel(x, n). Am Rand wird ueber die vorhandenen Werte gemittelt.
%   (Eigene Funktion statt movmean, damit der Code auch in aelteren MATLAB-
%   und Octave-Versionen identisch laeuft.)
x = x(:);
n = max(1, round(n));
if n == 1
    y = x;
    return
end
ok = isfinite(x);
x0 = x;
x0(~ok) = 0;
k = ones(n, 1);
s = conv(x0, k, 'same');
c = conv(double(ok), k, 'same');
y = s ./ c;
y(c == 0) = NaN;
end
