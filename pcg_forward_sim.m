function S = pcg_forward_sim(runDirs)
%PCG_FORWARD_SIM  Non-circular checks of H3 (advisor's review, R7) with the existing PCG runs.
%   sim_H     played clip filtered with the pure-tone response (+R, zero-phase): an ideal linear system
%             that has only the measured magnitude response (replaces the undocumented r = 0.77)
%   sim_Hn    sim_H plus Gaussian noise with the run's measured noise spectrum, scaled so that the
%             model-band SNR equals the clip's measured bandSnrDb in that run (one realisation per run)
%   steth_eqlow / steth_eqmid   real recordings corrected only below 100 Hz / only from 100 Hz up
%   Writes 44.1 kHz float WAVs for the model (pcg_test/sim/sim_H/, <run>/pcg_clips/{sim_Hn,steth_eqlow,
%   steth_eqmid}/) and pcg_test/results/pcg_forward_sim.csv (S1/S2 envelope correlation per clip).
%   Model decisions for these variants: pcg_test/pcg_model_compare.py.

if nargin < 1
    runDirs = {'data/20261009_190101_pcg_run1', 'data/20261009_190630_pcg_run2', 'data/20261009_191158_pcg_run3'};
end
here = fileparts(mfilename('fullpath'));
fs = 44100;  rng(2026);
R = chain_response();
sos4 = bp(4000);  sosR = bp(fs);
L = load(fullfile(here, runDirs{1}, 'meta.mat'));  layout = L.layout;
nC = numel(layout.files);  nR = numel(runDirs);
rH = zeros(nC,1);  rHn = zeros(nC,nR);  rLow = zeros(nC,nR);  rMid = zeros(nC,nR);  rRaw = zeros(nC,nR);

for k = 1:nC
    ref = double(layout.ref{k});  fsN = layout.fsNat(k);
    refR = resample(ref, fs, fsN);
    o4 = prep(resample(ref, 4000, fsN), sos4);
    simH = apply_chain_gain(refR, fs, R, 'forward');
    write_clip(fullfile(here, 'pcg_test', 'sim', 'sim_H', layout.files(k)), simH, fs);
    rH(k) = renv(o4, simH, fs, sos4);
    for r = 1:nR
        d = fullfile(here, runDirs{r});
        P = load(fullfile(d, 'results_pcg.mat'));  T = P.res.T;
        % noise with the run's measured spectrum (Welch PSD of the silent segment), random phase
        nz = shaped_noise(numel(simH), fs, P.res.noise.f, P.res.noise.P);
        sB = rms(filtfilt(sosR{:}, simH));  nB = rms(filtfilt(sosR{:}, nz));
        simHn = simH + nz * (sB / nB) * 10^(-T.bandSnrDb(k)/20);
        write_clip(fullfile(d, 'pcg_clips', 'sim_Hn', layout.files(k)), simHn, fs);
        rHn(k,r) = renv(o4, simHn, fs, sos4);

        rec = audioread(fullfile(d, 'pcg_clips', 'steth', layout.files(k)));
        low = apply_chain_gain(rec, fs, R, 'inverse', [0 100]);
        mid = apply_chain_gain(rec, fs, R, 'inverse', [100 Inf]);
        write_clip(fullfile(d, 'pcg_clips', 'steth_eqlow', layout.files(k)), low, fs);
        write_clip(fullfile(d, 'pcg_clips', 'steth_eqmid', layout.files(k)), mid, fs);
        rLow(k,r) = renv(o4, low, fs, sos4);  rMid(k,r) = renv(o4, mid, fs, sos4);
        rRaw(k,r) = T.rEnv(k);
    end
end
Out = table(layout.files(:), pcg_source_names(layout.orig), rH, mean(rHn,2), mean(rRaw,2), mean(rLow,2), mean(rMid,2), ...
    'VariableNames', {'file','source','rEnv_simH','rEnv_simHn','rEnv_raw','rEnv_eqlow','rEnv_eqmid'});
outDir = fullfile(here, 'pcg_test', 'results');  if ~isfolder(outDir), mkdir(outDir); end
writetable(Out, fullfile(outDir, 'pcg_forward_sim.csv'));
fprintf('S1/S2 envelope correlation with the played clip, median over 47 clips:\n');
fprintf('  ideal linear system (sim_H)            %.3f\n', median(rH));
fprintf('  ideal linear system + measured noise   %.3f\n', median(Out.rEnv_simHn));
fprintf('  real recording (raw)                   %.3f\n', median(Out.rEnv_raw));
fprintf('  real recording, corrected < 100 Hz     %.3f\n', median(Out.rEnv_eqlow));
fprintf('  real recording, corrected >= 100 Hz    %.3f\n', median(Out.rEnv_eqmid));
S = struct('table', Out);
end

% -------------------------------------------------------------------------------------------
function R = chain_response()
% pure-tone response (mean of the final runs), dB re 250 Hz -- as analyze_pcg
d = dir(fullfile(fileparts(mfilename('fullpath')), 'figures', 'birlesik_*'));
Tt = readtable(fullfile(d(end).folder, d(end).name, 'tr', 'ozet_tablo.csv'));
R.f = Tt.fNom_Hz;  R.dB = Tt.relLevel_dB;  R.maxBoostDb = 30;
end

function c = bp(fs)
[z, p, k] = butter(4, [25 900]/(fs/2), 'bandpass');
[sos, g] = zp2sos(z, p, k);  c = {sos, g};
end

function y = prep(x, sos4)
y = filtfilt(sos4{:}, x);  y = y / max(abs(y));
end

function e = env(x)
[b, a] = butter(2, 20/2000);  e = filtfilt(b, a, abs(hilbert(x)));
end

function r = renv(o4, x, fs, sos4)
% envelope correlation exactly as analyze_pcg (model preprocessing at 4 kHz, Pearson)
x4 = prep(resample(x, 4000, fs), sos4);
m = min(numel(o4), numel(x4));
c = corrcoef(env(o4(1:m)), env(x4(1:m)));  r = c(1,2);
end

function n = shaped_noise(len, fs, fP, P)
nfft = 2^nextpow2(len);
f = (0:nfft-1)'*fs/nfft;  f = min(f, fs - f);
A = sqrt(interp1(fP, P, f, 'linear', P(end)));
W = fft(randn(nfft, 1)) .* A;
n = real(ifft(W));  n = n(1:len);
end

function write_clip(path, x, fs)
if ~exist(fileparts(path), 'dir'), mkdir(fileparts(path)); end
audiowrite(path, 0.5 * x / max(abs(x)), fs, 'BitsPerSample', 32);
end
