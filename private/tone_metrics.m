function m = tone_metrics(x, noise, fs, f0, cfg)
%TONE_METRICS  Frequency, level, SNR and THD of a steady-state tone segment.
%   X      tone segment (column, full-scale = 1)
%   NOISE  silent segment of the same recording (at least numel(X) samples)
%   Level is in dBFS where 0 dBFS = full-scale sine amplitude.
%   SNR compares the tone with the noise floor measured with the same window
%   and length (identical equivalent noise bandwidth) around f0.

N    = numel(x);
nfft = 2^nextpow2(N) * cfg.ana.zeroPad;
f    = (0:nfft/2)' * fs / nfft;
x    = x - mean(x);

wF = flattopwin(N, 'periodic');          % amplitude-accurate window
wH = hann(N, 'periodic');                % frequency-accurate window
AF = amp_spec(x, wF, nfft);
AH = amp_spec(x, wH, nfft);

% noise floor spectrum: average power over N-length chunks of the silent segment
nCh = max(1, floor(numel(noise)/N));
PN  = zeros(size(AF));
for c = 1:nCh
    seg = noise((c-1)*N+1 : c*N);
    PN  = PN + amp_spec(seg - mean(seg), wF, nfft).^2;
end
AN = sqrt(PN / nCh);

% --- fundamental ---
hw   = max(cfg.ana.searchRel*f0, cfg.ana.searchMinHz);
band = find(f >= f0-hw & f <= f0+hw);
[~, i] = max(AH(band));  i = band(i);
m.fMeas   = parabolic_peak(f, AH, i);
m.amp     = max(AF(band));
m.levelDb = 20*log10(m.amp);
m.noiseDb = 20*log10(rms(AN(band)));
m.snrDb   = m.levelDb - m.noiseDb;

% --- harmonics ---
hAmp = [];
for h = 2:cfg.ana.nHarm
    fh = h * m.fMeas;
    if fh > min(fs/2, cfg.ana.thdMaxF), break; end
    hb = find(abs(f - fh) <= max(0.02*fh, cfg.ana.searchMinHz));
    hAmp(end+1) = max(AF(hb)); %#ok<AGROW>
end
m.thdPct = 100 * sqrt(sum(hAmp.^2)) / m.amp;
if isempty(hAmp), m.thdPct = NaN; end

% is the fundamental the strongest component between 15 Hz and fs/2?
valid = f >= 15;
m.dominant = m.amp >= max(AF(valid)) * 0.999;
end

function A = amp_spec(x, w, nfft)
X = fft(x .* w, nfft);
A = abs(X(1:nfft/2+1)) * 2 / sum(w);
end

function fp = parabolic_peak(f, A, i)
if i <= 1 || i >= numel(A), fp = f(i); return; end
a = log(A(i-1)); b = log(A(i)); c = log(A(i+1));
p = 0.5 * (a - c) / (a - 2*b + c);
fp = f(i) + p * (f(2) - f(1));
end
