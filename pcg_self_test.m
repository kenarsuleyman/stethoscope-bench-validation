function runDir = pcg_self_test()
%PCG_SELF_TEST  Synthetic heart-sound run with a known chain; checks analyze_pcg.
%   Chain: the pure-tone chain response (zero-phase magnitude), -20 dB, 0.237 s latency,
%   +30 ppm recorder clock, white noise at -85 dBFS, 44.1 kHz stereo, inverted polarity.
%   Expected: all clips aligned (lag within a few ms), rWave and rEnv high, and the
%   equalised versions (inverse of the same response) close to 1.
%   Output goes to data/pcg_selftest_<timestamp>/.

cfg = config();
[y, layout] = generate_pcg_stimulus(cfg);
fsP = cfg.stim.fs;
d = dir(fullfile(cfg.paths.figures, 'birlesik_*'));
Tt = readtable(fullfile(d(end).folder, d(end).name, 'tr', 'ozet_tablo.csv'));

% forward chain: zero-phase magnitude response, same interpolation as the equaliser
n = numel(y);  nfft = 2^nextpow2(n);
f = (0:nfft-1)'*fsP/nfft;  f = min(f, fsP - f);
fq = min(max(f, Tt.fNom_Hz(1)), Tt.fNom_Hz(end));
gDb = interp1(log(Tt.fNom_Hz), Tt.relLevel_dB, log(fq), 'pchip');
s = real(ifft(fft(y, nfft) .* 10.^(gDb/20)));  s = -0.1 * s(1:n);

pre = 1.0 + 0.237;
s = [zeros(round(pre*fsP),1); s; zeros(2*fsP,1)];
tOut = (0:floor(numel(s)/fsP*cfg.rec.fsSteth*(1+30e-6))-1)' / (cfg.rec.fsSteth*(1+30e-6));
xS = interp1((0:numel(s)-1)'/fsP, s, tOut, 'spline', 0);
rng(2);  xS = xS + 10^(-85/20) * randn(size(xS));

runDir = fullfile(cfg.paths.data, ['pcg_selftest_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(runDir);
audiowrite(fullfile(runDir, 'stethoscope.wav'), [xS xS], cfg.rec.fsSteth);
meta.label = 'pcg_selftest';  meta.startTime = datetime('now');  meta.preRoll = 1;
meta.devices = struct('stethoscope', 'SIM', 'speaker', 'SIM');  meta.stimType = 'pcg';
save(fullfile(runDir, 'meta.mat'), 'cfg', 'layout', 'meta');

res = analyze_pcg(runDir);
T = res.T;
fprintf('\nPCG self-test checks:\n');
fprintf('  clock        : %+.1f ppm (expected +30)\n', 1e6*(res.clockRatio - 1));
fprintf('  polarity     : %s (expected -1)\n', mat2str(unique(T.polarity)'));
fprintf('  rWaveEq      : min %.4f (expected ~1; only the 30 dB boost cap and noise limit it)\n', min(T.rWaveEq));
fprintf('  rEnvEq       : min %.4f\n', min(T.rEnvEq));
fprintf('  rWave / rEnv : median %.3f / %.3f (uncorrected chain)\n', median(T.rWave), median(T.rEnv));
end
