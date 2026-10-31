function runDir = run_measurement(label, mode, stimType, toneDbfs)
%RUN_MEASUREMENT  Play a stimulus on the speaker and record the stethoscope
%   (and the reference mic) simultaneously. Raw data go to data/<timestamp>_<label>/.
%
%   STIMTYPE 'tones' (default): stepped pure tones (generate_test_signal), analysed by
%                     analyze_measurement + make_figures.
%   STIMTYPE 'pcg'  : heart-sound clips (generate_pcg_stimulus), analysed by analyze_pcg.
%   STIMTYPE 'sweep': exponential sine sweeps (generate_sweep), analysed by analyze_sweep.
%
%   MODE 'pc' (default): MATLAB plays the stimulus on the configured speaker.
%   MODE 'external'    : only records; start stimulus/stimulus.wav on another player
%                        (e.g. a phone paired with the JBL) during the countdown.
%                        Alignment uses the sync chirps, so no timing is assumed.
%
%   Before running:
%     * Windows Sound settings: Teensy input level 100 %, "Ses geliştirmeleri" off,
%       same for the C615; JBL volume fixed (do not touch it between runs).
%     * Stethoscope diaphragm taped against the JBL grille; reference mic ~2 cm
%       from the same spot. Keep the room quiet.
%
%   TONEDBFS (optional, tones only): digital peak level of the tones in dBFS, overriding cfg.stim.amp
%                     (default -18 dBFS); stored in the run's config snapshot. Used for the THD-vs-level
%                     test (advisor's review, R9): see olcum_protokolu_R9_R10.md.
%
%   Example:  run_measurement('diyafram_run1')
%             run_measurement('thd_m24dB', 'pc', 'tones', -24)

if nargin < 1, label = 'run'; end
if nargin < 2, mode = 'pc'; end
if nargin < 3, stimType = 'tones'; end
if nargin < 4, toneDbfs = []; end
external = strcmpi(mode, 'external');
pcg = strcmpi(stimType, 'pcg');
sweep = strcmpi(stimType, 'sweep');
cfg = config();
if ~isempty(toneDbfs)
    cfg.stim.amp = 10^(toneDbfs/20);
    fprintf('Tone level overridden: %.1f dBFS (amp %.4f)\n', toneDbfs, cfg.stim.amp);
end
if pcg
    [y, layout] = generate_pcg_stimulus(cfg);
elseif sweep
    [y, layout] = generate_sweep(cfg);
else
    [y, layout] = generate_test_signal(cfg);
end
preRoll = 1.0;
if external, preRoll = cfg.rec.externalStartWindow; end

[idSteth, nmSteth] = find_device_id(cfg.dev.stethoscope, 'input');
if external
    nmSpk = 'external player';
else
    [idSpk, nmSpk] = find_device_id(cfg.dev.speaker, 'output');
end
useRef = ~isempty(cfg.dev.reference);
if useRef, [idRef, nmRef] = find_device_id(cfg.dev.reference, 'input'); end

fprintf('Speaker    : %s\nStethoscope: %s\n', nmSpk, nmSteth);
if useRef, fprintf('Reference  : %s\n', nmRef); end

recS = audiorecorder(cfg.rec.fsSteth, cfg.rec.nBits, cfg.rec.chSteth, idSteth);
if useRef, recR = audiorecorder(cfg.rec.fsRef, cfg.rec.nBits, cfg.rec.chRef, idRef); end
if ~external, player = audioplayer(y, cfg.stim.fs, 24, idSpk); end

slack = 8 * external;                   % extra time for a late press on the phone
fprintf('Recording ~%.0f s ... keep quiet.\n', preRoll + layout.duration + cfg.rec.tailMargin + slack);
record(recS);
if useRef, record(recR); end
t0 = datetime('now');
if external
    fprintf('>>> START stimulus.wav ON THE PHONE NOW (within %.0f s) <<<\n', preRoll - 2);
    for k = round(preRoll):-1:1, fprintf('%d ', k); pause(1); end
    fprintf('\nplaying ... wait %.0f s\n', layout.duration + cfg.rec.tailMargin + slack);
    wait_with_progress([], layout.duration + cfg.rec.tailMargin + slack, 'recording');
else
    pause(preRoll);
    play(player);                       % not playblocking: the GUI log and stop button stay responsive
    wait_with_progress(@() isplaying(player), layout.duration, 'playing');
    pause(cfg.rec.tailMargin);
end
stop(recS);
if useRef, stop(recR); end

xS = getaudiodata(recS, 'double');
if useRef, xR = getaudiodata(recR, 'double'); end

runDir = fullfile(cfg.paths.data, [char(datetime('now','Format','yyyyMMdd_HHmmss')) '_' label]);
mkdir(runDir);
audiowrite(fullfile(runDir, 'stethoscope.wav'), xS, cfg.rec.fsSteth);
if useRef, audiowrite(fullfile(runDir, 'reference.wav'), xR, cfg.rec.fsRef); end

meta.label = label;  meta.startTime = t0;  meta.mode = mode;  meta.preRoll = preRoll;
meta.stimType = stimType;
meta.devices.stethoscope = nmSteth;  meta.devices.speaker = nmSpk;
if useRef, meta.devices.reference = nmRef; end
meta.peakDbfsSteth = 20*log10(max(abs(xS(:))));
if useRef, meta.peakDbfsRef = 20*log10(max(abs(xR(:)))); end
save(fullfile(runDir, 'meta.mat'), 'cfg', 'layout', 'meta');

fprintf('Saved -> %s\n', runDir);
fprintf('Peak level: stethoscope %.1f dBFS', meta.peakDbfsSteth);
if useRef, fprintf(', reference %.1f dBFS', meta.peakDbfsRef); end
fprintf('\n');
if meta.peakDbfsSteth > -1, warning('Stethoscope near clipping: lower the JBL volume.'); end
if meta.peakDbfsSteth < -40, warning('Stethoscope signal very low: check taping / volume.'); end

% analyse immediately and store Turkish + English figures inside the run folder
if pcg
    analyze_pcg(runDir);
elseif sweep
    analyze_sweep(runDir);
else
    analyze_measurement(runDir);
    make_figures(runDir);
end
end
