function [y, gDb, f] = apply_chain_gain(x, fs, R, mode, fRange)
%APPLY_CHAIN_GAIN  Zero-phase magnitude filter built from the pure-tone response R (dB re 250 Hz).
%   The response measured at the 50 tone frequencies is interpolated with pchip on a log-frequency
%   axis; outside 30-6000 Hz the edge values are held. The gain is applied as a real (zero-phase)
%   spectral weight on an FFT of length 2^nextpow2(2n); no FIR is designed and no other
%   regularisation is used than the boost cap.
%     mode 'inverse'  response correction: gain = -R, boost capped at R.maxBoostDb (analyze_pcg)
%     mode 'forward'  simulation of the speaker + stethoscope magnitude response: gain = +R
%   fRange (optional, Hz) limits the gain to [f1 f2); elsewhere the gain is 0 dB. Partial corrections
%   use it to correct only one frequency region (a 1/3-octave cosine ramp avoids a hard step).

if nargin < 5, fRange = []; end
n = numel(x);  nfft = 2^nextpow2(2*n);
f = (0:nfft-1)'*fs/nfft;  f = min(f, fs - f);                % two-sided magnitude grid
fq = min(max(f, R.f(1)), R.f(end));
gDb = interp1(log(R.f), R.dB, log(fq), 'pchip');
switch mode
    case 'inverse', gDb = min(-gDb, R.maxBoostDb);
    case 'forward'   % gDb = +R
    otherwise, error('mode must be ''inverse'' or ''forward''');
end
if ~isempty(fRange)
    w = ones(size(f));
    lo = fRange(1);  hi = fRange(2);
    if lo > 0, w = w .* ramp(f, lo); end
    if isfinite(hi), w = w .* (1 - ramp(f, hi)); end
    gDb = gDb .* w;
end
Y = fft(x(:), nfft) .* 10.^(gDb/20);
y = real(ifft(Y));  y = y(1:n);
end

function r = ramp(f, fc)
% 0 below fc/2^(1/6), 1 above fc*2^(1/6), raised-cosine on log f in between
a = log2(max(f, eps) / fc) * 3;                % +-0.5 at the 1/3-octave edges
r = 0.5 + 0.5*sin(pi * min(max(a, -0.5), 0.5));
end
