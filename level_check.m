function level_check(freq, dur)
%LEVEL_CHECK  Play one tone on the configured speaker and report recorded levels.
%   Use before a full run to set the volume: aim for a stethoscope tone of about
%   -30 to -6 dBFS with a clear narrowband SNR (clipping above about -1 dBFS).
if nargin < 1, freq = 250; end
if nargin < 2, dur = 3; end
cfg = config();
idSpk   = find_device_id(cfg.dev.speaker, 'output');
idSteth = find_device_id(cfg.dev.stethoscope, 'input');
t = (0:round(dur*cfg.stim.fs)-1)'/cfg.stim.fs;
y = cfg.stim.amp * sin(2*pi*freq*t);
rec = audiorecorder(cfg.rec.fsSteth, cfg.rec.nBits, cfg.rec.chSteth, idSteth);
record(rec);  pause(0.5);
playblocking(audioplayer(y, cfg.stim.fs, 24, idSpk));
pause(0.5);  stop(rec);
x = getaudiodata(rec, 'double');  x = x(:, cfg.rec.stethChannel);
n = round(0.5*cfg.rec.fsSteth);
quiet = x(1:n);  sig = x(n+1:end-n);
fprintf('%d Hz tone: broadband peak %.1f dBFS, rms %.1f dBFS (idle rms %.1f dBFS)\n', ...
    freq, 20*log10(max(abs(sig))), 20*log10(rms(sig)), 20*log10(rms(quiet)));

% narrowband: tone amplitude vs. neighbouring spectrum
N = numel(sig);  w = flattopwin(N, 'periodic');
A = abs(fft((sig - mean(sig)) .* w)) * 2 / sum(w);
A = A(1:floor(N/2));
f = (0:numel(A)-1)' * cfg.rec.fsSteth / N;
pk = max(A(abs(f - freq) <= 3));
nb = A(abs(f - freq) > 10 & abs(f - freq) < 0.3*freq + 30);
valid = find(f > 15);
[~, iMax] = max(A(valid));
fprintf('    tone %.1f dBFS, local floor %.1f dBFS -> narrowband SNR %.1f dB; strongest component %.1f Hz\n', ...
    20*log10(pk), 20*log10(median(nb)), 20*log10(pk/median(nb)), f(valid(iMax)));
audiowrite(fullfile(tempdir, sprintf('level_check_%d.wav', freq)), x, cfg.rec.fsSteth);
end
