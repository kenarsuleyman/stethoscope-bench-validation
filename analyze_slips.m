function S = analyze_slips(runDirs, minLevelDb, minFreqHz)
%ANALYZE_SLIPS  Detect single-sample slips in the USB audio stream from the phase of steady tones.
%   Each tone segment (the same 1.4 s windows as analyze_measurement) is demodulated at its measured
%   frequency, averaged in 5 ms blocks and unwrapped. A dropped or repeated sample shifts the phase of
%   a tone at f by 2*pi*f/fs; jumps are detected after removing the linear phase trend and are converted
%   to samples. The slip rate gives the clock offset that the stream absorbs (Teensy I2S clock vs. USB
%   host). The record/playback clock ratio from the chirps is reported with its resolution.
%   Writes results/sample_slips.csv (one row per event) and prints a summary.

if nargin < 1 || isempty(runDirs)
    runDirs = {'data/20261009_140429_diyafram_run1', 'data/20261009_140717_diyafram_run2', ...
               'data/20261009_140956_diyafram_run3'};
end
if nargin < 2 || isempty(minLevelDb), minLevelDb = -45; end
if nargin < 3, minFreqHz = 300; end   % below this a one-sample phase step (2*pi*f/fs) is too small to detect reliably
here = fileparts(mfilename('fullpath'));
blk = 0.005;                                   % 5 ms blocks
ev = table();  tot = struct('t', 0, 'n', 0, 'samples', 0);

for r = 1:numel(runDirs)
    d = fullfile(here, runDirs{r});
    M = load(fullfile(d, 'meta.mat'));  R = load(fullfile(d, 'results.mat'));
    st = R.res.stethoscope;  T = st.T;
    [x, fs] = audioread(fullfile(d, 'stethoscope.wav'));
    x = x(:, M.cfg.rec.stethChannel);
    nb = round(blk * fs);
    use = find(T.levelDb >= minLevelDb & T.fNom >= minFreqHz & T.fNom <= 6000);
    tAnalysed = 0;  nEv = 0;  sumSamples = 0;
    for k = use'
        i1 = st.seg(k,1);  i2 = st.seg(k,2);
        seg = x(i1:i2);  n = (0:numel(seg)-1)';
        f0 = T.fMeas(k);
        z = seg .* exp(-1j*2*pi*f0*n/fs);
        nB = floor(numel(z)/nb);
        zb = mean(reshape(z(1:nB*nb), nb, nB), 1).';
        ph = unwrap(angle(zb));
        tb = ((0:nB-1)' + 0.5) * nb;
        ph = ph - polyval(polyfit(tb, ph, 1), tb);
        dph = diff(ph);
        step = 2*pi*f0/fs;                              % phase change of a one-sample slip
        thr = max(0.4*step, 6*1.4826*median(abs(dph - median(dph))));
        j = find(abs(dph) > thr);
        if ~isempty(j), j = j([true; diff(j) > 1]); end % one event per jump
        for q = j'
            % jump size: compare mean phase 10 blocks after vs. before (robust to a single noisy block)
            a = ph(max(1, q-9):q);  b = ph(q+1:min(nB, q+10));
            js = (mean(b) - mean(a)) / step;
            ev = [ev; table(string(runDirs{r}), T.fNom(k), T.levelDb(k), (i1 + tb(q) + nb/2)/fs, js, ...
                'VariableNames', {'run','fNom_Hz','level_dBFS','time_s','jump_samples'})]; %#ok<AGROW>
            sumSamples = sumSamples + js;
        end
        nEv = nEv + numel(j);  tAnalysed = tAnalysed + numel(seg)/fs;
    end
    fprintf('%s: %d tones (>= %d dBFS, %d-6000 Hz), %.1f s analysed, %d events, mean jump %+.2f samples, rate 1 per %.2f s, %+.1f ppm; chirp clock ratio %+.2f ppm (1 sample = %.2f ppm)\n', ...
        runDirs{r}, numel(use), minLevelDb, minFreqHz, tAnalysed, nEv, sumSamples/max(nEv,1), tAnalysed/max(nEv,1), ...
        1e6*sumSamples/(tAnalysed*fs), 1e6*(st.clockRatio-1), 1e6/(st.onsetEnd - st.onsetStart));
    tot.t = tot.t + tAnalysed;  tot.n = tot.n + nEv;  tot.samples = tot.samples + sumSamples;
end
outDir = fullfile(here, 'results');  if ~isfolder(outDir), mkdir(outDir); end
writetable(ev, fullfile(outDir, 'sample_slips.csv'));
fprintf('\nAll runs: %d events in %.1f s of tone -> 1 slip per %.2f s, mean jump %+.2f samples (median |jump| %.2f), equivalent offset %+.1f ppm\n', ...
    tot.n, tot.t, tot.t/max(tot.n,1), tot.samples/max(tot.n,1), median(abs(ev.jump_samples)), 1e6*tot.samples/(tot.t*fs));
S = struct('events', ev, 'total', tot);
end
