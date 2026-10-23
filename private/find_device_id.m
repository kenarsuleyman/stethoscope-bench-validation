function [id, name] = find_device_id(pattern, direction)
%FIND_DEVICE_ID  audiodevinfo ID of the first device whose name contains PATTERN.
%   DIRECTION is 'input' or 'output'.
d = audiodevinfo;
list = d.(direction);
hit = find(contains({list.Name}, pattern, 'IgnoreCase', true), 1);
if isempty(hit)
    error('No %s device matching "%s". Available:\n%s', direction, pattern, ...
        strjoin(strcat({'  '}, {list.Name}), newline));
end
id = list(hit).ID;
name = list(hit).Name;
end
