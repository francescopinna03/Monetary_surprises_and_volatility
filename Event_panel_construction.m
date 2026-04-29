%% STEP 4: ECB EVENT PANEL AND CONTRACT MATCHING.
%
% The script builds the ECB event panel and links each monetary policy event
% to the available cleaned futures contract-days. It uses the ECB meeting
% calendar together with the contract-day quality panel produced in the
% previous step.
%
% Moreover, it standardizes ECB event dates, press-release times and press
% conference times, then matches event dates with available futures
% contract-days and evaluates all candidate contracts by liquidity, observed
% bars, low-volume share and expected gap coverage.
%
% For each event date and futures family, the script ranks candidate
% contracts and selects the preferred contract. The selection rule is based
% on a weighted score that rewards higher volume, more observed bars, lower
% low-volume share and better 5-minute gap coverage.
%
% The resulting files define the empirical bridge between the ECB monetary
% policy calendar and the intraday futures data. They are used in the next
% step to extract PR, PC and announcement-window realized measures.
%
% Input files are the ECB meeting calendar and Output/diagnostics/contract_day_quality.csv, 
% output files are Output/diagnostics/ecb_event_panel.csv, Output/diagnostics/event_contract_day_candidates.csv, 
% Output/diagnostics/preferred_contract_by_event.csv and Output/diagnostics/event_coverage_summary.csv.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

diagDir = fullfile(projectRoot, 'Output', 'diagnostics');
dayQualityFile = fullfile(diagDir, 'contract_day_quality.csv');

calendarCandidates = cell(6, 1);
calendarCandidates{1} = fullfile(projectRoot, 'Output', 'cleaned', 'ECB_calendar_clean.csv');
calendarCandidates{2} = fullfile(projectRoot, 'Output', 'cleaned', 'ecb_calendar_clean.csv');
calendarCandidates{3} = fullfile(projectRoot, 'Raw', 'ECB_calendar', 'ECB_calendar_clean.csv');
calendarCandidates{4} = fullfile(projectRoot, 'Raw', 'ECB_calendar', 'ecb_calendar_clean.csv');
calendarCandidates{5} = fullfile(projectRoot, 'Raw', 'ECB_calendar', 'ecb_meeting_calendar_2013_2026.xlsx');
calendarCandidates{6} = fullfile(projectRoot, 'Data', 'ecb_meeting_calendar_2013_2026.xlsx');

calendarFile = locate_first_existing(calendarCandidates);

if strlength(calendarFile) == 0
    error('ECB calendar not found.');
end

params = struct();
params.min_bars_prelim = 24;
params.max_share_low_volume = 0.80;
params.min_pct_expected_gaps = 0.40;
params.min_total_volume = 1;
params.w_volume = 0.35;
params.w_bars = 0.20;
params.w_lowvol = 0.25;
params.w_gaps = 0.20;

fprintf('Reading ECB calendar:\n%s\n\n', calendarFile);

eventPanel = load_and_build_event_panel(calendarFile);

fprintf('ECB event dates: %d\n', height(eventPanel));

dayQ = readtable(dayQualityFile, 'TextType', 'string');

requiredVars = ["file_name_clean", "root_code", "expiry_code", "contract_year", "trade_date", "n_bars", "total_volume", "share_low_volume", "pct_expected_gaps", "max_gap_minutes"];
missing = requiredVars(~ismember(requiredVars, string(dayQ.Properties.VariableNames)));

if ~isempty(missing)
    error('Missing columns in contract_day_quality: %s', strjoin(missing, ', '));
end

dayQ.trade_date = parse_date_flex(dayQ.trade_date);
dayQ.root_code = string(dayQ.root_code);
dayQ.expiry_code = string(dayQ.expiry_code);
dayQ.file_name_clean = string(dayQ.file_name_clean);

numVars = ["contract_year", "n_bars", "total_volume", "share_low_volume", "pct_expected_gaps", "max_gap_minutes"];

for v = numVars
    if ~isnumeric(dayQ.(v))
        dayQ.(v) = str2double(dayQ.(v));
    end
end

cand = innerjoin(dayQ, eventPanel, 'LeftKeys', 'trade_date', 'RightKeys', 'event_date');

if ~ismember("event_date", string(cand.Properties.VariableNames))
    cand.event_date = cand.trade_date;
end

if isempty(cand)
    error('No match between trade_date and event_date.');
end

cand.prelim_eligible = cand.n_bars >= params.min_bars_prelim & cand.total_volume >= params.min_total_volume & cand.share_low_volume <= params.max_share_low_volume & cand.pct_expected_gaps >= params.min_pct_expected_gaps;
cand.log_total_volume = log1p(cand.total_volume);
cand.one_minus_lowvol = 1 - cand.share_low_volume;
cand.selection_score = nan(height(cand), 1);
cand.rank_within_root_day = nan(height(cand), 1);

groupKey = string(cand.event_date, 'yyyy-MM-dd') + "||" + cand.root_code;
[~, ~, g] = unique(groupKey);

for j = 1:max(g)
    idx = g == j;
    G = cand(idx, :);
    score = params.w_volume * minmax_01(G.log_total_volume) + params.w_bars * minmax_01(G.n_bars) + params.w_lowvol * minmax_01(G.one_minus_lowvol) + params.w_gaps * minmax_01(G.pct_expected_gaps);
    cand.selection_score(idx) = score;
    [~, ord] = sort(score, 'descend', 'MissingPlacement', 'last');
    rv = nan(height(G), 1);
    rv(ord) = (1:height(G))';
    cand.rank_within_root_day(idx) = rv;
end

pref = choose_preferred_contracts(cand);
coverage = summarize_event_coverage(eventPanel, cand, pref);

cand = sortrows(cand, {'event_date', 'root_code', 'rank_within_root_day'}, {'ascend', 'ascend', 'ascend'});
pref = sortrows(pref, {'event_date', 'root_code'});
coverage = sortrows(coverage, 'event_date');

eventPanelOut = eventPanel;
eventPanelOut.event_date = string(eventPanelOut.event_date, 'yyyy-MM-dd');
eventPanelOut.pr_datetime_local = string(eventPanelOut.pr_datetime_local, 'yyyy-MM-dd HH:mm');
eventPanelOut.pc_datetime_local = string(eventPanelOut.pc_datetime_local, 'yyyy-MM-dd HH:mm');

candOut = cand;
candOut.trade_date = string(candOut.trade_date, 'yyyy-MM-dd');
candOut.event_date = string(candOut.event_date, 'yyyy-MM-dd');
candOut.pr_datetime_local = string(candOut.pr_datetime_local, 'yyyy-MM-dd HH:mm');
candOut.pc_datetime_local = string(candOut.pc_datetime_local, 'yyyy-MM-dd HH:mm');

prefOut = pref;
prefOut.trade_date = string(prefOut.trade_date, 'yyyy-MM-dd');
prefOut.event_date = string(prefOut.event_date, 'yyyy-MM-dd');
prefOut.pr_datetime_local = string(prefOut.pr_datetime_local, 'yyyy-MM-dd HH:mm');
prefOut.pc_datetime_local = string(prefOut.pc_datetime_local, 'yyyy-MM-dd HH:mm');

coverageOut = coverage;
coverageOut.event_date = string(coverageOut.event_date, 'yyyy-MM-dd');
coverageOut.pr_datetime_local = string(coverageOut.pr_datetime_local, 'yyyy-MM-dd HH:mm');
coverageOut.pc_datetime_local = string(coverageOut.pc_datetime_local, 'yyyy-MM-dd HH:mm');

eventPanelFile = fullfile(diagDir, 'ecb_event_panel.csv');
candFile = fullfile(diagDir, 'event_contract_day_candidates.csv');
prefFile = fullfile(diagDir, 'preferred_contract_by_event.csv');
covFile = fullfile(diagDir, 'event_coverage_summary.csv');

writetable(eventPanelOut, eventPanelFile);
writetable(candOut, candFile);
writetable(prefOut, prefFile);
writetable(coverageOut, covFile);

fprintf('\n================ ECB EVENT PANEL SUMMARY ================\n');
fprintf('Calendar file           : %s\n', calendarFile);
fprintf('Event dates             : %d\n', height(eventPanel));
fprintf('Candidate contract-days : %d\n', height(cand));
fprintf('Preferred contracts     : %d\n', height(pref));
fprintf('ecb_event_panel         : %s\n', eventPanelFile);
fprintf('event_candidates        : %s\n', candFile);
fprintf('preferred_contracts     : %s\n', prefFile);
fprintf('coverage_summary        : %s\n', covFile);
fprintf('=========================================================\n');

if ~isempty(pref)
    roots = unique(pref.root_code);
    fprintf('\n%-8s %7s %15s\n', 'Root', 'Events', 'EligibleShare');

    for r = 1:numel(roots)
        sub = pref(pref.root_code == roots(r), :);
        fprintf('%-8s %7d %15.3f\n', roots(r), height(sub), mean(sub.prelim_eligible, 'omitnan'));
    end

    fprintf('\nTop 10 preferred contracts by selection score:\n');
    tmp = sortrows(pref, 'selection_score', 'descend');
    disp(tmp(1:min(10, height(tmp)), {'event_date', 'root_code', 'file_name_clean', 'expiry_code', 'contract_year', 'prelim_eligible', 'selection_score', 'total_volume', 'share_low_volume', 'pct_expected_gaps'}));
end

function pathOut = locate_first_existing(candidates)

    pathOut = "";

    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file')
            pathOut = string(candidates{i});
            return;
        end
    end
end

function eventPanel = load_and_build_event_panel(calendarFile)

    [~, ~, ext] = fileparts(calendarFile);

    if strcmpi(ext, '.xlsx') || strcmpi(ext, '.xls')
        T = readtable(calendarFile, 'Sheet', 'ECB_Meetings', 'TextType', 'string');
    else
        T = readtable(calendarFile, 'TextType', 'string');
    end

    names = string(T.Properties.VariableNames);

    dateVar = find_col(names, ["event_date", "date", "meeting_date", "govc_date"]);

    if strlength(dateVar) == 0
        error('Date column not found in ECB calendar.');
    end

    eventDate = parse_date_flex(T.(dateVar));
    eventDate = dateshift(eventDate, 'start', 'day');

    prVar = find_col(names, ["decision_time_local", "pr_time", "press_release_time"]);
    pcVar = find_col(names, ["press_conf_time_local", "pc_time", "press_conference_time"]);

    if strlength(prVar) > 0 && strlength(pcVar) > 0
        prDur = parse_hhmm_to_duration(T.(prVar));
        pcDur = parse_hhmm_to_duration(T.(pcVar));
    else
        cutoff = datetime(2022, 7, 21);
        prDur = repmat(hours(13) + minutes(45), numel(eventDate), 1);
        pcDur = repmat(hours(14) + minutes(30), numel(eventDate), 1);
        newMask = eventDate >= cutoff;
        prDur(newMask) = hours(14) + minutes(15);
        pcDur(newMask) = hours(14) + minutes(45);
    end

    regimeVar = find_col(names, ["timing_regime", "time_regime", "regime"]);
    locationVar = find_col(names, ["location", "city", "venue"]);

    raw = table();
    raw.event_date = eventDate;
    raw.pr_dur = prDur;
    raw.pc_dur = pcDur;
    raw.time_regime = assign_optional_col(T, regimeVar, numel(eventDate));
    raw.location = assign_optional_col(T, locationVar, numel(eventDate));

    raw = raw(~isnat(raw.event_date), :);
    raw = sortrows(raw, 'event_date');

    [~, ia] = unique(raw.event_date, 'stable');
    raw = raw(ia, :);

    eventPanel = table();
    eventPanel.event_date = raw.event_date;
    eventPanel.event_id = "ECB_" + string(raw.event_date, 'yyyyMMdd');
    eventPanel.time_regime = raw.time_regime;
    eventPanel.location = raw.location;
    eventPanel.pr_time_local = raw.pr_dur;
    eventPanel.pc_time_local = raw.pc_dur;
    eventPanel.pr_datetime_local = raw.event_date + raw.pr_dur;
    eventPanel.pc_datetime_local = raw.event_date + raw.pc_dur;
end

function col = find_col(allNames, candidates)

    col = "";
    lower_all = lower(allNames);
    lower_cand = lower(candidates);

    for i = 1:numel(lower_cand)
        idx = find(lower_all == lower_cand(i), 1);

        if ~isempty(idx)
            col = allNames(idx);
            return;
        end
    end
end

function out = assign_optional_col(T, varName, n)

    if strlength(varName) > 0
        out = string(T.(varName));
    else
        out = repmat("", n, 1);
    end
end

function dur = parse_hhmm_to_duration(x)

    if isduration(x)
        dur = x;
        return;
    end

    if isdatetime(x)
        dur = timeofday(x);
        return;
    end

    if isnumeric(x)
        dur = days(x);
        return;
    end

    if iscell(x)
        x = string(x);
    end

    if ischar(x)
        x = string(x);
    end

    s = strtrim(string(x));
    dur = minutes(nan(numel(s), 1));

    for i = 1:numel(s)

        if strlength(s(i)) == 0 || ismissing(s(i))
            continue;
        end

        parts = split(s(i), ':');

        if numel(parts) >= 2
            h = str2double(parts(1));
            m = str2double(parts(2));

            if ~isnan(h) && ~isnan(m)
                dur(i) = hours(h) + minutes(m);
            end
        end
    end
end

function dt = parse_date_flex(x)

    if isdatetime(x)
        dt = x;
        return;
    end

    if isnumeric(x)
        try
            dt = datetime(x, 'ConvertFrom', 'excel');
            return;
        catch
        end
    end

    if iscell(x)
        x = string(x);
    end

    if ischar(x)
        x = string(x);
    end

    fmts = {'yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd HH:mm', 'dd/MM/yyyy HH:mm', 'dd-MMM-yyyy'};
    bestDt = NaT(size(x));
    bestBad = inf;

    for i = 1:numel(fmts)

        try
            dTry = datetime(x, 'InputFormat', fmts{i});
            nBad = sum(isnat(dTry));

            if nBad < bestBad
                bestBad = nBad;
                bestDt = dTry;
            end

        catch
        end
    end

    dt = bestDt;
end

function y = minmax_01(x)

    x = double(x);
    xmin = min(x, [], 'omitnan');
    xmax = max(x, [], 'omitnan');

    if isempty(x) || ~isfinite(xmin) || ~isfinite(xmax)
        y = nan(size(x));
    elseif xmax == xmin
        y = ones(size(x));
    else
        y = (x - xmin) ./ (xmax - xmin);
    end
end

function pref = choose_preferred_contracts(cand)

    groupKey = string(cand.event_date, 'yyyy-MM-dd') + "||" + cand.root_code;
    [~, ~, g] = unique(groupKey);
    nGroups = max(g);
    rows = cell(nGroups, 1);

    for i = 1:nGroups
        G = cand(g == i, :);
        G = sortrows(G, {'prelim_eligible', 'selection_score', 'rank_within_root_day'}, {'descend', 'descend', 'ascend'});
        rows{i} = G(1, :);
    end

    pref = vertcat(rows{:});
end

function coverage = summarize_event_coverage(eventPanel, cand, pref)

    n = height(eventPanel);

    n_candidates_total = zeros(n, 1);
    n_candidates_fx = zeros(n, 1);
    n_candidates_gg = zeros(n, 1);
    has_preferred_fx = false(n, 1);
    has_preferred_gg = false(n, 1);
    pref_fx_eligible = false(n, 1);
    pref_gg_eligible = false(n, 1);

    for i = 1:n

        d = eventPanel.event_date(i);

        C = cand(cand.event_date == d, :);
        P = pref(pref.event_date == d, :);

        n_candidates_total(i) = height(C);
        n_candidates_fx(i) = sum(C.root_code == "fx");
        n_candidates_gg(i) = sum(C.root_code == "gg");

        Pfx = P(P.root_code == "fx", :);
        Pgg = P(P.root_code == "gg", :);

        has_preferred_fx(i) = ~isempty(Pfx);
        has_preferred_gg(i) = ~isempty(Pgg);

        if ~isempty(Pfx)
            pref_fx_eligible(i) = logical(Pfx.prelim_eligible(1));
        end

        if ~isempty(Pgg)
            pref_gg_eligible(i) = logical(Pgg.prelim_eligible(1));
        end
    end

    coverage = table();
    coverage.event_date = eventPanel.event_date;
    coverage.event_id = eventPanel.event_id;
    coverage.time_regime = eventPanel.time_regime;
    coverage.location = eventPanel.location;
    coverage.pr_datetime_local = eventPanel.pr_datetime_local;
    coverage.pc_datetime_local = eventPanel.pc_datetime_local;
    coverage.n_candidates_total = n_candidates_total;
    coverage.n_candidates_fx = n_candidates_fx;
    coverage.n_candidates_gg = n_candidates_gg;
    coverage.has_preferred_fx = has_preferred_fx;
    coverage.has_preferred_gg = has_preferred_gg;
    coverage.pref_fx_eligible = pref_fx_eligible;
    coverage.pref_gg_eligible = pref_gg_eligible;
end
