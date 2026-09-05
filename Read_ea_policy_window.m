function [T, metadata] = Read_ea_policy_window(filePath, phase, sourceId)
%READ_EA_POLICY_WINDOW Return one harmonised policy-event window.
%
% EA-EMPD stores all windows in the unified EA-EMPD sheet and identifies
% them by event_type. EA-MPD stores the three windows in separate sheets.
% The harmonised columns appended here keep downstream code source-agnostic.

    phaseCode = phase_definition(phase);
    sheets = string(sheetnames(filePath));
    normalSheets = normalise_names(sheets);
    if nargin < 3 || strlength(strtrim(string(sourceId))) == 0
        if any(normalSheets == "ea_empd")
            sourceId = "EA_EMPD";
        else
            sourceId = "EA_MPD";
        end
    end
    sourceId = upper(replace(strtrim(string(sourceId)), "-", "_"));

    if sourceId == "EA_EMPD"
        unifiedIndex = find(normalSheets == "ea_empd", 1);
        if isempty(unifiedIndex)
            error('EA_EMPD_SHEET_MISSING: EA-EMPD was not found in %s.', filePath);
        end
        sourceSheet = sheets(unifiedIndex);
        T = readtable(filePath, 'Sheet', sourceSheet, 'TextType', 'string', ...
            'VariableNamingRule', 'preserve');
        names = string(T.Properties.VariableNames);
        normal = normalise_names(names);
        eventTypeName = find_name(names, normal, ...
            ["event_type", "eventtype"], true);
        dateName = find_name(names, normal, ...
            ["date_time", "datetime", "date"], true);
        eventTypes = upper(strtrim(string(T.(eventTypeName))));
        T = T(eventTypes == phaseCode, :);
        datasetName = "EA-EMPD";
        sourceWindow = phaseCode;
    elseif sourceId == "EA_MPD"
        sourceSheet = legacy_sheet(phaseCode);
        sheetIndex = find(strcmpi(strtrim(sheets), sourceSheet), 1);
        if isempty(sheetIndex)
            error('EA_MPD_SHEET_MISSING: sheet "%s" was not found in %s.', ...
                sourceSheet, filePath);
        end
        sourceSheet = sheets(sheetIndex);
        T = readtable(filePath, 'Sheet', sourceSheet, 'TextType', 'string', ...
            'VariableNamingRule', 'preserve');
        names = string(T.Properties.VariableNames);
        normal = normalise_names(names);
        dateName = find_name(names, normal, ...
            ["event_date", "date", "meeting_date", "date_time", "datetime"], true);
        datasetName = "EA-MPD";
        sourceWindow = phaseCode;
    else
        error('EA_POLICY_SOURCE: unsupported source %s.', sourceId);
    end

    T.event_date = Parse_date_flexible(T.(dateName));
    T.dataset_name = repmat(datasetName, height(T), 1);
    T.dataset_window = repmat(sourceWindow, height(T), 1);
    % The coordinated 8-Oct-2008 announcement precedes the published
    % 13:25 baseline, so neither source brackets that news. The 17-Sep-2001
    % observation is not invalidated by this timing rule.
    invalidDates = datetime(2008, 10, 8);
    T.window_timing_valid = ~ismember(T.event_date, invalidDates);
    metadata.source_id = sourceId;
    metadata.dataset_name = datasetName;
    metadata.source_sheet = sourceSheet;
    metadata.source_window = sourceWindow;

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

function sheet = legacy_sheet(phaseCode)
    if phaseCode == "GC_PR"
        sheet = "Press Release Window";
    elseif phaseCode == "GC_PC"
        sheet = "Press Conference Window";
    else
        sheet = "Monetary Event Window";
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
