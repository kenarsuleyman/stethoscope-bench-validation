function src = pcg_source_names(orig)
%PCG_SOURCE_NAMES  Dataset display name from the original file names in filename_map.csv.
%   "05_circor_normal_..." -> "CirCor"; "other" files are PASCAL Dataset-B (normal__/murmur__ names).
tok = regexp(cellstr(orig), '^\d+_([^_]+)', 'tokens', 'once');
key = string(cellfun(@(t) t{1}, tok, 'UniformOutput', false));
names = dictionary(["buet" "circor" "other" "pascal" "physionet" "yaseen" "heart-sounds-public"], ...
                   ["BUET" "CirCor" "PASCAL-B" "PASCAL-B" "PhysioNet" "Yaseen" "Public"]);
src = names(key);
end
