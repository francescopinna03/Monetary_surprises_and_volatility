%% STEP 5: INTRADAY EVENT WINDOW EXTRACTION.
%
% The code opens the event-study stage of the project. It takes the
% preferred futures contracts selected in the previous step and extracts
% intraday windows around each ECB monetary policy event.
%
% For each eligible event-contract pair, the script constructs three windows.
% The PR window is centered around the press release, the PC one
% around the press conference, and the ANN window spans the broader announcement
% interval from before the press release to after the press conference.
%
% Within each window, the script computes coverage diagnostics and realized
% measures from 5-minute futures prices, which include the number of
% observed bars, the expected number of bars, the share of expected bars
% actually observed, exact event-bar availability, low-volume share and maximum
% internal gap. The realized measures include realized variance, positive and
% negative realized semivariance, absolute return variation and net log return.
%
% Then it writes both a long bar-level panel and a compact window-level
% summary, and builds a wide event-window panel, which is the main input
% for the PR baseline construction and the subsequent empirical models.
%
% Input files are Output/diagnostics/preferred_contract_by_event.csv and the
% cleaned futures files in Output/cleaned. Output files are
% Output/event_windows/event_window_bars.csv, Output/event_windows/event_window_summary.csv
% and Output/event_windows/event_window_panel.csv.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

cleanDir = fullfile(projectRoot, 'Output', 'cleaned');
diagDir = fullfile(projectRoot, 'Output', 'diagnostics');
windowDir = fullfile(projectRoot, 'Output', 'event_windows');
prefFile = fullfile(diagDir, 'preferred_contract_by_event.csv');

if ~exist(windowDir, 'dir'); mkdir(windowDir); end

params = struct();
params.bar_minutes = 5;
params.low_volume_threshold = 1;
params.pr_pre_minutes = 15;
params.pr_post_minutes = 30;
params.pc_pre_minutes = 15;
params.pc_post_minutes = 75;
params.ann_pre_from_pr_minutes = 15;
params.ann_post_from_pc_minutes = 75;
params.min_pct_expected_bars = 0.80;
params.max_share_low_volume = 0.50;
params.max_internal_gap_minutes = 15;
params.require_exact_event_bar = true;

pref = readtable(prefFile, 'TextType', 'string');

requiredVars = ["event_date", "event_id", "root_code", "file_name_clean", "pr_datetime_local", "pc_datetime_local", "prelim_eligible", "expiry_code", "contract_year"];
missingVars = requiredVars(~ismember(requiredVars, string(pref.Properties.VariableNames)));

if ~isempty(missingVars)
    error('Missing columns in preferred_contract_by_event.csv: %s', strjoin(missingVars, ', '));
end

pref.event_date = parse_date_flex(pref.event_date);
pref.pr_datetime_local = parse_datetime_flex(pref.pr_datetime_local);
pref.pc_datetime_local = parse_datetime_flex(pref.pc_datetime_local);
pref.root_code = string(pref.root_code);
pref.file_name_clean = string(pref.file_name_clean);
pref.event_id = string(pref.event_id);
pref.expiry_code = string(pref.expiry_code);

if ismember("trade_date", string(pref.Properties.VariableNames))
    pref.trade_date = parse_date_flex(pref.trade_date);
else
    pref.trade_date = pref.event_date;
end

if ~islogical(pref.prelim_eligible)
    pref.prelim_eligible = string_to_bool(pref.prelim_eligible);
end

pref = pref(pref.prelim_eligible, :);

if isempty(pref)
    error('No preliminarily eligible preferred contracts found.');
end

fprintf('Preferred eligible contracts to process: %d\n', height(pref));

uniqueFiles = unique(pref.file_name_clean);
fileCache = containers.Map('KeyType', 'char', 'ValueType', 'any');

fprintf('Caching %d cleaned files...\n', numel(uniqueFiles));

for i = 1:numel(uniqueFiles)

    fname = char(uniqueFiles(i));
    fpath = fullfile(cleanDir, fname);

    if ~exist(fpath, 'file')
        warning('Missing cleaned file: %s', fpath);
        continue;
    end

    T = read_cleaned_file(fpath);
    fileCache(fname) = sortrows(T, 'Time');
end

summaryCell = cell(height(pref), 1);
barsCell = cell(height(pref), 1);

for i = 1:height(pref)

    row = pref(i, :);
    fname = char(row.file_name_clean);

    fprintf('[%3d/%3d] %s | %s | %s\n', i, height(pref), string(row.event_date, 'yyyy-MM-dd'), row.root_code, row.file_name_clean);

    if ~isKey(fileCache, fname)
        warning('File not in cache, skipping: %s', fname);
        continue;
    end

    winDef = build_window_definitions(row, params);
    [summaryCell{i}, barsCell{i}] = process_event_windows(fileCache(fname), row, winDef, params);
end

idxS = ~cellfun(@isempty, summaryCell);
idxB = ~cellfun(@isempty, barsCell);

if any(idxS)
    eventWindowSummary = vertcat(summaryCell{idxS});
else
    eventWindowSummary = empty_window_summary_table();
end

if any(idxB)
    eventWindowBars = vertcat(barsCell{idxB});
else
    eventWindowBars = empty_window_bars_table();
end

if ~isempty(eventWindowSummary)
    eventWindowSummary = sortrows(eventWindowSummary, {'event_date', 'root_code', 'window_name'});
end

if ~isempty(eventWindowBars)
    eventWindowBars = sortrows(eventWindowBars, {'event_date', 'root_code', 'window_name', 'Time'});
end

eventWindowPanel = build_wide_window_panel(eventWindowSummary);

barsFile = fullfile(windowDir, 'event_window_bars.csv');
sumFile = fullfile(windowDir, 'event_window_summary.csv');
panelFile = fullfile(windowDir, 'event_window_panel.csv');

barsOut = format_bars_for_write(eventWindowBars);
sumOut = format_summary_for_write(eventWindowSummary);
panelOut = format_panel_for_write(eventWindowPanel);

writetable(barsOut, barsFile);
writetable(sumOut, sumFile);
writetable(panelOut, panelFile);

fprintf('\n================ EVENT WINDOW EXTRACTION SUMMARY ================\n');
fprintf('Preferred contracts processed : %d\n', height(pref));
fprintf('Window-summary rows           : %d\n', height(eventWindowSummary));
fprintf('Window-bar rows               : %d\n', height(eventWindowBars));
fprintf('Wide panel rows               : %d\n', height(eventWindowPanel));
fprintf('event_window_bars.csv         : %s\n', barsFile);
fprintf('event_window_summary.csv      : %s\n', sumFile);
fprintf('event_window_panel.csv        : %s\n', panelFile);
fprintf('=================================================================\n');

if ~isempty(eventWindowSummary)

    fprintf('\nCoverage by window:\n');

    disp(groupsummary(eventWindowSummary, 'window_name', {'mean', 'sum'}, {'pct_expected_bars', 'exact_event_bar_present', 'window_eligible'}));

    fprintf('\nTop 10 best windows by coverage:\n');

    tmp = sortrows(eventWindowSummary, {'pct_expected_bars', 'share_low_volume'}, {'descend', 'ascend'});
    showVars = {'event_date', 'root_code', 'window_name', 'file_name_clean', 'pct_expected_bars', 'exact_event_bar_present', 'share_low_volume', 'max_gap_minutes', 'window_eligible'};

    disp(tmp(1:min(10, height(tmp)), showVars));
end

function T = read_cleaned_file(fpath)

    opts = detectImportOptions(fpath, 'TextType', 'string');
    T = readtable(fpath, opts);

    required = ["Time", "Open", "High", "Low", "Latest", "Volume"];
    miss = required(~ismember(required, string(T.Properties.VariableNames)));

    if ~isempty(miss)
        error('Missing columns in %s: %s', fpath, strjoin(miss, ', '));
    end

    if ~isdatetime(T.Time)
        T.Time = datetime(T.Time, 'InputFormat', 'yyyy-MM-dd HH:mm');
    end
end

function winDef = build_window_definitions(row, params)

    prTime = row.pr_datetime_local;
    pcTime = row.pc_datetime_local;

    winDef = table();
    winDef.window_name = ["PR"; "PC"; "ANN"];
    winDef.event_time = [prTime; pcTime; prTime];
    winDef.window_start = [prTime - minutes(params.pr_pre_minutes); pcTime - minutes(params.pc_pre_minutes); prTime - minutes(params.ann_pre_from_pr_minutes)];
    winDef.window_end = [prTime + minutes(params.pr_post_minutes); pcTime + minutes(params.pc_post_minutes); pcTime + minutes(params.ann_post_from_pc_minutes)];
end

function [winSummary, winBars] = process_event_windows(T, row, winDef, params)

    summaryRows = cell(height(winDef), 1);
    barsRows = cell(height(winDef), 1);

    for k = 1:height(winDef)

        w = winDef(k, :);

        X = T(T.Time >= w.window_start & T.Time <= w.window_end, :);
        X = sortrows(X, 'Time');

        expectedTimes = transpose(w.window_start : minutes(params.bar_minutes) : w.window_end);
        nExpected = numel(expectedTimes);

        met = compute_window_metrics(X, w, expectedTimes, params);

        eligible = met.pctExpected >= params.min_pct_expected_bars & met.shareLV <= params.max_share_low_volume & (isnan(met.maxGap) | met.maxGap <= params.max_internal_gap_minutes) & (~params.require_exact_event_bar | met.exactEventBar);

        met.nExpected = nExpected;

        summaryRows{k} = build_window_summary(row, w, met, eligible, params);
        barsRows{k} = build_window_bars(row, w, X);
    end

    idxS = ~cellfun(@isempty, summaryRows);
    idxB = ~cellfun(@isempty, barsRows);

    if any(idxS)
        winSummary = vertcat(summaryRows{idxS});
    else
        winSummary = empty_window_summary_table();
    end

    if any(idxB)
        winBars = vertcat(barsRows{idxB});
    else
        winBars = empty_window_bars_table();
    end
end

function met = compute_window_metrics(X, w, expectedTimes, params)

    met = struct();
    met.nObs = height(X);

    if isempty(X)
        met.exactEventBar = false;
        met.pctExpected = 0;
        met.maxGap = NaN;
        met.medGap = NaN;
        met.nLongGaps = 0;
        met.shareLV = NaN;
        met.firstBar = NaT;
        met.lastBar = NaT;
        met.rv = NaN;
        met.rsv_pos = NaN;
        met.rsv_neg = NaN;
        met.absRet = NaN;
        met.netRet = NaN;
        return;
    end

    obsTimes = X.Time;

    met.exactEventBar = any(obsTimes == w.event_time);
    met.pctExpected = mean(ismember(expectedTimes, obsTimes));
    met.shareLV = mean(X.Volume <= params.low_volume_threshold);
    met.firstBar = obsTimes(1);
    met.lastBar = obsTimes(end);

    if met.nObs >= 2

        gaps = minutes(diff(obsTimes));
        r = diff(log(X.Latest));

        met.maxGap = max(gaps);
        met.medGap = median(gaps);
        met.nLongGaps = sum(gaps > params.max_internal_gap_minutes);
        met.rv = sum(r .^ 2, 'omitnan');
        met.rsv_pos = sum((r > 0) .* (r .^ 2), 'omitnan');
        met.rsv_neg = sum((r < 0) .* (r .^ 2), 'omitnan');
        met.absRet = sum(abs(r), 'omitnan');
        met.netRet = log(X.Latest(end) / X.Latest(1));

    else

        met.maxGap = NaN;
        met.medGap = NaN;
        met.nLongGaps = 0;
        met.rv = NaN;
        met.rsv_pos = NaN;
        met.rsv_neg = NaN;
        met.absRet = NaN;
        met.netRet = NaN;
    end
end

function S = build_window_summary(row, w, met, eligible, params)

    S = table();
    S.event_date = row.event_date;
    S.trade_date = row.trade_date;
    S.event_id = row.event_id;
    S.root_code = row.root_code;
    S.file_name_clean = row.file_name_clean;
    S.expiry_code = row.expiry_code;
    S.contract_year = row.contract_year;
    S.window_name = w.window_name;
    S.event_time = w.event_time;
    S.window_start = w.window_start;
    S.window_end = w.window_end;
    S.n_obs_bars = met.nObs;
    S.n_expected_bars = met.nExpected;
    S.pct_expected_bars = met.pctExpected;
    S.exact_event_bar_present = met.exactEventBar;
    S.first_bar_time = met.firstBar;
    S.last_bar_time = met.lastBar;
    S.max_gap_minutes = met.maxGap;
    S.median_gap_minutes = met.medGap;
    S.n_long_gaps = met.nLongGaps;
    S.share_low_volume = met.shareLV;
    S.rv = met.rv;
    S.rsv_pos = met.rsv_pos;
    S.rsv_neg = met.rsv_neg;
    S.abs_return_sum = met.absRet;
    S.net_log_return = met.netRet;
    S.window_eligible = logical(eligible);
    S.low_volume_threshold = params.low_volume_threshold;
    S.bar_minutes = params.bar_minutes;
end

function B = build_window_bars(row, w, X)

    if isempty(X)
        B = empty_window_bars_table();
        return;
    end

    n = height(X);

    B = table();
    B.event_date = repmat(row.event_date, n, 1);
    B.trade_date = repmat(row.trade_date, n, 1);
    B.event_id = repmat(row.event_id, n, 1);
    B.root_code = repmat(row.root_code, n, 1);
    B.file_name_clean = repmat(row.file_name_clean, n, 1);
    B.expiry_code = repmat(row.expiry_code, n, 1);
    B.contract_year = repmat(row.contract_year, n, 1);
    B.window_name = repmat(w.window_name, n, 1);
    B.event_time = repmat(w.event_time, n, 1);
    B.window_start = repmat(w.window_start, n, 1);
    B.window_end = repmat(w.window_end, n, 1);
    B.Time = X.Time;
    B.Open = X.Open;
    B.High = X.High;
    B.Low = X.Low;
    B.Latest = X.Latest;
    B.Volume = X.Volume;
    B.rel_event_minutes = minutes(X.Time - w.event_time);
end

function panel = build_wide_window_panel(S)

    if isempty(S)
        panel = empty_window_panel_table();
        return;
    end

    keys = {'event_date', 'trade_date', 'event_id', 'root_code', 'file_name_clean', 'expiry_code', 'contract_year'};

    [G, panel] = findgroups(S(:, keys));

    panel.pr_datetime_local = NaT(height(panel), 1);
    panel.pc_datetime_local = NaT(height(panel), 1);

    winNames = ["PR", "PC", "ANN"];
    numFields = {'n_obs_bars', 'n_expected_bars', 'pct_expected_bars', 'share_low_volume', 'max_gap_minutes', 'rv', 'rsv_pos', 'rsv_neg', 'abs_return_sum', 'net_log_return'};
    logFields = {'window_eligible', 'exact_event_bar_present'};

    for a = 1:numel(winNames)

        wn = winNames(a);

        for b = 1:numel(numFields)
            colName = char(wn + "_" + string(numFields{b}));
            panel.(colName) = nan(height(panel), 1);
        end

        for b = 1:numel(logFields)
            colName = char(wn + "_" + string(logFields{b}));
            panel.(colName) = false(height(panel), 1);
        end
    end

    for i = 1:max(G)

        X = S(G == i, :);

        prRow = X(X.window_name == "PR", :);

        if ~isempty(prRow)
            panel.pr_datetime_local(i) = prRow.event_time(1);
        end

        pcRow = X(X.window_name == "PC", :);

        if ~isempty(pcRow)
            panel.pc_datetime_local(i) = pcRow.event_time(1);
        end

        for a = 1:numel(winNames)

            wn = winNames(a);
            wRow = X(X.window_name == wn, :);

            if isempty(wRow)
                continue;
            end

            for b = 1:numel(numFields)
                colName = char(wn + "_" + string(numFields{b}));
                panel.(colName)(i) = wRow.(numFields{b})(1);
            end

            for b = 1:numel(logFields)
                colName = char(wn + "_" + string(logFields{b}));
                panel.(colName)(i) = wRow.(logFields{b})(1);
            end
        end
    end
end

function T = format_bars_for_write(T)

    if isempty(T)
        return;
    end

    T.event_date = string(T.event_date, 'yyyy-MM-dd');
    T.trade_date = string(T.trade_date, 'yyyy-MM-dd');
    T.event_time = string(T.event_time, 'yyyy-MM-dd HH:mm');
    T.window_start = string(T.window_start, 'yyyy-MM-dd HH:mm');
    T.window_end = string(T.window_end, 'yyyy-MM-dd HH:mm');
    T.Time = string(T.Time, 'yyyy-MM-dd HH:mm');
end

function T = format_summary_for_write(T)

    if isempty(T)
        return;
    end

    T.event_date = string(T.event_date, 'yyyy-MM-dd');
    T.trade_date = string(T.trade_date, 'yyyy-MM-dd');
    T.event_time = string(T.event_time, 'yyyy-MM-dd HH:mm');
    T.window_start = string(T.window_start, 'yyyy-MM-dd HH:mm');
    T.window_end = string(T.window_end, 'yyyy-MM-dd HH:mm');
    T.first_bar_time = string(T.first_bar_time, 'yyyy-MM-dd HH:mm');
    T.last_bar_time = string(T.last_bar_time, 'yyyy-MM-dd HH:mm');
end

function T = format_panel_for_write(T)

    if isempty(T)
        return;
    end

    T.event_date = string(T.event_date, 'yyyy-MM-dd');
    T.trade_date = string(T.trade_date, 'yyyy-MM-dd');
    T.pr_datetime_local = string(T.pr_datetime_local, 'yyyy-MM-dd HH:mm');
    T.pc_datetime_local = string(T.pc_datetime_local, 'yyyy-MM-dd HH:mm');
end

function dt = parse_date_flex(x)

    if isdatetime(x)
        dt = dateshift(x, 'start', 'day');
        return;
    end

    if isnumeric(x)
        dt = dateshift(datetime(x, 'ConvertFrom', 'excel'), 'start', 'day');
        return;
    end

    if iscell(x)
        x = string(x);
    end

    if ischar(x)
        x = string(x);
    end

    fmts = {'yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'dd-MMM-yyyy'};
    best = NaT(size(x));
    bestBad = inf;

    for i = 1:numel(fmts)

        try
            dTry = datetime(x, 'InputFormat', fmts{i});
            nBad = sum(isnat(dTry));

            if nBad < bestBad
                bestBad = nBad;
                best = dTry;
            end

        catch
        end
    end

    dt = dateshift(best, 'start', 'day');
end

function dt = parse_datetime_flex(x)

    if isdatetime(x)
        dt = x;
        return;
    end

    if isnumeric(x)
        dt = datetime(x, 'ConvertFrom', 'excel');
        return;
    end

    if iscell(x)
        x = string(x);
    end

    if ischar(x)
        x = string(x);
    end

    fmts = {'yyyy-MM-dd HH:mm', 'dd/MM/yyyy HH:mm', 'MM/dd/yyyy HH:mm', 'dd-MMM-yyyy HH:mm'};
    best = NaT(size(x));
    bestBad = inf;

    for i = 1:numel(fmts)

        try
            dTry = datetime(x, 'InputFormat', fmts{i});
            nBad = sum(isnat(dTry));

            if nBad < bestBad
                bestBad = nBad;
                best = dTry;
            end

        catch
        end
    end

    dt = best;
end

function y = string_to_bool(x)

    x = lower(strtrim(string(x)));
    y = x == "true" | x == "1";
end

function T = empty_window_summary_table()

    T = table();
    T.event_date = NaT(0, 1);
    T.trade_date = NaT(0, 1);
    T.event_id = strings(0, 1);
    T.root_code = strings(0, 1);
    T.file_name_clean = strings(0, 1);
    T.expiry_code = strings(0, 1);
    T.contract_year = nan(0, 1);
    T.window_name = strings(0, 1);
    T.event_time = NaT(0, 1);
    T.window_start = NaT(0, 1);
    T.window_end = NaT(0, 1);
    T.n_obs_bars = nan(0, 1);
    T.n_expected_bars = nan(0, 1);
    T.pct_expected_bars = nan(0, 1);
    T.exact_event_bar_present = false(0, 1);
    T.first_bar_time = NaT(0, 1);
    T.last_bar_time = NaT(0, 1);
    T.max_gap_minutes = nan(0, 1);
    T.median_gap_minutes = nan(0, 1);
    T.n_long_gaps = nan(0, 1);
    T.share_low_volume = nan(0, 1);
    T.rv = nan(0, 1);
    T.rsv_pos = nan(0, 1);
    T.rsv_neg = nan(0, 1);
    T.abs_return_sum = nan(0, 1);
    T.net_log_return = nan(0, 1);
    T.window_eligible = false(0, 1);
    T.low_volume_threshold = nan(0, 1);
    T.bar_minutes = nan(0, 1);
end

function T = empty_window_bars_table()

    T = table();
    T.event_date = NaT(0, 1);
    T.trade_date = NaT(0, 1);
    T.event_id = strings(0, 1);
    T.root_code = strings(0, 1);
    T.file_name_clean = strings(0, 1);
    T.expiry_code = strings(0, 1);
    T.contract_year = nan(0, 1);
    T.window_name = strings(0, 1);
    T.event_time = NaT(0, 1);
    T.window_start = NaT(0, 1);
    T.window_end = NaT(0, 1);
    T.Time = NaT(0, 1);
    T.Open = nan(0, 1);
    T.High = nan(0, 1);
    T.Low = nan(0, 1);
    T.Latest = nan(0, 1);
    T.Volume = nan(0, 1);
    T.rel_event_minutes = nan(0, 1);
end

function T = empty_window_panel_table()

    T = table();
    T.event_date = NaT(0, 1);
    T.trade_date = NaT(0, 1);
    T.event_id = strings(0, 1);
    T.root_code = strings(0, 1);
    T.file_name_clean = strings(0, 1);
    T.expiry_code = strings(0, 1);
    T.contract_year = nan(0, 1);
    T.pr_datetime_local = NaT(0, 1);
    T.pc_datetime_local = NaT(0, 1);

    winNames = ["PR", "PC", "ANN"];
    numFields = {'n_obs_bars', 'n_expected_bars', 'pct_expected_bars', 'share_low_volume', 'max_gap_minutes', 'rv', 'rsv_pos', 'rsv_neg', 'abs_return_sum', 'net_log_return'};
    logFields = {'window_eligible', 'exact_event_bar_present'};

    for a = 1:numel(winNames)

        wn = winNames(a);

        for b = 1:numel(numFields)
            colName = char(wn + "_" + string(numFields{b}));
            T.(colName) = nan(0, 1);
        end

        for b = 1:numel(logFields)
            colName = char(wn + "_" + string(logFields{b}));
            T.(colName) = false(0, 1);
        end
    end
end
