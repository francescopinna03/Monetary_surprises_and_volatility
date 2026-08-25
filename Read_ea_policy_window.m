function [T, metadata] = Read_ea_policy_window(filePath, phase)

    phaseCode = phase_definition(phase);
    sheets = string(sheetnames(filePath));
    normalSheets = normalise_names(sheets);
    unifiedIndex = find(normalSheets == "ea_empd", 1);

    if isempty(unifiedIndex)
        error('EA_EMPD_SHEET_MISSING: EA-EMPD was not found in %s.', filePath);
    end

    sourceSheet = sheets(unifiedIndex);
    T = readtable(filePath, 'Sheet', sourceSheet, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    names = string(T.Properties.VariableNames);
    normal = normalise_names(names);
    eventTypeName = find_name(names, normal, ["event_type", "eventtype"], true);
    dateName = find_name(names, normal, ["date_time", "datetime", "date"], true);
    eventTypes = upper(strtrim(string(T.(eventTypeName))));
    T = T(eventTypes == phaseCode, :);
    T.event_date = Parse_date_flexible(T.(dateName));
    T.dataset_name = repmat("EA-EMPD", height(T), 1);
    T.dataset_window = repmat(phaseCode, height(T), 1);
    invalidDates = datetime([2001, 2008], [9, 10], [17, 8])';
    T.window_timing_valid = ~ismember(T.event_date, invalidDates);
    metadata.dataset_name = "EA-EMPD";
    metadata.source_sheet = sourceSheet;
    metadata.source_window = phaseCode;

    T = T(~isnat(T.event_date), :);
    T = sortrows(T, 'event_date');
    [dates, ~, groups] = unique(T.event_date);
    counts = accumarray(groups, 1);
    if any(counts > 1)
        duplicates = dates(counts > 1);
        error('EA_POLICY_WINDOW_DUPLICATES: %s contains %s.', phaseCode, ...
            strjoin(string(duplicates, 'yyyy-MM-dd'), ', '));
    end
end

function phaseCode = phase_definition(phase)
    value = upper(strtrim(string(phase)));
    if ismember(value, ["PR", "GC_PR"])
        phaseCode = "GC_PR";
    elseif ismember(value, ["PC", "GC_PC"])
        phaseCode = "GC_PC";
    elseif ismember(value, ["ME", "GC_ME"])
        phaseCode = "GC_ME";
    else
        error('EA_POLICY_WINDOW_PHASE: unsupported phase %s.', value);
    end
end

function name = find_name(names, normal, candidates, required)
    name = "";
    for candidate = candidates
        hit = find(normal == candidate, 1);
        if ~isempty(hit)
            name = names(hit);
            return;
        end
    end
    if required
        error('EA_POLICY_WINDOW_COLUMNS: missing one of %s.', ...
            strjoin(candidates, ', '));
    end
end

function normal = normalise_names(names)
    normal = lower(strtrim(string(names)));
    normal = regexprep(normal, '[^a-z0-9]+', '_');
    normal = regexprep(normal, '_+', '_');
    normal = regexprep(normal, '^_|_$', '');
end
