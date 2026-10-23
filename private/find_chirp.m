function [onset, quality] = find_chirp(x, fs, cfg, win)
%FIND_CHIRP  Matched-filter search for the sync chirp inside sample window WIN = [i1 i2].
%   ONSET is the sample index of the chirp start; QUALITY is peak / median of the
%   matched-filter envelope (values above ~20 indicate a reliable detection).
tpl = make_chirp(fs, cfg);
i1 = max(1, win(1));  i2 = min(numel(x), win(2));
seg = x(i1:i2) - mean(x(i1:i2));
mf  = abs(hilbert(fftfilt(flipud(tpl), [seg; zeros(numel(tpl),1)])));
[pk, k] = max(mf);
onset   = i1 + k - numel(tpl);
quality = pk / median(mf);
end
