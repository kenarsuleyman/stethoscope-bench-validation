function [y, layout] = generate_pcg_stimulus(cfg)
%GENERATE_PCG_STIMULUS  Heart-sound playback stimulus for the original-vs-stethoscope test.
%   Layout: lead silence | chirp | 1 s | noise (silence) | clip, gap, clip, gap ... | chirp | 1 s
%   Clips are the demo PCG recordings in cfg.pcg.dir, in filename_map.csv order (sources and
%   classes interleaved, so slow drifts during a run do not bias one class). Each clip is
%   conditioned by condition_pcg_clip and played at a common peak level cfg.pcg.peakDbfs.
%   LAYOUT holds the timing and, in LAYOUT.ref{k}, the conditioned clip at its native rate
%   and played level: the reference for the comparison (exactly what was played).
%   Writes pcg_test/stimulus/pcg_stimulus.wav (+ layout .mat), playable from a phone too.

if nargin < 1, cfg = config(); end
fs = cfg.stim.fs;  s = cfg.stim;  p = cfg.pcg;
map = readtable(fullfile(p.dir, 'filename_map.csv'), 'Delimiter', ',', ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
files = map{:,1};  orig = map{:,2};
amp = 10^(p.peakDbfs/20);
sil = @(d) zeros(round(d*fs), 1);
chp = make_chirp(fs, cfg);

parts = {sil(s.leadSilence)};
t = 0;
layout.chirpStart = 0;
parts{end+1} = chp;   t = t + numel(chp)/fs;
parts{end+1} = sil(1); t = t + 1;
layout.noiseStart = t;  layout.noiseEnd = t + s.noiseDur;
parts{end+1} = sil(s.noiseDur); t = t + s.noiseDur;

nC = numel(files);
layout.clipStart = zeros(nC,1);  layout.clipDur = zeros(nC,1);
layout.fsNat = zeros(nC,1);  layout.label = zeros(nC,1);  layout.ref = cell(nC,1);
for k = 1:nC
    [xNat, fsNat, x48] = condition_pcg_clip(fullfile(p.dir, files(k)), cfg);
    layout.clipStart(k) = t;
    layout.clipDur(k)   = numel(x48)/fs;
    layout.fsNat(k)     = fsNat;
    layout.label(k)     = double(startsWith(files(k), "anormal"));
    layout.ref{k}       = single(amp * xNat);
    parts{end+1} = amp * x48;  t = t + numel(x48)/fs;   %#ok<AGROW>
    parts{end+1} = sil(p.gapDur); t = t + p.gapDur;     %#ok<AGROW>
end
layout.chirpEnd = t;
parts{end+1} = chp;
parts{end+1} = sil(1);

y = vertcat(parts{:});
layout.files    = files;
layout.orig     = orig;
layout.fs       = fs;
layout.lead     = s.leadSilence;
layout.duration = numel(y)/fs;
layout.type     = 'pcg';
layout.peakDbfs = p.peakDbfs;

outDir = fullfile(cfg.paths.pcg, 'stimulus');
if ~exist(outDir, 'dir'), mkdir(outDir); end
% conditioned clips at native rate (32-bit float): model input "as played" (checks conditioning)
for k = 1:nC
    f = fullfile(outDir, 'played_ref', files(k));
    if ~exist(fileparts(f), 'dir'), mkdir(fileparts(f)); end
    audiowrite(f, double(layout.ref{k}), layout.fsNat(k), 'BitsPerSample', 32);
end
audiowrite(fullfile(outDir, 'pcg_stimulus.wav'), y, fs, 'BitsPerSample', 24);
save(fullfile(outDir, 'pcg_stimulus_layout.mat'), 'layout');
fprintf('PCG stimulus: %d clips (%d normal, %d abnormal), peak %.0f dBFS, %.1f s total -> %s\n', ...
    nC, sum(layout.label==0), sum(layout.label==1), p.peakDbfs, layout.duration, ...
    fullfile(outDir, 'pcg_stimulus.wav'));
end
