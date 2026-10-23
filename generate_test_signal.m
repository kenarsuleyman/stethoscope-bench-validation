function [y, layout] = generate_test_signal(cfg)
%GENERATE_TEST_SIGNAL  Stepped-tone stimulus with sync chirps and a silent noise segment.
%   Layout: lead silence | chirp | 1 s | noise (silence) | tone, gap, tone, gap ... | chirp | 1 s
%   All times in LAYOUT are seconds relative to the onset of the first chirp.
%   Also writes stimulus/stimulus.wav so the same signal can be played from a phone.

if nargin < 1, cfg = config(); end
fs = cfg.stim.fs;
s  = cfg.stim;

freqs = [s.freqs, s.freqsExt];
freqs = freqs(freqs < fs/2);

tone = @(f) fade(s.amp * sin(2*pi*f*(0:round(s.toneDur*fs)-1)'/fs), fs, s.fadeDur);
sil  = @(d) zeros(round(d*fs), 1);
chp  = make_chirp(fs, cfg);

parts = {sil(s.leadSilence)};
t = 0;                                  % time since first chirp onset
layout.chirpStart = 0;
parts{end+1} = chp;   t = t + numel(chp)/fs;
parts{end+1} = sil(1); t = t + 1;
layout.noiseStart = t;
layout.noiseEnd   = t + s.noiseDur;
parts{end+1} = sil(s.noiseDur); t = t + s.noiseDur;
layout.toneStart = zeros(size(freqs));
for k = 1:numel(freqs)
    layout.toneStart(k) = t;
    parts{end+1} = tone(freqs(k)); t = t + s.toneDur; %#ok<AGROW>
    parts{end+1} = sil(s.gapDur);  t = t + s.gapDur;  %#ok<AGROW>
end
layout.chirpEnd = t;
parts{end+1} = chp;
parts{end+1} = sil(1);

y = vertcat(parts{:});
layout.freqs    = freqs;
layout.toneDur  = s.toneDur;
layout.fs       = fs;
layout.lead     = s.leadSilence;
layout.duration = numel(y)/fs;

if ~exist(cfg.paths.stim, 'dir'), mkdir(cfg.paths.stim); end
audiowrite(fullfile(cfg.paths.stim, 'stimulus.wav'), y, fs, 'BitsPerSample', 24);
save(fullfile(cfg.paths.stim, 'stimulus_layout.mat'), 'layout');
fprintf('Stimulus: %d tones, %.1f s total -> %s\n', numel(freqs), layout.duration, ...
    fullfile(cfg.paths.stim, 'stimulus.wav'));
end

function x = fade(x, fs, d)
n = round(d*fs);
w = 0.5 - 0.5*cos(pi*(0:n-1)'/n);
x(1:n) = x(1:n) .* w;
x(end-n+1:end) = x(end-n+1:end) .* flipud(w);
end
