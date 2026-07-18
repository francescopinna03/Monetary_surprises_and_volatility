%% STEP 15: PRESS RELEASE BAR PANEL CONSTRUCTION.
%
% The script reconstructs a bar-level panel for the PR event window. 
%
% For each event and asset-family observation, the code locates the cleaned
% contract file, identifies the first bar at or after the press-release time
% and extracts the same number of bars used in the PR-window panel. The first
% return is computed using the bar immediately preceding the PR window, so that
% the extracted return sequence is internally consistent with the intraday
% price path.
%
% The output contains one row per extracted PR bar, including the event
% metadata, the cleaned source file, the current price, the previous price and
% the bar-level log return. A companion summary file compares realized
% variance and net return recomputed from the extracted bars with the
% corresponding values already stored in the PR state-dependent panel.
%
% This step is mainly preparatory, considering that it creates the bar-level structure needed
% for the later BNS-type volatility decomposition. A PR window is marked as
% BNS-eligible when it contains at least five extracted returns.
%
% Input file is Output/analysis/pr_state_dependent_panel.csv. Cleaned
% intraday files are read from Output/cleaned. Output files are
% Output/analysis/pr_bar_panel.csv, Output/analysis/pr_bar_panel_summary.csv
% and Output/analysis/pr_bar_extractor_diagnostics.csv.

clear; clc;

projectRoot = Get_project_root();
Require_time_alignment_manifest(projectRoot);

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
cleanDir = fullfile(projectRoot, 'Output', 'cleaned');
panelFile = fullfile(analysisDir, 'pr_state_dependent_panel.csv');

minBarsForBNS = 5;

P = readtable(panelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

P.event_date = Parse_date_flexible(P.event_date);
P.pr_datetime_local = Parse_datetime_flexible(P.pr_datetime_local);
P.pr_datetime_utc = Parse_utc_datetime(P.pr_datetime_utc);
P.root_code = string(P.root_code);
P.file_name_clean = string(P.file_name_clean);

numVars = ["PR_n_obs_bars", "PR_rv", "PR_net_log_return", "asinh_PR_rv", "asinh_PR_rsv_neg"];

for v = numVars
    if ismember(v, string(P.Properties.VariableNames)) && ~isnumeric(P.(v))
        P.(v) = str2double(P.(v));
    end
end

barCell = cell(height(P), 1);
sumCell = cell(height(P), 1);
diagCell = cell(height(P), 1);
fileCache = containers.Map('KeyType', 'char', 'ValueType', 'any');

for i = 1:height(P)

    eventDate = P.event_date(i);
    rootCode = string(P.root_code(i));
    cleanName = string(P.file_name_clean(i));
    prDT = P.pr_datetime_utc(i);
    nTarget = P.PR_n_obs_bars(i);

    eventId = "";
    if ismember("event_id", string(P.Properties.VariableNames))
        eventId = string(P.event_id(i));
    end

    filePath = locate_clean_file(cleanDir, cleanName);

    if strlength(filePath) == 0
        diagCell{i} = make_diag_row(i, eventDate, rootCode, cleanName, "file_not_found", nTarget, NaN, "", NaT, NaT, "");
        continue;
    end

    cacheKey = char(filePath);

    if isKey(fileCache, cacheKey)
        C = fileCache(cacheKey);
    else
        C = read_clean_file(filePath);
        fileCache(cacheKey) = C;
    end

    [B, S] = extract_pr_window(C, prDT, nTarget, minBarsForBNS);

    if isempty(B)
        diagCell{i} = make_diag_row(i, eventDate, rootCode, cleanName, S.status, nTarget, 0, filePath, S.first_bar_time, S.last_bar_time, S.message);
        continue;
    end

    prRV = get_optional_numeric(P(i, :), "PR_rv");
    prNet = get_optional_numeric(P(i, :), "PR_net_log_return");
    asinhRV = get_optional_numeric(P(i, :), "asinh_PR_rv");
    asinhRSVneg = get_optional_numeric(P(i, :), "asinh_PR_rsv_neg");

    nB = height(B);

    Bt = table();
    Bt.event_date = repmat(eventDate, nB, 1);
    Bt.event_id = repmat(eventId, nB, 1);
    Bt.root_code = repmat(rootCode, nB, 1);
    Bt.file_name_clean = repmat(cleanName, nB, 1);
    Bt.source_file = repmat(filePath, nB, 1);
    Bt.pr_datetime_local = repmat(P.pr_datetime_local(i), nB, 1);
    Bt.pr_datetime_utc = repmat(prDT, nB, 1);
    Bt.bar_index_in_pr = (1:nB)';
    Bt.bar_time = B.bar_time;
    Bt.price_bar = B.price_bar;
    Bt.prev_price_bar = B.prev_price_bar;
    Bt.r_bar = B.r_bar;
    Bt.n_bars_target = repmat(nTarget, nB, 1);
    Bt.n_bars_extracted = repmat(nB, nB, 1);
    Bt.bns_eligible = repmat(S.bns_eligible, nB, 1);
    Bt.PR_rv_panel = repmat(prRV, nB, 1);
    Bt.PR_net_log_return_panel = repmat(prNet, nB, 1);
    Bt.asinh_PR_rv_panel = repmat(asinhRV, nB, 1);
    Bt.asinh_PR_rsv_neg_panel = repmat(asinhRSVneg, nB, 1);
    barCell{i} = Bt;

    St = table();
    St.event_date = eventDate;
    St.event_id = eventId;
    St.root_code = rootCode;
    St.file_name_clean = cleanName;
    St.source_file = filePath;
    St.pr_datetime_local = P.pr_datetime_local(i);
    St.pr_datetime_utc = prDT;
    St.status = S.status;
    St.n_bars_target = nTarget;
    St.n_bars_extracted = nB;
    St.rv_from_bars = S.rv_from_bars;
    St.net_return_from_bars = S.net_return_from_bars;
    St.PR_rv_panel = prRV;
    St.PR_net_log_return_panel = prNet;
    St.absdiff_rv = abs(S.rv_from_bars - prRV);
    St.absdiff_net_return = abs(S.net_return_from_bars - prNet);
    St.first_bar_time = S.first_bar_time;
    St.last_bar_time = S.last_bar_time;
    St.bns_eligible = S.bns_eligible;
    sumCell{i} = St;

    diagCell{i} = make_diag_row(i, eventDate, rootCode, cleanName, S.status, nTarget, nB, filePath, S.first_bar_time, S.last_bar_time, S.message);
end

barPanel = stack_tables(barCell, rows_to_bar_table({}));
sumPanel = stack_tables(sumCell, rows_to_summary_table({}));
diagPanel = stack_tables(diagCell, rows_to_diag_table({}));

barFile = fullfile(analysisDir, 'pr_bar_panel.csv');
sumFile = fullfile(analysisDir, 'pr_bar_panel_summary.csv');
diagFile = fullfile(analysisDir, 'pr_bar_extractor_diagnostics.csv');

writetable(format_dates(barPanel), barFile);
writetable(format_dates(sumPanel), sumFile);
writetable(format_dates(diagPanel), diagFile);

fprintf('\n================ PR BAR PANEL SUMMARY ================\n');
fprintf('Panel rows        : %d\n', height(P));
fprintf('Bar rows          : %d\n', height(barPanel));
fprintf('Summary rows      : %d\n', height(sumPanel));
fprintf('Diagnostics rows  : %d\n', height(diagPanel));
fprintf('Bar panel         : %s\n', barFile);
fprintf('Summary panel     : %s\n', sumFile);
fprintf('Diagnostics       : %s\n', diagFile);
fprintf('======================================================\n');

function filePath = locate_clean_file(cleanDir, cleanName)

    filePath = "";

    if strlength(cleanName) == 0 || ismissing(cleanName)
        return;
    end

    if exist(cleanName, 'file') == 2
        filePath = string(cleanName);
        return;
    end

    [~, nameOnly, extOnly] = fileparts(cleanName);

    if strlength(extOnly) == 0
        baseName = nameOnly + ".csv";
    else
        baseName = nameOnly + extOnly;
    end

    candidate = fullfile(cleanDir, baseName);

    if exist(candidate, 'file') == 2
        filePath = string(candidate);
    end
end

function C = read_clean_file(filePath)

    T = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');

    T.Time = Parse_utc_datetime(T.Time);

    if ~isnumeric(T.Latest)
        T.Latest = str2double(T.Latest);
    end

    if ismember("Volume", string(T.Properties.VariableNames))
        if ~isnumeric(T.Volume)
            T.Volume = str2double(T.Volume);
        end
    else
        T.Volume = nan(height(T), 1);
    end

    C = table();
    C.bar_time = T.Time;
    C.price_bar = T.Latest;
    C.volume_bar = T.Volume;

    C = C(~isnat(C.bar_time) & isfinite(C.price_bar), :);
    C = sortrows(C, 'bar_time');
end

function [B, S] = extract_pr_window(C, prDT, nTarget, minBarsForBNS)

    B = table();

    S = struct();
    S.status = "unknown";
    S.message = "";
    S.first_bar_time = NaT;
    S.last_bar_time = NaT;
    S.rv_from_bars = NaN;
    S.net_return_from_bars = NaN;
    S.bns_eligible = false;

    if isempty(C)
        S.status = "empty_clean_file";
        return;
    end

    if isnat(prDT) || ~isfinite(nTarget) || nTarget <= 0
        S.status = "invalid_pr_window";
        return;
    end

    idx0 = find(C.bar_time >= prDT, 1, 'first');

    if isempty(idx0)
        S.status = "no_bar_at_or_after_pr";
        return;
    end

    if idx0 <= 1
        S.status = "no_previous_bar";
        return;
    end

    idxN = min(idx0 + nTarget - 1, height(C));
    idx = idx0:idxN;

    prevPrice = C.price_bar(idx - 1);
    currPrice = C.price_bar(idx);
    r = log(currPrice) - log(prevPrice);

    B = table();
    B.bar_time = C.bar_time(idx);
    B.price_bar = currPrice;
    B.prev_price_bar = prevPrice;
    B.r_bar = r;

    S.status = "ok";
    S.first_bar_time = B.bar_time(1);
    S.last_bar_time = B.bar_time(end);
    S.rv_from_bars = sum(B.r_bar .^ 2, 'omitnan');
    S.net_return_from_bars = sum(B.r_bar, 'omitnan');
    S.bns_eligible = height(B) >= minBarsForBNS;

    if height(B) < nTarget
        S.status = "insufficient_bars_but_usable";
        S.message = "Extracted fewer bars than PR_n_obs_bars.";
    end
end

function x = get_optional_numeric(row, varName)

    if ismember(varName, string(row.Properties.VariableNames))
        x = row.(varName);
        if isstring(x)
            x = str2double(x);
        end
    else
        x = NaN;
    end
end

function row = make_diag_row(panelRow, eventDate, rootCode, cleanName, status, nTarget, nExtracted, sourceFile, firstBar, lastBar, message)

    row = table();
    row.panel_row = panelRow;
    row.event_date = eventDate;
    row.root_code = string(rootCode);
    row.file_name_clean = string(cleanName);
    row.status = string(status);
    row.n_bars_target = nTarget;
    row.n_bars_extracted = nExtracted;
    row.source_file = string(sourceFile);
    row.first_bar_time = firstBar;
    row.last_bar_time = lastBar;
    row.message = string(message);
end

function T = stack_tables(cellOfTables, emptyTable)

    keep = ~cellfun(@isempty, cellOfTables);

    if any(keep)
        T = vertcat(cellOfTables{keep});
    else
        T = emptyTable;
    end
end

function T = rows_to_bar_table(rows)

    names = {'event_date', 'event_id', 'root_code', 'file_name_clean', 'source_file', 'pr_datetime_local', 'pr_datetime_utc', 'bar_index_in_pr', 'bar_time', 'price_bar', 'prev_price_bar', 'r_bar', 'n_bars_target', 'n_bars_extracted', 'bns_eligible', 'PR_rv_panel', 'PR_net_log_return_panel', 'asinh_PR_rv_panel', 'asinh_PR_rsv_neg_panel'};

    if isempty(rows)
        T = cell2table(cell(0, numel(names)), 'VariableNames', names);
    else
        T = cell2table(rows, 'VariableNames', names);
    end
end

function T = rows_to_summary_table(rows)

    names = {'event_date', 'event_id', 'root_code', 'file_name_clean', 'source_file', 'pr_datetime_local', 'pr_datetime_utc', 'status', 'n_bars_target', 'n_bars_extracted', 'rv_from_bars', 'net_return_from_bars', 'PR_rv_panel', 'PR_net_log_return_panel', 'absdiff_rv', 'absdiff_net_return', 'first_bar_time', 'last_bar_time', 'bns_eligible'};

    if isempty(rows)
        T = cell2table(cell(0, numel(names)), 'VariableNames', names);
    else
        T = cell2table(rows, 'VariableNames', names);
    end
end

function T = rows_to_diag_table(rows)

    names = {'panel_row', 'event_date', 'root_code', 'file_name_clean', 'status', 'n_bars_target', 'n_bars_extracted', 'source_file', 'first_bar_time', 'last_bar_time', 'message'};

    if isempty(rows)
        T = cell2table(cell(0, numel(names)), 'VariableNames', names);
    else
        T = cell2table(rows, 'VariableNames', names);
    end
end

function T = format_dates(T)

    vars = string(T.Properties.VariableNames);

    for v = vars
        if isdatetime(T.(v))
            T.(v) = string(T.(v), 'yyyy-MM-dd HH:mm:ss');
        end
    end
end
