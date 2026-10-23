function save_figure(fig, name, cfg)
%SAVE_FIGURE  Vector PDF + 300 dpi PNG into the figures folder.
if ~exist(cfg.paths.figures, 'dir'), mkdir(cfg.paths.figures); end
base = fullfile(cfg.paths.figures, name);
exportgraphics(fig, [base '.pdf'], 'ContentType', 'vector', 'BackgroundColor', 'white');
exportgraphics(fig, [base '.png'], 'Resolution', cfg.fig.dpi, 'BackgroundColor', 'white');
close(fig);
fprintf('  figure -> %s.{pdf,png}\n', base);
end
