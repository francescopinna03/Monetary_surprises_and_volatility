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
% The cleaned CSV contains Time, Open, High, Low, Latest and Volume.

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

    raw_line_no = nan(nRawDataLines, 1);
    timeStr = strings(nRawDataLines, 1);
    Open = nan(nRawDataLines, 1);
    High = nan(nRawDataLines, 1);
    Low = nan(nRawDataLines, 1);
    Latest = nan(nRawDataLines, 1);
    Volume = nan(nRawDataLines, 1);
    parse_ok = false(nRawDataLines, 1);

    for i = 1:nRawDataLines

        raw_line_no(i) = i + 1;
        line = strtrim(dataLines{i});

        fields = split_csv_line(line);

        if numel(fields) < 8
            rowLog = [rowLog; make_log_row(fileName, raw_line_no(i), "", "dropped", "parse_failed")]; %#ok<AGROW>
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

    T = table(raw_line_no, timeStr, Open, High, Low, Latest, Volume, parse_ok);
    T = T(T.parse_ok, :);

    nParseFailed = nRawDataLines - height(T);

    if isempty(T)
        fileSummary = build_file_summary(fileName, nRawDataLines, nParseFailed, 0, 0, 0, 0, 0, hasFooter, NaT, NaT);
        write_clean_csv(cleanTbl, outPath);
        return;
    end

    T.Time = parse_datetime_flex(T.timeStr);

    bad_dt = isnat(T.Time);
    missing_core = any(isnan([T.Open T.High T.Low T.Latest T.Volume]), 2);
    nonpositive_price = T.Open <= 0 | T.High <= 0 | T.Low <= 0 | T.Latest <= 0;
    negative_volume = T.Volume < 0;
    ohlc_bad = ~(T.High >= T.Open & T.High >= T.Low & T.High >= T.Latest & T.Low <= T.Open & T.Low <= T.High & T.Low <= T.Latest);

    invalidMask = bad_dt | missing_core | nonpositive_price | negative_volume | ohlc_bad;

    if any(invalidMask)
        idxBad = find(invalidMask);

        for j = 1:numel(idxBad)

            ii = idxBad(j);
            reasonList = strings(0, 1);

            if bad_dt(ii); reasonList(end+1) = "bad_datetime"; end
            if missing_core(ii); reasonList(end+1) = "missing_core_fields"; end
            if nonpositive_price(ii); reasonList(end+1) = "nonpositive_price"; end
            if negative_volume(ii); reasonList(end+1) = "negative_volume"; end
            if ohlc_bad(ii); reasonList(end+1) = "ohlc_inconsistency"; end

            rowLog = [rowLog; make_log_row(fileName, T.raw_line_no(ii), T.timeStr(ii), "dropped", strjoin(reasonList, ';'))]; %#ok<AGROW>
        end
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

        for j = 1:numel(idxDup)
            ii = idxDup(j);
            rowLog = [rowLog; make_log_row(fileName, T.raw_line_no(ii), string(T.Time(ii), 'yyyy-MM-dd HH:mm'), "dropped", "duplicate_timestamp")]; %#ok<AGROW>
        end
    end

    nDupDropped = sum(dupMask);
    T = T(keepDup, :);

    if isempty(T)
        fileSummary = build_file_summary(fileName, nRawDataLines, nParseFailed, nInvalidCore, nDupDropped, 0, 0, 0, hasFooter, NaT, NaT);
        write_clean_csv(cleanTbl, outPath);
        return;
    end

    spikeMask = false(height(T), 1);
    x = T.Latest;
    d = dateshift(T.Time, 'start', 'day');

    for t = 2:height(T)-1

        sameDay = (d(t-1) == d(t)) && (d(t) == d(t+1));
        gap1 = minutes(T.Time(t) - T.Time(t-1));
        gap2 = minutes(T.Time(t+1) - T.Time(t));

        if ~sameDay || gap1 > params.max_spike_gap_minutes || gap2 > params.max_spike_gap_minutes
            continue;
        end

        localMed = median([x(t-1), x(t+1)]);

        if localMed <= 0
            continue;
        end

        ratio = max(x(t) / localMed, localMed / x(t));
        r1 = log(x(t) / x(t-1));
        r2 = log(x(t+1) / x(t));

        if ratio >= params.spike_ratio_threshold && abs(r1) >= params.spike_logjump_threshold && abs(r2) >= params.spike_logjump_threshold && sign(r1) ~= sign(r2)
            spikeMask(t) = true;
        end
    end

    if any(spikeMask)
        idxSpike = find(spikeMask);

        for j = 1:numel(idxSpike)
            ii = idxSpike(j);
            rowLog = [rowLog; make_log_row(fileName, T.raw_line_no(ii), string(T.Time(ii), 'yyyy-MM-dd HH:mm'), "dropped", "one_bar_price_spike")]; %#ok<AGROW>
        end
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

        for j = 1:numel(idxLV)
            ii = idxLV(j);
            rowLog = [rowLog; make_log_row(fileName, T.raw_line_no(ii), string(T.Time(ii), 'yyyy-MM-dd HH:mm'), "flagged_only", "low_volume")]; %#ok<AGROW>
        end
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

function dt = parse_datetime_flex(timeStr)

    n = numel(timeStr);
    formats = {'yyyy-MM-dd HH:mm', 'yyyy-MM-dd HH:mm:ss', 'MM/dd/yyyy HH:mm', 'MM/dd/yyyy HH:mm:ss'};

    bestBad = inf;
    bestDt = NaT(n, 1);

    for k = 1:numel(formats)

        try
            dtTry = datetime(timeStr, 'InputFormat', formats{k});
            nBad = sum(isnat(dtTry));

            if nBad < bestBad
                bestBad = nBad;
                bestDt = dtTry;
            end

        catch
        end
    end

    dt = bestDt;
end

function write_clean_csv(cleanTbl, outPath)

    outTbl = cleanTbl;
    outTbl.Time = string(outTbl.Time, 'yyyy-MM-dd HH:mm');
    writetable(outTbl, outPath);
end

function row = make_log_row(fileName, rawLineNo, timeStr, action, reason)

    row = table(string(fileName), rawLineNo, string(timeStr), string(action), string(reason), 'VariableNames', {'file_name', 'raw_line_no', 'time_ref', 'action', 'reason'});
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
