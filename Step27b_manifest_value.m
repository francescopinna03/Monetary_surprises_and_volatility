function value = Step27b_manifest_value(M, fieldName)
%STEP27B_MANIFEST_VALUE Read one key/value field across MATLAB import modes.
%
% Some MATLAB releases can promote a textual first column named "name" to
% table row names.  The Step-27B gate must accept that representation without
% weakening its requirement that every requested manifest field occur once.

    fieldName = string(fieldName);
    if ~isscalar(fieldName) || ismissing(fieldName) || strlength(fieldName) == 0
        error('STEP27B_MANIFEST_FIELD_NAME: a nonempty scalar field is required.');
    end

    variableNames = strtrim(string(M.Properties.VariableNames));
    keyColumn = find(strcmpi(variableNames, "name"), 1);
    valueColumn = find(strcmpi(variableNames, "value"), 1);
    rowNames = string(M.Properties.RowNames);

    if ~isempty(keyColumn) && ~isempty(valueColumn)
        keys = string(M{:, keyColumn});
        values = string(M{:, valueColumn});
    elseif isempty(keyColumn) && ~isempty(valueColumn) && ...
            numel(rowNames) == height(M)
        keys = rowNames(:);
        values = string(M{:, valueColumn});
    elseif width(M) == 2
        keys = string(M{:, 1});
        values = string(M{:, 2});
    else
        error('STEP27B_MANIFEST_SCHEMA: expected a two-column name/value manifest.');
    end

    keys = strtrim(keys(:));
    values = strtrim(values(:));
    row = keys == fieldName;
    if sum(row) ~= 1
        error('STEP27B_MANIFEST_FIELD: expected one field named %s.', fieldName);
    end
    value = values(row);
    if ismissing(value)
        error('STEP27B_MANIFEST_VALUE: field %s has a missing value.', fieldName);
    end
end
