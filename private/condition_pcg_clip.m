function [xNat, fsNat, x48] = condition_pcg_clip(path, cfg)
%CONDITION_PCG_CLIP  Minimal conditioning of a PCG recording for loudspeaker playback.
%   Stereo -> mono (channel mean, as in the model's inference code), DC/baseline removal
%   (4th-order Butterworth high-pass at cfg.pcg.hpf, zero-phase), raised-cosine fades.
%   XNAT is the conditioned clip at its native rate FSNAT; X48 is the same clip resampled
%   to cfg.stim.fs. Both are scaled so that max(abs(X48)) = 1 (level is applied by the caller).
[x, fsNat] = audioread(path);
x = mean(x, 2);
x = x - mean(x);
[z, p, k] = butter(4, cfg.pcg.hpf/(fsNat/2), 'high');
[sos, g] = zp2sos(z, p, k);
x = filtfilt(sos, g, x);
n = round(cfg.pcg.fadeDur*fsNat);
w = 0.5 - 0.5*cos(pi*(0:n-1)'/n);
x(1:n) = x(1:n).*w;  x(end-n+1:end) = x(end-n+1:end).*flipud(w);
x48 = resample(x, cfg.stim.fs, fsNat);
s = max(abs(x48));
x48 = x48 / s;
xNat = x / s;
end
