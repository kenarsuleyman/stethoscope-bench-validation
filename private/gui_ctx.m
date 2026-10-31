function v = gui_ctx(key, default)
%GUI_CTX  Setting passed by stetoskop_gui to the task it is running, or DEFAULT outside the GUI.
%   Keys: 'outDir'     folder for result tables and figures (instead of results/, figures/, pcg_test/results ...)
%         'toneResp'   folder of the pure-tone response used as the chain response (holds tr/ozet_tablo.csv)
%         'bandSnrCsv' in-band SNR table read by make_figures
%         'perClipCsv' model comparison table read by make_pcg_figures
%         'stop'       true when the stop button was pressed (checked by wait_with_progress)
%   Called from the command line, every script keeps its documented paths.
c = getappdata(groot, 'stethGuiCtx');
if isstruct(c) && isfield(c, key) && ~isempty(c.(key))
    v = c.(key);
else
    v = default;
end
end
