function pcg_coherence_check(runDirs)
%PCG_COHERENCE_CHECK  Why the coherence (~0.8) is lower than the band SNR (~31 dB) suggests (review item).
%   For a linear system with additive noise, gamma^2(f) = 1 - N(f)/Pyy(f). Using the summed spectra of
%   the 47 clips (analyze_pcg: Welch, Hann 8192, 50 % overlap, 5.4 Hz bins) and the noise PSD of the
%   in-run silence, this prints the coherence that noise alone would give next to the measured one,
%   the per-frequency SNR, and the agreement of the heart-sound transfer function with the pure-tone
%   response restricted to frequencies where the coherence is high.

if nargin < 1
    runDirs = {'data/20261009_190101_pcg_run1', 'data/20261009_190630_pcg_run2', 'data/20261009_191158_pcg_run3'};
end
here = fileparts(mfilename('fullpath'));
for r = 1:numel(runDirs)
    S = load(fullfile(here, runDirs{r}, 'results_pcg.mat'));  H = S.res.H;
    f = H.f;  N = interp1(S.res.noise.f, S.res.noise.P, f) * H.nClips;   % noise power in the summed Pyy
    cohMeas(:, r) = H.coh;                                    %#ok<AGROW>
    cohNoise(:, r) = max(0, 1 - N ./ H.Pyy);                   %#ok<AGROW>
    snrF(:, r) = 10*log10(max(H.Pyy - N, eps) ./ N);           %#ok<AGROW>
    Hdb(:, r) = H.dB;                                          %#ok<AGROW>
end
cm = mean(cohMeas, 2);  cn = mean(cohNoise, 2);  sf = mean(snrF, 2);
Hdb = mean(Hdb, 2);  Hdb = Hdb - interp1(f, Hdb, 250);
R = S.res.chain;  Rt = interp1(log(R.f), R.dB, log(min(max(f, R.f(1)), R.f(end))), 'pchip');

fprintf('band        measured coh   coh from noise only   per-frequency SNR (dB)\n');
for b = [25 50; 50 100; 100 200; 200 550; 550 900]'
    m = f >= b(1) & f < b(2);
    fprintf('%4d-%4d Hz   %.2f           %.2f                 %5.1f\n', b, median(cm(m)), median(cn(m)), median(sf(m)));
end
m = f >= 50 & f < 550;
fprintf('50-550 Hz: measured %.2f, noise-only %.2f -> the remaining loss is not explained by additive noise\n', ...
    median(cm(m)), median(cn(m)));
d = abs(Hdb - Rt);
for thr = [0 0.5 0.8]
    m = f >= 30 & f <= 800 & cm >= thr;
    fprintf('|H_heart - H_tone|, 30-800 Hz, coherence >= %.1f: max %.1f dB, median %.1f dB (%d of %d bins)\n', ...
        thr, max(d(m)), median(d(m)), nnz(m), nnz(f >= 30 & f <= 800));
end
% the same at the tone frequencies (as quoted before: H_heart interpolated to the 50 tones)
ft = R.f(R.f >= 30 & R.f <= 800);
Ht = interp1(f, Hdb, ft);  Rt0 = interp1(R.f, R.dB, ft);  ct = interp1(f, cm, ft);
for thr = [0 0.5 0.8]
    m = ct >= thr;
    fprintf('at tone frequencies, coherence >= %.1f: max %.1f dB, median %.1f dB (%d of %d tones)\n', ...
        thr, max(abs(Ht(m) - Rt0(m))), median(abs(Ht(m) - Rt0(m))), nnz(m), numel(ft));
end
end
