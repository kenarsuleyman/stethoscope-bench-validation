function [y, layout] = generate_sweep(cfg)
%GENERATE_SWEEP  Exponential sine sweep stimulus (Farina) with the same sync chirps and silent noise segment as
%   generate_test_signal. Layout: lead silence | chirp | 1 s | noise (silence) | sweep, gap (x cfg.sweep.n) | chirp | 1 s
%   All times in LAYOUT are seconds relative to the onset of the first chirp. Writes stimulus/sweep.wav.

if nargin < 1, cfg = config(); end
fs = cfg.stim.fs;
s  = cfg.stim;
w  = cfg.sweep;

sw  = s.amp * make_ess(fs, w);
sil = @(d) zeros(round(d*fs), 1);
chp = make_chirp(fs, cfg);

parts = {sil(s.leadSilence)};
t = 0;
layout.chirpStart = 0;
parts{end+1} = chp;    t = t + numel(chp)/fs;
parts{end+1} = sil(1); t = t + 1;
layout.noiseStart = t;
layout.noiseEnd   = t + s.noiseDur;
parts{end+1} = sil(s.noiseDur); t = t + s.noiseDur;
layout.sweepStart = zeros(1, w.n);
for k = 1:w.n
    layout.sweepStart(k) = t;
    parts{end+1} = sw;         t = t + numel(sw)/fs; %#ok<AGROW>
    parts{end+1} = sil(w.gap); t = t + w.gap;        %#ok<AGROW>
end
layout.chirpEnd = t;
parts{end+1} = chp;
parts{end+1} = sil(1);

y = vertcat(parts{:});
layout.sweep    = w;
layout.amp      = s.amp;
layout.fs       = fs;
layout.lead     = s.leadSilence;
layout.duration = numel(y)/fs;

if ~exist(cfg.paths.stim, 'dir'), mkdir(cfg.paths.stim); end
audiowrite(fullfile(cfg.paths.stim, 'sweep.wav'), y, fs, 'BitsPerSample', 24);
fprintf('Stimulus: %d sweeps %g-%g Hz x %.0f s, %.1f s total -> %s\n', w.n, w.f(1), w.f(2), w.dur, ...
    layout.duration, fullfile(cfg.paths.stim, 'sweep.wav'));
end
