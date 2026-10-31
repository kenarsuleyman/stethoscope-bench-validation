function pcg_originals_figures()
%PCG_ORIGINALS_FIGURES  Spectral overview of the demo PCG recordings (no hardware needed).
%   G1: model-band spectrograms (25-900 Hz, model preprocessing) of one normal and one
%       abnormal recording per source.
%   G2: mean power spectrum of normal vs abnormal recordings after the model's bandpass,
%       each recording normalised to unit power, with the measured chain response overlaid
%       (shows where heart-sound energy sits relative to the speaker + stethoscope response).
%   Output: pcg_test/figures/{tr,en}/ (PDF + PNG).

cfg = config();
map = readtable(fullfile(cfg.pcg.dir, 'filename_map.csv'), 'Delimiter', ',', ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
files = map{:,1};  orig = map{:,2};
src = pcg_source_names(orig);
isAb = startsWith(files, "anormal");
fsM = 4000;  [z, p, k] = butter(4, [25 900]/(fsM/2), 'bandpass');  [sos, g] = zp2sos(z, p, k);

X = cell(numel(files),1);
for i = 1:numel(files)
    [x, fs] = audioread(fullfile(cfg.pcg.dir, files(i)));
    x = resample(mean(x,2), fsM, fs);
    x = filtfilt(sos, g, x(1:min(end, 5*fsM)));               % first 5 s segment, as the model
    X{i} = x / max(abs(x));
end

srcs = unique(src, 'stable');
f0 = (0:1024)'/2048*fsM;  Pn = [];  Pa = [];
for i = 1:numel(files)
    P = pwelch(X{i}, hann(512), 256, 2048, fsM);  P = P / sum(P);
    if isAb(i), Pa(:,end+1) = P; else, Pn(:,end+1) = P; end %#ok<AGROW>
end
R = load_chain_response(cfg);

for lang = {'tr', 'en'}
    cfg.lang = lang{1};  tr = strcmp(cfg.lang, 'tr');
    cfg.paths.figures = fullfile(gui_ctx('outDir', fullfile(cfg.paths.pcg, 'figures')), cfg.lang);

    % --- G1: spectrogram grid (sources x {normal, abnormal}) ---
    fig = new_figure(cfg, 3.2*numel(srcs));
    tl = tiledlayout(fig, numel(srcs), 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    for s = 1:numel(srcs)
        for c = 0:1
            ax = nexttile(tl);
            i = find(src == srcs(s) & isAb == c, 1);
            if isempty(i), axis(ax, 'off'); continue; end
            [S, F, T] = spectrogram(X{i}, hann(256), 192, 1024, fsM);
            imagesc(ax, T, F, 20*log10(abs(S) + eps));  axis(ax, 'xy');  ylim(ax, [0 900]);
            clim(ax, max(clim(ax)) + [-70 0]);  colormap(ax, parula);
            title(ax, sprintf('%s: %s (%s)', srcs(s), pick(tr, ["Normal" "Anormal"], ["Normal" "Abnormal"], c+1), ...
                strrep(files(i), "_", "\_")), 'FontWeight', 'normal', 'FontSize', cfg.fig.fontSize - 1);
            if c == 0, ylabel(ax, pick(tr, "Frekans (Hz)", "Frequency (Hz)")); end
            if s == numel(srcs), xlabel(ax, pick(tr, "Zaman (s)", "Time (s)")); end
            set(ax, 'FontName', cfg.fig.font, 'FontSize', cfg.fig.fontSize - 1);
        end
    end
    save_figure(fig, 'G1_pcg_spektrogramlar', cfg);

    % --- G2: mean spectra normal vs abnormal + chain response ---
    fig = new_figure(cfg, 9);  ax = axes(fig);  hold(ax, 'on');
    db = @(P) 10*log10(mean(P, 2));
    h1 = semilogx(ax, f0, db(Pn), 'Color', [0 0.3 0.6], 'LineWidth', 1.2);
    h2 = semilogx(ax, f0, db(Pa), 'Color', [0.8 0.2 0.1], 'LineWidth', 1.2);
    hs = [h1 h2];
    lg = [pick(tr, sprintf("Normal (n = %d)", size(Pn,2)), sprintf("Normal (n = %d)", size(Pn,2))), ...
          pick(tr, sprintf("Anormal (n = %d)", size(Pa,2)), sprintf("Abnormal (n = %d)", size(Pa,2)))];
    set(ax, 'XScale', 'log');  xlim(ax, [20 1000]);  grid(ax, 'on');
    mark_band(ax, cfg, false);                 % before yyaxis: uistack fails on two-axis plots
    if ~isempty(R)
        yyaxis(ax, 'right');
        h3 = semilogx(ax, R.f, R.dB, 'k--', 'LineWidth', 1);  ylabel(ax, pick(tr, ...
            "Hoparlör + MEMS stetoskop bağıl yanıtı (dB)", "Speaker + MEMS stethoscope relative response (dB)"));
        ax.YAxis(2).Color = 'k';  yyaxis(ax, 'left');
        hs(end+1) = h3;  lg(end+1) = pick(tr, "Hoparlör + MEMS stetoskop (saf ton)", "Speaker + MEMS stethoscope (pure tones)");
    end
    xlabel(ax, pick(tr, "Frekans (Hz)", "Frequency (Hz)"));
    ylabel(ax, pick(tr, "Ortalama bağıl güç (dB)", "Mean relative power (dB)"));
    legend(ax, hs, lg, 'Location', 'southwest');
    set(ax, 'FontName', cfg.fig.font, 'FontSize', cfg.fig.fontSize);
    save_figure(fig, 'G2_pcg_ortalama_spektrum', cfg);
end

% console summary: share of model-band power below 100 Hz per class
lo = f0 >= 25 & f0 < 100;  band = f0 >= 25 & f0 <= 900;
fprintf('Model-band power below 100 Hz: normal %.0f %% (median), abnormal %.0f %% (median)\n', ...
    100*median(sum(Pn(lo,:))./sum(Pn(band,:))), 100*median(sum(Pa(lo,:))./sum(Pa(band,:))));
end

function R = load_chain_response(cfg)
% latest combined tone-run table (mean relative level re 250 Hz)
d = tone_response_dir();
R = [];
if isempty(d), return; end
T = readtable(fullfile(d, 'tr', 'ozet_tablo.csv'));
R.f = T.fNom_Hz;  R.dB = T.relLevel_dB;
end

function s = pick(tr, a, b, i)
if nargin < 4, i = 1; end
if tr, s = a(i); else, s = b(i); end
end
