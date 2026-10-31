function x = make_ess(fs, w)
%MAKE_ESS  Unit-amplitude exponential sine sweep (Farina) w.f(1) -> w.f(2) Hz over w.dur s with raised-cosine
%   fades of w.fadeDur s. Same phase at any sample rate, so the analysis can rebuild it at the recording rate.
T = w.dur;  L = T / log(w.f(2)/w.f(1));
t = (0:round(T*fs)-1)'/fs;
x = sin(2*pi*w.f(1)*L*(exp(t/L) - 1));
n = round(w.fadeDur*fs);  r = 0.5 - 0.5*cos(pi*(0:n-1)'/n);
x(1:n) = x(1:n).*r;  x(end-n+1:end) = x(end-n+1:end).*flipud(r);
end
