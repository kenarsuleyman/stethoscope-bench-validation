function summary = make_figures(runDirs, outDir)
%MAKE_FIGURES  Thesis figures and summary table, in Turkish and English.
%   make_figures(runDir)                      -> <runDir>/figures/{tr,en}/
%   make_figures({run1, run2, run3})          -> figures/birlesik_<timestamp>/{tr,en}/
%   make_figures(runDirs, outDir)             -> <outDir>/{tr,en}/
%   Runs not yet analysed are analysed first. The first run is used for the
%   single-run figures (spectra, spectrogram, noise floor).

if ischar(runDirs) || isstring(runDirs), runDirs = cellstr(runDirs); end
cfg = config();
if nargin < 2
    if isscalar(runDirs)
        outDir = fullfile(runDirs{1}, 'figures');
    else
        outDir = fullfile(cfg.paths.figures, ...
            ['birlesik_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
    end
end
langs = {'tr', 'en'};
for k = 1:numel(langs)
    cfg.lang = langs{k};
    cfg.paths.figures = fullfile(outDir, langs{k});
    summary = render(runDirs, cfg, k == 1);
end
fprintf('Figures -> %s (tr, en)\n', outDir);
end

function summary = render(runDirs, cfg, verbose)
R = cell(size(runDirs));
for k = 1:numel(runDirs)
    f = fullfile(runDirs{k}, 'results.mat');
    if ~isfile(f), analyze_measurement(runDirs{k}); end
    R{k} = load(f).res;
end
hasRef = cfg.ana.useReference && all(cellfun(@(r) isfield(r, 'reference'), R));

C.s = [0.00 0.30 0.60];  C.r = [0.80 0.35 0.00];  C.g = [0.45 0.45 0.45];
fNom = R{1}.stethoscope.T.fNom;
inBand = fNom <= 1000;
nRun = numel(R);

% ---------- stack per-run metrics: rows = frequencies, cols = runs ----------
get = @(dev, v) cell2mat(cellfun(@(r) r.(dev).T.(v), R, 'UniformOutput', false));
Ls = get('stethoscope', 'levelDb');
Es = get('stethoscope', 'fErrPct');
Fs = get('stethoscope', 'fMeas');
Ss = get('stethoscope', 'snrDb');
Hs = get('stethoscope', 'thdPct');
Ds = get('stethoscope', 'dominant');
normS = @(L) L - interp1(log(fNom), L, log(cfg.ana.normFreq));
Rs = cell2mat(arrayfun(@(k) normS(Ls(:,k)), 1:nRun, 'UniformOutput', false));
if hasRef
    Lr = get('reference', 'levelDb');
    % hide reference points where the reference itself did not capture the tone
    % (C615 has an internal high-pass below ~70 Hz and noise gating)
    refBad = get('reference', 'snrDb') < cfg.ana.refMinSnr | ~get('reference', 'dominant');
    Lr(refBad) = NaN;
    Rr = cell2mat(arrayfun(@(k) normS(Lr(:,k)), 1:nRun, 'UniformOutput', false));
    Hr = get('reference', 'thdPct');  Hr(refBad) = NaN;
    Dd = Rs - Rr;
end
mu = @(A) mean(A, 2);  sd = @(A) std(A, 0, 2);
fticks = cfg.fig.fticks;                 % the same ticks in every figure (config.m)

% ===== Fig. A: frequency response =====
fig = new_figure(cfg, 12);
tl = tiledlayout(fig, 1 + hasRef, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(tl);  hold(ax, 'on');
band_fill(ax, fNom, mu(Rs), sd(Rs), C.s);
hS = plot(ax, fNom, mu(Rs), '-o', 'Color', C.s, 'MarkerFaceColor', C.s, 'MarkerSize', 3.5, ...
    'DisplayName', lbl('chain', cfg));
hh = hS;
if hasRef
    band_fill(ax, fNom, mu(Rr), sd(Rr), C.r);
    hR = plot(ax, fNom, mu(Rr), '--s', 'Color', C.r, 'MarkerSize', 3.5, 'DisplayName', lbl('ref', cfg));
    hh = [hS hR];
end
set(ax, 'XScale', 'log', 'XTick', fticks);  xlim(ax, [fNom(1)*0.9 fNom(end)*1.1]);  ylim(ax, cfg.fig.respYlim);
ylabel(ax, sprintf('%s, 0 dB @ %d Hz', lbl('relDb', cfg), cfg.ana.normFreq));
yline(ax, -3, ':', '−3 dB', 'Color', C.g, 'LabelHorizontalAlignment', 'right', ...
    'LabelVerticalAlignment', 'bottom', 'FontName', cfg.fig.font, 'HandleVisibility', 'off');
hb = mark_band(ax, cfg);
legend(ax, [hh hb], 'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off');
if nRun > 1, title(ax, sprintf('n = %d (%s)', nRun, lbl('meanStd', cfg))); end
if hasRef
    xticklabels(ax, {});
    ax2 = nexttile(tl);  hold(ax2, 'on');
    band_fill(ax2, fNom, mu(Dd), sd(Dd), C.s);
    plot(ax2, fNom, mu(Dd), '-o', 'Color', C.s, 'MarkerFaceColor', C.s, 'MarkerSize', 3.5);
    yline(ax2, 0, '-', 'Color', C.g, 'HandleVisibility', 'off');
    set(ax2, 'XScale', 'log', 'XTick', fticks);  xlim(ax2, xlim(ax));
    ylabel(ax2, lbl('diffDb', cfg));
    mark_band(ax2, cfg);
    xlabel(ax2, lbl('freq', cfg));
else
    xlabel(ax, lbl('freq', cfg));
end
save_figure(fig, 'A_frekans_yaniti', cfg);

% ===== Fig. B: frequency accuracy =====
fig = new_figure(cfg, 11);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(tl);  hold(ax, 'on');
plot(ax, [10 1e4], [10 1e4], '-', 'Color', C.g, 'DisplayName', lbl('ideal', cfg));
plot(ax, fNom, mu(Fs), 'o', 'Color', C.s, 'MarkerFaceColor', C.s, 'MarkerSize', 3.5, ...
    'DisplayName', lbl('steth', cfg));
set(ax, 'XScale', 'log', 'YScale', 'log', 'XTick', fticks, 'YTick', fticks);
xlim(ax, [fNom(1)*0.9 fNom(end)*1.1]);  ylim(ax, xlim(ax));
ylabel(ax, lbl('freqMeas', cfg));  xticklabels(ax, {});
legend(ax, 'Location', 'northwest', 'Box', 'off');
ax2 = nexttile(tl);  hold(ax2, 'on');
yline(ax2, 0, '-', 'Color', C.g, 'HandleVisibility', 'off');
if cfg.thesis.showDecimationMarks
    yline(ax2, -100*(1 - 4000/cfg.thesis.fsDec), '--', lbl('labelErr', cfg), 'Color', C.r, ...
        'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'bottom', ...
        'FontName', cfg.fig.font, 'FontSize', cfg.fig.fontSize-1);
end
if nRun > 1
    errorbar(ax2, fNom, mu(Es), sd(Es), 'o', 'Color', C.s, 'MarkerFaceColor', C.s, 'MarkerSize', 3.5, 'CapSize', 2);
else
    plot(ax2, fNom, mu(Es), 'o', 'Color', C.s, 'MarkerFaceColor', C.s, 'MarkerSize', 3.5);
end
set(ax2, 'XScale', 'log', 'XTick', fticks);  xlim(ax2, xlim(ax));
if cfg.thesis.showDecimationMarks
    ylim(ax2, [-0.3 0.1]);
else
    e = abs(mu(Es));  if nRun > 1, e = e + sd(Es); end
    lim = max(0.1, ceil(20*max(e(isfinite(e))))/20);      % +/-0.1 %, widened in 0.05 % steps if needed
    ylim(ax2, [-lim lim]);
end
ylabel(ax2, lbl('freqErr', cfg));  xlabel(ax2, lbl('freqNom', cfg));
save_figure(fig, 'B_frekans_dogrulugu', cfg);

% ===== Fig. C: SNR and THD =====
fig = new_figure(cfg, 11);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(tl);  hold(ax, 'on');
band_fill(ax, fNom, mu(Ss), sd(Ss), C.s);
hP = plot(ax, fNom, mu(Ss), '-o', 'Color', C.s, 'MarkerFaceColor', C.s, 'MarkerSize', 3.5, 'DisplayName', lbl('p2f', cfg));
hh = hP;
% in-band SNR (tone power vs. noise integrated over 25-900 Hz), written by tone_band_snr.m
bf = gui_ctx('bandSnrCsv', fullfile(fileparts(mfilename('fullpath')), 'results', 'tone_band_snr.csv'));
if isfile(bf)
    Tb = readtable(bf);
    ib = Tb.fNom_Hz <= 1000;   % in-band SNR only for the 40 model-band tones (30-1000 Hz), as in Table 2
    hB = plot(ax, Tb.fNom_Hz(ib), Tb.inBandSNR_dB(ib), '--s', 'Color', C.r, 'MarkerSize', 3.5, 'DisplayName', lbl('snrBand', cfg));
    hh = [hP hB];
end
set(ax, 'XScale', 'log', 'XTick', fticks);  xlim(ax, [fNom(1)*0.9 fNom(end)*1.1]);
ylabel(ax, lbl('ratioDb', cfg));  xticklabels(ax, {});
mark_band(ax, cfg);
legend(ax, hh, 'Location', 'northoutside', 'Orientation', 'vertical', 'Box', 'off');
ax2 = nexttile(tl);  hold(ax2, 'on');
plot(ax2, fNom, mu(Hs), '-o', 'Color', C.s, 'MarkerFaceColor', C.s, 'MarkerSize', 3.5, 'DisplayName', lbl('chain', cfg));
if hasRef
    plot(ax2, fNom, mu(Hr), '--s', 'Color', C.r, 'MarkerSize', 3.5, 'DisplayName', lbl('ref', cfg));
end
set(ax2, 'XScale', 'log', 'YScale', 'log', 'XTick', fticks);  xlim(ax2, xlim(ax));
ylabel(ax2, lbl('thd', cfg));  xlabel(ax2, lbl('freq', cfg));
mark_band(ax2, cfg);
legend(ax2, 'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off');
save_figure(fig, 'C_snr_thd', cfg);

% ===== single-run figures (first run) =====
r1 = R{1};  S1 = load(fullfile(r1.runDir, 'meta.mat'));
[xs, fsS] = audioread(fullfile(r1.runDir, 'stethoscope.wav'));
xs = xs(:, cfg.rec.stethChannel);

% ===== Fig. D: spectra of selected tones =====
sel = cfg.thesis.selectedTones;
fig = new_figure(cfg, 11);
tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
for k = 1:numel(sel)
    [~, i] = min(abs(fNom - sel(k)));
    seg = xs(r1.stethoscope.seg(i,1):r1.stethoscope.seg(i,2));
    [f, A] = amp_spectrum(seg, fsS, cfg);
    ax = nexttile(tl);  hold(ax, 'on');
    plot(ax, f, 20*log10(A), '-', 'Color', C.s, 'LineWidth', 0.8);
    fmax = min(4000, max(300, 4.5*fNom(i)));
    xline(ax, fNom(i), '--', 'Color', C.r, 'LineWidth', 0.8);
    xlim(ax, [0 fmax]);  ylim(ax, [-120 0]);
    title(ax, sprintf('%d Hz', fNom(i)));
    if mod(k-1, 3) == 0, ylabel(ax, lbl('ampDbfs', cfg)); else, yticklabels(ax, {}); end
    if k > 3, xlabel(ax, lbl('freq', cfg)); end
end
save_figure(fig, 'D_secili_ton_spektrumlari', cfg);

% ===== Fig. E: spectrogram of the whole sequence =====
fig = new_figure(cfg, 8);
ax = axes(fig);
i0 = max(1, r1.stethoscope.onsetStart - round(0.5*fsS));
i1 = min(numel(xs), r1.stethoscope.onsetEnd + round(1.0*fsS));
[sp, fsp, tsp] = spectrogram(xs(i0:i1), hann(8192), 8192-2048, 8192, fsS);
imagesc(ax, tsp, fsp, 10*log10(abs(sp).^2 / sum(hann(8192))^2 * 4 + eps));
axis(ax, 'xy');  ylim(ax, [0 min(6500, fsS/2)]);
colormap(ax, parula);  cb = colorbar(ax);  cb.Label.String = lbl('ampDbfs', cfg);
clim(ax, [-120 0]);
xlabel(ax, lbl('time', cfg));  ylabel(ax, lbl('freq', cfg));
set(ax, 'Layer', 'top', 'XGrid', 'off', 'YGrid', 'off');
save_figure(fig, 'E_spektrogram', cfg);

% ===== Fig. F: noise floor =====
fig = new_figure(cfg, 8);
ax = axes(fig);  hold(ax, 'on');
nz = xs(r1.stethoscope.noise(1):r1.stethoscope.noise(2));
[p, f] = pwelch(nz - mean(nz), hann(8192), 4096, 8192, fsS);
plot(ax, f, 10*log10(p), '-', 'Color', C.s, 'DisplayName', lbl('steth', cfg));
if hasRef
    [xr, fsR] = audioread(fullfile(r1.runDir, 'reference.wav'));
    nr = xr(r1.reference.noise(1):r1.reference.noise(2), 1);
    [p, f] = pwelch(nr - mean(nr), hann(8192), 4096, 8192, fsR);
    plot(ax, f, 10*log10(p), '--', 'Color', C.r, 'DisplayName', lbl('ref', cfg));
end
set(ax, 'XScale', 'log', 'XTick', [20 50 100 200 500 1000 2000 5000 10000 20000]);
xlim(ax, [10 fsS/2]);
xlabel(ax, lbl('freq', cfg));  ylabel(ax, lbl('psd', cfg));
mark_band(ax, cfg);
legend(ax, 'Location', 'northoutside', 'NumColumns', 2, 'Box', 'off');
save_figure(fig, 'F_gurultu_tabani', cfg);

% ===== summary table =====
summary = table(fNom, mu(Fs), mu(Es), sd(Es), mu(Rs), sd(Rs), mu(Ss), mu(Hs), all(Ds, 2), ...
    'VariableNames', {'fNom_Hz','fMeas_Hz','fErr_pct','fErr_pct_std','relLevel_dB', ...
    'relLevel_dB_std','SNR_dB','THD_pct','fundamentalDominant'});
if hasRef
    summary.refRelLevel_dB = mu(Rr);
    summary.stethMinusRef_dB = mu(Dd);
    summary.refTHD_pct = mu(Hr);
end
writetable(summary, fullfile(cfg.paths.figures, 'ozet_tablo.csv'));
save(fullfile(cfg.paths.figures, 'figure_sources.mat'), 'runDirs');
if ~verbose, return; end

fprintf('\n--- Summary (%d run(s)), %d-%d Hz ---\n', nRun, fNom(1), 1000);
fprintf('max |frequency error|      : %.4f %%\n', max(abs(mu(Es(inBand,:)))));
fprintf('median SNR                 : %.1f dB (min %.1f dB at %d Hz)\n', median(mu(Ss(inBand,:))), ...
    min(mu(Ss(inBand,:))), fNom(find(mu(Ss) == min(mu(Ss(inBand,:))), 1)));
fprintf('fundamental dominant       : %d / %d tones\n', sum(all(Ds(inBand,:), 2)), sum(inBand));
above = fNom(mu(Rs) >= -10);
fprintf('-10 dB range (steth, raw)  : %g - %g Hz\n', min(above), max(above));
if hasRef
    above = fNom(mu(Dd) >= -10);
    fprintf('-10 dB range (steth - ref) : %g - %g Hz\n', min(above), max(above));
end
end

function band_fill(ax, f, m, s, c)
if all(s == 0 | isnan(s)), return; end
fill(ax, [f; flipud(f)], [m - s; flipud(m + s)], c, 'FaceAlpha', 0.15, 'EdgeColor', 'none', ...
    'HandleVisibility', 'off');
end

function [f, A] = amp_spectrum(x, fs, cfg)
N = numel(x);  nfft = 2^nextpow2(N) * cfg.ana.zeroPad;
w = hann(N, 'periodic');
X = fft((x - mean(x)) .* w, nfft);
A = abs(X(1:nfft/2+1)) * 2 / sum(w);
f = (0:nfft/2)' * fs / nfft;
end
