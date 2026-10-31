function res = analyze_sweep(runDir, toneRun, tubeL)
%ANALYZE_SWEEP  Continuous magnitude response from an exponential-sweep run (run_measurement(label,'pc','sweep')).
%   Aligns the recording with the sync chirps (as analyze_measurement), deconvolves every sweep with the unit
%   sweep rebuilt at the recording rate (regularized spectral division), keeps the linear impulse response
%   (cfg.sweep.irLen; the harmonic products arrive before it and are cut off) and averages the transfer functions.
%   The level is expressed like the tone levels: dBFS of a tone played at the stimulus amplitude, so the curve can
%   be overlaid on a tone run of the same setup (TONERUN, optional) as a consistency check.
%   Peaks in 120-1500 Hz are listed and compared with the quarter-wave prediction (2k-1)c/4L for tube length TUBEL (m).
%   Writes results_sweep.mat / .csv and figures/{tr,en}/S_supurme_yaniti.{pdf,png} into RUNDIR.
%
%   analyze_sweep('data/..._sweep_run1', 'data/20261023_234641_tube30cm_run1', 0.30)
if nargin < 2, toneRun = ''; end
if nargin < 3, tubeL = 0.30; end
S = load(fullfile(runDir, 'meta.mat'));
cfg = S.cfg;  layout = S.layout;  w = layout.sweep;
cfg.fig = config().fig;                                  % current figure style (ticks, dpi), not the run snapshot
[x, fs] = audioread(fullfile(runDir, 'stethoscope.wav'));
x = x(:, cfg.rec.stethChannel);

% --- alignment (same as analyze_measurement) ---
preRoll = 1;  if isfield(S.meta, 'preRoll'), preRoll = S.meta.preRoll; end
[on1, q1] = find_chirp(x, fs, cfg, [1, round((preRoll + layout.lead + 5)*fs)]);
[on2, q2] = find_chirp(x, fs, cfg, on1 + round(layout.chirpEnd*fs) + round([-3 3]*fs));
clockRatio = (on2 - on1) / (layout.chirpEnd*fs);
if q2 < 10 || abs(clockRatio - 1) > 0.01, clockRatio = 1; warning('end chirp unreliable, nominal clock'); end
t2i = @(t) on1 + round(t * fs * clockRatio);

% --- deconvolution ---
ref = make_ess(fs, w);                                 % unit amplitude -> |H| includes the stimulus amplitude
N = numel(ref) + round(0.9*w.gap*fs);
nfft = 2^nextpow2(2*N);
Sref = fft(ref, nfft);
fAx = (0:nfft-1)' * fs / nfft;  fAx(fAx > fs/2) = fs - fAx(fAx > fs/2);    % two-sided |f|
% regularization: negligible inside the sweep band (the sweep spectrum falls as 1/f, so a larger in-band term
% would attenuate the high frequencies), strong outside it
reg = 1e-8 * max(abs(Sref).^2) + (fAx < w.f(1) | fAx > w.f(2)) * max(abs(Sref).^2);
nKeep = round(w.irLen*fs);  nPre = round(0.005*fs);  nFade = round(0.02*fs);
win = zeros(nfft, 1);
win(1:nKeep) = 1;  win(nKeep-nFade+1:nKeep) = 0.5 + 0.5*cos(pi*(1:nFade)'/nFade);
win(end-nPre+1:end) = 0.5 - 0.5*cos(pi*(0:nPre-1)'/nPre);
H = zeros(nfft, w.n);
for k = 1:w.n
    i0 = t2i(layout.sweepStart(k));
    seg = x(i0 : min(i0+N-1, numel(x)));
    h = real(ifft(fft(seg, nfft) .* conj(Sref) ./ (abs(Sref).^2 + reg)));
    H(:, k) = fft(h .* win);
end

% --- 1/n-octave smoothing on a log grid, mean and run-to-run std ---
f = (0:nfft/2)' * fs / nfft;
fg = logspace(log10(w.f(1)), log10(w.f(2)), 2000)';
oct = cfg.sweep.smoothOct;
P = abs(H(1:nfft/2+1, :)).^2;
Ls = zeros(numel(fg), w.n);
cs = [zeros(1, w.n); cumsum(P)];
for i = 1:numel(fg)
    lo = find(f >= fg(i)*2^(-oct/2), 1);  hi = find(f <= fg(i)*2^(oct/2), 1, 'last');
    Ls(i, :) = 10*log10((cs(hi+1, :) - cs(lo, :)) / (hi - lo + 1));
end
Pm = abs(mean(H(1:nfft/2+1, :), 2)).^2;  cm = [0; cumsum(Pm)];
level = zeros(numel(fg), 1);
for i = 1:numel(fg)
    lo = find(f >= fg(i)*2^(-oct/2), 1);  hi = find(f <= fg(i)*2^(oct/2), 1, 'last');
    level(i) = 10*log10((cm(hi+1) - cm(lo)) / (hi - lo + 1));
end
sdRuns = std(Ls, 0, 2);

% --- peaks ---
c = 343;
m = fg >= 120 & fg <= 1500;
[pv, loc] = findpeaks(level(m), 'MinPeakProminence', 3);
fm = fg(m);  pk = fm(loc);
pred = (2*(1:4) - 1) * c / (4*tubeL);
fprintf('sweep %s: chirp q=%.0f/%.0f, clock %+.0f ppm, %d sweeps, run-to-run std median %.2f dB (30-6000 Hz)\n', ...
    runDir, q1, q2, 1e6*(clockRatio-1), w.n, median(sdRuns(fg >= 30 & fg <= 6000)));
fprintf('peaks (120-1500 Hz): %s Hz (levels %s dBFS)\n', mat2str(round(pk', 1)), mat2str(round(pv', 1)));
fprintf('quarter-wave (2k-1)c/4L, L = %.0f mm: %s Hz; measured/predicted: %s\n', 1000*tubeL, ...
    mat2str(round(pred)), mat2str(round(pk'./pred(1:min(end, numel(pk))), 3)));

res = struct('f', fg, 'levelDb', level, 'sdRunsDb', sdRuns, 'peaksHz', pk, 'peaksDb', pv, ...
    'predHz', pred, 'tubeL', tubeL, 'clockRatio', clockRatio, 'chirpQ', [q1 q2]);
T = table(fg, level, sdRuns, 'VariableNames', {'f_Hz', 'level_dBFS', 'std_runs_dB'});

% --- consistency with a tone run of the same setup ---
if ~isempty(toneRun)
    R = load(fullfile(toneRun, 'results.mat'));  Tt = R.res.stethoscope.T;
    sw = interp1(fg, level, Tt.fNom);
    ok = Tt.fNom >= 30 & Tt.fNom <= 6000 & Tt.snrDb >= 20;
    d = sw(ok) - Tt.levelDb(ok);
    fprintf('sweep minus tone level at %d tones (30-6000 Hz, SNR >= 20 dB): median %+.2f dB, |d| median %.2f, max %.2f dB\n', ...
        nnz(ok), median(d), median(abs(d)), max(abs(d)));
    res.toneRun = toneRun;  res.toneDiffDb = d;
end
save(fullfile(runDir, 'results_sweep.mat'), 'res');
writetable(T, fullfile(runDir, 'results_sweep.csv'));

% --- figure (TR + EN) ---
for lang = {'tr', 'en'}
    cfg.lang = lang{1};  tr = strcmp(cfg.lang, 'tr');
    cfg.paths.figures = fullfile(runDir, 'figures', cfg.lang);
    fig = new_figure(cfg, 8);  ax = axes(fig);  hold(ax, 'on');
    hS = semilogx(ax, fg, level, '-', 'Color', [0.8 0.35 0], 'LineWidth', 1);
    hh = hS;  names = {pick(tr, sprintf('Üstel süpürme (n = %d)', w.n), sprintf('Exponential sweep (n = %d)', w.n))};
    if ~isempty(toneRun)
        hT = semilogx(ax, Tt.fNom, Tt.levelDb, 'o', 'MarkerSize', 3, 'Color', [0.3 0.3 0.3]);
        hh(end+1) = hT;  names{end+1} = pick(tr, 'Saf tonlar', 'Pure tones'); %#ok<AGROW>
    end
    for p = pred(pred < 6600), xline(ax, p, '--', 'Color', [0.8 0.35 0], 'LineWidth', 0.6); end
    set(ax, 'XScale', 'log');  xlim(ax, [27 6600]);  ylim(ax, [-90 0]);
    set(ax, 'XTick', cfg.fig.fticks);
    mark_band(ax, cfg, false);
    legend(ax, hh, names, 'Location', 'southeast');
    text(ax, 0.02, 0.97, pick(tr, sprintf('Kesikli çizgiler: çeyrek dalga öngörüsü, L = %.0f mm', 1000*tubeL), ...
        sprintf('Dashed lines: quarter-wave prediction, L = %.0f mm', 1000*tubeL)), 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'FontSize', cfg.fig.fontSize - 1);
    ylabel(ax, pick(tr, 'Ton seviyesi (dBFS)', 'Tone level (dBFS)'));
    xlabel(ax, pick(tr, 'Frekans (Hz)', 'Frequency (Hz)'));
    save_figure(fig, 'S_supurme_yaniti', cfg);
end
end

function s = pick(tr, a, b)
if tr, s = a; else, s = b; end
end
