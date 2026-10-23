function res = analyze_measurement(runDir)
%ANALYZE_MEASUREMENT  Align a recorded run to the stimulus and compute per-tone metrics.
%   Writes results.mat and results_<device>.csv into RUNDIR.

S = load(fullfile(runDir, 'meta.mat'));
cfg = S.cfg;  layout = S.layout;

devs = {'stethoscope'};
cfg.ana.useReference = config().ana.useReference;     % current setting, not the run snapshot
if cfg.ana.useReference && isfile(fullfile(runDir, 'reference.wav')), devs{end+1} = 'reference'; end

for d = 1:numel(devs)
    [x, fs] = audioread(fullfile(runDir, [devs{d} '.wav']));
    if strcmp(devs{d}, 'stethoscope'), x = x(:, cfg.rec.stethChannel); else, x = x(:,1); end
    r = struct('fs', fs);

    % --- alignment: start chirp, end chirp, linear clock mapping ---
    preRoll = 1;  if isfield(S.meta, 'preRoll'), preRoll = S.meta.preRoll; end
    [r.onsetStart, r.qStart] = find_chirp(x, fs, cfg, [1, round((preRoll + layout.lead + 5)*fs)]);
    expEnd = r.onsetStart + round(layout.chirpEnd*fs);
    [r.onsetEnd, r.qEnd] = find_chirp(x, fs, cfg, expEnd + round([-3 3]*fs));
    r.clockRatio = (r.onsetEnd - r.onsetStart) / (layout.chirpEnd*fs);   % rec clock / play clock
    if r.qEnd < 10 || abs(r.clockRatio - 1) > 0.01
        warning('%s: end chirp unreliable (q=%.1f) -> assuming nominal clock.', devs{d}, r.qEnd);
        r.clockRatio = 1;
    end
    if r.qStart < 10, warning('%s: start chirp detection weak (q=%.1f).', devs{d}, r.qStart); end
    t2i = @(t) r.onsetStart + round(t * fs * r.clockRatio);

    noise = x(t2i(layout.noiseStart + 0.3) : t2i(layout.noiseEnd - 0.3));
    r.noise = [t2i(layout.noiseStart + 0.3), t2i(layout.noiseEnd - 0.3)];

    nF = numel(layout.freqs);
    T = table('Size', [nF 9], 'VariableTypes', repmat({'double'},1,9), 'VariableNames', ...
        {'fNom','fMeas','fErrHz','fErrPct','levelDb','noiseDb','snrDb','thdPct','dominant'});
    r.seg = zeros(nF, 2);
    for k = 1:nF
        i1 = t2i(layout.toneStart(k) + cfg.ana.skipStart);
        i2 = t2i(layout.toneStart(k) + layout.toneDur - cfg.ana.skipEnd);
        r.seg(k,:) = [i1 i2];
        m = tone_metrics(x(i1:i2), noise, fs, layout.freqs(k), cfg);
        T(k,:) = {layout.freqs(k), m.fMeas, m.fMeas - layout.freqs(k), ...
            100*(m.fMeas - layout.freqs(k))/layout.freqs(k), m.levelDb, m.noiseDb, ...
            m.snrDb, m.thdPct, m.dominant};
    end
    r.T = T;
    res.(devs{d}) = r;
    writetable(T, fullfile(runDir, ['results_' devs{d} '.csv']));
    fprintf('%-11s fs=%d  chirp q=%.0f/%.0f  clock ratio=%.6f (%+.0f ppm)  chirp at %.3f s\n', ...
        devs{d}, fs, r.qStart, r.qEnd, r.clockRatio, 1e6*(r.clockRatio-1), ...
        r.onsetStart/fs);
end
res.runDir = runDir;
save(fullfile(runDir, 'results.mat'), 'res');
end
