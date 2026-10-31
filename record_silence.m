function runDir = record_silence(label, seconds)
%RECORD_SILENCE  Record the stethoscope without any stimulus (noise floor), e.g. with the coupler inlet sealed to
%   separate electrical from acoustic noise (advisor's 2nd review K3). Raw WAV + meta.mat in data/<timestamp>_<label>/.
%   Analysed with noise_floor_compare.
%
%   record_silence('sealed_pc', 30)
if nargin < 2, seconds = 30; end
cfg = config();
[idSteth, nmSteth] = find_device_id(cfg.dev.stethoscope, 'input');
rec = audiorecorder(cfg.rec.fsSteth, cfg.rec.nBits, cfg.rec.chSteth, idSteth);
fprintf('Recording %s for %.0f s ... keep quiet.\n', nmSteth, seconds);
record(rec, seconds);
wait_with_progress(@() isrecording(rec), seconds, 'recording');
x = getaudiodata(rec, 'double');
runDir = fullfile(cfg.paths.data, [char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')) '_' label]);
mkdir(runDir);
audiowrite(fullfile(runDir, 'stethoscope.wav'), x, cfg.rec.fsSteth);
meta.label = label;  meta.mode = 'silence';  meta.stimType = 'none';  meta.startTime = datetime('now');
meta.devices.stethoscope = nmSteth;  meta.peakDbfsSteth = 20*log10(max(abs(x(:))));
save(fullfile(runDir, 'meta.mat'), 'cfg', 'meta');
fprintf('Saved -> %s (peak %.1f dBFS)\n', runDir, meta.peakDbfsSteth);
end
