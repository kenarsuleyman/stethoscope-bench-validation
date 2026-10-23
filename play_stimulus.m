function play_stimulus(stimType, toneDbfs, countdownS)
%PLAY_STIMULUS  Play the tone or heart-sound sequence on the configured speaker without recording.
%   Used when the stethoscope is plugged into the smartphone (advisor's review R6): the phone records
%   with the app's test mode, the PC only plays. Nothing is saved here; the phone WAV is imported
%   afterwards with import_phone_recording, which finds the sync chirps in the recording itself.
%
%   STIMTYPE  'tones' (default, 134 s) or 'pcg' (47 heart-sound segments, 315 s)
%   TONEDBFS  optional tone level override (as in run_measurement), [] = default -18 dBFS
%   COUNTDOWNS seconds to wait before playback (default 5): start the phone recording in this time
%
%   play_stimulus('pcg')      % phone: "Test kaydını başlat" during the countdown
if nargin < 1 || isempty(stimType), stimType = 'tones'; end
if nargin < 2, toneDbfs = []; end
if nargin < 3, countdownS = 5; end
cfg = config();
if ~isempty(toneDbfs), cfg.stim.amp = 10^(toneDbfs/20); end
if strcmpi(stimType, 'pcg')
    [y, layout] = generate_pcg_stimulus(cfg);
else
    [y, layout] = generate_test_signal(cfg);
end
[idSpk, nmSpk] = find_device_id(cfg.dev.speaker, 'output');
player = audioplayer(y, cfg.stim.fs, 24, idSpk);
fprintf('Speaker: %s\nStimulus: %s, %.1f s\n', nmSpk, stimType, layout.duration);
fprintf('>>> Start the test recording on the phone now <<<\n');
for k = countdownS:-1:1, fprintf('%d ', k); pause(1); end
fprintf('\nplaying (%s) ... keep quiet\n', char(datetime('now', 'Format', 'HH:mm:ss')));
playblocking(player);
fprintf('done (%s): press "Durdur ve kaydet" on the phone\n', char(datetime('now', 'Format', 'HH:mm:ss')));
end
