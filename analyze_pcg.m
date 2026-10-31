function res = analyze_pcg(runDir)
%ANALYZE_PCG  Align a heart-sound playback run to the stimulus and compare every clip with
%   what was played (LAYOUT.ref, the conditioned clip at its native rate).
%
%   Per clip (model band 25-900 Hz, model preprocessing: 4th-order Butterworth zero-phase,
%   peak normalisation, at 4000 Hz):
%     bandSnrDb  clip power vs. the in-run silent segment
%     rWave      waveform correlation, played vs. recorded
%     rEnv       correlation of the S1/S2 envelopes (Hilbert magnitude, 20 Hz low-pass)
%     rWaveEq, rEnvEq   the same after correcting the recording with the inverse of the
%                chain response measured with pure tones (independent of the heart sounds)
%   Also: transfer function and coherence estimated from all clips (tfestimate / mscohere).
%
%   Writes to RUNDIR: results_pcg.csv, results_pcg.mat and the aligned recordings
%   pcg_clips/steth/<clip>.wav, pcg_clips/steth_eq/<clip>.wav (44.1 kHz, float) for the model.

S = load(fullfile(runDir, 'meta.mat'));
cfg = S.cfg;  layout = S.layout;
[x, fs] = audioread(fullfile(runDir, 'stethoscope.wav'));
x = x(:, cfg.rec.stethChannel);

% --- run alignment: start/end chirp, linear clock mapping (as analyze_measurement) ---
preRoll = 1;  if isfield(S.meta, 'preRoll'), preRoll = S.meta.preRoll; end
[on1, q1] = find_chirp(x, fs, cfg, [1, round((preRoll + layout.lead + 5)*fs)]);
expEnd = on1 + round(layout.chirpEnd*fs);
[on2, q2] = find_chirp(x, fs, cfg, expEnd + round([-3 3]*fs));
clockRatio = (on2 - on1) / (layout.chirpEnd*fs);
if q2 < 10 || abs(clockRatio - 1) > 0.01
    warning('End chirp unreliable (q=%.1f) -> assuming nominal clock.', q2);  clockRatio = 1;
end
t2i = @(t) on1 + round(t * fs * clockRatio);

bp = @(f) design_bp(f);
sosR = bp(fs);  sos4 = bp(4000);
noise = x(t2i(layout.noiseStart + 0.3) : t2i(layout.noiseEnd - 0.3));
noiseRms = rms(filtfilt(sosR{:}, noise));

R = chain_response(cfg);                         % tone-measured response (dB re 250 Hz)
outS  = fullfile(runDir, 'pcg_clips', 'steth');
outEq = fullfile(runDir, 'pcg_clips', 'steth_eq');

nC = numel(layout.files);
T = table('Size', [nC 12], 'VariableTypes', [{'string','string'}, repmat({'double'},1,10)], ...
    'VariableNames', {'file','source','label','lagMs','polarity','peakDbfs','bandSnrDb', ...
    'rWave','rEnv','rWaveEq','rEnvEq','gainDb'});
src = pcg_source_names(layout.orig);
maxLag = round(0.15*fs);
Pxy = 0;  Pxx = 0;  Pyy = 0;  nfftT = 8192;
for k = 1:nC
    ref = double(layout.ref{k});  fsN = layout.fsNat(k);
    refR = resample(ref, fs, fsN);  n = numel(refR);
    i0 = t2i(layout.clipStart(k));
    win = x(max(1, i0 - maxLag) : min(numel(x), i0 + n - 1 + maxLag));
    [c, lags] = xcorr(filtfilt(sosR{:}, win), filtfilt(sosR{:}, refR), 2*maxLag);
    [~, j] = max(abs(c));
    pol = sign(c(j));
    i1 = max(1, i0 - maxLag) + lags(j);
    rec = pol * x(i1 : i1 + n - 1);
    recEq = equalize(rec, fs, R);

    write_clip(fullfile(outS,  layout.files(k)), rec, fs);
    write_clip(fullfile(outEq, layout.files(k)), recEq, fs);

    % model-band comparison at 4 kHz with the model preprocessing
    o4 = prep(resample(ref, 4000, fsN), sos4);
    r4 = prep(resample(rec, 4000, fs), sos4);
    e4 = prep(resample(recEq, 4000, fs), sos4);
    m = min([numel(o4) numel(r4) numel(e4)]);
    o4 = o4(1:m);  r4 = r4(1:m);  e4 = e4(1:m);
    recB = filtfilt(sosR{:}, rec);
    g = (refR' * recB) / (refR' * refR);         % overall chain gain for this clip
    T(k,:) = {layout.files(k), src(k), layout.label(k), 1000*(i1 - i0)/fs, pol, ...
        20*log10(max(abs(rec))), 20*log10(rms(recB)/noiseRms), ...
        pcorr(o4, r4), pcorr(env(o4), env(r4)), pcorr(o4, e4), pcorr(env(o4), env(e4)), 20*log10(abs(g))};

    % transfer function accumulated over clips (played -> recorded, both at fs)
    [p, f] = cpsd(refR, rec, hann(nfftT), nfftT/2, nfftT, fs);  Pxy = Pxy + p;
    Pxx = Pxx + pwelch(refR, hann(nfftT), nfftT/2, nfftT, fs);
    Pyy = Pyy + pwelch(rec,  hann(nfftT), nfftT/2, nfftT, fs);
end
H.f = f;  H.dB = 20*log10(abs(Pxy ./ Pxx));  H.coh = abs(Pxy).^2 ./ (Pxx .* Pyy);
H.Pxx = Pxx;  H.Pyy = Pyy;  H.Pxy = Pxy;  H.nClips = nC;  % spectra summed over clips (coherence check)
[Pn, fn] = pwelch(noise, hann(nfftT), nfftT/2, nfftT, fs);

res.T = T;  res.H = H;  res.noise = struct('f', fn, 'P', Pn, 'bandRms', noiseRms);
res.clockRatio = clockRatio;  res.chirpQ = [q1 q2];  res.runDir = runDir;  res.chain = R;
save(fullfile(runDir, 'results_pcg.mat'), 'res');
writetable(T, fullfile(runDir, 'results_pcg.csv'));

fprintf('PCG run %s: clock %+.1f ppm, chirp q=%.0f/%.0f, noise (25-900 Hz) %.1f dBFS rms\n', ...
    runDir, 1e6*(clockRatio-1), q1, q2, 20*log10(noiseRms));
fprintf('  %d clips: band SNR median %.1f dB (min %.1f), rWave median %.3f, rEnv median %.3f, rEnvEq median %.3f\n', ...
    nC, median(T.bandSnrDb), min(T.bandSnrDb), median(T.rWave), median(T.rEnv), median(T.rEnvEq));
fprintf('  peak %.1f dBFS max; alignment lag %.1f..%.1f ms; polarity %s\n', max(T.peakDbfs), ...
    min(T.lagMs), max(T.lagMs), mat2str(unique(T.polarity)'));
end

% -------------------------------------------------------------------------------------------
function c = design_bp(fs)
[z, p, k] = butter(4, [25 900]/(fs/2), 'bandpass');
[sos, g] = zp2sos(z, p, k);
c = {sos, g};
end

function y = prep(x, sos4)
% model preprocessing: bandpass 25-900 Hz zero-phase, peak normalisation
y = filtfilt(sos4{:}, x);
y = y / max(abs(y));
end

function e = env(x)
% S1/S2 envelope: Hilbert magnitude, 20 Hz low-pass (zero-phase), at 4 kHz
[b, a] = butter(2, 20/2000);
e = filtfilt(b, a, abs(hilbert(x)));
end

function R = chain_response(cfg)
% pure-tone chain response (mean of the final runs), dB re 250 Hz
d = tone_response_dir();
Tt = readtable(fullfile(d, 'tr', 'ozet_tablo.csv'));
R.f = Tt.fNom_Hz;  R.dB = Tt.relLevel_dB;  R.source = d;
R.maxBoostDb = 30;
end

function y = equalize(x, fs, R)
% zero-phase correction with the inverse tone-measured response (boost capped at
% R.maxBoostDb); outside the measured range the edge values are held.
y = apply_chain_gain(x, fs, R, 'inverse');
end

function write_clip(path, x, fs)
% audiowrite clips floats to [-1, 1]; the model peak-normalises, so scale to a 0.5 peak
if ~exist(fileparts(path), 'dir'), mkdir(fileparts(path)); end
audiowrite(path, 0.5 * x / max(abs(x)), fs, 'BitsPerSample', 32);
end

function r = pcorr(a, b)
% Pearson correlation (base MATLAB; corr needs the Statistics Toolbox)
c = corrcoef(a, b);  r = c(1,2);
end
