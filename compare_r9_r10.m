function compare_r9_r10(reseatRuns, levelRuns, baseRuns)
%COMPARE_R9_R10  Analysis of the two extra pure-tone tests asked for in the advisor's review.
%   R10  repeatability with re-seating: the chestpiece is removed and seated again before every run
%        (RESEATRUNS, >= 5). Compared with BASERUNS (the three runs made without touching the setup).
%   R9   level dependence: the same setup at several tone levels (LEVELRUNS, >= 3, each recorded with
%        run_measurement(label, 'pc', 'tones', levelDbfs)). If THD at 30-100 Hz rises quickly with level,
%        the distortion comes from the speaker driver; the measured level change per played step also
%        shows the linearity of the whole system.
%   Every run must already be analysed (run_measurement does it). Writes results/r10_reseat.csv,
%   results/r9_levels.csv and figures/R9_R10_<timestamp>/{tr,en}/ (PDF + PNG). See olcum_protokolu_R9_R10.md.
%
%   compare_r9_r10({'data/..._reseat1', ...}, {'data/..._thd_m30dB', ...})

if nargin < 3 || isempty(baseRuns)
    baseRuns = {'data/20261009_140429_diyafram_run1', 'data/20261009_140717_diyafram_run2', ...
                'data/20261009_140956_diyafram_run3'};
end
here = fileparts(mfilename('fullpath'));
cfg = config();
minSnr = 20;                                          % R9: tones below this SNR are noise, not tone (dB)
outDir = fullfile(here, 'figures', ['R9_R10_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
resDir = fullfile(here, 'results');  if ~isfolder(resDir), mkdir(resDir); end

% ---------------- R10: re-seating ----------------
if ~isempty(reseatRuns)
    [f, Lr, rel_r] = load_levels(here, reseatRuns);
    [~, Lb, rel_b] = load_levels(here, baseRuns);
    sdR = std(rel_r, 0, 2);  sdB = std(rel_b, 0, 2);  sdRabs = std(Lr, 0, 2);
    T = table(f, mean(rel_b, 2), sdB, mean(rel_r, 2), sdR, sdRabs, mean(rel_r, 2) - mean(rel_b, 2), ...
        'VariableNames', {'fNom_Hz', 'rel_base_dB', 'std_base_dB', 'rel_reseat_dB', 'std_reseat_dB', ...
        'std_reseat_abs_dB', 'reseat_minus_base_dB'});
    writetable(T, fullfile(resDir, 'r10_reseat.csv'));
    m = f >= 30 & f <= 900;  lo = f >= 30 & f < 100;
    fprintf('R10 (%d re-seated runs vs %d untouched): relative response std in 30-900 Hz: median %.2f dB, max %.2f dB at %g Hz (untouched: median %.2f, max %.2f dB)\n', ...
        numel(reseatRuns), numel(baseRuns), median(sdR(m)), max(sdR(m)), f(find(m & sdR == max(sdR(m)), 1)), median(sdB(m)), max(sdB(m)));
    fprintf('     below 100 Hz: max std %.2f dB; mean shift re-seated vs untouched in 30-900 Hz: %.1f to %+.1f dB\n', ...
        max(sdR(lo)), min(T.reseat_minus_base_dB(m)), max(T.reseat_minus_base_dB(m)));
end

% ---------------- R9: level dependence ----------------
if ~isempty(levelRuns)
    nL = numel(levelRuns);  lev = zeros(1, nL);
    for r = 1:nL
        d = run_dir(here, levelRuns{r});
        M = load(fullfile(d, 'meta.mat'));  R = load(fullfile(d, 'results.mat'));
        lev(r) = 20*log10(M.cfg.stim.amp);
        thd(:, r) = R.res.stethoscope.T.thdPct;     %#ok<AGROW>
        L(:, r) = R.res.stethoscope.T.levelDb;      %#ok<AGROW>
        snr(:, r) = R.res.stethoscope.T.snrDb;      %#ok<AGROW>
        pk(r) = M.meta.peakDbfsSteth;               %#ok<AGROW>
        f = R.res.stethoscope.T.fNom;
    end
    [lev, o] = sort(lev);  thd = thd(:, o);  L = L(:, o);  snr = snr(:, o);  pk = pk(o);  levelRuns = levelRuns(o);
    [~, ref] = min(abs(lev - (-18)));                 % the standard level of all other runs
    dev = (L - L(:, ref)) - (lev - lev(ref));         % measured minus played level change (dB)
    % at the lowest levels the 30-40 Hz tones sink into the ambient low-frequency noise: the "tone" bin then
    % holds noise and both THD and level change are meaningless there, so such tones are masked
    low = snr < minSnr;
    thd(low) = NaN;  dev(low | low(:, ref)) = NaN;
    fprintf('R9 tones masked (SNR < %g dB): %s\n', minSnr, strjoin(arrayfun(@(r) sprintf('%g dBFS: %s Hz', lev(r), ...
        strjoin(compose('%g', f(low(:, r))), ', ')), find(any(low, 1)), 'UniformOutput', false), '; '));
    T = table(f, 'VariableNames', {'fNom_Hz'});
    for r = 1:nL
        tag = strrep(sprintf('%g', lev(r)), '-', 'm');
        T.(['thd_pct_' tag 'dBFS']) = thd(:, r);
        T.(['lindev_dB_' tag 'dBFS']) = dev(:, r);
        T.(['snr_dB_' tag 'dBFS']) = snr(:, r);
    end
    writetable(T, fullfile(resDir, 'r9_levels.csv'));
    lo = f >= 30 & f <= 100;  hi = f >= 120 & f <= 6000;  m = f >= 30 & f <= 900;
    for r = 1:nL
        fprintf('R9 %6.1f dBFS (peak in recording %.1f dBFS%s): THD 30-100 Hz %.1f-%.1f %%, 120 Hz-6 kHz max %.2f %%, linearity deviation in 30-900 Hz %.2f to %+.2f dB\n', ...
            lev(r), pk(r), ternary(pk(r) > -1, ', CLIPPING RISK', ''), min(thd(lo, r)), max(thd(lo, r)), max(thd(hi, r)), ...
            min(dev(m, r)), max(dev(m, r)));
    end
    if numel(unique(round(lev))) > 1
        % THD growth with level at 30-100 Hz: harmonic distortion of a driver rises with level
        % (about +1 dB per dB for a 2nd-order nonlinearity); distortion limited by noise would fall instead
        g = diff(20*log10(thd(lo, :)), 1, 2) ./ diff(lev);
        fprintf('R9 THD at 30-100 Hz changes by %+.2f dB per dB of level (median over tones and steps; %d valid steps)\n', ...
            median(g, 'all', 'omitnan'), nnz(~isnan(g)));
        gt = 20*log10(thd(lo, end) ./ thd(lo, 1)) / (lev(end) - lev(1));
        fprintf('   per tone, %g -> %g dBFS (dB/dB): %s\n', lev(1), lev(end), strjoin(compose('%g Hz %+.2f', [f(lo) gt]), ', '));
    end
end

% ---------------- figures (TR + EN) ----------------
for lang = {'tr', 'en'}
    cfg.lang = lang{1};  tr = strcmp(cfg.lang, 'tr');  Lb_ = @(a, b) pick(tr, a, b);
    cfg.paths.figures = fullfile(outDir, cfg.lang);
    if ~isempty(reseatRuns)
        fig = new_figure(cfg, 11);
        tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
        ax = nexttile(tl);  hold(ax, 'on');
        hB = errorbar(ax, f, mean(rel_b, 2), std(rel_b, 0, 2), 'o-', 'MarkerSize', 3, 'Color', [0.45 0.45 0.45]);
        hR = errorbar(ax, f, mean(rel_r, 2), std(rel_r, 0, 2), 's-', 'MarkerSize', 3, 'Color', [0.8 0.35 0]);
        set(ax, 'XScale', 'log', 'XTickLabel', []);  xlim(ax, [27 6600]);  ylim(ax, cfg.fig.respYlim);  mark_band(ax, cfg, false);
        ylabel(ax, Lb_("Bağıl genlik (dB, 0 dB = 250 Hz)", "Relative level (dB, 0 dB = 250 Hz)"));
        legend(ax, [hB hR], [Lb_(sprintf("Dokunulmadan (n = %d)", numel(baseRuns)), sprintf("Untouched (n = %d)", numel(baseRuns))), ...
            Lb_(sprintf("Her ölçümde yeniden yerleştirilmiş (n = %d)", numel(reseatRuns)), sprintf("Re-seated before each run (n = %d)", numel(reseatRuns)))], ...
            'Location', 'southeast');
        ax2 = nexttile(tl);  hold(ax2, 'on');
        semilogx(ax2, f, std(rel_b, 0, 2), 'o-', 'MarkerSize', 3, 'Color', [0.45 0.45 0.45]);
        semilogx(ax2, f, std(rel_r, 0, 2), 's-', 'MarkerSize', 3, 'Color', [0.8 0.35 0]);
        set(ax2, 'XScale', 'log');  xlim(ax2, [27 6600]);  mark_band(ax2, cfg, false);
        ylabel(ax2, Lb_("Standart sapma (dB)", "Standard deviation (dB)"));  xlabel(ax2, Lb_("Frekans (Hz)", "Frequency (Hz)"));
        save_figure(fig, 'R10_yeniden_yerlestirme', cfg);
    end
    if ~isempty(levelRuns)
        fig = new_figure(cfg, 11);
        tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
        ax = nexttile(tl);  hold(ax, 'on');  cm = parula(nL + 1);
        for r = 1:nL
            semilogy(ax, f, thd(:, r), 'o-', 'MarkerSize', 3, 'Color', cm(r, :), 'DisplayName', ...
                Lb_(strrep(sprintf('%g dBFS', lev(r)), '.', ','), sprintf('%g dBFS', lev(r))));
        end
        set(ax, 'XScale', 'log', 'YScale', 'log', 'XTickLabel', []);  xlim(ax, [27 6600]);  mark_band(ax, cfg, false);
        ylabel(ax, 'THD (%)');  legend(ax, flipud(findobj(ax, 'Type', 'line')),'Location', 'southwest');   % lines only, not the band patch
        ax2 = nexttile(tl);  hold(ax2, 'on');
        for r = 1:nL, semilogx(ax2, f, dev(:, r), 'o-', 'MarkerSize', 3, 'Color', cm(r, :)); end
        yline(ax2, 0, '-', 'Color', [0.6 0.6 0.6]);
        set(ax2, 'XScale', 'log');  xlim(ax2, [27 6600]);  mark_band(ax2, cfg, false);
        ylabel(ax2, Lb_("Doğrusallık sapması (dB)", "Linearity deviation (dB)"));  xlabel(ax2, Lb_("Frekans (Hz)", "Frequency (Hz)"));
        save_figure(fig, 'R9_thd_seviye', cfg);
    end
end
fprintf('figures -> %s\n', outDir);
end

function [f, L, rel] = load_levels(here, runs)
for r = 1:numel(runs)
    R = load(fullfile(run_dir(here, runs{r}), 'results.mat'));  T = R.res.stethoscope.T;
    f = T.fNom;  L(:, r) = T.levelDb;                  %#ok<AGROW>
    rel(:, r) = T.levelDb - interp1(f, T.levelDb, 250); %#ok<AGROW>
end
end

function d = run_dir(here, p)
% run folders may be given relative to the project or as absolute paths (run_measurement returns absolute)
if isfolder(p), d = p; else, d = fullfile(here, p); end
end

function s = pick(tr, a, b)
if tr, s = a; else, s = b; end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
