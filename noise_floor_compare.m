function T = noise_floor_compare(recs)
%NOISE_FLOOR_COMPARE  Advisor's 2nd review K3: noise floor of the stethoscope with the coupler inlet open and sealed,
%   recorded on the computer and on the smartphone, to separate acoustic noise from the noise of the electronics.
%   RECS: N x 3 cell {path, label, gainDb}; LABEL is text or {Turkish, English}. PATH is a run folder (record_silence, stethoscope.wav) or a WAV file
%   (smartphone test recording). GAINDB is subtracted from the level, e.g. 9.15 dB for the fixed digital gain of the
%   Android capture path (results/k3_phone_level.csv), so all levels refer to the computer scale.
%   Levels: in-band floor 25-900 Hz in dBFS (0 dBFS = full-scale sine, as in tone_band_snr) and band powers.
%   Writes results/k3_sealed_noise.csv and figures/K3_<timestamp>/{tr,en}/K3_gurultu_tabani.{pdf,png}.
%
%   noise_floor_compare({'data/..._k3_open_pc', 'PC open', 0; 'phone_rec/test_...wav', 'Phone open', 9.15; ...})

here = fileparts(mfilename('fullpath'));
cfg = config();
edges = [20 40 63 100 160 250 400 630 900 1600 3000 6000];
trim = 2;                                               % s skipped at both ends (connection / button clicks)
n = size(recs, 1);
floorDb = nan(n, 1);  bandDb = nan(n, numel(edges) - 1);  fsAll = nan(n, 1);  P = cell(n, 1);  F = cell(n, 1);
for k = 1:n
    p = recs{k, 1};  if ~isfile(p) && ~isfolder(p), p = fullfile(here, p); end
    if isfolder(p), p = fullfile(p, 'stethoscope.wav'); end
    [x, fs] = audioread(p);  x = x(:, 1);  x = x(round(trim*fs)+1:end-round(trim*fs));  x = x - mean(x);
    g = 10^(-recs{k, 3}/20);  x = x * g;
    [b, a] = butter(4, cfg.thesis.band / (fs/2));
    y = filtfilt(b, a, x);
    floorDb(k) = 20*log10(rms(y) * sqrt(2));
    [P{k}, F{k}] = pwelch(x, hann(fs, 'periodic'), round(fs/2), fs, fs);     % 1 Hz resolution, one-sided
    for j = 1:numel(edges) - 1
        m = F{k} >= edges(j) & F{k} < edges(j+1);
        if edges(j+1) <= fs/2, bandDb(k, j) = 10*log10(sum(P{k}(m)) * (F{k}(2) - F{k}(1)) * 2); end
    end
    fsAll(k) = fs;
    fprintf('%-14s fs %5d Hz, gain %+5.2f dB: in-band floor %6.1f dBFS\n', label(recs{k, 2}, 'en'), fs, -recs{k, 3}, floorDb(k));
end
names = arrayfun(@(a, b) sprintf('band_%d_%d_dB', a, b), edges(1:end-1), edges(2:end), 'UniformOutput', false);
T = [table(string(cellfun(@(c) label(c, 'en'), recs(:, 2), 'UniformOutput', false)), string(recs(:, 1)), cell2mat(recs(:, 3)), fsAll, floorDb, 'VariableNames', ...
    {'label', 'source', 'gain_removed_dB', 'fs_Hz', 'inband_floor_dBFS'}), array2table(bandDb, 'VariableNames', names)];
resDir = gui_ctx('outDir', fullfile(here, 'results'));  if ~isfolder(resDir), mkdir(resDir); end
writetable(T, fullfile(resDir, 'k3_sealed_noise.csv'));
fprintf('-> %s\n', fullfile(resDir, 'k3_sealed_noise.csv'));

outDir = gui_ctx('outDir', fullfile(here, 'figures', ['K3_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]));
col = [0.1 0.3 0.7; 0.55 0.7 0.95; 0.8 0.35 0; 0.95 0.7 0.45; 0.4 0.4 0.4; 0.7 0.7 0.7];
sty = {'-', '--', '-', '--', '-', '--'};
for lang = {'tr', 'en'}
    cfg.lang = lang{1};  tr = strcmp(cfg.lang, 'tr');
    cfg.paths.figures = fullfile(outDir, cfg.lang);
    fig = new_figure(cfg, 8);  ax = axes(fig);  hold(ax, 'on');
    h = gobjects(n, 1);
    for k = 1:n
        m = F{k} >= 15 & F{k} <= min(6000, fsAll(k)/2);
        Ps = movmean(10*log10(P{k}(m)), 9);             % light smoothing (9 Hz) for readability
        h(k) = plot(ax, F{k}(m), Ps, sty{mod(k-1, 6)+1}, 'Color', col(mod(k-1, 6)+1, :));
    end
    set(ax, 'XScale', 'log', 'XTick', cfg.fig.fticks);  xlim(ax, [15 6000]);
    mark_band(ax, cfg, false);
    legend(ax, h, arrayfun(@(k) sprintf('%s (%.1f dBFS)', label(recs{k, 2}, cfg.lang), floorDb(k)), 1:n, 'UniformOutput', false), ...
        'Location', 'northeast');
    xlabel(ax, lbl('freq', cfg));  ylabel(ax, lbl('psd', cfg));
    if tr, ttl = 'Parantez içinde: bant içi gürültü tabanı (25–900 Hz)';
    else,  ttl = 'In brackets: in-band noise floor (25–900 Hz)'; end
    text(ax, 0.02, 0.04, ttl, 'Units', 'normalized', 'FontSize', cfg.fig.fontSize - 1);
    save_figure(fig, 'K3_gurultu_tabani', cfg);
end
fprintf('figures -> %s\n', outDir);
end

function s = label(c, lang)
if ischar(c) || isstring(c), s = char(c); return; end
s = c{1 + strcmp(lang, 'en')};
end
