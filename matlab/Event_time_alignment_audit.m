%% EVENT-TIME ALIGNMENT AUDIT (RUN AFTER STEP 4).
%
% This diagnostic is deliberately descriptive. For each preferred ECB
% contract it compares the five-minute return and volume at the corrected UTC
% release instant, at one-bar perturbations (-5/+5 minutes), and at the legacy
% timestamp obtained when the Europe/Berlin wall clock was incorrectly treated
% as if it were already UTC. No model selection or pass/fail decision depends
% on the magnitudes reported here.

clear; clc;

projectRoot = Get_project_root();
Require_time_alignment_manifest(projectRoot);
timeCfg = Time_alignment_config();

cleanDir = fullfile(projectRoot, 'Output', 'cleaned');
diagDir = fullfile(projectRoot, 'Output', 'diagnostics');
prefFile = fullfile(diagDir, 'preferred_contract_by_event.csv');

if exist(prefFile, 'file') ~= 2
    error('Preferred-contract input not found: %s', prefFile);
end

P = readtable(prefFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');
required = ["event_date", "root_code", "file_name_clean", "prelim_eligible", ...
    "pr_datetime_local", "pr_datetime_utc"];
missing = required(~ismember(required, string(P.Properties.VariableNames)));

if ~isempty(missing)
    error('Time-alignment audit input is missing: %s', strjoin(missing, ', '));
end

P.event_date = Parse_date_flexible(P.event_date);
P.pr_datetime_local = Parse_datetime_flexible(P.pr_datetime_local);
P.pr_datetime_utc = Parse_utc_datetime(P.pr_datetime_utc);
P.root_code = string(P.root_code);
P.file_name_clean = string(P.file_name_clean);

recomputedUtc = Wall_clock_to_utc(P.pr_datetime_local, timeCfg.event_time_zone);
validClock = ~isnat(P.pr_datetime_utc) & ~isnat(recomputedUtc);
if any(P.pr_datetime_utc(validClock) ~= recomputedUtc(validClock))
    error('EVENT_CLOCK_MISMATCH: stored UTC release clocks differ from Europe/Berlin conversion.');
end

if ~islogical(P.prelim_eligible)
    P.prelim_eligible = String_to_boolean(P.prelim_eligible);
end

P = P(P.prelim_eligible & ~isnat(P.pr_datetime_utc), :);
fileCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
offsets = [-5, 0, 5];
labels = ["corrected_minus_5m", "corrected_primary", "corrected_plus_5m"];
rowCell = cell(height(P) * 4, 1);
outIndex = 0;

for i = 1:height(P)
    filePath = fullfile(cleanDir, P.file_name_clean(i));
    cacheKey = char(filePath);

    if isKey(fileCache, cacheKey)
        C = fileCache(cacheKey);
    else
        C = read_clean_file(filePath);
        fileCache(cacheKey) = C;
    end

    for k = 1:numel(offsets)
        evalTime = P.pr_datetime_utc(i) + minutes(offsets(k));
        outIndex = outIndex + 1;
        rowCell{outIndex} = make_row(P(i, :), labels(k), offsets(k), ...
            evalTime, C);
    end

    % This reproduces the old semantic error: 14:15 Frankfurt wall clock was
    % compared directly with 14:15 in the Barchart clock column.
    legacyUtc = Wall_clock_to_utc(P.pr_datetime_local(i), timeCfg.raw_time_zone);
    legacyOffset = minutes(legacyUtc - P.pr_datetime_utc(i));
    outIndex = outIndex + 1;
    rowCell{outIndex} = make_row(P(i, :), "legacy_naive_clock", ...
        legacyOffset, legacyUtc, C);
end

rowCell = rowCell(1:outIndex);

if isempty(rowCell)
    auditTable = empty_audit_table();
else
    auditTable = vertcat(rowCell{:});
end

summaryTable = summarize_audit(auditTable);
auditFile = fullfile(diagDir, 'time_alignment_event_audit.csv');
summaryFile = fullfile(diagDir, 'time_alignment_event_audit_summary.csv');
writetable(format_dates_for_write(auditTable), auditFile);
writetable(summaryTable, summaryFile);

fprintf('\n================ EVENT-TIME ALIGNMENT AUDIT ================\n');
fprintf('Preferred event-contract rows : %d\n', height(P));
fprintf('Audit rows                    : %d\n', height(auditTable));
fprintf('Event audit                   : %s\n', auditFile);
fprintf('Audit summary                 : %s\n', summaryFile);
fprintf('============================================================\n');
disp(summaryTable);


function C = read_clean_file(filePath)

    if exist(filePath, 'file') ~= 2
        C = table();
        return;
    end

    T = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    required = ["Time", "Latest", "Volume"];

    if ~all(ismember(required, string(T.Properties.VariableNames)))
        C = table();
        return;
    end

    T.Time = Parse_utc_datetime(T.Time);
    if ~isnumeric(T.Latest); T.Latest = str2double(T.Latest); end
    if ~isnumeric(T.Volume); T.Volume = str2double(T.Volume); end

    C = table(T.Time, T.Latest, T.Volume, ...
        'VariableNames', {'bar_time_utc', 'price', 'volume'});
    valid = ~isnat(C.bar_time_utc) & isfinite(C.price) & C.price > 0;
    C = sortrows(C(valid, :), 'bar_time_utc');
    [~, keep] = unique(C.bar_time_utc, 'last');
    C = C(sort(keep), :);
end


function R = make_row(P, label, offsetMinutes, evalTime, C)

    exactCurrent = false;
    exactLag = false;
    logReturn = NaN;
    volume = NaN;

    if ~isempty(C)
        [exactCurrent, currentLoc] = ismember(evalTime, C.bar_time_utc);
        [exactLag, lagLoc] = ismember(evalTime - minutes(5), C.bar_time_utc);

        if exactCurrent
            volume = C.volume(currentLoc);
        end

        if exactCurrent && exactLag
            logReturn = log(C.price(currentLoc)) - log(C.price(lagLoc));
        end
    end

    R = table();
    R.event_date = P.event_date;
    R.root_code = P.root_code;
    R.file_name_clean = P.file_name_clean;
    R.alignment = string(label);
    R.offset_from_corrected_minutes = offsetMinutes;
    R.pr_datetime_local = P.pr_datetime_local;
    R.pr_datetime_utc = P.pr_datetime_utc;
    R.evaluation_time_utc = evalTime;
    R.exact_current_bar = exactCurrent;
    R.exact_lag_bar = exactLag;
    R.exact_return_pair = exactCurrent & exactLag;
    R.log_return_5min = logReturn;
    R.abs_log_return_5min = abs(logReturn);
    R.volume = volume;
end


function S = summarize_audit(A)

    if isempty(A)
        S = table(strings(0, 1), zeros(0, 1), nan(0, 1), nan(0, 1), ...
            nan(0, 1), nan(0, 1), 'VariableNames', {'alignment', 'n_rows', ...
            'share_exact_return_pairs', 'median_abs_log_return_5min', ...
            'mean_abs_log_return_5min', 'median_volume'});
        return;
    end

    alignments = unique(A.alignment, 'stable');
    n = numel(alignments);
    nRows = zeros(n, 1);
    shareExact = nan(n, 1);
    medianAbsReturn = nan(n, 1);
    meanAbsReturn = nan(n, 1);
    medianVolume = nan(n, 1);

    for i = 1:n
        X = A(A.alignment == alignments(i), :);
        nRows(i) = height(X);
        shareExact(i) = mean(X.exact_return_pair);
        medianAbsReturn(i) = median(X.abs_log_return_5min, 'omitnan');
        meanAbsReturn(i) = mean(X.abs_log_return_5min, 'omitnan');
        medianVolume(i) = median(X.volume, 'omitnan');
    end

    S = table(alignments, nRows, shareExact, medianAbsReturn, meanAbsReturn, ...
        medianVolume, 'VariableNames', {'alignment', 'n_rows', ...
        'share_exact_return_pairs', 'median_abs_log_return_5min', ...
        'mean_abs_log_return_5min', 'median_volume'});
end


function T = format_dates_for_write(T)

    vars = string(T.Properties.VariableNames);
    for v = vars
        if isdatetime(T.(v))
            if v == "event_date"
                T.(v) = string(T.(v), 'yyyy-MM-dd');
            else
                T.(v) = string(T.(v), 'yyyy-MM-dd HH:mm:ss');
            end
        end
    end
end


function T = empty_audit_table()

    T = table(NaT(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
        nan(0, 1), NaT(0, 1), NaT(0, 1), NaT(0, 1), false(0, 1), ...
        false(0, 1), false(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), ...
        'VariableNames', {'event_date', 'root_code', 'file_name_clean', ...
        'alignment', 'offset_from_corrected_minutes', 'pr_datetime_local', ...
        'pr_datetime_utc', 'evaluation_time_utc', 'exact_current_bar', ...
        'exact_lag_bar', 'exact_return_pair', 'log_return_5min', ...
        'abs_log_return_5min', 'volume'});
end
