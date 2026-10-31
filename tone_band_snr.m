function S = tone_band_snr(runDirs)
%TONE_BAND_SNR  Broadband (in-band) SNR, noise floor and dynamic range of the pure-tone runs.
%   The per-tone "SNR" written by analyze_measurement (private/tone_metrics.m) is a spectral
%   peak-to-noise-floor ratio: flat-top window, 1.4 s segment, noise in the same window bins
%   (ENBW printed below). Here the same tones are compared with the noise power integrated over
%   the model band (25-900 Hz), which is the figure comparable to a datasheet SNR.
%   Writes results/tone_band_snr.csv (per tone, mean over runs) and prints a summary.
%
%   S = tone_band_snr({'data/20261009_140429_diyafram_run1', ...})

if nargin < 1
    runDirs = {'data/20261009_140429_diyafram_run1', 'data/20261009_140717_diyafram_run2', ...
               'data/20261009_140956_diyafram_run3'};
end
here = fileparts(mfilename('fullpath'));
band = [25 900];

for r = 1:numel(runDirs)
    d = fullfile(here, runDirs{r});
    M = load(fullfile(d, 'meta.mat'));  R = load(fullfile(d, 'results.mat'));
    st = R.res.stethoscope;  T = st.T;
    [x, fs] = audioread(fullfile(d, 'stethoscope.wav'));
    x = x(:, M.cfg.rec.stethChannel);
    noise = x(st.noise(1):st.noise(2));  noise = noise - mean(noise);

    [z, p, k] = butter(4, band/(fs/2), 'bandpass');
    sos = zp2sos(z, p, k);
    nb = filtfilt(sos, 1, noise);
    PnBand = mean(nb.^2);                         % noise power in the model band (full scale = 1)
    PnWide = mean(noise.^2);                      % 0 - fs/2

    Ptone = 10.^(T.levelDb/10) / 2;               % sine of amplitude A has power A^2/2
    snrBand(:, r)  = 10*log10(Ptone / PnBand);                    %#ok<AGROW>
    level(:, r)    = T.levelDb;                                   %#ok<AGROW>
    peakSnr(:, r)  = T.snrDb;                                     %#ok<AGROW>
    floorBand(r)   = 10*log10(PnBand / 0.5);      %#ok<AGROW>  dB re full-scale sine (dBFS)
    floorWide(r)   = 10*log10(PnWide / 0.5);      %#ok<AGROW>

    N = diff(st.seg(1,:)) + 1;
    enbwHz = enbw(flattopwin(N, 'periodic'), fs);
    fprintf('%s: N = %d (%.2f s), flat-top ENBW = %.2f Hz, bin spacing %.3f Hz\n', runDirs{r}, N, N/fs, ...
        enbwHz, fs / (2^nextpow2(N) * M.cfg.ana.zeroPad));
    fprintf('   noise floor 25-900 Hz = %.1f dBFS, 0-%.0f Hz = %.1f dBFS, run peak %.1f dBFS\n', ...
        floorBand(r), fs/2, floorWide(r), M.meta.peakDbfsSteth);
end

f = T.fNom;
Out = table(f, mean(level,2), std(level,0,2), mean(peakSnr,2), mean(snrBand,2), std(snrBand,0,2), ...
    'VariableNames', {'fNom_Hz','level_dBFS','level_std_dB','peakToFloor_dB','inBandSNR_dB','inBandSNR_std_dB'});
outDir = gui_ctx('outDir', fullfile(here, 'results'));  if ~isfolder(outDir), mkdir(outDir); end
writetable(Out, fullfile(outDir, 'tone_band_snr.csv'));

inModel = f >= band(1) & f <= band(2);
rng = @(v) sprintf('%.1f-%.1f', min(v), max(v));
fprintf('\nModel-band tones (%d): in-band SNR %s dB (median %.1f), peak-to-floor %s dB\n', nnz(inModel), ...
    rng(Out.inBandSNR_dB(inModel)), median(Out.inBandSNR_dB(inModel)), rng(Out.peakToFloor_dB(inModel)));
for g = {[30 60], [70 100], [110 1000], [1100 6000]}
    s = f >= g{1}(1) & f <= g{1}(2);
    fprintf('  %4d-%4d Hz: in-band SNR %s dB, peak-to-floor %s dB, level %s dBFS\n', g{1}, ...
        rng(Out.inBandSNR_dB(s)), rng(Out.peakToFloor_dB(s)), rng(Out.level_dBFS(s)));
end
fprintf('Noise floor 25-900 Hz: %.1f dBFS (runs %s)\n', mean(floorBand), rng(floorBand));
fprintf('Dynamic range in the model band (0 dBFS full-scale sine vs. in-band noise floor): %.1f dB\n', -mean(floorBand));
S = struct('table', Out, 'floorBand', floorBand, 'floorWide', floorWide);
end
