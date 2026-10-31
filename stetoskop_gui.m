function stetoskop_gui()
%STETOSKOP_GUI  One window for the bench-test scripts: measurements, analyses, figures, model comparison.
%   Every tool (private/gui_tools.m) has its own tab with its parameters. Each run gets its own folder
%   cikti/<tool>/<yyyyMMdd_HHmmss>[_label]/ with log.txt (the full log), komut.txt (the command and the
%   parameters) and the outputs of the tool. Measurements keep writing their raw data to
%   data/<timestamp>_<label>/ as before; the log is copied there as gui_log.txt.
%   MATLAB tools run in this MATLAB session (the log follows the command window through a diary file),
%   Python tools (pcg_test/*.py) in a separate process with the Python set at the top of the window.
%   Called from the command line, every script keeps its documented output paths (see private/gui_ctx.m).
%
%   stetoskop_gui

root = fileparts(mfilename('fullpath'));
cd(root);
tools = gui_tools();
cats = unique({tools.cat}, 'stable');

busy = false;  reading = false;  cur = [];  proc = [];  prevDiary = [];  stopReq = false;
logFile = '';  logPos = 0;  pyFile = '';  pyPos = 0;  lastOut = '';
runCache = scan_runs();
W = struct();
runButtons = gobjects(0);

% ------------------------------------------------------------------ window
fig = uifigure('Name', 'Stetoskop test arayüzü', 'Position', [60 40 1280 880], 'CloseRequestFcn', @onClose);
main = uigridlayout(fig, [3 1], 'RowHeight', {26, '1.6x', '1x'}, 'Padding', [8 8 8 8], 'RowSpacing', 6);

cfg = config();
top = uigridlayout(main, [1 7], 'ColumnWidth', {'fit', '1x', 'fit', 380, 'fit', 'fit', 'fit'}, ...
    'Padding', 0, 'ColumnSpacing', 8);
uilabel(top, 'Text', 'config.m:', 'FontWeight', 'bold');
uilabel(top, 'Text', sprintf('stetoskop "%s" · hoparlör "%s" · kayıt %d Hz', cfg.dev.stethoscope, ...
    cfg.dev.speaker, cfg.rec.fsSteth));
uilabel(top, 'Text', 'Python:');
pyField = uieditfield(top, 'text', 'Value', default_python(), 'Tooltip', 'Python araçlarının yorumlayıcısı', ...
    'ValueChangedFcn', @(s, ~) setpref('stetoskop_gui', 'python', s.Value));
uibutton(top, 'Text', 'Koşuları yenile', 'ButtonPushedFcn', @(~, ~) refreshRuns());
uibutton(top, 'Text', 'config.m', 'ButtonPushedFcn', @(~, ~) edit(fullfile(root, 'config.m')));
uibutton(top, 'Text', 'Proje klasörü', 'ButtonPushedFcn', @(~, ~) winopen(root));

tg = uitabgroup(main);
for c = cats
    ct = uitab(tg, 'Title', c{1});
    sub = uitabgroup(uigridlayout(ct, [1 1], 'Padding', 0));
    for t = tools(strcmp({tools.cat}, c{1}))
        buildTool(sub, t);
    end
end

lp = uipanel(main, 'Title', 'Log');
lg = uigridlayout(lp, [2 1], 'RowHeight', {'1x', 26}, 'Padding', 4, 'RowSpacing', 4);
logArea = uitextarea(lg, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11, 'Value', {''});
bar = uigridlayout(lg, [1 4], 'ColumnWidth', {'1x', 'fit', 'fit', 'fit'}, 'Padding', 0);
status = uilabel(bar, 'Text', 'Hazır.', 'FontWeight', 'bold');
stopBtn = uibutton(bar, 'Text', '■  Durdur', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) onStop());
uibutton(bar, 'Text', 'Son çıktı klasörünü aç', 'ButtonPushedFcn', @(~, ~) openDir(lastOut));
uibutton(bar, 'Text', 'Logu temizle', 'ButtonPushedFcn', @(~, ~) set(logArea, 'Value', {''}));

appendLog(sprintf(['Arayüz hazır (%s). Proje: %s\n' ...
    'MATLAB araçları bu oturumda, Python araçları ayrı bir süreçte çalışır. Her çalıştırma ' ...
    'cikti/<araç>/<tarih_saat>/ klasörüne log.txt ve komut.txt yazar.\n'], ...
    char(datetime('now', 'Format', 'dd.MM.yyyy HH:mm')), root));

tmr = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.3, 'BusyMode', 'drop', ...
    'Name', 'stetoskop_gui', 'TimerFcn', @(~, ~) poll());
start(tmr);

% ================================================================== tool tabs
    function buildTool(sub, t)
        tab = uitab(sub, 'Title', t.title);
        g = uigridlayout(tab, [1 2], 'ColumnWidth', {'1.25x', '1x'}, 'Padding', 8, 'ColumnSpacing', 10);
        pp = uipanel(g, 'Title', 'Parametreler');
        np = numel(t.params);
        hts = arrayfun(@(q) row_height(q.type), t.params, 'UniformOutput', false);
        if np == 0, hts = {24}; end
        pg = uigridlayout(pp, [max(np, 1) 3], 'ColumnWidth', {200, '1x', 'fit'}, 'RowHeight', hts, ...
            'Scrollable', 'on', 'RowSpacing', 8);
        w = struct('get', struct(), 'refresh', {{}}, 'out', [], 'last', '');
        if np == 0, uilabel(pg, 'Text', 'Bu aracın parametresi yok.'); end
        for k = 1:np
            q = t.params(k);
            lab = uilabel(pg, 'Text', q.label, 'WordWrap', 'on', 'Tooltip', q.tip);
            lab.Layout.Row = k;  lab.Layout.Column = 1;
            [getter, ref] = makeWidget(pg, k, q);
            w.get.(q.name) = getter;
            if ~isempty(ref), w.refresh{end+1} = ref; end
        end

        rp = uipanel(g, 'Title', t.fn);
        rg = uigridlayout(rp, [4 1], 'RowHeight', {'1x', 20, 26, 40}, 'RowSpacing', 6);
        uitextarea(rg, 'Value', help_lines(t), 'Editable', 'off');
        uilabel(rg, 'Text', 'Çıktı klasörü (proje köküne göre; içinde tarih_saat klasörü açılır):');
        og = uigridlayout(rg, [1 2], 'ColumnWidth', {'1x', 'fit'}, 'Padding', 0);
        w.out = uieditfield(og, 'text', 'Value', ['cikti/' t.key]);
        uibutton(og, 'Text', 'Son çıktıyı aç', 'ButtonPushedFcn', @(~, ~) openToolOut(t.key));
        b = uibutton(rg, 'Text', '▶  Çalıştır', 'FontWeight', 'bold', 'FontSize', 14, ...
            'ButtonPushedFcn', @(~, ~) runTool(t));
        runButtons(end+1) = b;
        W.(t.key) = w;
    end

    function [getter, ref] = makeWidget(pg, row, q)
        ref = [];
        switch q.type
            case 'text'
                h = place(uieditfield(pg, 'text', 'Value', q.default, 'Tooltip', q.tip), row);
                getter = @() strtrim(h.Value);
            case {'num', 'vec'}
                h = place(uieditfield(pg, 'text', 'Value', num_text(q.default), 'Tooltip', q.tip), row);
                getter = @() parse_num(h.Value, q);
            case 'choice'
                h = place(uidropdown(pg, 'Items', q.items{2}, 'ItemsData', q.items{1}, 'Value', q.default, ...
                    'Tooltip', q.tip), row);
                getter = @() h.Value;
            case 'check'
                h = place(uicheckbox(pg, 'Text', '', 'Value', q.default, 'Tooltip', q.tip), row);
                getter = @() h.Value;
            case 'multi'
                h = place(uilistbox(pg, 'Multiselect', 'on', 'Items', q.items{2}, 'ItemsData', q.items{1}, ...
                    'Value', q.default, 'Tooltip', 'Ctrl ile birden çok seçin'), row);
                getter = @() h.Value;
            case 'run'
                h = place(uidropdown(pg, 'Items', {'—'}, 'ItemsData', {''}, 'Tooltip', q.tip), row);
                fillRunDropdown(h, q, prefixed(q.default));
                ref = @() fillRunDropdown(h, q, h.Value);
                getter = @() h.Value;
            case 'runs'
                sg = place(uigridlayout(pg, [2 3], 'RowHeight', {22, '1x'}, 'ColumnWidth', {'1x', 'fit', 'fit'}, ...
                    'Padding', 0, 'RowSpacing', 2, 'ColumnSpacing', 6), row);
                flt = uieditfield(sg, 'text', 'Placeholder', 'süz (örneğin sweep_final)');
                cnt = uilabel(sg, 'Text', '');
                b = uibutton(sg, 'Text', 'Temizle');
                h = uilistbox(sg, 'Multiselect', 'on', 'Items', {}, ...
                    'Tooltip', 'Ctrl / Shift ile birden çok koşu seçin; seçilenler üstte, koşular tarih sırasıyla verilir');
                h.Layout.Row = 2;  h.Layout.Column = [1 3];
                h.ValueChangedFcn = @(~, ~) set(cnt, 'Text', sprintf('%d seçili', numel(cellstr(h.Value))));
                b.ButtonPushedFcn = @(~, ~) fillRunList(h, flt.Value, q, {}, cnt);
                flt.ValueChangingFcn = @(~, e) fillRunList(h, e.Value, q, h.Value, cnt);
                fillRunList(h, '', q, prefixed(q.default), cnt);
                ref = @() fillRunList(h, flt.Value, q, h.Value, cnt);
                getter = @() sort(cellstr(h.Value));
            case {'file', 'dir'}
                h = place(uieditfield(pg, 'text', 'Value', q.default, 'Tooltip', q.tip), row);
                b = uibutton(pg, 'Text', 'Seç…', 'ButtonPushedFcn', @(~, ~) pickPath(h, q));
                b.Layout.Row = row;  b.Layout.Column = 3;
                getter = @() strtrim(h.Value);
            case 'toneresp'
                h = place(uidropdown(pg, 'Items', {'—'}, 'ItemsData', {''}, 'Tooltip', q.tip), row);
                fillToneResp(h, '');
                ref = @() fillToneResp(h, h.Value);
                getter = @() h.Value;
            otherwise
                error('unknown parameter type %s', q.type);
        end
    end

    function fillRunDropdown(h, q, keep)
        if iscell(keep) && isempty(keep), keep = ''; elseif iscell(keep), keep = keep{1}; end
        [data, labels] = run_items(q, '', {});
        first = '(koşu seçin)';  if q.optional, first = '(yok)'; end
        set(h, 'Items', [{first}, labels], 'ItemsData', [{''}, data]);
        if any(strcmp(data, keep)), h.Value = keep; else, h.Value = ''; end
    end

    function fillRunList(h, filt, q, keep, cnt)
        keep = cellstr(keep);
        [data, labels] = run_items(q, filt, keep);
        sel = ismember(data, keep);
        o = [find(sel), find(~sel)];                         % selected runs on top
        set(h, 'Items', labels(o), 'ItemsData', data(o));
        h.Value = data(sel);
        cnt.Text = sprintf('%d seçili', nnz(sel));
    end

    function [data, labels] = run_items(q, filt, keep)
        R = runCache;  data = {};  labels = {};
        if ~isempty(q.filter) && ~isempty(R), R = R(ismember({R.type}, q.filter)); end
        if isempty(R), return; end
        R = R(end:-1:1);                                     % newest first
        data = strcat('data/', {R.name});
        m = true(size(data));
        if ~isempty(filt), m = contains({R.name}, filt, 'IgnoreCase', true); end
        m = m | ismember(data, keep);
        data = data(m);  R = R(m);
        labels = arrayfun(@(r) sprintf('%s   [%s]', r.name, type_label(r.type)), R, 'UniformOutput', false);
    end

    function fillToneResp(h, keep)
        groups = {fullfile(root, 'figures', '*', 'tr', 'ozet_tablo.csv'), ...
                  fullfile(root, 'cikti', '**', 'tr', 'ozet_tablo.csv'), ...
                  fullfile(root, 'data', '*', 'figures', 'tr', 'ozet_tablo.csv')};
        data = {};
        for gI = 1:numel(groups)
            L = dir(groups{gI});
            d = sort(cellfun(@(f) rel(fileparts(f)), {L.folder}, 'UniformOutput', false));
            data = [data, d(end:-1:1)]; %#ok<AGROW>
        end
        if isempty(data), set(h, 'Items', {'(ton yanıtı yok)'}, 'ItemsData', {''}); return; end
        labels = data;
        def = find(startsWith(data, 'figures/birlesik_'), 1);
        if ~isempty(def), labels{def} = [data{def} '   (varsayılan: en yeni birleşik)']; end
        set(h, 'Items', labels, 'ItemsData', data);
        if any(strcmp(data, keep)), h.Value = keep;
        elseif ~isempty(def), h.Value = data{def};
        end
    end

    function pickPath(h, q)
        d0 = fullfile(root, q.startDir);  if ~isfolder(d0), d0 = root; end
        if strcmp(q.type, 'dir')
            d = uigetdir(d0, q.label);
            if ~isequal(d, 0), h.Value = rel(d); end
        else
            [f, d] = uigetfile(fullfile(d0, q.pattern), q.label);
            if ~isequal(f, 0), h.Value = rel(fullfile(d, f)); end
        end
        figure(fig);
    end

    function refreshRuns()
        runCache = scan_runs();
        for k = fieldnames(W)'
            for r = W.(k{1}).refresh, r{1}(); end
        end
    end

% ================================================================== running a tool
    function runTool(t)
        if busy
            uialert(fig, 'Başka bir görev çalışıyor; bitmesini bekleyin.', 'Meşgul');  return
        end
        cd(root);
        w = W.(t.key);
        ts = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        try
            p = collect(t, w);
            name = ts;
            if ~isempty(t.labelParam), name = [ts '_' safe_name(p.(t.labelParam))]; end
            base = strtrim(w.out.Value);  if isempty(base), base = ['cikti/' t.key]; end
            outDir = abspath(fullfile(base, name));
            k = 2;  d1 = outDir;
            while isfolder(outDir), outDir = sprintf('%s_%d', d1, k);  k = k + 1; end   % same second
            outRel = rel(outDir);
            cmdTxt = command_text(t, p, outDir, outRel);
        catch ME
            uialert(fig, ME.message, 'Parametre');  return
        end
        if ~isfolder(outDir), mkdir(outDir); end
        write_lines(fullfile(outDir, 'komut.txt'), [{sprintf('Araç: %s (%s)', t.title, t.fn), ...
            sprintf('Başlangıç: %s', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'))), ...
            sprintf('Komut: %s', cmdTxt), 'Parametreler:'}, param_lines(t, p)]);

        beginLog(outDir);
        say('▶ %s başladı', t.title);
        say('Komut: %s', cmdTxt);
        for q = t.params
            if ~isempty(q.ctx) && ~isempty(p.(q.name)), say('%s: %s', q.label, p.(q.name)); end
        end
        say('Çıktı klasörü: %s', outRel);
        if strcmp(t.out, 'data')
            say('Veri ve sonuçlar betiğin kendi klasörüne (data/…) yazılır; buradaki klasör logu tutar.');
        end
        cur = struct('tool', t, 'outDir', outDir, 't0', tic, 'snap', {file_keys(outDir)});
        stopReq = false;
        setBusy(true);

        if strcmp(t.kind, 'python')
            try
                startPython(t, p, outDir, outRel);
            catch ME
                say('✖ Python başlatılamadı: %s', ME.message);
                finish('error');
            end
            return
        end

        setappdata(groot, 'stethGuiCtx', make_ctx(t, p, outDir));
        state = 'ok';
        try
            if ~isempty(t.run)
                t.run(p, outDir);
            else
                a = t.args(p, outDir);
                feval(t.fn, a{:});
            end
        catch ME
            if strcmp(ME.identifier, 'stetoskop:stopped')
                state = 'stopped';
                say('■ %s', ME.message);
            else
                state = 'error';
                fprintf('%s\n', ME.getReport('extended', 'hyperlinks', 'off'));
            end
        end
        if isappdata(groot, 'stethGuiCtx'), rmappdata(groot, 'stethGuiCtx'); end
        finish(state);
    end

    function startPython(t, p, outDir, outRel)
        if ~isempty(t.prepare), t.prepare(p, outDir); end
        cl = python_command(t, p, outRel);
        pyFile = fullfile(outDir, 'python_cikti.txt');  pyPos = 0;
        full = sprintf('set PYTHONIOENCODING=utf-8&& set PYTHONUTF8=1&& %s > %s 2>&1', cl, ...
            qarg(strrep(rel(pyFile), '/', '\')));
        psi = System.Diagnostics.ProcessStartInfo('cmd.exe', ['/s /c "' full '"']);
        psi.UseShellExecute = false;  psi.CreateNoWindow = true;  psi.WorkingDirectory = root;
        proc = System.Diagnostics.Process.Start(psi);
        say('Python süreci başladı (PID %d).', proc.Id);
    end

    function cl = python_command(t, p, outRel)
        py = strtrim(pyField.Value);
        a = t.args(p, outRel);
        cl = strjoin([{qarg(py), '-u', qarg(strrep(t.script, '/', '\'))}, cellfun(@qarg, a, 'UniformOutput', false)], ' ');
    end

    function s = command_text(t, p, outDir, outRel)
        if strcmp(t.kind, 'python')
            s = python_command(t, p, outRel);
        elseif ~isempty(t.cmd)
            s = t.cmd(p, outRel);
        else
            a = t.args(p, outDir);
            s = sprintf('%s(%s)', t.fn, strjoin(cellfun(@(x) mlit(x, outDir, outRel), a, 'UniformOutput', false), ', '));
        end
    end

    function finish(state)
        % STATE: 'ok', 'stopped' (stop button) or 'error'
        tt = cur.tool;
        newRuns = report_saved();
        switch state
            case 'ok',      say('✔ %s bitti (%s).', tt.title, elapsed(toc(cur.t0)));
            case 'stopped', say('■ %s kullanıcı tarafından durduruldu (%s).', tt.title, elapsed(toc(cur.t0)));
            otherwise,      say('✖ %s hata ile bitti (%s). Ayrıntı yukarıda.', tt.title, elapsed(toc(cur.t0)));
        end
        reading = true;
        diary off
        txt = readAll();
        if ~isempty(txt), appendLog(txt); end
        reading = false;
        if tt.copyLog
            for r = newRuns, copyfile(logFile, fullfile(root, r{1}, 'gui_log.txt')); end
        end
        if prevDiary.on, diary(prevDiary.file); diary on; end
        logFile = '';
        lastOut = cur.outDir;  W.(tt.key).last = cur.outDir;
        setBusy(false);
        refreshRuns();
    end

    function newRuns = report_saved()
        % files that are new or changed since the start (snapshot comparison), grouped by folder;
        % the log/command files of this run are left out
        [keys, files] = file_keys(cur.outDir);
        files = unique(files(~ismember(keys, cur.snap)));
        files = files(~ismember(files, fullfile(cur.outDir, {'log.txt', 'komut.txt', 'python_cikti.txt'})));
        relf = cellfun(@rel, files, 'UniformOutput', false);
        newRuns = unique(regexp(relf, '^data/[^/]+', 'match', 'once'));
        newRuns = newRuns(~cellfun(@isempty, newRuns));
        if isempty(files)
            say('Yeni dosya yazılmadı.');  return
        end
        [folders, ~, ic] = unique(cellfun(@fileparts, relf, 'UniformOutput', false));
        say('Kaydedilenler (%d dosya):', numel(files));
        for k = 1:min(numel(folders), 20)
            [~, n, e] = cellfun(@fileparts, relf(ic == k), 'UniformOutput', false);
            nm = strcat(n, e);
            more = '';  if numel(nm) > 6, more = sprintf(', … (+%d)', numel(nm) - 6); nm = nm(1:6); end
            fprintf('           %s/  %s%s\n', folders{k}, strjoin(nm, ', '), more);
        end
        if numel(folders) > 20, fprintf('           … ve %d klasör daha\n', numel(folders) - 20); end
    end

% ================================================================== log
    function beginLog(outDir)
        prevDiary = struct('on', strcmp(get(0, 'Diary'), 'on'), 'file', get(0, 'DiaryFile'));
        logFile = fullfile(outDir, 'log.txt');  logPos = 0;
        diary(logFile);  diary on
    end

    function poll()
        try
            if busy && ~isempty(proc)
                [txt, pyPos] = read_new(pyFile, pyPos, false);
                if ~isempty(txt), fprintf('%s', strrep(txt, char(13), '')); end
                if proc.HasExited
                    [txt, pyPos] = read_new(pyFile, pyPos, true);
                    if ~isempty(txt), fprintf('%s\n', strrep(txt, char(13), '')); end
                    code = proc.ExitCode;  proc = [];
                    if stopReq
                        finish('stopped');
                    elseif code ~= 0
                        say('Python çıkış kodu %d.', code);
                        finish('error');
                    else
                        finish('ok');
                    end
                    return
                end
            end
            if ~reading && ~isempty(logFile)
                [txt, logPos] = read_new(logFile, logPos, false);
                if ~isempty(txt), appendLog(txt); end
            end
            if busy, status.Text = sprintf('Çalışıyor: %s · %s', cur.tool.title, elapsed(toc(cur.t0))); end
            drawnow
        catch
            % the timer must survive a bad read or a closed window
        end
    end

    function txt = readAll()
        [txt, logPos] = read_new(logFile, logPos, true);
    end

    function appendLog(txt)
        lines = strsplit(strrep(txt, char(13), ''), newline);
        if isempty(lines{end}), lines(end) = []; end
        v = logArea.Value;
        if isscalar(v) && isempty(v{1}), v = {}; end
        v = [v(:); lines(:)];
        if numel(v) > 5000, v = v(end-4999:end); end
        logArea.Value = v;
        try
            scroll(logArea, 'bottom');
        catch
        end
    end

    function setBusy(b)
        busy = b;
        set(runButtons, 'Enable', onoff(~b));
        stopBtn.Enable = onoff(b);
        if b, status.Text = sprintf('Çalışıyor: %s', cur.tool.title); else, status.Text = 'Hazır.'; end
        drawnow
    end

    function onStop()
        if ~busy, return; end
        stopReq = true;
        if ~isempty(proc)
            system(sprintf('taskkill /PID %d /T /F >NUL 2>&1', proc.Id));
            say('■ Python süreci sonlandırıldı.');
            return
        end
        cx = getappdata(groot, 'stethGuiCtx');
        if isstruct(cx), cx.stop = true;  setappdata(groot, 'stethGuiCtx', cx); end
        if cur.tool.stoppable
            say('■ Durdurma isteği gönderildi; çalma / kayıt döngüsünde durur.');
        else
            say('■ Bu MATLAB aracı ancak komut penceresinde Ctrl+C ile durdurulabilir.');
        end
    end

    function onClose(~, ~)
        if busy && isempty(proc)
            uialert(fig, 'Bir MATLAB görevi çalışıyor; bitmesini bekleyin (ya da komut penceresinde Ctrl+C).', 'Meşgul');
            return
        end
        if busy
            a = uiconfirm(fig, 'Python görevi çalışıyor. Sonlandırılıp kapatılsın mı?', 'Kapat', ...
                'Options', {'Sonlandır ve kapat', 'İptal'}, 'DefaultOption', 2);
            if strcmp(a, 'İptal'), return; end
            system(sprintf('taskkill /PID %d /T /F >NUL 2>&1', proc.Id));
            diary off
        end
        stop(tmr);  delete(tmr);
        delete(fig);
    end

    function openToolOut(key)
        d = W.(key).last;
        if isempty(d), d = abspath(strtrim(W.(key).out.Value)); end
        openDir(d);
    end

    function openDir(d)
        if isempty(d) || ~isfolder(d)
            uialert(fig, 'Henüz bu klasörde çıktı yok.', 'Klasör');  return
        end
        winopen(d);
    end

% ================================================================== helpers that need root
    function p = abspath(p)
        if ~(numel(p) > 1 && (p(2) == ':' || startsWith(p, '\\'))), p = fullfile(root, p); end
    end

    function r = rel(p)
        if startsWith(lower(p), lower([root filesep]))
            r = strrep(p(numel(root)+2:end), '\', '/');
        else
            r = p;
        end
    end

    function [keys, files] = file_keys(outDir)
        % "path|modification time" of every file in the run folder and in the folders the scripts write to
        scan = [{outDir}, fullfile(root, {'data', 'figures', 'results', 'stimulus', 'pcg_test/results', ...
            'pcg_test/figures', 'pcg_test/sim', 'pcg_test/stimulus'})];
        files = {};  stamps = [];
        for k = 1:numel(scan)
            if ~isfolder(scan{k}), continue; end
            L = dir(fullfile(scan{k}, '**', '*'));
            L = L(~[L.isdir]);
            files = [files, fullfile({L.folder}, {L.name})]; %#ok<AGROW>
            stamps = [stamps, [L.datenum]]; %#ok<AGROW>
        end
        keys = strcat(files, '|', compose('%.9f', stamps));
    end

    function R = scan_runs()
        d = dir(fullfile(root, 'data'));
        d = d([d.isdir] & ~startsWith({d.name}, '.'));
        R = struct('name', {d.name}, 'type', '');
        key = regexp({R.name}, '\d{8}_\d{6}', 'match', 'once');   % pcg_selftest_<ts> sorts by its time too
        [~, o] = sort(key);  R = R(o);
        for k = 1:numel(R)
            f = fullfile(root, 'data', R(k).name);
            if isfile(fullfile(f, 'results_pcg.mat')), R(k).type = 'pcg';
            elseif isfile(fullfile(f, 'results_sweep.mat')), R(k).type = 'sweep';
            elseif isfile(fullfile(f, 'results.mat')), R(k).type = 'tones';
            else, R(k).type = 'raw';
            end
        end
    end

    function c = make_ctx(t, p, outDir)
        c = struct('stop', false);
        if strcmp(t.out, 'dir'), c.outDir = outDir; end
        for q = t.params
            if ~isempty(q.ctx) && ~isempty(p.(q.name)), c.(q.ctx) = abspath(p.(q.name)); end
        end
    end

    function p = collect(t, w)
        p = struct();
        for q = t.params
            v = w.get.(q.name)();
            if isempty(v) && ~q.optional && ~strcmp(q.type, 'check')
                error('"%s" boş bırakılamaz.', q.label);
            end
            if strcmp(q.type, 'file') && ~isempty(v) && ~isfile(abspath(v)), error('Dosya bulunamadı: %s', v); end
            if strcmp(q.type, 'dir') && ~isempty(v) && ~isfolder(abspath(v)), error('Klasör bulunamadı: %s', v); end
            p.(q.name) = v;
        end
    end

    function s = mlit(x, outDir, outRel)
        % MATLAB literal of an argument, for the log (the output folder shown relative)
        if ischar(x) || isstring(x)
            x = char(x);  if strcmp(x, outDir), x = outRel; end
            s = ['''' strrep(x, '''', '''''') ''''];
        elseif iscell(x)
            s = ['{' strjoin(cellfun(@(y) mlit(y, outDir, outRel), x, 'UniformOutput', false), ', ') '}'];
        elseif isempty(x)
            s = '[]';
        else
            s = mat2str(x);
        end
    end
end

% ====================================================================== local functions
function say(fmt, varargin)
fprintf(['[%s] ' fmt '\n'], char(datetime('now', 'Format', 'HH:mm:ss')), varargin{:});
end

function [txt, pos] = read_new(f, pos, all)
% new complete lines (or everything, if ALL) of a growing UTF-8 file, from byte POS on
txt = '';
if isempty(f) || ~isfile(f), return; end
fid = fopen(f, 'r');
if fid < 0, return; end
fseek(fid, 0, 'eof');  n = ftell(fid);
if n > pos
    fseek(fid, pos, 'bof');
    b = fread(fid, n - pos, '*uint8')';
    if all, k = numel(b); else, k = find(b == 10, 1, 'last'); end
    if ~isempty(k) && k > 0
        txt = native2unicode(b(1:k), 'UTF-8');
        pos = pos + k;
    end
end
fclose(fid);
end

function h = place(h, row)
h.Layout.Row = row;  h.Layout.Column = 2;
end

function r = row_height(type)
switch type
    case 'runs',  r = 150;
    case 'multi', r = 100;
    otherwise,    r = 24;
end
end

function lines = help_lines(t)
switch t.kind
    case 'python', how = sprintf('Python, ayrı süreç: %s', t.script);
    otherwise,     how = 'MATLAB, bu oturumda';
end
switch t.out
    case 'dir',  where = 'Çıktılar: cikti/<araç>/<tarih_saat>/ (log.txt ve komut.txt ile birlikte).';
    case 'data', where = 'Çıktılar: data/ altındaki koşu klasörü; cikti/ klasöründe log.txt ve komut.txt.';
    otherwise,   where = 'Çıktı: yalnızca log (cikti/<araç>/<tarih_saat>/log.txt).';
end
lines = {t.help, '', ['Çalışma: ' how], where};
end

function s = type_label(type)
switch type
    case 'tones', s = 'ton';
    case 'pcg',   s = 'kalp sesi';
    case 'sweep', s = 'süpürme';
    otherwise,    s = 'analiz edilmemiş';
end
end

function c = prefixed(names)
if ischar(names), names = {names}; end
names = names(~cellfun(@isempty, names));
c = strcat('data/', names);
if isempty(c), c = {}; end
if isscalar(c), c = c{1}; end
end

function s = num_text(v)
if isempty(v), s = ''; elseif isscalar(v), s = num2str(v); else, s = mat2str(v); end
end

function v = parse_num(s, q)
s = strtrim(s);
if isempty(s), v = []; return; end
if strcmp(q.type, 'num')
    v = str2double(strrep(s, ',', '.'));
    if isnan(v), error('"%s" bir sayı olmalı (girilen: %s).', q.label, s); end
else
    v = sscanf(regexprep(s, '[\[\];,]', ' '), '%f')';
    if isempty(v), error('"%s" sayı listesi olmalı, örneğin [-18 -12 -6].', q.label); end
end
end

function lines = param_lines(t, p)
lines = {};
for q = t.params
    v = p.(q.name);
    if iscell(v), v = strjoin(v, ', '); elseif islogical(v), v = mat2str(v); elseif isnumeric(v), v = num_text(v); end
    lines{end+1} = sprintf('  %s (%s) = %s', q.name, q.label, v); %#ok<AGROW>
end
end

function write_lines(f, lines)
fid = fopen(f, 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end

function s = qarg(s)
s = char(s);
if isempty(s) || any(isspace(s)) || any(ismember(s, '&()^|<>,;=')), s = ['"' s '"']; end
end

function s = safe_name(s)
s = regexprep(strtrim(char(s)), '[^\w\-]', '_');
end

function s = onoff(b)
if b, s = 'on'; else, s = 'off'; end
end

function s = elapsed(sec)
s = sprintf('%d:%02d', floor(sec/60), floor(mod(sec, 60)));
end

function py = default_python()
py = getpref('stetoskop_gui', 'python', '');
if isempty(py) || ~(isfile(py) || strcmp(py, 'python'))
    c = fullfile(getenv('USERPROFILE'), '.venvs', 'stetoskop', 'Scripts', 'python.exe');
    if isfile(c), py = c; else, py = 'python'; end
end
end
