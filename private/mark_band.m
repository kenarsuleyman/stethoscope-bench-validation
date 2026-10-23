function h = mark_band(ax, cfg, showNyq)
%MARK_BAND  Shade the model band (25-900 Hz) and optionally the 4009 Hz stream Nyquist line.
if nargin < 3, showNyq = cfg.thesis.showDecimationMarks; end
yl = ylim(ax);
h = patch(ax, cfg.thesis.band([1 2 2 1]), yl([1 1 2 2]), [0.85 0.90 1.0], ...
    'EdgeColor', 'none', 'FaceAlpha', 0.5, 'DisplayName', lbl('band', cfg));
uistack(h, 'bottom');
if showNyq && cfg.thesis.fsDec/2 < max(xlim(ax))
    xline(ax, cfg.thesis.fsDec/2, ':', 'Color', [0.4 0.4 0.4], 'LineWidth', 1, ...
        'DisplayName', lbl('nyq', cfg));
end
ylim(ax, yl);
end
