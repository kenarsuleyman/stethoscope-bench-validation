function d = tone_response_dir()
%TONE_RESPONSE_DIR  Folder of the pure-tone response used as the chain response (tr/ozet_tablo.csv inside it):
%   the newest figures/birlesik_* (combined final runs), or the folder chosen in stetoskop_gui. '' if there is none.
d = gui_ctx('toneResp', '');
if isempty(d)
    s = dir(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'figures', 'birlesik_*'));
    if ~isempty(s), d = fullfile(s(end).folder, s(end).name); end
end
end
