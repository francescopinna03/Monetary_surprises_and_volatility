%% STEP 2: BATCH CLEANING OF RAW BARCHART FILES.
%
% The code applies the uniform Barchart cleaning helper to all raw
% intraday futures CSV files used in the project. It is the batch wrapper of
% the single-file cleaning function clean_single_barchart_file, and should be
% executed after the raw-file audit step and before the contract-day quality
% step.
%
% The script scans Raw/Barchart_futures for raw Barchart CSV files, applies
% the same conservative cleaning rules to each file, and writes one cleaned
% CSV file for each raw input file. The cleaning procedure removes Barchart
% footers, non-parsable rows, invalid datetimes, missing core fields,
% non-positive prices, negative volumes, OHLC inconsistencies, duplicate
% timestamps and isolated one-bar price spikes. Low-volume bars are flagged
% in the diagnostic log but are not removed from the cleaned data.
%
% The parameter block below controls the spike-detection rule and the
% low-volume flag. The thresholds are intentionally conservative, since the
% purpose of this step is to preserve the intraday structure of the event
% windows while removing clear data errors.
%
% Input file pattern is Raw/Barchart_futures/*.csv.
% Output cleaned files are written to Output/cleaned/*_clean.csv.
% Output diagnostics are Output/diagnostics/cleaning_row_flags.csv and Output/diagnostics/cleaning_file_summary.csv.
% Required helper is clean_single_barchart_file.m, which must be available on the MATLAB path or in the same folder as this script.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

rawDir = fullfile(projectRoot, 'Raw', 'Barchart_futures');
cleanDir = fullfile(projectRoot, 'Output', 'cleaned');
diagDir = fullfile(projectRoot, 'Output', 'diagnostics');

if ~exist(cleanDir, 'dir'); mkdir(cleanDir); end
if ~exist(diagDir, 'dir'); mkdir(diagDir); end

params = struct();
params.spike_ratio_threshold = 5;
params.spike_logjump_threshold = 1.0;
params.max_spike_gap_minutes = 60;
params.low_volume_flag_threshold = 1;

files = dir(fullfile(rawDir, '*.csv'));
files = files(~[files.isdir]);
nFiles = numel(files);

fprintf('Found %d raw CSV files to clean.\n\n', nFiles);

rowLogCell = cell(nFiles, 1);
summaryCell = cell(nFiles, 1);

for i = 1:nFiles

    fname = files(i).name;
    fpath = fullfile(files(i).folder, fname);

    [~, nm, ~] = fileparts(fname);
    outName = string(nm) + "_clean.csv";
    outPath = fullfile(cleanDir, char(outName));

    fprintf('[%3d/%3d] %s\n', i, nFiles, fname);

    [~, rowLog, fileSummary] = clean_single_barchart_file(fpath, outPath, params);

    rowLogCell{i} = rowLog;
    summaryCell{i} = fileSummary;
end

idxLog = ~cellfun(@isempty, rowLogCell);
idxSummary = ~cellfun(@isempty, summaryCell);

if any(idxLog)
    cleaningRowFlags = vertcat(rowLogCell{idxLog});
else
    cleaningRowFlags = empty_rowlog_table();
end

if any(idxSummary)
    cleaningFileSummary = vertcat(summaryCell{idxSummary});
else
    cleaningFileSummary = empty_filesummary_table();
end

rowLogFile = fullfile(diagDir, 'cleaning_row_flags.csv');
summaryFile = fullfile(diagDir, 'cleaning_file_summary.csv');

writetable(cleaningRowFlags, rowLogFile);
writetable(cleaningFileSummary, summaryFile);

fprintf('\n================ CLEANING SUMMARY ================\n');
fprintf('Raw files processed       : %d\n', nFiles);
fprintf('Cleaned files written     : %d\n', height(cleaningFileSummary));
fprintf('Rows dropped or flagged   : %d\n', height(cleaningRowFlags));
fprintf('Cleaned directory         : %s\n', cleanDir);
fprintf('Row-level log             : %s\n', rowLogFile);
fprintf('File-level summary        : %s\n', summaryFile);
fprintf('==================================================\n');

function T = empty_rowlog_table()

    T = table(strings(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), 'VariableNames', {'file_name', 'raw_line_no', 'time_ref', 'action', 'reason'});
end

function T = empty_filesummary_table()

    T = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), NaT(0, 1), NaT(0, 1), 'VariableNames', {'file_name', 'n_raw_rows', 'n_parse_failed', 'n_invalid_core_dropped', 'n_duplicate_ts_dropped', 'n_spike_rows_dropped', 'n_lowvol_flagged', 'n_clean_rows', 'footer_present', 'first_time_clean', 'last_time_clean'});
end
