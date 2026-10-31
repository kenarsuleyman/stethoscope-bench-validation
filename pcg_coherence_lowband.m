function T = pcg_coherence_lowband(runDirs)
%PCG_COHERENCE_LOWBAND  Why is the played-vs-recorded coherence low below 50 Hz? (advisor's 2nd review, M2)
%   The coherence is estimated exactly as in analyze_pcg (Welch, Hann 8192 at 44.1 kHz = 5.4 Hz bins, 50 % overlap,
%   spectra summed over the 47 segments) for
%     (a) the recordings,
%     (b) an ideal linear system: the played segments filtered with the measured tone response (no noise, no
%         distortion, no clock effects), i.e. the same estimator bias without any physical cause,
%     (c) the played segments themselves: share of their power below 50 Hz.
%   If (b) is as low as (a) below 50 Hz, the low value is an estimation effect of a band with little signal power
%   and a steep response (leakage from the stronger 50-100 Hz content through the window side lobes).
%   Writes results/pcg_coherence_lowband.csv.
if nargin < 1
    runDirs = {'data/20261009_190101_pcg_run1', 'data/20261009_190630_pcg_run2', 'data/20261009_191158_pcg_run3'};
end
here = fileparts(mfilename('fullpath'));
L = load(fullfile(here, runDirs{1}, 'meta.mat'));  layout = L.layout;
P = load(fullfile(here, runDirs{1}, 'results_pcg.mat'));
fs = 44100;  nfftT = 8192;  win = hann(nfftT);
Tt = readtable(fullfile(tone_response_dir(), 'tr', 'ozet_tablo.csv'));   % pure-tone response, as pcg_forward_sim / analyze_pcg
R = struct('f', Tt.fNom_Hz, 'dB', Tt.relLevel_dB, 'maxBoostDb', 30);

Pxy = 0;  Pxx = 0;  Pyy = 0;  Esub = 0;  Eall = 0;
for k = 1:numel(layout.files)
    ref = double(layout.ref{k});  refR = resample(ref, fs, layout.fsNat(k));
    y = apply_chain_gain(refR, fs, R, 'forward');
    [p, f] = cpsd(refR, y, win, nfftT/2, nfftT, fs);  Pxy = Pxy + p;
    Pxx = Pxx + pwelch(refR, win, nfftT/2, nfftT, fs);
    Pyy = Pyy + pwelch(y, win, nfftT/2, nfftT, fs);
    [pr, fr] = pwelch(ref, [], [], [], layout.fsNat(k));
    m = fr >= 25 & fr <= 900;
    Esub = Esub + sum(pr(m & fr < 50));  Eall = Eall + sum(pr(m));
end
cohIdeal = abs(Pxy).^2 ./ (Pxx .* Pyy);
cohMeas = P.res.H.coh;  fm = P.res.H.f;
bands = [25 50; 50 100; 100 200; 200 550; 550 900];
T = table('Size', [size(bands, 1) 4], 'VariableTypes', repmat({'double'}, 1, 4), ...
    'VariableNames', {'f1_Hz', 'f2_Hz', 'coh_measured_run1', 'coh_ideal_linear'});
for b = 1:size(bands, 1)
    mi = f >= bands(b, 1) & f < bands(b, 2);  mm = fm >= bands(b, 1) & fm < bands(b, 2);
    T{b, :} = [bands(b, :), mean(cohMeas(mm)), mean(cohIdeal(mi))];
end
% (d) noise during the run: the 1.5 s gaps between the segments vs the 4 s silent section at the start.
%     The coherence expected from noise alone uses the noise measured where the segments are played.
nb = [25 50; 50 100; 100 200];
gapPow = zeros(numel(runDirs), size(nb, 1));  silPow = gapPow;  cohGap = gapPow;
for r = 1:numel(runDirs)
    S = load(fullfile(here, runDirs{r}, 'meta.mat'));  cfg = S.cfg;  lay = S.layout;
    Pr = load(fullfile(here, runDirs{r}, 'results_pcg.mat'));  H = Pr.res.H;
    [x, fsr] = audioread(fullfile(here, runDirs{r}, 'stethoscope.wav'));  x = x(:, cfg.rec.stethChannel);
    preRoll = 1;  if isfield(S.meta, 'preRoll'), preRoll = S.meta.preRoll; end
    on1 = find_chirp(x, fsr, cfg, [1, round((preRoll + lay.lead + 5)*fsr)]);
    t2i = @(t) on1 + round(t * fsr * Pr.res.clockRatio);
    sil = x(t2i(lay.noiseStart + 0.3) : t2i(lay.noiseEnd - 0.3));
    gaps = [];
    for k = 1:numel(lay.files) - 1
        g1 = lay.clipStart(k) + numel(lay.ref{k}) / lay.fsNat(k) + 0.2;  g2 = lay.clipStart(k+1) - 0.2;
        if g2 - g1 > 0.8, gaps = [gaps; x(t2i(g1) : t2i(g2))]; end %#ok<AGROW>
    end
    nw = 8192;
    [ps, fq] = pwelch(sil, hann(nw), nw/2, nw, fsr);  pg = pwelch(gaps, hann(nw), nw/2, nw, fsr);
    % expected coherence from the gap noise: noise PSD per segment-sum, scaled like H.Pyy (summed over segments)
    Ng = interp1(fq, pg, H.f) * H.nClips;
    cg = max(0, 1 - Ng ./ H.Pyy);
    for b = 1:size(nb, 1)
        mq = fq >= nb(b, 1) & fq < nb(b, 2);  mh = H.f >= nb(b, 1) & H.f < nb(b, 2);
        silPow(r, b) = 10*log10(sum(ps(mq)));  gapPow(r, b) = 10*log10(sum(pg(mq)));  cohGap(r, b) = mean(cg(mh));
    end
end
disp(T)
fprintf('played segments: %.1f %% of the 25-900 Hz power lies below 50 Hz\n', 100*Esub/Eall);
for b = 1:size(nb, 1)
    fprintf('%3d-%3d Hz: noise in the gaps minus noise in the initial silence %+.1f dB (runs: %s); coherence expected from gap noise %.2f\n', ...
        nb(b, 1), nb(b, 2), mean(gapPow(:, b) - silPow(:, b)), mat2str(round(gapPow(:, b)' - silPow(:, b)', 1)), mean(cohGap(:, b)));
end
writetable(T, fullfile(gui_ctx('outDir', fullfile(here, 'results')), 'pcg_coherence_lowband.csv'));
end
