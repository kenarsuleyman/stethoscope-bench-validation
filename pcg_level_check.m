function T = pcg_level_check(levels)
%PCG_LEVEL_CHECK  Play a few PCG clips at several peak levels and check linearity.
%   Each clip (cfg.pcg.levelCheckClips) is played at every level in cfg.pcg.levelCheckLevels.
%   PCG_LEVEL_CHECK(LEVELS) overrides the levels (dBFS peak).
%   In the model band (25-900 Hz) the stethoscope response at each level is fitted to the
%   response at the highest level (best SNR): the least-squares gain should equal the level
%   difference. bandSnrDb is the model-band signal-to-noise ratio against the silent gap.
%   Pick cfg.pcg.peakDbfs as the highest level that stays linear (gain error well below
%   0.5 dB) and keeps the stethoscope peak below about -6 dBFS.

cfg = config();
map = readtable(fullfile(cfg.pcg.dir, 'filename_map.csv'), 'Delimiter', ',', ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
if nargin < 1, levels = cfg.pcg.levelCheckLevels; end
idx = cfg.pcg.levelCheckClips;  L = sort(levels);
fs = cfg.stim.fs;  chp = make_chirp(fs, cfg);

parts = {zeros(fs,1), chp, zeros(fs,1)};
t = numel(chp)/fs + 1;                       % seconds after chirp onset
seg = zeros(0, 4);                           % [clip level start dur]
for i = idx
    [~, ~, x48] = condition_pcg_clip(fullfile(cfg.pcg.dir, map{i,1}), cfg);
    for l = L
        parts{end+1} = 10^(l/20) * x48;      %#ok<AGROW>
        seg(end+1,:) = [i l t numel(x48)/fs];%#ok<AGROW>
        t = t + numel(x48)/fs;
        parts{end+1} = zeros(fs,1);  t = t + 1;  %#ok<AGROW>
    end
end
y = vertcat(parts{:}, zeros(fs,1));

idSpk   = find_device_id(cfg.dev.speaker, 'output');
idSteth = find_device_id(cfg.dev.stethoscope, 'input');
rec = audiorecorder(cfg.rec.fsSteth, cfg.rec.nBits, cfg.rec.chSteth, idSteth);
fprintf('PCG level check: %d clips x %d levels, %.0f s ... keep quiet.\n', numel(idx), numel(L), numel(y)/fs + 1.5);
record(rec);  pause(0.5);
playblocking(audioplayer(y, fs, 24, idSpk));
pause(1);  stop(rec);
x = getaudiodata(rec, 'double');  x = x(:, cfg.rec.stethChannel);
fsR = cfg.rec.fsSteth;
audiowrite(fullfile(tempdir, 'pcg_level_check.wav'), x, fsR);

onset = find_chirp(x, fsR, cfg, [1 round(5*fsR)]);
[z, p, k] = butter(4, [25 900]/(fsR/2), 'bandpass');  [sos, g] = zp2sos(z, p, k);
xb = filtfilt(sos, g, x);
gapIdx = onset + round((numel(chp)/fs + [0.2 0.8])*fsR);       % 1 s gap after the chirp
noiseRms = rms(xb(gapIdx(1):gapIdx(2)));

T = table('Size', [size(seg,1) 8], 'VariableTypes', [{'string'}, repmat({'double'},1,7)], ...
    'VariableNames', {'clip','levelDbfs','peakDbfs','bandSnrDb','gainDb','expectedDb','residualDb','clipping'});
for r = 1:size(seg,1)
    i1 = onset + round(seg(r,3)*fsR);  i2 = i1 + round(seg(r,4)*fsR) - 1;
    seg_r = xb(i1:i2);
    ref = xb(onset + round(seg(find(seg(:,1)==seg(r,1),1,'last'),3)*fsR) + (0:numel(seg_r)-1));   % highest level
    gl = (ref'*seg_r) / (ref'*ref);
    T(r,:) = {map{seg(r,1),1}, seg(r,2), 20*log10(max(abs(x(i1:i2)))), ...
        20*log10(rms(seg_r)/noiseRms), 20*log10(gl), seg(r,2) - L(end), ...
        20*log10(norm(seg_r - gl*ref)/norm(seg_r)), double(max(abs(x(i1:i2))) > 0.99)};
end
disp(T);
fprintf(['Linear chain: gainDb = expectedDb (fit against the highest level, whose residual is 0 by\n' ...
         'definition; lower levels are dominated by their own noise). Raw recording: %s\n'], ...
         fullfile(tempdir, 'pcg_level_check.wav'));
end
