function runDir = self_test()
%SELF_TEST  Synthesise a fake run with a known chain and check the analysis recovers it.
%   Speaker: 4th-order HPF at 110 Hz (JBL GO 3 spec) + mild cubic distortion.
%   Stethoscope: 1st-order HPF 50 Hz, 4th-order LPF 3.5 kHz, -20 dB, noise, 44.1 kHz, +30 ppm clock.
%   Reference: 2nd-order HPF 80 Hz, -10 dB, noise, 48 kHz.
%   Output goes to data/selftest_<timestamp>/ and figures/ (overwrites figures).

cfg = config();
[y, layout] = generate_test_signal(cfg);
fsP = cfg.stim.fs;

[b, a] = butter(4, 110/(fsP/2), 'high');
spk = filter(b, a, y);
spk = spk + 0.05*spk.^3;

pre = 1.0 + 0.237;                                   % recorder pre-roll + Bluetooth latency
spk = [zeros(round(pre*fsP),1); spk; zeros(2*fsP,1)];

runDir = fullfile(cfg.paths.data, ['selftest_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(runDir);
rng(1);

% stethoscope
[b1, a1] = butter(1, 50/(fsP/2), 'high');
[b2, a2] = butter(4, 3500/(fsP/2), 'low');
s = 0.1 * filter(b2, a2, filter(b1, a1, spk));
xS = resample_skew(s, fsP, cfg.rec.fsSteth, 30e-6);
xS = xS + 10^(-85/20) * randn(size(xS));
audiowrite(fullfile(runDir, 'stethoscope.wav'), [xS xS], cfg.rec.fsSteth);

% reference
[b3, a3] = butter(2, 80/(fsP/2), 'high');
r = 0.3 * filter(b3, a3, spk);
xR = r + 10^(-75/20) * randn(size(r));
audiowrite(fullfile(runDir, 'reference.wav'), xR, cfg.rec.fsRef);

meta.label = 'selftest';  meta.startTime = datetime('now');
meta.devices = struct('stethoscope', 'SIM', 'speaker', 'SIM', 'reference', 'SIM');
save(fullfile(runDir, 'meta.mat'), 'cfg', 'layout', 'meta');

res = analyze_measurement(runDir);
T = res.stethoscope.T;
fprintf('\nSelf-test checks (stethoscope):\n');
fprintf('  clock ratio  : %+.1f ppm (expected +30)\n', 1e6*(res.stethoscope.clockRatio - 1));
fprintf('  max |fErr|   : %.4f %% (expected ~0.003)\n', max(abs(T.fErrPct)));
expGain = 20*log10(abs(freqz(b,a,T.fNom,fsP) .* freqz(b1,a1,T.fNom,fsP) .* ...
    freqz(b2,a2,T.fNom,fsP))) + 20*log10(0.1*cfg.stim.amp);
fprintf('  level error  : max %.2f dB vs. analytic chain (ignoring distortion)\n', ...
    max(abs(T.levelDb - expGain)));
make_figures({runDir});
end

function x = resample_skew(s, fsIn, fsOut, skew)
% recorder clock runs (1+skew) faster than the player clock
tOut = (0:floor(numel(s)/fsIn*fsOut*(1+skew))-1)' / (fsOut*(1+skew));
x = interp1((0:numel(s)-1)'/fsIn, s, tOut, 'spline', 0);
end
