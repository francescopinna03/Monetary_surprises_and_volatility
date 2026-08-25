function [T, metadata] = Read_ea_policy_window(filePath, phase)

    [phaseCode, legacySheet] = phase_definition(phase);
    sheets = string(sheetnames(filePath));
    normalSheets = normalise_names(sheets);
    unifiedIndex = find(normalSheets == "ea_empd", 1);

    if ~isempty(unifiedIndex)
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
    else
        legacyIndex = find(normalSheets == normalise_names(legacySheet), 1);
        if isempty(legacyIndex)
            error('EA_POLICY_WINDOW_MISSING: %s was not found in %s.', ...
                legacySheet, filePath);
        end
        sourceSheet = sheets(legacyIndex);
        T = readtable(filePath, 'Sheet', sourceSheet, 'TextType', 'string', ...
            'VariableNamingRule', 'preserve');
        names = string(T.Properties.VariableNames);
        normal = normalise_names(names);
        dateName = find_name(names, normal, ...
            ["event_date", "date", "meeting_date"], true);
        T.event_date = Parse_date_flexible(T.(dateName));
        T.dataset_name = repmat("EA-MPD", height(T), 1);
        T.dataset_window = repmat(phaseCode, height(T), 1);
        T.window_timing_valid = true(height(T), 1);
        metadata.dataset_name = "EA-MPD";
        metadata.source_sheet = sourceSheet;
        metadata.source_window = legacySheet;
    end

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

function [phaseCode, legacySheet] = phase_definition(phase)
    value = upper(strtrim(string(phase)));
    if ismember(value, ["PR", "GC_PR", "PRESS RELEASE WINDOW"])
        phaseCode = "GC_PR";
        legacySheet = "Press Release Window";
    elseif ismember(value, ["PC", "GC_PC", "PRESS CONFERENCE WINDOW"])
        phaseCode = "GC_PC";
        legacySheet = "Press Conference Window";
    elseif ismember(value, ["ME", "GC_ME", "MONETARY EVENT WINDOW"])
        phaseCode = "GC_ME";
        legacySheet = "Monetary Event Window";
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
