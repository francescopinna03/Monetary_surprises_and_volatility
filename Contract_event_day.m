%% STEP 3: CONTRACT-DAY QUALITY PANEL.
%
% Building of a contract-day quality panel from the cleaned Barchart
% futures files produced by the cleaning step. It scans Output/cleaned for
% *_clean.csv files and aggregates each intraday contract file at the daily
% level.
%
% For each contract and trading day, the script computes the number of
% observed bars, total and average volume, low-volume shares, first and last
% bar times, time span, expected 5-minute gap coverage, long gaps (20-60 minutes), very long
% gaps (>65 minutes), realized variance and absolute return variation (these diagnostics
% are then used to evaluate whether a contract-day is sufficiently liquid and
% complete for event-window construction).
%
% The script also produces a file-level summary by averaging the daily
% diagnostics within each cleaned contract file. The resulting outputs are
% used by the event-linking step to rank candidate contracts around ECB
% monetary policy dates.
%
% Input file pattern is Output/cleaned/*_clean.csv, output files are
% Output/diagnostics/contract_day_quality.csv and Output/diagnostics/contract_file_quality_summary.csv.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

cleanDir = fullfile(projectRoot, 'Output', 'cleaned');
diagDir = fullfile(projectRoot, 'Output', 'diagnostics');

if ~exist(diagDir, 'dir'); mkdir(diagDir); end

params = struct();
params.expected_bar_minutes = 5;
params.low_volume_threshold = 1;
params.long_gap_minutes = 15;
params.very_long_gap_minutes = 60;

files = dir(fullfile(cleanDir, '*_clean.csv'));
files = files(~[files.isdir]);
nFiles = numel(files);

fprintf('Found %d cleaned CSV files.\n\n', nFiles);

dayCell = cell(nFiles, 1);
fileCell = cell(nFiles, 1);

for i = 1:nFiles

    fname = files(i).name;
    fpath = fullfile(files(i).folder, fname);

    fprintf('[%3d/%3d] %s\n', i, nFiles, fname);

    meta = parse_clean_filename(fname);
    T = read_cleaned_file(fpath);

    if isempty(T)
        fileCell{i} = empty_file_row(meta);
        continue;
    end

    T = sortrows(T, 'Time');

    dayCell{i} = build_day_quality_table(T, meta, params);
    fileCell{i} = build_file_quality_summary(dayCell{i}, meta);
end

idxDay = ~cellfun(@isempty, dayCell);
idxFile = ~cellfun(@isempty, fileCell);

if any(idxDay)
    allDayRows = vertcat(dayCell{idxDay});
    allDayRows = sortrows(allDayRows, {'root_code', 'contract_year', 'expiry_code', 'trade_date'});
else
    allDayRows = empty_day_table();
end

if any(idxFile)
    allFileRows = vertcat(fileCell{idxFile});
    allFileRows = sortrows(allFileRows, {'root_code', 'contract_year', 'expiry_code'});
else
    allFileRows = empty_file_table();
end

dayOutFile = fullfile(diagDir, 'contract_day_quality.csv');
fileOutFile = fullfile(diagDir, 'contract_file_quality_summary.csv');

writetable(allDayRows, dayOutFile);
writetable(allFileRows, fileOutFile);

fprintf('\n================ CONTRACT DAY QUALITY SUMMARY ================\n');
fprintf('Files processed   : %d\n', nFiles);
fprintf('Daily rows        : %d\n', height(allDayRows));
fprintf('Contract rows     : %d\n', height(allFileRows));
fprintf('Day quality CSV   : %s\n', dayOutFile);
fprintf('File summary CSV  : %s\n', fileOutFile);
fprintf('==============================================================\n');

if ~isempty(allFileRows)

    roots = unique(allFileRows.root_code);

    fprintf('\n%-8s %5s %12s %12s %12s\n', 'Root', 'N', 'AvgDayVol', 'AvgLowVol', 'AvgGapOK');

    for r = 1:numel(roots)

        sub = allFileRows(allFileRows.root_code == roots(r), :);

        fprintf('%-8s %5d %12.0f %12.3f %12.3f\n', roots(r), height(sub), mean(sub.avg_daily_volume, 'omitnan'), mean(sub.avg_share_low_volume, 'omitnan'), mean(sub.avg_pct_expected_gaps, 'omitnan'));
    end
end

if ~isempty(allFileRows)

    fprintf('\nTop 10 contracts by avg daily volume:\n');

    tmp = sortrows(allFileRows, 'avg_daily_volume', 'descend');

    disp(tmp(1:min(10, height(tmp)), {'file_name_clean', 'n_days', 'avg_daily_volume', 'avg_share_low_volume', 'avg_pct_expected_gaps'}));
end

if ~isempty(allDayRows)

    fprintf('\nTop 10 days with highest share of low-volume bars:\n');

    tmp = sortrows(allDayRows, 'share_low_volume', 'descend');

    disp(tmp(1:min(10, height(tmp)), {'file_name_clean', 'trade_date', 'n_bars', 'share_low_volume', 'total_volume', 'max_gap_minutes'}));
end

function meta = parse_clean_filename(fname)

    meta = struct('file_name_clean', string(fname), 'root_code', "", 'expiry_code', "", 'contract_year', NaN, 'bar_minutes', NaN, 'download_date', NaT);

    tok = regexp(lower(fname), '^([a-z]+)([hmuz])(\d{2})_intraday-(\d+)min_historical-data-(\d{2})-(\d{2})-(\d{4})_clean\.csv$', 'tokens', 'once');

    if isempty(tok)
        return;
    end

    meta.root_code = string(tok{1});
    meta.expiry_code = string(upper(tok{2}));
    meta.contract_year = 2000 + str2double(tok{3});
    meta.bar_minutes = str2double(tok{4});
    meta.download_date = datetime(str2double(tok{7}), str2double(tok{5}), str2double(tok{6}));
end

function T = read_cleaned_file(fpath)

    opts = detectImportOptions(fpath, 'TextType', 'string');
    T = readtable(fpath, opts);

    if ~ismember("Time", string(T.Properties.VariableNames))
        error('Column "Time" not found in %s', fpath);
    end

    if ~isdatetime(T.Time)
        T.Time = datetime(T.Time, 'InputFormat', 'yyyy-MM-dd HH:mm');
    end
end

function dayTbl = build_day_quality_table(T, meta, params)

    tradeDate = dateshift(T.Time, 'start', 'day');
    uDays = unique(tradeDate);
    nDays = numel(uDays);

    file_name_clean = repmat(meta.file_name_clean, nDays, 1);
    root_code = repmat(meta.root_code, nDays, 1);
    expiry_code = repmat(meta.expiry_code, nDays, 1);
    contract_year = repmat(meta.contract_year, nDays, 1);
    bar_minutes = repmat(meta.bar_minutes, nDays, 1);
    download_date = repmat(meta.download_date, nDays, 1);

    trade_date = NaT(nDays, 1);
    n_bars = nan(nDays, 1);
    total_volume = nan(nDays, 1);
    median_volume = nan(nDays, 1);
    mean_volume = nan(nDays, 1);
    min_volume = nan(nDays, 1);
    max_volume = nan(nDays, 1);
    n_low_volume = nan(nDays, 1);
    share_low_volume = nan(nDays, 1);
    first_bar_time = NaT(nDays, 1);
    last_bar_time = NaT(nDays, 1);
    span_minutes = nan(nDays, 1);
    n_gaps = zeros(nDays, 1);
    n_expected_gaps = zeros(nDays, 1);
    pct_expected_gaps = nan(nDays, 1);
    max_gap_minutes = nan(nDays, 1);
    median_gap_minutes = nan(nDays, 1);
    n_long_gaps = zeros(nDays, 1);
    n_very_long_gaps = zeros(nDays, 1);
    ret_var = nan(nDays, 1);
    abs_return_sum = nan(nDays, 1);

    for d = 1:nDays

        X = T(tradeDate == uDays(d), :);

        trade_date(d) = uDays(d);
        n_bars(d) = height(X);
        total_volume(d) = sum(X.Volume, 'omitnan');
        median_volume(d) = median(X.Volume, 'omitnan');
        mean_volume(d) = mean(X.Volume, 'omitnan');
        min_volume(d) = min(X.Volume);
        max_volume(d) = max(X.Volume);

        lv = X.Volume <= params.low_volume_threshold;

        n_low_volume(d) = sum(lv);
        share_low_volume(d) = mean(lv);

        first_bar_time(d) = X.Time(1);
        last_bar_time(d) = X.Time(end);
        span_minutes(d) = minutes(last_bar_time(d) - first_bar_time(d));

        if n_bars(d) >= 2

            gaps = minutes(diff(X.Time));
            is_expected_gap = abs(gaps - params.expected_bar_minutes) < 1e-9;

            n_gaps(d) = numel(gaps);
            n_expected_gaps(d) = sum(is_expected_gap);
            pct_expected_gaps(d) = mean(is_expected_gap);
            max_gap_minutes(d) = max(gaps);
            median_gap_minutes(d) = median(gaps);
            n_long_gaps(d) = sum(gaps > params.long_gap_minutes);
            n_very_long_gaps(d) = sum(gaps > params.very_long_gap_minutes);

            r = diff(log(X.Latest));

            ret_var(d) = sum(r.^2, 'omitnan');
            abs_return_sum(d) = sum(abs(r), 'omitnan');
        end
    end

    dayTbl = table(file_name_clean, root_code, expiry_code, contract_year, bar_minutes, download_date, trade_date, n_bars, total_volume, median_volume, mean_volume, min_volume, max_volume, n_low_volume, share_low_volume, first_bar_time, last_bar_time, span_minutes, n_gaps, n_expected_gaps, pct_expected_gaps, max_gap_minutes, median_gap_minutes, n_long_gaps, n_very_long_gaps, ret_var, abs_return_sum);
end

function fileRow = build_file_quality_summary(dayTbl, meta)

    fileRow = make_file_row(meta, height(dayTbl), mean(dayTbl.n_bars, 'omitnan'), mean(dayTbl.total_volume, 'omitnan'), median(dayTbl.total_volume, 'omitnan'), mean(dayTbl.share_low_volume, 'omitnan'), mean(dayTbl.pct_expected_gaps, 'omitnan'), mean(dayTbl.max_gap_minutes, 'omitnan'), mean(dayTbl.ret_var, 'omitnan'));
end

function row = empty_file_row(meta)

    row = make_file_row(meta, 0, NaN, NaN, NaN, NaN, NaN, NaN, NaN);
end

function row = make_file_row(meta, n_days, avg_bars_per_day, avg_daily_volume, median_daily_volume, avg_share_low_volume, avg_pct_expected_gaps, avg_max_gap_minutes, avg_ret_var)

    row = table(meta.file_name_clean, meta.root_code, meta.expiry_code, meta.contract_year, meta.bar_minutes, meta.download_date, n_days, avg_bars_per_day, avg_daily_volume, median_daily_volume, avg_share_low_volume, avg_pct_expected_gaps, avg_max_gap_minutes, avg_ret_var, 'VariableNames', {'file_name_clean', 'root_code', 'expiry_code', 'contract_year', 'bar_minutes', 'download_date', 'n_days', 'avg_bars_per_day', 'avg_daily_volume', 'median_daily_volume', 'avg_share_low_volume', 'avg_pct_expected_gaps', 'avg_max_gap_minutes', 'avg_ret_var'});
end

function T = empty_day_table()

    T = table(strings(0, 1), strings(0, 1), strings(0, 1), nan(0, 1), nan(0, 1), NaT(0, 1), NaT(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), NaT(0, 1), NaT(0, 1), nan(0, 1), zeros(0, 1), zeros(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), zeros(0, 1), zeros(0, 1), nan(0, 1), nan(0, 1), 'VariableNames', {'file_name_clean', 'root_code', 'expiry_code', 'contract_year', 'bar_minutes', 'download_date', 'trade_date', 'n_bars', 'total_volume', 'median_volume', 'mean_volume', 'min_volume', 'max_volume', 'n_low_volume', 'share_low_volume', 'first_bar_time', 'last_bar_time', 'span_minutes', 'n_gaps', 'n_expected_gaps', 'pct_expected_gaps', 'max_gap_minutes', 'median_gap_minutes', 'n_long_gaps', 'n_very_long_gaps', 'ret_var', 'abs_return_sum'});
end

function T = empty_file_table()

    T = table(strings(0, 1), strings(0, 1), strings(0, 1), nan(0, 1), nan(0, 1), NaT(0, 1), zeros(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), 'VariableNames', {'file_name_clean', 'root_code', 'expiry_code', 'contract_year', 'bar_minutes', 'download_date', 'n_days', 'avg_bars_per_day', 'avg_daily_volume', 'median_daily_volume', 'avg_share_low_volume', 'avg_pct_expected_gaps', 'avg_max_gap_minutes', 'avg_ret_var'});
end
