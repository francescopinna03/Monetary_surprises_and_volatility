%% STEP 2 HELPER: CLEANING OF THE SINGLE FILE.
%
% The helper function below applies the uniform cleaning rules to one raw Barchart
% futures CSV file. It is designed to be called by Contract_event_day.m (or the file from step two under a different name, 
% although it is not recommended to make any internal changes to the files), which
% iterates over the manifest produced by the audit step.
%
% The function removes the Barchart footer, drops non-parsable rows, invalid
% datetimes, missing core fields, non-positive prices, negative volumes, OHLC
% inconsistencies, duplicate timestamps and isolated one-bar price spikes. 
% Low volume bars are flagged but not removed.
%
% The input is one raw Barchart CSV path (The authors are open to suggestions on how to efficiently set up reading multiple files simultaneously.),
% one output path for the cleaned file and a parameter structure controlling the conservative spike and low-volume
% rules. 
% 
% The outputs are the cleaned table, a row-level cleaning log and a file-level cleaning summary.
% The cleaned CSV contains Time, Open, High, Low, Latest and Volume. Raw Time
% is interpreted as America/Chicago wall clock and serialized as UTC clock
% time according to Time_alignment_config.m.

function [cleanTbl, rowLog, fileSummary] = clean_single_barchart_file(fpath, outPath, params)

    params = set_default_params(params);

    [~, nm, ext] = fileparts(fpath);
    fileName = string([nm ext]);

    cleanTbl = empty_clean_table();
    rowLog = empty_rowlog_table();
    fileSummary = empty_filesummary_table();

    fid = fopen(fpath, 'r');
    txt = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);

    lines = txt{1};

    while ~isempty(lines) && isempty(strtrim(lines{end}))
        lines(end) = [];
    end

    if numel(lines) < 2
        fileSummary = build_file_summary(fileName, 0, 0, 0, 0, 0, 0, 0, false, NaT, NaT);
        write_clean_csv(cleanTbl, outPath);
        return;
    end

    hasFooter = ~isempty(regexpi(strtrim(lines{end}), 'Downloaded from Barchart', 'once'));
    dataLines = lines(2:end - double(hasFooter));
    nRawDataLines = numel(dataLines);

    if nRawDataLines == 0
        fileSummary = build_file_summary(fileName, 0, 0, 0, 0, 0, 0, 0, hasFooter, NaT, NaT);
        write_clean_csv(cleanTbl, outPath);
        return;
    end

    raw_line_no = (2:(nRawDataLines + 1))';
    [timeStr, Open, High, Low, Latest, Volume, parse_ok] = parse_data_lines(dataLines);

    failIdx = find(~parse_ok);

    if ~isempty(failIdx)
        rowLog = [rowLog; make_log_rows(fileName, raw_line_no(failIdx), strings(numel(failIdx), 1), "dropped", "parse_failed")];
    end

    T = table(raw_line_no, timeStr, Open, High, Low, Latest, Volume, parse_ok);
    T = T(T.parse_ok, :);

    nParseFailed = nRawDataLines - height(T);

    if isempty(T)
        fileSummary = build_file_summary(fileName, nRawDataLines, nParseFailed, 0, 0, 0, 0, 0, hasFooter, NaT, NaT);
        write_clean_csv(cleanTbl, outPath);
        return;
    end

    T.Time = Wall_clock_to_utc(T.timeStr, params.raw_time_zone);

    bad_dt = isnat(T.Time);
    missing_core = any(isnan([T.Open T.High T.Low T.Latest T.Volume]), 2);
    nonpositive_price = T.Open <= 0 | T.High <= 0 | T.Low <= 0 | T.Latest <= 0;
    negative_volume = T.Volume < 0;
    ohlc_bad = ~(T.High >= T.Open & T.High >= T.Low & T.High >= T.Latest & T.Low <= T.Open & T.Low <= T.High & T.Low <= T.Latest);

    invalidMask = bad_dt | missing_core | nonpositive_price | negative_volume | ohlc_bad;

    if any(invalidMask)
        idxBad = find(invalidMask);
        reasonMat = [bad_dt(idxBad), missing_core(idxBad), nonpositive_price(idxBad), negative_volume(idxBad), ohlc_bad(idxBad)];
        reasonNames = ["bad_datetime", "missing_core_fields", "nonpositive_price", "negative_volume", "ohlc_inconsistency"];
        reasons = strings(numel(idxBad), 1);

        for k = 1:numel(reasonNames)
            m = reasonMat(:, k);
            reasons(m) = reasons(m) + reasonNames(k) + ";";
        end

        reasons = regexprep(reasons, ';$', '');
        rowLog = [rowLog; make_log_rows(fileName, T.raw_line_no(idxBad), T.timeStr(idxBad), "dropped", reasons)];
    end

    nInvalidCore = sum(invalidMask);
    T = T(~invalidMask, :);

    if isempty(T)
        fileSummary = build_file_summary(fileName, nRawDataLines, nParseFailed, nInvalidCore, 0, 0, 0, 0, hasFooter, NaT, NaT);
        write_clean_csv(cleanTbl, outPath);
        return;
    end

    T = sortrows(T, {'Time', 'raw_line_no'});

    [~, idxKeep] = unique(T.Time, 'last');
    keepDup = false(height(T), 1);
    keepDup(idxKeep) = true;
    dupMask = ~keepDup;

    if any(dupMask)
        idxDup = find(dupMask);
        rowLog = [rowLog; make_log_rows(fileName, T.raw_line_no(idxDup), string(T.Time(idxDup), 'yyyy-MM-dd HH:mm'), "dropped", "duplicate_timestamp")];
    end

    nDupDropped = sum(dupMask);
    T = T(keepDup, :);

    if isempty(T)
        fileSummary = build_file_summary(fileName, nRawDataLines, nParseFailed, nInvalidCore, nDupDropped, 0, 0, 0, hasFooter, NaT, NaT);
        write_clean_csv(cleanTbl, outPath);
        return;
    end

    spikeMask = false(height(T), 1);

    if height(T) >= 3
        x = T.Latest;
        d = dateshift(T.Time, 'start', 'day');
        xPrev = x(1:end-2);
        xCurr = x(2:end-1);
        xNext = x(3:end);
        sameDay = d(1:end-2) == d(2:end-1) & d(2:end-1) == d(3:end);
        gap1 = minutes(T.Time(2:end-1) - T.Time(1:end-2));
        gap2 = minutes(T.Time(3:end) - T.Time(2:end-1));
        localMed = (xPrev + xNext) / 2;
        ratio = max(xCurr ./ localMed, localMed ./ xCurr);
        r1 = log(xCurr ./ xPrev);
        r2 = log(xNext ./ xCurr);
        eligible = sameDay & gap1 <= params.max_spike_gap_minutes & gap2 <= params.max_spike_gap_minutes & localMed > 0;
        isSpike = eligible & ratio >= params.spike_ratio_threshold & abs(r1) >= params.spike_logjump_threshold & abs(r2) >= params.spike_logjump_threshold & sign(r1) ~= sign(r2);
        spikeMask(2:end-1) = isSpike;
    end

    if any(spikeMask)
        idxSpike = find(spikeMask);
        rowLog = [rowLog; make_log_rows(fileName, T.raw_line_no(idxSpike), string(T.Time(idxSpike), 'yyyy-MM-dd HH:mm'), "dropped", "one_bar_price_spike")];
    end

    nSpikeDropped = sum(spikeMask);
    T = T(~spikeMask, :);

    if isempty(T)
        fileSummary = build_file_summary(fileName, nRawDataLines, nParseFailed, nInvalidCore, nDupDropped, nSpikeDropped, 0, 0, hasFooter, NaT, NaT);
        write_clean_csv(cleanTbl, outPath);
        return;
    end

    lowVolMask = T.Volume <= params.low_volume_flag_threshold;

    if any(lowVolMask)
        idxLV = find(lowVolMask);
        rowLog = [rowLog; make_log_rows(fileName, T.raw_line_no(idxLV), string(T.Time(idxLV), 'yyyy-MM-dd HH:mm'), "flagged_only", "low_volume")];
    end

    cleanTbl = T(:, {'Time', 'Open', 'High', 'Low', 'Latest', 'Volume'});
    write_clean_csv(cleanTbl, outPath);

    nLowVolFlag = sum(lowVolMask);
    firstTime = cleanTbl.Time(1);
    lastTime = cleanTbl.Time(end);

    fileSummary = build_file_summary(fileName, nRawDataLines, nParseFailed, nInvalidCore, nDupDropped, nSpikeDropped, nLowVolFlag, height(cleanTbl), hasFooter, firstTime, lastTime);
end

function params = set_default_params(params)

    if ~isfield(params, 'spike_ratio_threshold')
        params.spike_ratio_threshold = 5;
    end

    if ~isfield(params, 'spike_logjump_threshold')
        params.spike_logjump_threshold = 1.0;
    end

    if ~isfield(params, 'max_spike_gap_minutes')
        params.max_spike_gap_minutes = 60;
    end

    if ~isfield(params, 'low_volume_flag_threshold')
        params.low_volume_flag_threshold = 1;
    end

    if ~isfield(params, 'raw_time_zone')
        timeCfg = Time_alignment_config();
        params.raw_time_zone = timeCfg.raw_time_zone;
    end
end

function [timeStr, Open, High, Low, Latest, Volume, parse_ok] = parse_data_lines(dataLines)

    n = numel(dataLines);
    timeStr = strings(n, 1);
    Open = nan(n, 1);
    High = nan(n, 1);
    Low = nan(n, 1);
    Latest = nan(n, 1);
    Volume = nan(n, 1);
    parse_ok = false(n, 1);

    try
        C = textscan(strjoin(dataLines, newline), '%q%q%q%q%q%q%q%q', 'Delimiter', ',', 'EndOfLine', '\n', 'ReturnOnError', false);
        nParsed = cellfun(@numel, C);

        if all(nParsed == n)
            timeStr = string(strtrim(C{1}));
            Open = clean_numeric_field(C{2});
            High = clean_numeric_field(C{3});
            Low = clean_numeric_field(C{4});
            Latest = clean_numeric_field(C{5});
            Volume = clean_numeric_field(C{8});
            parse_ok(:) = true;
            return;
        end
    catch
    end

    for i = 1:n
        fields = split_csv_line(strtrim(dataLines{i}));

        if numel(fields) < 8
            continue;
        end

        parse_ok(i) = true;
        timeStr(i) = string(strtrim(fields{1}));
        Open(i) = safe_str2double(fields{2});
        High(i) = safe_str2double(fields{3});
        Low(i) = safe_str2double(fields{4});
        Latest(i) = safe_str2double(fields{5});
        Volume(i) = safe_str2double(fields{8});
    end
end

function x = clean_numeric_field(c)

    s = strtrim(string(c));
    s = erase(s, '"');
    s = erase(s, ',');
    s = erase(s, '%');
    x = str2double(s);
end

function fields = split_csv_line(line)

    C = textscan(line, '%q', 'Delimiter', ',', 'Whitespace', '');
    fields = C{1};
end

function x = safe_str2double(s)

    if isstring(s)
        s = char(s);
    end

    s = strtrim(s);
    s = strrep(s, '"', '');
    s = strrep(s, ',', '');
    s = strrep(s, '%', '');

    if isempty(s)
        x = NaN;
    else
        x = str2double(s);
    end
end

function write_clean_csv(cleanTbl, outPath)

    outTbl = cleanTbl;
    outTbl.Time = string(outTbl.Time, 'yyyy-MM-dd HH:mm');
    writetable(outTbl, outPath);
end

function rows = make_log_rows(fileName, rawLineNo, timeRef, action, reason)

    n = numel(rawLineNo);
    reason = string(reason);

    if isscalar(reason)
        reason = repmat(reason, n, 1);
    end

    rows = table(repmat(string(fileName), n, 1), rawLineNo(:), string(timeRef(:)), repmat(string(action), n, 1), reason(:), 'VariableNames', {'file_name', 'raw_line_no', 'time_ref', 'action', 'reason'});
end

function T = empty_clean_table()

    T = table(NaT(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), 'VariableNames', {'Time', 'Open', 'High', 'Low', 'Latest', 'Volume'});
end

function T = empty_rowlog_table()

    T = table(strings(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), 'VariableNames', {'file_name', 'raw_line_no', 'time_ref', 'action', 'reason'});
end

function T = empty_filesummary_table()

    T = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), NaT(0, 1), NaT(0, 1), 'VariableNames', {'file_name', 'n_raw_rows', 'n_parse_failed', 'n_invalid_core_dropped', 'n_duplicate_ts_dropped', 'n_spike_rows_dropped', 'n_lowvol_flagged', 'n_clean_rows', 'footer_present', 'first_time_clean', 'last_time_clean'});
end

function T = build_file_summary(fileName, nRawRows, nParseFailed, nInvalidCore, nDupDropped, nSpikeDropped, nLowVolFlagged, nCleanRows, footerPresent, firstTime, lastTime)

    T = table(string(fileName), nRawRows, nParseFailed, nInvalidCore, nDupDropped, nSpikeDropped, nLowVolFlagged, nCleanRows, logical(footerPresent), firstTime, lastTime, 'VariableNames', {'file_name', 'n_raw_rows', 'n_parse_failed', 'n_invalid_core_dropped', 'n_duplicate_ts_dropped', 'n_spike_rows_dropped', 'n_lowvol_flagged', 'n_clean_rows', 'footer_present', 'first_time_clean', 'last_time_clean'});
end
