function make_pcg_figures(runDirs)
%MAKE_PCG_FIGURES  Figures of the heart-sound playback test (Turkish + English).
%   H1  transfer function estimated from the heart-sound clips (mean over runs) vs. the
%       pure-tone chain response, with coherence
%   H2  model-band spectrograms of one normal and one abnormal clip: as played and as
%       recorded by the stethoscope
%   H3  model probability per clip: played vs. stethoscope recording (mean +/- std over runs)
%   If cfg.pcg.showCorrection (diagnostic: inverse of the pure-tone chain response):
%   H4  (a) correction gain vs. frequency with the measured chain response, (b) mean model-band
%       spectrum of the clips: played, recorded, recorded + correction
%   H5  model probability: played vs. corrected stethoscope recording
%   H3/H5 need pcg_test/results/pcg_per_clip.csv (pcg_test/pcg_model_compare.py)
%   Output: pcg_test/figures/{tr,en}/ (PDF + PNG) and pcg_test/results/pcg_signal_summary.csv

cfg = config();
if ischar(runDirs) || isstring(runDirs), runDirs = cellstr(runDirs); end
nR = numel(runDirs);
for r = 1:nR, S(r) = load(fullfile(runDirs{r}, 'results_pcg.mat')); end %#ok<AGROW>
layout = load(fullfile(runDirs{1}, 'meta.mat')).layout;

% --- signal-level summary over runs ---
T = S(1).res.T;
T.label = true_labels(T.file, cfg);       % layout/T.label keep the old, inverted PhysioNet labels
vars = {'bandSnrDb','rWave','rEnv','rWaveEq','rEnvEq'};
for v = vars, T.(v{1}) = mean(cell2mat(arrayfun(@(s) s.res.T.(v{1}), S, 'UniformOutput', false)), 2); end
resDir = gui_ctx('outDir', fullfile(cfg.paths.pcg, 'results'));  if ~exist(resDir, 'dir'), mkdir(resDir); end
G = groupsummary(T, {'source','label'}, 'median', vars);
writetable(G, fullfile(resDir, 'pcg_signal_summary.csv'));
writetable(T, fullfile(resDir, 'pcg_signal_per_clip.csv'));
disp(G);
fprintf('all clips: band SNR median %.1f dB (min %.1f); rWave %.3f -> %.3f eq; rEnv %.3f -> %.3f eq (medians)\n', ...
    median(T.bandSnrDb), min(T.bandSnrDb), median(T.rWave), median(T.rWaveEq), median(T.rEnv), median(T.rEnvEq));

% --- transfer function (mean over runs, dB re 250 Hz) ---
f = S(1).res.H.f;
Hdb = mean(cell2mat(arrayfun(@(s) s.res.H.dB, S, 'UniformOutput', false)), 2);
coh = mean(cell2mat(arrayfun(@(s) s.res.H.coh, S, 'UniformOutput', false)), 2);
Hdb = Hdb - interp1(f, Hdb, 250);
R = S(1).res.chain;

% --- correction gain (as analyze_pcg/equalize) and mean model-band spectra ---
fg = logspace(log10(20), log10(1000), 400)';
gDb = min(-interp1(log(R.f), R.dB, log(min(max(fg, R.f(1)), R.f(end))), 'pchip'), R.maxBoostDb);
[Ps, fs4] = mean_spectra(layout, runDirs);

P = [];
pf = gui_ctx('perClipCsv', fullfile(cfg.paths.pcg, 'results', 'pcg_per_clip.csv'));
if isfile(pf), P = readtable(pf, 'TextType', 'string'); end

for lang = {'tr', 'en'}
    cfg.lang = lang{1};  tr = strcmp(cfg.lang, 'tr');
    L = @(a, b) pick(tr, a, b);
    cfg.paths.figures = fullfile(gui_ctx('outDir', fullfile(cfg.paths.pcg, 'figures')), cfg.lang);

    % ---------------- H1 ----------------
    fig = new_figure(cfg, 11);
    tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl, [2 1]);  hold(ax, 'on');
    m = f >= 20 & f <= 1000;
    h1 = semilogx(ax, f(m), Hdb(m), 'Color', [0 0.3 0.6], 'LineWidth', 1.2);
    h2 = semilogx(ax, R.f, R.dB, 'ko--', 'MarkerSize', 3, 'LineWidth', 0.9);
    set(ax, 'XScale', 'log', 'XTick', cfg.fig.fticks);  xlim(ax, [20 1000]);  ylim(ax, cfg.fig.respYlim);
    mark_band(ax, cfg, false);
    ylabel(ax, L("Bağıl genlik (dB)", "Relative level (dB)"));
    legend(ax, [h1 h2], [L(sprintf("Kalp sesi kayıtlarından (n = %d segment × %d)", height(T), nR), ...
        sprintf("From heart-sound segments (n = %d segments × %d)", height(T), nR)), ...
        L("Saf ton ölçümünden", "From pure-tone measurement")], 'Location', 'southeast');
    title(ax, L("Hoparlör + MEMS stetoskop, 0 dB = 250 Hz", ...
        "Speaker + MEMS stethoscope, 0 dB = 250 Hz"));
    set(ax, 'XTickLabel', []);
    ax2 = nexttile(tl);  hold(ax2, 'on');
    semilogx(ax2, f(m), coh(m), 'Color', [0 0.3 0.6], 'LineWidth', 1.1);
    set(ax2, 'XScale', 'log', 'XTick', cfg.fig.fticks);  xlim(ax2, [20 1000]);  ylim(ax2, [0 1.05]);
    mark_band(ax2, cfg, false);
    xlabel(ax2, L("Frekans (Hz)", "Frequency (Hz)"));  ylabel(ax2, L("Koherens", "Coherence"));
    linkaxes([ax ax2], 'x');
    save_figure(fig, 'H1_pcg_transfer', cfg);

    % ---------------- H2 ----------------
    ex = pick_examples(T, P);
    nCol = 2;
    fig = new_figure(cfg, 12);
    tl = tiledlayout(fig, 2, nCol, 'TileSpacing', 'compact', 'Padding', 'compact');
    cols = {L("Oynatılan segment", "Played segment"), L("Stetoskop kaydı", "Stethoscope recording"), ...
            L("Stetoskop + yanıt düzeltmesi", "Stethoscope + response correction")};
    % all four panels on one dB scale: 0 dB = the largest bin of the four (each signal peak-normalized first)
    Sp = cell(2, nCol);
    for e = 1:2
        k = ex(e);  name = layout.files(k);
        sig = {resample(double(layout.ref{k}), 4000, layout.fsNat(k)), ...
               read4(fullfile(runDirs{1}, 'pcg_clips', 'steth', name)), ...
               read4(fullfile(runDirs{1}, 'pcg_clips', 'steth_eq', name))};
        for c = 1:nCol
            [Sx, F, Tm] = spectrogram(model_prep(sig{c}), hann(256), 192, 1024, 4000);
            Sp{e, c} = 20*log10(abs(Sx) + eps);
        end
    end
    top = max(cellfun(@(s) max(s(F >= 25 & F <= 900, :), [], 'all'), Sp), [], 'all');
    for e = 1:2
        k = ex(e);  name = layout.files(k);
        for c = 1:nCol
            ax = nexttile(tl);
            imagesc(ax, Tm, F, Sp{e, c} - top);  axis(ax, 'xy');  ylim(ax, [25 900]);
            clim(ax, [-70 0]);  colormap(ax, parula);
            ttl = cols{c};
            if ~isempty(P)
                j = find(P.file == name, 1);
                pv = [P.p_played(j), P.p_steth_mean(j), P.p_steth_eq_mean(j)];
                ttl = sprintf('%s\np = %.2f', ttl, pv(c));
            end
            title(ax, ttl, 'FontSize', cfg.fig.fontSize - 1);
            if c == 1
                lab = L(["Normal" "Anormal"], ["Normal" "Abnormal"]);
                ylabel(ax, {sprintf('%s (%s)', lab(T.label(k)+1), T.source(k)), L("Frekans (Hz)", "Frequency (Hz)")});
            else
                set(ax, 'YTickLabel', []);
            end
            if e == 2, xlabel(ax, L("Zaman (s)", "Time (s)")); end
        end
    end
    cb = colorbar(ax);  cb.Layout.Tile = 'east';
    cb.Label.String = L("Bağıl seviye (dB)", "Relative level (dB)");  cb.Label.FontName = cfg.fig.font;
    save_figure(fig, 'H2_pcg_spektrogram_karsilastirma', cfg);

    % ---------------- H3: model probabilities, uncorrected ----------------
    if ~isempty(P)
        prob_figure(cfg, P, 'p_steth', L("Stetoskop kaydı", "Stethoscope recording"), L, 'H3_pcg_model_olasilik');
    end
    if ~cfg.pcg.showCorrection, continue; end

    % ---------------- H4: what the correction does ----------------
    fig = new_figure(cfg, 12);
    tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl);  hold(ax, 'on');
    h1 = semilogx(ax, R.f, R.dB, 'ko--', 'MarkerSize', 3, 'LineWidth', 0.9);
    h2 = semilogx(ax, fg, gDb, '-', 'Color', [0.8 0.2 0.1], 'LineWidth', 1.4);
    yline(ax, 0, '-', 'Color', [0.6 0.6 0.6]);
    set(ax, 'XScale', 'log', 'XTick', cfg.fig.fticks);  xlim(ax, [20 1000]);  ylim(ax, [-35 35]);
    mark_band(ax, cfg, false);
    ylabel(ax, L("Kazanç (dB)", "Gain (dB)"));  set(ax, 'XTickLabel', []);
    legend(ax, [h1 h2], [L("Hoparlör + MEMS stetoskop yanıtı (saf ton, 0 dB = 250 Hz)", "Speaker + MEMS stethoscope response (pure tones, 0 dB = 250 Hz)"), ...
        L(sprintf("Düzeltme kazancı (ters yanıt, en fazla +%d dB)", R.maxBoostDb), ...
          sprintf("Correction gain (inverse response, at most +%d dB)", R.maxBoostDb))], 'Location', 'southeast');
    title(ax, L("(a) Düzeltmenin frekansa göre etkisi", "(a) Effect of the correction by frequency"));
    ax2 = nexttile(tl);  hold(ax2, 'on');
    m = fs4 >= 20 & fs4 <= 1000;
    cl = {[0.3 0.3 0.3], [0 0.3 0.6], [0.8 0.2 0.1]};  ls = {'-', '-', '--'};
    hs = gobjects(1, 3);
    for v = 1:3
        hs(v) = semilogx(ax2, fs4(m), Ps(m, v), ls{v}, 'Color', cl{v}, 'LineWidth', 1.2);
    end
    set(ax2, 'XScale', 'log', 'XTick', cfg.fig.fticks);  xlim(ax2, [20 1000]);
    mark_band(ax2, cfg, false);
    xlabel(ax2, L("Frekans (Hz)", "Frequency (Hz)"));
    ylabel(ax2, L("Ortalama bağıl güç (dB)", "Mean relative power (dB)"));
    legend(ax2, hs, [L("Oynatılan segment", "Played segment"), L("Stetoskop kaydı", "Stethoscope recording"), ...
        L("Stetoskop kaydı + düzeltme", "Stethoscope recording + correction")], 'Location', 'southwest');
    title(ax2, L(sprintf("(b) %d kalp sesi segmentinin ortalama spektrumu (model bandı)", numel(layout.files)), ...
        sprintf("(b) Mean spectrum of %d heart-sound segments (model band)", numel(layout.files))));
    linkaxes([ax ax2], 'x');
    save_figure(fig, 'H4_pcg_duzeltme_etkisi', cfg);

    % ---------------- H5: model probabilities, corrected ----------------
    if ~isempty(P)
        prob_figure(cfg, P, 'p_steth_eq', L("Stetoskop kaydı + düzeltme", "Stethoscope recording + correction"), ...
            L, 'H5_pcg_model_olasilik_duzeltilmis');
    end

    % ---------------- H6: decision consistency per variant (pcg_stats.py) ----------------
    sf = fullfile(resDir, 'pcg_stats.csv');
    if isfile(sf), consistency_figure(cfg, readtable(sf, 'TextType', 'string'), L); end
end
end

function consistency_figure(cfg, St, L)
% decision consistency (clip x run pairs) with Wilson 95 % CI, raw -> simulation -> partial/full correction
v = ["steth" "sim_H" "sim_Hn" "steth_eqmid" "steth_eqlow" "steth_eq"];
names = L(["Stetoskop kaydı" "Benzetim: oynatılan × ölçülen yanıt" "Benzetim + ölçülen gürültü" ...
           "Düzeltme yalnızca ≥ 100 Hz" "Düzeltme yalnızca < 100 Hz" "Tam yanıt düzeltmesi"], ...
          ["Stethoscope recording" "Simulation: played × measured response" "Simulation + measured noise" ...
           "Correction ≥ 100 Hz only" "Correction < 100 Hz only" "Full response correction"]);
[ok, j] = ismember(v, St.variant);  assert(all(ok), 'pcg_stats.csv lacks a variant');
y = St.agree_pct(j);  lo = St.ci_lo(j);  hi = St.ci_hi(j);
fig = new_figure(cfg, 7);
ax = axes(fig);  hold(ax, 'on');
cl = repmat([0 0.3 0.6], numel(v), 1);  cl(2:3,:) = repmat([0.5 0.5 0.5], 2, 1);  cl(4:6,:) = repmat([0.8 0.2 0.1], 3, 1);
% points with Wilson 95 % CI (bars starting at 50 % would exaggerate the differences; advisor's 2nd review)
for i = 1:numel(v)
    errorbar(ax, y(i), i, y(i) - lo(i), hi(i) - y(i), 'horizontal', 'o', 'Color', cl(i,:), ...
        'MarkerFaceColor', cl(i,:), 'MarkerSize', 5, 'CapSize', 4, 'LineWidth', 1);
    text(ax, hi(i) + 1, i, L(strrep(sprintf('%%%.1f', y(i)), '.', ','), sprintf('%.1f%%', y(i))), ...
        'VerticalAlignment', 'middle', 'FontName', cfg.fig.font, 'FontSize', cfg.fig.fontSize - 1);
end
set(ax, 'YTick', 1:numel(v), 'YTickLabel', names, 'YDir', 'reverse');
xlim(ax, [50 105]);  ylim(ax, [0.4 numel(v) + 0.6]);  grid(ax, 'on');
xlabel(ax, L("Karar tutarlılığı (%, 47 segment × 3 ölçüm, %95 GA)", ...
    "Decision consistency (%, 47 segments × 3 runs, 95% CI)"));
save_figure(fig, 'H6_pcg_karar_tutarliligi_varyantlar', cfg);
end

function prob_figure(cfg, P, var, yname, L, fileName)
% played vs. recorded P(abnormal), mean +/- std over runs, by class and dataset
fig = new_figure(cfg, 8);
ax = axes(fig);  hold(ax, 'on');
plot(ax, [0 1], [0 1], '-', 'Color', [0.6 0.6 0.6]);
xline(ax, 0.5, ':');  yline(ax, 0.5, ':');
mk = {'o', '^'};  cl = [0 0.3 0.6; 0.8 0.2 0.1];  hh = gobjects(0);
for lab = 0:1
    for s = ["physionet" "pascal"]
        q = P.label == lab & P.source == s;
        hh(end+1) = errorbar(ax, P.p_played(q), P.([var '_mean'])(q), P.([var '_std'])(q), ...
            mk{(s == "pascal") + 1}, 'Color', cl(lab+1,:), 'MarkerFaceColor', cl(lab+1,:), ...
            'MarkerSize', 4, 'CapSize', 2, 'LineWidth', 0.6); %#ok<AGROW>
    end
end
nRuns = numel(split(P.([var '_runs'])(1), ";"));
same = 100 * sum(P.(['sameclass_' extractAfter(var, 'p_') '_runs'])) / (height(P) * nRuns);
axis(ax, 'square');  xlim(ax, [0 1]);  ylim(ax, [0 1]);
xlabel(ax, L("Oynatılan segment: anormal olasılığı", "Played segment: P(abnormal)"));
ylabel(ax, sprintf('%s: %s', yname, L("anormal olasılığı", "P(abnormal)")));
title(ax, L(strrep(sprintf("Karar tutarlılığı: %%%.1f", same), ".", ","), ...
    sprintf("Decision consistency: %.1f%%", same)), ...
    'FontWeight', 'normal');
legend(ax, hh, L(["Normal, PhysioNet" "Normal, PASCAL-B" "Anormal, PhysioNet" "Anormal, PASCAL-B"], ...
    ["Normal, PhysioNet" "Normal, PASCAL-B" "Abnormal, PhysioNet" "Abnormal, PASCAL-B"]), ...
    'Location', 'eastoutside', 'FontSize', cfg.fig.fontSize - 2);
save_figure(fig, fileName, cfg);
end

function [Ps, f] = mean_spectra(layout, runDirs)
% mean model-band power spectrum (dB) over clips and runs: [played, recorded, recorded + correction];
% each clip is model-preprocessed (bandpass, 4 kHz) and normalised to unit band power first
acc = 0;  n = 0;
for r = 1:numel(runDirs)
    for k = 1:numel(layout.files)
        name = layout.files(k);
        sig = {resample(double(layout.ref{k}), 4000, layout.fsNat(k)), ...
               read4(fullfile(runDirs{r}, 'pcg_clips', 'steth', name)), ...
               read4(fullfile(runDirs{r}, 'pcg_clips', 'steth_eq', name))};
        P3 = zeros(1025, 3);
        for v = 1:3
            [p, f] = pwelch(model_prep(sig{v}), hann(512), 256, 2048, 4000);
            P3(:, v) = p / sum(p);
        end
        acc = acc + P3;  n = n + 1;
    end
end
Ps = 10*log10(acc / n);
end

% -------------------------------------------------------------------------------------------
function ex = pick_examples(T, P)
% normal: the normal clip with median envelope agreement (representative, not best).
% abnormal: among abnormal clips the model detects when played but not in the stethoscope recording
% (the main finding), the one with median envelope agreement; without model results, as for normal.
ex = zeros(1, 2);
for lab = 0:1
    k = find(T.label == lab);
    if lab == 1 && ~isempty(P)
        [~, j] = ismember(T.file(k), P.file);
        flip = P.p_played(j) >= 0.5 & P.p_steth_mean(j) < 0.5;
        if any(flip), k = k(flip); end
    end
    [~, o] = sort(T.rEnv(k));
    ex(lab+1) = k(o(ceil(end/2)));
end
fprintf('H2 examples: %s (label %d), %s (label %d)\n', T.file(ex(1)), T.label(ex(1)), T.file(ex(2)), T.label(ex(2)));
end

function y = true_labels(files, cfg)
% label_true from pcg_test/clips/filename_map.csv (PhysioNet labels corrected on 2026-10-21)
M = readtable(fullfile(cfg.paths.pcg, 'clips', 'filename_map.csv'), 'TextType', 'string', 'Delimiter', ',');
[ok, j] = ismember(string(files), M.new);
assert(all(ok), 'clips missing from filename_map.csv');
y = M.label_true(j);
end

function x = read4(path)
[x, fs] = audioread(path);
x = resample(x, 4000, fs);
end

function y = model_prep(x)
[z, p, k] = butter(4, [25 900]/2000, 'bandpass');  [sos, g] = zp2sos(z, p, k);
y = filtfilt(sos, g, x);  y = y / max(abs(y));
end

function s = pick(tr, a, b)
if tr, s = a; else, s = b; end
end
