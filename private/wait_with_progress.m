function wait_with_progress(busy, totalS, what)
%WAIT_WITH_PROGRESS  Wait while BUSY() is true (or for TOTALS seconds if BUSY is empty), printing the elapsed time
%   every 15 s. Used instead of playblocking/recordblocking so that stetoskop_gui keeps updating its log and can
%   stop the task (error 'stetoskop:stopped'; the audio objects stop when the calling function exits).
t0 = tic;  next = 15;
while true
    el = toc(t0);
    if isempty(busy)
        if el >= totalS, break; end
    elseif ~busy()
        break;
    end
    if gui_ctx('stop', false)
        error('stetoskop:stopped', 'Stopped by the user (%s, %.0f s).', what, el);
    end
    if el >= next
        fprintf('  %s: %.0f / %.0f s\n', what, el, totalS);
        next = next + 15;
    end
    pause(0.1);
end
end
