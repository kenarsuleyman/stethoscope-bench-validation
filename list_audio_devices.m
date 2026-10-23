function list_audio_devices()
%LIST_AUDIO_DEVICES  Print audio devices and check that the configured ones are present.
cfg = config();
d = audiodevinfo;
fprintf('Inputs:\n');  for i = 1:numel(d.input),  fprintf('  [%d] %s\n', d.input(i).ID,  d.input(i).Name); end
fprintf('Outputs:\n'); for i = 1:numel(d.output), fprintf('  [%d] %s\n', d.output(i).ID, d.output(i).Name); end
checks = {cfg.dev.stethoscope, 'input'; cfg.dev.reference, 'input'; cfg.dev.speaker, 'output'};
fprintf('\n');
for k = 1:size(checks, 1)
    if isempty(checks{k,1}), continue; end
    try
        [~, nm] = find_device_id(checks{k,1}, checks{k,2});
        fprintf('OK      %-7s "%s" -> %s\n', checks{k,2}, checks{k,1}, nm);
    catch
        fprintf('MISSING %-7s "%s"\n', checks{k,2}, checks{k,1});
    end
end
end
