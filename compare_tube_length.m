function compare_tube_length(longRuns, shortRuns, Llong, Lshort)
%COMPARE_TUBE_LENGTH  Advisor's review R4: do the response peaks move with the tube length?
%   Compares the tone levels (dBFS, same playback level) measured with the original tube (LONGRUNS, length LLONG in m)
%   and with the shortened tube (SHORTRUNS, LSHORT), lists the local maxima in 120-1500 Hz and the quarter-wave
%   predictions (2k-1)*c/(4L) (tube nearly closed at the coupler end, open into the chestpiece volume).
%   Writes results/r4_tube_length.csv and figures/R4_<timestamp>/{tr,en}/R4_tup_boyu.{pdf,png}.
%
%   compare_tube_length({'data/..._reseat_run1', ...}, {'data/..._tube30cm_run1'}, 0.45, 0.30)

if nargin < 3, Llong = 0.45; end
if nargin < 4, Lshort = 0.30; end
here = fileparts(mfilename('fullpath'));
cfg = config();
c = 343;                                              % speed of sound at ~20 C (m/s)
% absolute tone levels: a fixed reference frequency would sit on a peak or flank of one of the two curves
[f, relL] = load_rel(here, longRuns);
[~, relS] = load_rel(here, shortRuns);
mL = mean(relL, 2);  mS = mean(relS, 2);

predL = (2*(1:3) - 1) * c / (4*Llong);  predS = (2*(1:3) - 1) * c / (4*Lshort);
pkL = peaks_of(f, mL);  pkS = peaks_of(f, mS);
fprintf('R4 tube %.0f mm: measured peaks %s Hz, quarter-wave %s Hz\n', 1000*Llong, mat2str(pkL'), mat2str(round(predL)));
fprintf('R4 tube %.0f mm: measured peaks %s Hz, quarter-wave %s Hz\n', 1000*Lshort, mat2str(pkS'), mat2str(round(predS)));
T = table(f, mL, mS, mS - mL, 'VariableNames', {'fNom_Hz', sprintf('level_%dmm_dBFS', round(1000*Llong)), ...
    sprintf('level_%dmm_dBFS', round(1000*Lshort)), 'short_minus_long_dB'});
b = f >= 30 & f < 100;  fprintf('R4 short minus long tube, 30-100 Hz: %.1f to %.1f dB\n', min(T.short_minus_long_dB(b)), max(T.short_minus_long_dB(b)));
resDir = fullfile(here, 'results');  if ~isfolder(resDir), mkdir(resDir); end
writetable(T, fullfile(resDir, 'r4_tube_length.csv'));

outDir = fullfile(here, 'figures', ['R4_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
for lang = {'tr', 'en'}
    cfg.lang = lang{1};  tr = strcmp(cfg.lang, 'tr');  Lb_ = @(a, b) pick(tr, a, b);
    cfg.paths.figures = fullfile(outDir, cfg.lang);
    fig = new_figure(cfg, 8);  ax = axes(fig);  hold(ax, 'on');
    cL = [0.45 0.45 0.45];  cS = [0.8 0.35 0];
    hL = plot(ax, f, mL, 'o-', 'MarkerSize', 3, 'Color', cL);
    hS = plot(ax, f, mS, 's-', 'MarkerSize', 3, 'Color', cS);
    set(ax, 'XScale', 'log');  xlim(ax, [27 6600]);  ylim(ax, [-80 0]);
    for p = predL, xline(ax, p, '--', 'Color', cL, 'LineWidth', 0.8); end
    for p = predS, xline(ax, p, '--', 'Color', cS, 'LineWidth', 0.8); end
    mark_band(ax, cfg, false);
    nL = numel(longRuns);  nS = numel(shortRuns);
    legend(ax, [hL hS], ...
        [Lb_(sprintf("Tüp %d mm (n = %d)", round(1000*Llong), nL), sprintf("Tube %d mm (n = %d)", round(1000*Llong), nL)), ...
         Lb_(sprintf("Tüp %d mm (n = %d)", round(1000*Lshort), nS), sprintf("Tube %d mm (n = %d)", round(1000*Lshort), nS))], ...
        'Location', 'southeast');
    text(ax, 0.02, 0.97, Lb_("Kesikli çizgiler: çeyrek dalga öngörüsü (2k-1)c/4L", "Dashed lines: quarter-wave prediction (2k-1)c/4L"), ...
        'Units', 'normalized', 'VerticalAlignment', 'top', 'FontSize', cfg.fig.fontSize - 1);
    ylabel(ax, Lb_("Ton seviyesi (dBFS)", "Tone level (dBFS)"));
    xlabel(ax, Lb_("Frekans (Hz)", "Frequency (Hz)"));
    save_figure(fig, 'R4_tup_boyu', cfg);
end
fprintf('figures -> %s\n', outDir);
end

function [f, rel] = load_rel(here, runs)
for r = 1:numel(runs)
    p = runs{r};  if ~isfolder(p), p = fullfile(here, p); end
    R = load(fullfile(p, 'results.mat'));  T = R.res.stethoscope.T;
    f = T.fNom;  rel(:, r) = T.levelDb;   %#ok<AGROW>
end
end

function pk = peaks_of(f, y)
% local maxima in 120-1500 Hz that stand at least 3 dB above both neighbouring minima
m = f >= 120 & f <= 1500;  ff = f(m);  yy = y(m);
[~, loc] = findpeaks(yy, 'MinPeakProminence', 3);
pk = ff(loc);
end

function s = pick(tr, a, b)
if tr, s = a; else, s = b; end
end
