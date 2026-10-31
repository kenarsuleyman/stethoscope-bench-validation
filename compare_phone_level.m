function T = compare_phone_level(preRun, phoneRun, postRun, sweepRuns)
%COMPARE_PHONE_LEVEL  Advisor's 2nd review K3 + M4: smartphone vs computer level, and sweep vs tone peaks.
%   PRERUN / POSTRUN: computer tone runs immediately before and after the smartphone tone run PHONERUN (same setup,
%   stethoscope unplugged from the computer only for the phone run). The phone level minus the mean computer level
%   is listed per tone (tones with SNR < 20 dB in any run are left out); the pre/post difference bounds the drift of
%   the setup. SWEEPRUNS (optional): sweep runs of the same setup, analysed with analyze_sweep(run, PRERUN, 0.30);
%   their peaks and the sweep-minus-tone level difference are summarised.
%   Writes results/k3_phone_level.csv (and results/m4_sweep_peaks.csv).
%
%   compare_phone_level('data/..._tube30cm_pre_phone', 'data/..._phone_tones_level', 'data/..._tube30cm_post_phone', ...
%       {'data/..._sweep_final_run1', 'data/..._sweep_final_run2', 'data/..._sweep_final_run3'})

if nargin < 4, sweepRuns = {}; end
here = fileparts(mfilename('fullpath'));
P0 = tone_table(here, preRun);  Ph = tone_table(here, phoneRun);  P1 = tone_table(here, postRun);
f = P0.fNom;
ok = P0.snrDb >= 20 & Ph.snrDb >= 20 & P1.snrDb >= 20;
pc = (P0.levelDb + P1.levelDb) / 2;
T = table(f, P0.levelDb, P1.levelDb, Ph.levelDb, Ph.levelDb - pc, P1.levelDb - P0.levelDb, ok, ...
    'VariableNames', {'fNom_Hz', 'pc_pre_dBFS', 'pc_post_dBFS', 'phone_dBFS', 'phone_minus_pc_dB', ...
    'post_minus_pre_dB', 'snr_ok'});
resDir = gui_ctx('outDir', fullfile(here, 'results'));  if ~isfolder(resDir), mkdir(resDir); end
writetable(T, fullfile(resDir, 'k3_phone_level.csv'));
for b = [30 1000; 1000 6000]'
    m = ok & f >= b(1) & f <= b(2);  d = T.phone_minus_pc_dB(m);  s = T.post_minus_pre_dB(m);
    fprintf('K3 %4d-%4d Hz (%d tones): phone - PC median %+.2f dB (%+.2f to %+.2f); post - pre median %+.2f dB, max |%.2f|\n', ...
        b(1), b(2), nnz(m), median(d), min(d), max(d), median(s), max(abs(s)));
end

if isempty(sweepRuns), return; end
n = numel(sweepRuns);  pk = nan(n, 3);  dMax = nan(n, 1);  dMed = nan(n, 1);
for k = 1:n
    S = load(fullfile(abs_path(here, sweepRuns{k}), 'results_sweep.mat'));  r = S.res;
    pk(k, 1:min(3, numel(r.peaksHz))) = r.peaksHz(1:min(3, numel(r.peaksHz)));
    m = f >= 30 & f <= 1000 & P0.snrDb >= 20;              % analyze_sweep kept the tones with SNR >= 20 dB in 30-6000 Hz
    keep = f >= 30 & f <= 6000 & P0.snrDb >= 20;
    d = nan(size(f));  d(keep) = r.toneDiffDb;
    dMax(k) = max(abs(d(m)));  dMed(k) = median(abs(d(m)));
end
pred = (2*(1:3) - 1) * 343 / (4*0.30);
Ts = table(string(sweepRuns(:)), pk(:, 1), pk(:, 2), pk(:, 3), dMed, dMax, 'VariableNames', ...
    {'run', 'peak1_Hz', 'peak2_Hz', 'peak3_Hz', 'sweep_minus_tone_absmedian_dB_30_1000', 'sweep_minus_tone_absmax_dB_30_1000'});
writetable(Ts, fullfile(resDir, 'm4_sweep_peaks.csv'));
fprintf('M4 sweep peaks (mean of %d runs): %s Hz, measured/predicted %s; sweep - tone 30-1000 Hz max |%.2f| dB\n', ...
    n, mat2str(round(mean(pk, 1), 1)), mat2str(round(mean(pk, 1)./pred, 3)), max(dMax));
end

function Tt = tone_table(here, run)
R = load(fullfile(abs_path(here, run), 'results.mat'));
Tt = R.res.stethoscope.T;
end

function p = abs_path(here, p)
if ~isfolder(p), p = fullfile(here, p); end
end
