function c = make_chirp(fs, cfg)
%MAKE_CHIRP  Logarithmic sync chirp (same definition for stimulus and matched filter).
T = cfg.stim.chirpDur;
t = (0:round(T*fs)-1)'/fs;
c = cfg.stim.amp * chirp(t, cfg.stim.chirpF(1), T, cfg.stim.chirpF(2), 'logarithmic');
n = round(0.01*fs);
w = 0.5 - 0.5*cos(pi*(0:n-1)'/n);
c(1:n) = c(1:n).*w;  c(end-n+1:end) = c(end-n+1:end).*flipud(w);
end
