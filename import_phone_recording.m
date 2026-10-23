function runDir = import_phone_recording(wavPath, label, stimType, toneDbfs)
%IMPORT_PHONE_RECORDING  Turn a test recording of the mobile app into a normal run folder and analyse it.
%   Advisor's review R6: the stethoscope is plugged into the smartphone, the app records the raw capture
%   stream (AudioRecord, 16 kHz mono, test mode of the test-recording branch) while play_stimulus plays the
%   sequence. The WAV (and its JSON sidecar: audio source, routed device, phone model) is copied into
%   data/<timestamp>_<label>/ unchanged, a meta.mat like run_measurement's is written, and the usual
%   analysis runs (analyze_measurement + make_figures for tones, analyze_pcg for heart sounds).
%   The raw phone file is never modified.
%
%   import_phone_recording('phone_rec/test_2026-10-24_14-03-11.wav', 'phone_pcg_run1', 'pcg')
if nargin < 3 || isempty(stimType), stimType = 'tones'; end
if nargin < 4, toneDbfs = []; end
here = fileparts(mfilename('fullpath'));
cfg = config();
if ~isempty(toneDbfs), cfg.stim.amp = 10^(toneDbfs/20); end
pcg = strcmpi(stimType, 'pcg');
if pcg
    [~, layout] = generate_pcg_stimulus(cfg);
else
    [~, layout] = generate_test_signal(cfg);
end

info = audioinfo(wavPath);
x = audioread(wavPath);
cfg.rec.fsSteth = info.SampleRate;  cfg.rec.chSteth = info.NumChannels;  cfg.rec.stethChannel = 1;

meta.label = label;  meta.mode = 'phone';  meta.stimType = stimType;
meta.preRoll = 30;                     % the phone starts recording an unknown time before playback
meta.sourceFile = wavPath;
meta.startTime = datetime(dir(wavPath).datenum, 'ConvertFrom', 'datenum');   % fallback; JSON startedAt is more exact
[d, n] = fileparts(wavPath);  js = fullfile(d, [n '.json']);
meta.devices.stethoscope = 'smartphone app';
if isfile(js)
    J = jsondecode(fileread(js));  meta.phone = J;
    try meta.startTime = datetime(J.startedAt, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''', 'TimeZone', 'UTC'); catch, end
    if isfield(J, 'capture') && ~isempty(J.capture)
        meta.devices.stethoscope = sprintf('%s %s, %s, %s', string(J.device.manufacturer), string(J.device.model), ...
            J.capture.source, J.capture.routedDevice);
    end
end
meta.devices.speaker = cfg.dev.speaker;
meta.peakDbfsSteth = 20*log10(max(abs(x(:))));

runDir = fullfile(cfg.paths.data, [char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')) '_' label]);
mkdir(runDir);
copyfile(wavPath, fullfile(runDir, 'stethoscope.wav'));
if isfile(js), copyfile(js, fullfile(runDir, 'phone_capture.json')); end
save(fullfile(runDir, 'meta.mat'), 'cfg', 'layout', 'meta');
fprintf('Imported %s (%.1f s, %d Hz) -> %s\n', wavPath, info.Duration, info.SampleRate, runDir);
fprintf('Recorded with: %s; peak %.1f dBFS\n', meta.devices.stethoscope, meta.peakDbfsSteth);
if meta.peakDbfsSteth > -1, warning('Phone recording near clipping.'); end

if pcg
    analyze_pcg(runDir);
else
    analyze_measurement(runDir);
    make_figures(runDir);
end
end
