%% STEP 18: NON-ECB COUNTERFACTUAL AND ABNORMAL ANNOUNCEMENT VOLATILITY.
%
% This script implements the counterfactual experiment that separates the
% normal continuation of the pre-announcement volatility environment from
% volatility specifically associated with an ECB press release.
%
% The design uses the full cleaned intraday panel, not only ECB dates. For
% every trading day and futures family it assigns the scheduled ECB release
% clock in Europe/Berlin, converts it to canonical UTC, selects the contract
% using information available before that clock,
% and constructs the same non-overlapping windows:
%
%   pre-announcement base : return endpoints from -55 to -5 minutes
%   post-announcement     : return endpoints from   0 to +45 minutes
%
% Each return is computed only when both exact five-minute endpoints are
% observed. Contract selection depends on pre-window coverage and volume only;
% post-window realizations never enter the ranking.
%
% Non-ECB dates estimate the normal mapping from the pre-window environment
% to post-window volatility. ECB abnormal volatility is the observed outcome
% minus that non-event prediction. The second stage asks whether surprise
% magnitude explains abnormal bipower variation and whether this response
% changes with the pre-announcement state. Event-date clustered standard
% errors, null-imposed wild-cluster bootstrap p-values and a pre-declared
% equivalence margin are reported.
%
% Required inputs:
%   Output/diagnostics/contract_day_quality.csv
%   Output/diagnostics/ecb_event_panel.csv
%   Output/analysis/event_state_panel.csv
%   Output/cleaned/*_clean.csv
%
% Main outputs are written to Output/analysis with the prefix
% announcement_counterfactual_.

clear; clc;

projectRoot = Get_project_root();
Require_time_alignment_manifest(projectRoot);
timeCfg = Time_alignment_config();

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
diagnosticsDir = fullfile(projectRoot, 'Output', 'diagnostics');
cleanDir = fullfile(projectRoot, 'Output', 'cleaned');

if ~exist(analysisDir, 'dir'); mkdir(analysisDir); end

dayQualityFile = fullfile(diagnosticsDir, 'contract_day_quality.csv');
eventCalendarFile = fullfile(diagnosticsDir, 'ecb_event_panel.csv');
eventStateFile = fullfile(analysisDir, 'event_state_panel.csv');

requiredFiles = string({dayQualityFile, eventCalendarFile, eventStateFile});

for f = requiredFiles
    if exist(f, 'file') ~= 2
        error('Required input not found: %s', f);
    end
end

cfg = struct();
cfg.barMinutes = 5;
cfg.preStartMinutes = -60;
cfg.preEndMinutes = -5;
cfg.postStartMinutes = 0;
cfg.postEndMinutes = 45;
cfg.minPreCoverage = 0.80;
cfg.minPostCoverage = 0.80;
cfg.minReturnsForBV = 5;
cfg.lowVolumeThreshold = 1;
cfg.scheduleCutoff = datetime(2022, 7, 21);
cfg.earlyReleaseTime = hours(13) + minutes(45);
cfg.lateReleaseTime = hours(14) + minutes(15);
cfg.slowStateDays = 5;
cfg.bootstrapRep = 999;
cfg.seed = 20260717;
cfg.equivalenceLogMargin = log(1.25);
cfg.minimumControlRows = 100;
cfg.minimumEventClusters = 30;
cfg.eventTimeZone = timeCfg.event_time_zone;

rng(cfg.seed, 'twister');

Q = load_day_quality(dayQualityFile);
E = load_event_calendar(eventCalendarFile);
S = load_event_state(eventStateFile);

eventDatesWithState = S.event_date(~isnat(S.event_date));

if isempty(eventDatesWithState)
    error('event_state_panel.csv contains no valid event dates.');
end

studyStart = min(eventDatesWithState) - caldays(60);
studyEnd = max(eventDatesWithState);

Q = Q(Q.trade_date >= studyStart & Q.trade_date <= studyEnd, :);
Q = Q(ismember(Q.root_code, ["fx", "gg"]), :);

[dayNumber, ~] = weekday(Q.trade_date);
Q = Q(dayNumber >= 2 & dayNumber <= 6, :);

fprintf('Building event and non-event windows from %s to %s.\n', string(studyStart, 'yyyy-MM-dd'), string(studyEnd, 'yyyy-MM-dd'));
fprintf('Candidate contract-days: %d\n', height(Q));

[W, candidateDiagnostics] = build_counterfactual_windows(Q, E, cleanDir, cfg);

if isempty(W)
    error('No counterfactual windows could be constructed.');
end

W = add_slow_state(W, cfg.slowStateDays);
W = merge_event_state(W, S);
W = standardize_pre_state_on_controls(W);

W.q_target = W.shock_target_10bp .^ 2;
W.q_target_x_pre = W.q_target .* W.pre_state_z;
W.q_factor = W.target_pca_10bp .^ 2 + W.path_pca_10bp .^ 2;
W.q_factor_x_pre = W.q_factor .* W.pre_state_z;

normalSpecs = struct( ...
    'outcome', {"log_BV_post", "log_RV_post", "jump_share_post"}, ...
    'preVar', {"log_BV_pre", "log_RV_pre", "jump_share_pre"}, ...
    'prediction', {"cf_log_BV_post", "cf_log_RV_post", "cf_jump_share_post"}, ...
    'abnormal', {"abnormal_log_BV", "abnormal_log_RV", "abnormal_jump_share"});

[W, normalCoef, normalSummary] = fit_normal_counterfactuals(W, normalSpecs, cfg);

[eventCoef, eventSummary, equivalenceResults, effectResults] = fit_event_models(W, cfg);

windowFile = fullfile(analysisDir, 'announcement_counterfactual_windows.csv');
eventRowsFile = fullfile(analysisDir, 'announcement_counterfactual_event_rows.csv');
candidateFile = fullfile(analysisDir, 'announcement_counterfactual_contract_candidates.csv');
normalCoefFile = fullfile(analysisDir, 'announcement_counterfactual_normal_coefficients.csv');
normalSummaryFile = fullfile(analysisDir, 'announcement_counterfactual_normal_summary.csv');
eventCoefFile = fullfile(analysisDir, 'announcement_counterfactual_event_coefficients.csv');
eventSummaryFile = fullfile(analysisDir, 'announcement_counterfactual_event_summary.csv');
equivalenceFile = fullfile(analysisDir, 'announcement_counterfactual_equivalence.csv');
effectsFile = fullfile(analysisDir, 'announcement_counterfactual_effects.csv');

writetable(format_dates_for_write(W), windowFile);
writetable(format_dates_for_write(W(W.is_event, :)), eventRowsFile);
writetable(format_dates_for_write(candidateDiagnostics), candidateFile);
writetable(normalCoef, normalCoefFile);
writetable(normalSummary, normalSummaryFile);
writetable(eventCoef, eventCoefFile);
writetable(eventSummary, eventSummaryFile);
writetable(equivalenceResults, equivalenceFile);
writetable(effectResults, effectsFile);

fprintf('\n================ ANNOUNCEMENT COUNTERFACTUAL ================\n');
fprintf('Selected root-days             : %d\n', height(W));
fprintf('Eligible non-ECB root-days     : %d\n', sum(~W.is_event & W.window_eligible));
fprintf('Eligible ECB root-days         : %d\n', sum(W.is_event & W.window_eligible));
fprintf('Distinct eligible ECB events   : %d\n', numel(unique(W.trade_date(W.is_event & W.window_eligible))));
fprintf('Window panel                   : %s\n', windowFile);
fprintf('ECB estimation rows            : %s\n', eventRowsFile);
fprintf('Normal-model summary           : %s\n', normalSummaryFile);
fprintf('Event-model coefficients       : %s\n', eventCoefFile);
fprintf('Equivalence tests              : %s\n', equivalenceFile);
fprintf('==============================================================\n');

keyTerms = ["q_target", "q_target_x_pre", "q_factor", "q_factor_x_pre"];

if ~isempty(eventCoef)
    disp(eventCoef(ismember(eventCoef.term, keyTerms), {'model_name', 'term', 'beta', 'se_cluster', 't_stat', 'p_value', 'p_wild_cluster', 'ci95_lo', 'ci95_hi', 'n_clusters'}));
end

function Q = load_day_quality(filePath)

    Q = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    required = ["trade_date", "root_code", "file_name_clean", "ret_var"];
    missing = required(~ismember(required, string(Q.Properties.VariableNames)));

    if ~isempty(missing)
        error('Missing columns in contract_day_quality.csv: %s', strjoin(missing, ', '));
    end

    Q.trade_date = Parse_date_flexible(Q.trade_date);
    Q.root_code = string(Q.root_code);
    Q.file_name_clean = string(Q.file_name_clean);

    numericVars = ["ret_var", "total_volume", "share_low_volume", "pct_expected_gaps", "n_bars"];

    for v = numericVars
        if ismember(v, string(Q.Properties.VariableNames)) && ~isnumeric(Q.(v))
            Q.(v) = str2double(Q.(v));
        end
    end

    Q = Q(~isnat(Q.trade_date) & Q.root_code ~= "" & Q.file_name_clean ~= "", :);
end

function E = load_event_calendar(filePath)

    E = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    required = ["event_date", "event_id", "pr_datetime_local", "pr_datetime_utc"];
    missing = required(~ismember(required, string(E.Properties.VariableNames)));

    if ~isempty(missing)
        error('Missing columns in ecb_event_panel.csv: %s', strjoin(missing, ', '));
    end

    E.event_date = Parse_date_flexible(E.event_date);
    E.pr_datetime_local = Parse_datetime_flexible(E.pr_datetime_local);
    E.pr_datetime_utc = Parse_utc_datetime(E.pr_datetime_utc);
    E.event_id = string(E.event_id);
    E = E(~isnat(E.event_date) & ~isnat(E.pr_datetime_local) & ~isnat(E.pr_datetime_utc), :);
    E = sortrows(E, 'event_date');

    [~, keep] = unique(E.event_date, 'stable');
    E = E(keep, :);
end

function S = load_event_state(filePath)

    S = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');

    if ~ismember("event_date", string(S.Properties.VariableNames))
        error('event_state_panel.csv does not contain event_date.');
    end

    S.event_date = Parse_date_flexible(S.event_date);
    numericVars = ["shock_target_10bp", "target_pca_10bp", "path_pca_10bp", "regime_hike", "state_pre_rv_z"];

    for v = numericVars
        if ismember(v, string(S.Properties.VariableNames)) && ~isnumeric(S.(v))
            S.(v) = str2double(S.(v));
        end
    end

    S = S(~isnat(S.event_date), :);
    S = sortrows(S, 'event_date');

    [~, keep] = unique(S.event_date, 'stable');
    S = S(keep, :);
end

function [W, candidateDiagnostics] = build_counterfactual_windows(Q, E, cleanDir, cfg)

    groupKey = string(Q.trade_date, 'yyyy-MM-dd') + "__" + Q.root_code;
    [G, groupNames] = findgroups(groupKey);
    nGroups = numel(groupNames);

    windowCells = cell(nGroups, 1);
    candidateCells = cell(nGroups, 1);
    fileCache = containers.Map('KeyType', 'char', 'ValueType', 'any');

    eventDateString = string(E.event_date, 'yyyy-MM-dd');

    fprintf('Root-day groups to process: %d\n', nGroups);

    for g = 1:nGroups

        Cands = Q(G == g, :);
        tradeDate = Cands.trade_date(1);
        rootCode = Cands.root_code(1);

        [isEvent, eventLoc] = ismember(string(tradeDate, 'yyyy-MM-dd'), eventDateString);

        if isEvent
            pseudoTimeLocal = E.pr_datetime_local(eventLoc);
            pseudoTimeUtc = E.pr_datetime_utc(eventLoc);
            eventId = E.event_id(eventLoc);
        else
            [pseudoTimeLocal, pseudoTimeUtc] = scheduled_release_datetimes(tradeDate, cfg);
            eventId = "CONTROL_" + string(tradeDate, 'yyyyMMdd');
        end

        nC = height(Cands);
        measures = repmat(empty_measure_struct(), nC, 1);
        preEligible = false(nC, 1);
        preCoverage = nan(nC, 1);
        preVolume = nan(nC, 1);
        fileFound = false(nC, 1);

        for j = 1:nC
            filePath = fullfile(cleanDir, Cands.file_name_clean(j));

            if exist(filePath, 'file') ~= 2
                continue;
            end

            fileFound(j) = true;
            cacheKey = char(filePath);

            if isKey(fileCache, cacheKey)
                C = fileCache(cacheKey);
            else
                C = read_clean_file(filePath);
                fileCache(cacheKey) = C;
            end

            measures(j) = compute_windows(C, pseudoTimeUtc, cfg);
            preCoverage(j) = measures(j).preCoverage;
            preVolume(j) = measures(j).preVolume;
            preEligible(j) = measures(j).preCoverage >= cfg.minPreCoverage & measures(j).nPreReturns >= cfg.minReturnsForBV & isfinite(measures(j).BVpre);
        end

        coverageRank = preCoverage;
        coverageRank(~isfinite(coverageRank)) = -Inf;
        volumeRank = log1p(max(preVolume, 0));
        volumeRank(~isfinite(volumeRank)) = -Inf;
        ranking = table(preEligible, coverageRank, volumeRank, Cands.file_name_clean, 'VariableNames', {'eligible', 'coverage', 'volume', 'file'});
        [~, order] = sortrows(ranking, {'eligible', 'coverage', 'volume', 'file'}, {'descend', 'descend', 'descend', 'ascend'});
        selected = order(1);

        selectedMeasure = measures(selected);
        selectedPreEligible = preEligible(selected);
        selectedPostEligible = selectedMeasure.postCoverage >= cfg.minPostCoverage & selectedMeasure.nPostReturns >= cfg.minReturnsForBV & isfinite(selectedMeasure.BVpost);

        if ~fileFound(selected)
            status = "selected_file_missing";
        elseif ~selectedPreEligible
            status = "no_pre_eligible_contract";
        elseif ~selectedPostEligible
            status = "post_window_ineligible";
        else
            status = "ok";
        end

        windowCells{g} = make_window_row(Cands(selected, :), tradeDate, rootCode, ...
            pseudoTimeLocal, pseudoTimeUtc, eventId, isEvent, status, ...
            selectedMeasure, selectedPreEligible, selectedPostEligible, cfg);

        D = table();
        D.trade_date = repmat(tradeDate, nC, 1);
        D.root_code = repmat(rootCode, nC, 1);
        D.pseudo_pr_datetime_local = repmat(pseudoTimeLocal, nC, 1);
        D.pseudo_pr_datetime_utc = repmat(pseudoTimeUtc, nC, 1);
        D.is_event = repmat(isEvent, nC, 1);
        D.file_name_clean = Cands.file_name_clean;
        D.file_found = fileFound;
        D.pre_eligible = preEligible;
        D.pre_coverage = preCoverage;
        D.pre_volume = preVolume;
        D.post_coverage = arrayfun(@(x) x.postCoverage, measures);
        D.selected = false(nC, 1);
        D.selected(selected) = true;
        candidateCells{g} = D;

        if mod(g, 500) == 0 || g == nGroups
            fprintf('[%5d/%5d] root-days processed\n', g, nGroups);
        end
    end

    W = vertcat(windowCells{:});
    candidateDiagnostics = vertcat(candidateCells{:});
    W = sortrows(W, {'trade_date', 'root_code'});
    candidateDiagnostics = sortrows(candidateDiagnostics, {'trade_date', 'root_code', 'selected', 'pre_coverage'}, {'ascend', 'ascend', 'descend', 'descend'});
end

function [dtLocal, dtUtc] = scheduled_release_datetimes(tradeDate, cfg)

    if tradeDate < cfg.scheduleCutoff
        dtLocal = tradeDate + cfg.earlyReleaseTime;
    else
        dtLocal = tradeDate + cfg.lateReleaseTime;
    end

    dtUtc = Wall_clock_to_utc(dtLocal, cfg.eventTimeZone);
end

function C = read_clean_file(filePath)

    T = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    required = ["Time", "Latest", "Volume"];
    missing = required(~ismember(required, string(T.Properties.VariableNames)));

    if ~isempty(missing)
        error('Missing columns in %s: %s', filePath, strjoin(missing, ', '));
    end

    T.Time = Parse_utc_datetime(T.Time);

    if ~isnumeric(T.Latest); T.Latest = str2double(T.Latest); end
    if ~isnumeric(T.Volume); T.Volume = str2double(T.Volume); end

    C = table();
    C.bar_time = T.Time;
    C.price = T.Latest;
    C.volume = T.Volume;
    C = C(~isnat(C.bar_time) & isfinite(C.price) & C.price > 0, :);
    C = sortrows(C, 'bar_time');
end

function M = compute_windows(C, pseudoTime, cfg)

    M = empty_measure_struct();

    preEndpoints = transpose(pseudoTime + minutes(cfg.preStartMinutes + cfg.barMinutes) : minutes(cfg.barMinutes) : pseudoTime + minutes(cfg.preEndMinutes));
    postEndpoints = transpose(pseudoTime + minutes(cfg.postStartMinutes) : minutes(cfg.barMinutes) : pseudoTime + minutes(cfg.postEndMinutes));
    preVolumeTimes = transpose(pseudoTime + minutes(cfg.preStartMinutes) : minutes(cfg.barMinutes) : pseudoTime + minutes(cfg.preEndMinutes));

    [rPre, M.preCoverage] = returns_on_grid(C, preEndpoints, cfg.barMinutes);
    [rPost, M.postCoverage] = returns_on_grid(C, postEndpoints, cfg.barMinutes);

    M.nPreExpected = numel(preEndpoints);
    M.nPostExpected = numel(postEndpoints);
    M.nPreReturns = sum(isfinite(rPre));
    M.nPostReturns = sum(isfinite(rPost));
    M.preVolume = volume_on_grid(C, preVolumeTimes);

    pre = variation_components(rPre, cfg.minReturnsForBV);
    post = variation_components(rPost, cfg.minReturnsForBV);

    M.RVpre = pre.RV;
    M.BVpre = pre.BV;
    M.JVpre = pre.JV;
    M.jumpSharePre = pre.jumpShare;
    M.RVpost = post.RV;
    M.BVpost = post.BV;
    M.JVpost = post.JV;
    M.jumpSharePost = post.jumpShare;
end

function [r, coverage] = returns_on_grid(C, endpoints, barMinutes)

    endpoints = endpoints(:);
    previousEndpoints = endpoints - minutes(barMinutes);

    [hasCurrent, currentLoc] = ismember(endpoints, C.bar_time);
    [hasPrevious, previousLoc] = ismember(previousEndpoints, C.bar_time);
    valid = hasCurrent & hasPrevious;

    r = nan(numel(endpoints), 1);

    if any(valid)
        currentPrice = C.price(currentLoc(valid));
        previousPrice = C.price(previousLoc(valid));
        goodPrice = isfinite(currentPrice) & isfinite(previousPrice) & currentPrice > 0 & previousPrice > 0;
        validIndex = find(valid);
        validIndex = validIndex(goodPrice);
        r(validIndex) = log(currentPrice(goodPrice)) - log(previousPrice(goodPrice));
    end

    coverage = mean(isfinite(r));
end

function totalVolume = volume_on_grid(C, gridTimes)

    [present, loc] = ismember(gridTimes, C.bar_time);

    if any(present)
        totalVolume = sum(C.volume(loc(present)), 'omitnan');
    else
        totalVolume = NaN;
    end
end

function V = variation_components(r, minReturns)

    V = struct('RV', NaN, 'BV', NaN, 'JV', NaN, 'jumpShare', NaN);
    valid = isfinite(r);

    if sum(valid) < minReturns
        return;
    end

    V.RV = sum(r(valid) .^ 2, 'omitnan');
    adjacent = isfinite(r(2:end)) & isfinite(r(1:end - 1));

    if sum(adjacent) < max(minReturns - 1, 1)
        return;
    end

    V.BV = (pi / 2) * sum(abs(r(2:end)) .* abs(r(1:end - 1)) .* adjacent, 'omitnan');
    V.JV = max(V.RV - V.BV, 0);

    if isfinite(V.RV) && V.RV > 0
        V.jumpShare = V.JV / V.RV;
    end
end

function M = empty_measure_struct()

    M = struct('preCoverage', NaN, 'postCoverage', NaN, 'nPreExpected', NaN, 'nPostExpected', NaN, 'nPreReturns', NaN, 'nPostReturns', NaN, 'preVolume', NaN, 'RVpre', NaN, 'BVpre', NaN, 'JVpre', NaN, 'jumpSharePre', NaN, 'RVpost', NaN, 'BVpost', NaN, 'JVpost', NaN, 'jumpSharePost', NaN);
end

function R = make_window_row(candidate, tradeDate, rootCode, pseudoTimeLocal, pseudoTimeUtc, eventId, isEvent, status, M, preEligible, postEligible, cfg)

    R = table();
    R.trade_date = tradeDate;
    R.event_date = tradeDate;
    R.event_id = string(eventId);
    R.root_code = string(rootCode);
    R.file_name_clean = string(candidate.file_name_clean);
    R.pseudo_pr_datetime_local = pseudoTimeLocal;
    R.pseudo_pr_datetime_utc = pseudoTimeUtc;
    R.is_event = logical(isEvent);
    R.selection_status = string(status);
    R.pre_eligible = logical(preEligible);
    R.post_eligible = logical(postEligible);
    R.window_eligible = logical(preEligible & postEligible);
    R.pre_coverage = M.preCoverage;
    R.post_coverage = M.postCoverage;
    R.n_pre_expected = M.nPreExpected;
    R.n_post_expected = M.nPostExpected;
    R.n_pre_returns = M.nPreReturns;
    R.n_post_returns = M.nPostReturns;
    R.pre_volume = M.preVolume;
    R.RV_pre = M.RVpre;
    R.BV_pre = M.BVpre;
    R.JV_pre = M.JVpre;
    R.jump_share_pre = M.jumpSharePre;
    R.RV_post = M.RVpost;
    R.BV_post = M.BVpost;
    R.JV_post = M.JVpost;
    R.jump_share_post = M.jumpSharePost;
    R.log_RV_pre = positive_log(M.RVpre);
    R.log_BV_pre = positive_log(M.BVpre);
    R.log_RV_post = positive_log(M.RVpost);
    R.log_BV_post = positive_log(M.BVpost);
    R.day_rv = optional_numeric(candidate, "ret_var");
    R.log_day_rv = positive_log(R.day_rv);
    R.root_gg = double(rootCode == "gg");
    R.regime_hike = double(tradeDate >= datetime(2022, 7, 1));
    R.clock_late = double(tradeDate >= cfg.scheduleCutoff);
    R.weekday_number = weekday(tradeDate);
    R.month_number = month(tradeDate);
    R.year_number = year(tradeDate);
end

function x = optional_numeric(T, varName)

    if ismember(varName, string(T.Properties.VariableNames))
        x = T.(varName);
        if isstring(x); x = str2double(x); end
    else
        x = NaN;
    end
end

function y = positive_log(x)

    if isfinite(x) && x > 0
        y = log(x);
    else
        y = NaN;
    end
end

function W = add_slow_state(W, K)

    W = sortrows(W, {'root_code', 'trade_date'});
    W.slow5_log_rv = nan(height(W), 1);
    roots = unique(W.root_code);

    for r = 1:numel(roots)
        idx = find(W.root_code == roots(r));
        values = W.log_day_rv(idx);

        for j = 1:numel(idx)
            previous = find(isfinite(values(1:max(j - 1, 0))), K, 'last');

            if ~isempty(previous)
                W.slow5_log_rv(idx(j)) = mean(values(previous), 'omitnan');
            end
        end
    end
end

function W = merge_event_state(W, S)

    stateVars = ["shock_target_10bp", "target_pca_10bp", "path_pca_10bp", "state_pre_rv_z"];

    for v = stateVars
        W.(v) = nan(height(W), 1);
    end

    [matched, loc] = ismember(string(W.trade_date, 'yyyy-MM-dd'), string(S.event_date, 'yyyy-MM-dd'));

    for v = stateVars
        if ismember(v, string(S.Properties.VariableNames))
            values = S.(v);
            if isstring(values); values = str2double(values); end
            W.(v)(matched) = values(loc(matched));
        end
    end

    W.is_event_with_state = W.is_event & matched;
end

function W = standardize_pre_state_on_controls(W)

    W.pre_state_z = nan(height(W), 1);
    W.pre_state_control_mean = nan(height(W), 1);
    W.pre_state_control_sd = nan(height(W), 1);
    roots = unique(W.root_code);

    for r = 1:numel(roots)
        rootMask = W.root_code == roots(r);
        controlMask = rootMask & ~W.is_event & W.window_eligible & isfinite(W.log_BV_pre);
        mu = mean(W.log_BV_pre(controlMask), 'omitnan');
        sigma = std(W.log_BV_pre(controlMask), 0, 'omitnan');

        if isfinite(sigma) && sigma > 0
            W.pre_state_z(rootMask) = (W.log_BV_pre(rootMask) - mu) ./ sigma;
            W.pre_state_control_mean(rootMask) = mu;
            W.pre_state_control_sd(rootMask) = sigma;
        end
    end
end

function [W, coefficientTable, summaryTable] = fit_normal_counterfactuals(W, specs, cfg)

    coefficientCells = {};
    summaryCells = {};
    roots = unique(W.root_code);

    for s = 1:numel(specs)
        outcome = specs(s).outcome;
        preVar = specs(s).preVar;
        predictionVar = specs(s).prediction;
        abnormalVar = specs(s).abnormal;

        W.(predictionVar) = nan(height(W), 1);
        W.(abnormalVar) = nan(height(W), 1);

        for r = 1:numel(roots)
            rootCode = roots(r);
            rootMask = W.root_code == rootCode;
            trainMask = rootMask & ~W.is_event & W.window_eligible & finite_variables(W, [outcome, preVar, "slow5_log_rv"]);

            if sum(trainMask) < cfg.minimumControlRows
                warning('Too few controls for %s, root %s: %d.', outcome, rootCode, sum(trainMask));
                continue;
            end

            meta = normal_design_meta(W, trainMask, preVar);
            [X, terms] = normal_design(W, trainMask, preVar, meta);
            y = W.(outcome)(trainMask);
            [beta, V, se, tstat, pval, r2, adjR2, residual] = hc3_ols(y, X);

            predictionMask = rootMask & W.window_eligible & finite_variables(W, [preVar, "slow5_log_rv"]);
            Xpred = normal_design(W, predictionMask, preVar, meta);
            predictions = Xpred * beta;
            W.(predictionVar)(predictionMask) = predictions;
            W.(abnormalVar)(predictionMask) = W.(outcome)(predictionMask) - predictions;

            modelName = "NORMAL_" + outcome + "_" + rootCode;
            nTerms = numel(beta);
            C = table();
            C.model_name = repmat(modelName, nTerms, 1);
            C.root_code = repmat(rootCode, nTerms, 1);
            C.outcome = repmat(outcome, nTerms, 1);
            C.term = terms;
            C.beta = beta;
            C.se_hc3 = se;
            C.t_stat = tstat;
            C.p_value = pval;
            C.n_obs = repmat(sum(trainMask), nTerms, 1);
            C.r2 = repmat(r2, nTerms, 1);
            coefficientCells{end + 1, 1} = C;

            [oosR2, oosRMSE, nOos] = leave_year_out_normal(W, trainMask, outcome, preVar);

            M = table();
            M.model_name = modelName;
            M.root_code = rootCode;
            M.outcome = outcome;
            M.pre_variable = preVar;
            M.n_controls = sum(trainMask);
            M.n_parameters = size(X, 2);
            M.rank_design = rank(X);
            M.r2_in_sample = r2;
            M.adj_r2_in_sample = adjR2;
            M.rmse_in_sample = sqrt(mean(residual .^ 2, 'omitnan'));
            M.r2_leave_year_out = oosR2;
            M.rmse_leave_year_out = oosRMSE;
            M.n_leave_year_out = nOos;
            summaryCells{end + 1, 1} = M;
        end
    end

    if isempty(coefficientCells)
        coefficientTable = table();
        summaryTable = table();
    else
        coefficientTable = vertcat(coefficientCells{:});
        summaryTable = vertcat(summaryCells{:});
    end
end

function meta = normal_design_meta(T, mask, preVar)

    meta.preCenter = mean(T.(preVar)(mask), 'omitnan');
    meta.slowCenter = mean(T.slow5_log_rv(mask), 'omitnan');
    rawTrend = days(T.trade_date(mask) - min(T.trade_date(mask)));
    meta.trendOrigin = min(T.trade_date(mask));
    meta.trendCenter = mean(rawTrend, 'omitnan');
end

function [X, terms] = normal_design(T, mask, preVar, meta)

    pre = T.(preVar)(mask) - meta.preCenter;
    slow = T.slow5_log_rv(mask) - meta.slowCenter;
    trend = days(T.trade_date(mask) - meta.trendOrigin) - meta.trendCenter;
    trend = trend ./ 365.25;

    X = [ones(sum(mask), 1), pre, pre .^ 2, slow, T.clock_late(mask), trend];
    terms = ["Intercept"; preVar + "_centered"; preVar + "_centered_sq"; "slow5_log_rv_centered"; "clock_late"; "time_trend_years"];

    weekdayBase = 5;

    for d = 2:6
        if d == weekdayBase; continue; end
        X = [X, double(T.weekday_number(mask) == d)];
        terms(end + 1, 1) = "weekday_" + string(d);
    end

    for m = 2:12
        X = [X, double(T.month_number(mask) == m)];
        terms(end + 1, 1) = "month_" + string(m);
    end
end

function [beta, V, se, tstat, pval, r2, adjR2, residual] = hc3_ols(y, X)

    n = numel(y);
    k = size(X, 2);
    beta = X \ y;
    residual = y - X * beta;
    XtXi = pinv(X' * X);
    leverage = sum((X * XtXi) .* X, 2);
    adjustedResidual = residual ./ max(1 - leverage, 1e-8);
    Xu = X .* adjustedResidual;
    V = XtXi * (Xu' * Xu) * XtXi;
    se = sqrt(max(diag(V), 0));
    tstat = beta ./ se;
    df = max(n - k, 1);
    pval = 2 * tcdf(-abs(tstat), df);
    sse = residual' * residual;
    tss = sum((y - mean(y, 'omitnan')) .^ 2);
    r2 = 1 - sse / tss;
    adjR2 = 1 - (1 - r2) * (n - 1) / max(n - k, 1);
end

function [oosR2, oosRMSE, nOos] = leave_year_out_normal(T, baseMask, outcome, preVar)

    years = unique(T.year_number(baseMask));
    prediction = nan(height(T), 1);

    for y = transpose(years)
        testMask = baseMask & T.year_number == y;
        trainMask = baseMask & T.year_number ~= y;

        if sum(testMask) == 0 || sum(trainMask) < 50
            continue;
        end

        meta = normal_design_meta(T, trainMask, preVar);
        Xtrain = normal_design(T, trainMask, preVar, meta);
        Xtest = normal_design(T, testMask, preVar, meta);
        beta = Xtrain \ T.(outcome)(trainMask);
        prediction(testMask) = Xtest * beta;
    end

    valid = baseMask & isfinite(prediction);
    nOos = sum(valid);

    if nOos == 0
        oosR2 = NaN;
        oosRMSE = NaN;
        return;
    end

    y = T.(outcome)(valid);
    err = y - prediction(valid);
    oosRMSE = sqrt(mean(err .^ 2, 'omitnan'));
    tss = sum((y - mean(y, 'omitnan')) .^ 2);
    oosR2 = 1 - sum(err .^ 2) / tss;
end

function mask = finite_variables(T, vars)

    mask = true(height(T), 1);

    for v = vars
        x = T.(v);
        if isstring(x); x = str2double(x); end
        mask = mask & isfinite(x);
    end
end

function [coefficientTable, summaryTable, equivalenceTable, effectTable] = fit_event_models(W, cfg)

    specs = struct('name', {}, 'outcome', {}, 'q', {}, 'interaction', {}, 'root', {});
    outcomes = ["abnormal_log_BV", "abnormal_log_RV", "abnormal_jump_share"];

    for o = outcomes
        specs(end + 1) = make_event_spec("CF_TARGET_" + o + "_pooled", o, "q_target", "q_target_x_pre", "pooled");
    end

    specs(end + 1) = make_event_spec("CF_FACTOR_abnormal_log_BV_pooled", "abnormal_log_BV", "q_factor", "q_factor_x_pre", "pooled");
    specs(end + 1) = make_event_spec("CF_TARGET_abnormal_log_BV_fx", "abnormal_log_BV", "q_target", "q_target_x_pre", "fx");
    specs(end + 1) = make_event_spec("CF_TARGET_abnormal_log_BV_gg", "abnormal_log_BV", "q_target", "q_target_x_pre", "gg");

    coefficientCells = {};
    summaryCells = {};
    equivalenceCells = {};
    effectCells = {};

    for s = 1:numel(specs)
        spec = specs(s);

        if spec.root == "pooled"
            rootMask = true(height(W), 1);
            rhs = [spec.q, "pre_state_z", spec.interaction, "regime_hike", "root_gg"];
        else
            rootMask = W.root_code == spec.root;
            rhs = [spec.q, "pre_state_z", spec.interaction, "regime_hike"];
        end

        mask = W.is_event_with_state & W.window_eligible & rootMask & finite_variables(W, [spec.outcome, rhs]);
        nClusters = numel(unique(W.trade_date(mask)));

        if nClusters < cfg.minimumEventClusters
            warning('Skipping %s: only %d usable event clusters.', spec.name, nClusters);
            continue;
        end

        y = W.(spec.outcome)(mask);
        X = ones(sum(mask), 1);
        terms = "Intercept";

        for v = rhs
            X = [X, W.(v)(mask)];
            terms(end + 1, 1) = v;
        end

        clusters = string(W.trade_date(mask), 'yyyy-MM-dd');
        [beta, V, se, tstat, pval, G, r2, adjR2] = cluster_ols_core(y, X, clusters);
        pWild = nan(numel(beta), 1);

        for targetTerm = [spec.q, spec.interaction]
            j = find(terms == targetTerm, 1);
            pWild(j) = wild_cluster_pvalue(y, X, clusters, j, tstat(j), cfg.bootstrapRep);
        end

        crit = tinv(0.975, max(G - 1, 1));
        C = table();
        C.model_name = repmat(spec.name, numel(beta), 1);
        C.outcome = repmat(spec.outcome, numel(beta), 1);
        C.term = terms;
        C.beta = beta;
        C.se_cluster = se;
        C.t_stat = tstat;
        C.p_value = pval;
        C.p_wild_cluster = pWild;
        C.ci95_lo = beta - crit * se;
        C.ci95_hi = beta + crit * se;
        C.n_obs = repmat(numel(y), numel(beta), 1);
        C.n_clusters = repmat(G, numel(beta), 1);
        C.r2 = repmat(r2, numel(beta), 1);
        coefficientCells{end + 1, 1} = C;

        M = table();
        M.model_name = spec.name;
        M.outcome = spec.outcome;
        M.shock_measure = spec.q;
        M.root_sample = spec.root;
        M.n_obs = numel(y);
        M.n_clusters = G;
        M.n_parameters = size(X, 2);
        M.rank_design = rank(X);
        M.r2 = r2;
        M.adj_r2 = adjR2;
        summaryCells{end + 1, 1} = M;

        jInteraction = find(terms == spec.interaction, 1);

        if contains(spec.outcome, "log")
            equivalenceCells{end + 1, 1} = equivalence_test(spec.name, spec.interaction, beta(jInteraction), se(jInteraction), G - 1, cfg.equivalenceLogMargin);
        end

        jQ = find(terms == spec.q, 1);
        effectCells{end + 1, 1} = conditional_effects(spec.name, spec.outcome, beta, V, jQ, jInteraction, G - 1);
    end

    if isempty(coefficientCells)
        coefficientTable = table();
        summaryTable = table();
        equivalenceTable = table();
        effectTable = table();
    else
        coefficientTable = vertcat(coefficientCells{:});
        summaryTable = vertcat(summaryCells{:});
        effectTable = vertcat(effectCells{:});

        if isempty(equivalenceCells)
            equivalenceTable = table();
        else
            equivalenceTable = vertcat(equivalenceCells{:});
        end
    end
end

function s = make_event_spec(name, outcome, q, interaction, root)

    s = struct('name', string(name), 'outcome', string(outcome), 'q', string(q), 'interaction', string(interaction), 'root', string(root));
end

function [beta, V, se, tstat, pval, G, r2, adjR2] = cluster_ols_core(y, X, clusters)

    n = numel(y);
    k = size(X, 2);
    beta = X \ y;
    residual = y - X * beta;
    clusterId = findgroups(clusters);
    G = max(clusterId);
    XtXi = pinv(X' * X);
    meat = zeros(k, k);

    for g = 1:G
        idx = clusterId == g;
        score = X(idx, :)' * residual(idx);
        meat = meat + score * score';
    end

    correction = (G / max(G - 1, 1)) * ((n - 1) / max(n - k, 1));
    V = correction * XtXi * meat * XtXi;
    se = sqrt(max(diag(V), 0));
    tstat = beta ./ se;
    pval = 2 * tcdf(-abs(tstat), max(G - 1, 1));
    sse = residual' * residual;
    tss = sum((y - mean(y, 'omitnan')) .^ 2);
    r2 = 1 - sse / tss;
    adjR2 = 1 - (1 - r2) * (n - 1) / max(n - k, 1);
end

function p = wild_cluster_pvalue(y, X, clusters, testedColumn, observedT, B)

    if ~isfinite(observedT)
        p = NaN;
        return;
    end

    keep = setdiff(1:size(X, 2), testedColumn);
    X0 = X(:, keep);
    beta0 = X0 \ y;
    fitted0 = X0 * beta0;
    residual0 = y - fitted0;
    clusterId = findgroups(clusters);
    G = max(clusterId);
    exceed = 0;
    usable = 0;

    for b = 1:B
        weights = 2 * (rand(G, 1) >= 0.5) - 1;
        yStar = fitted0 + residual0 .* weights(clusterId);
        [betaStar, VStar] = cluster_ols_core(yStar, X, clusters);
        seStar = sqrt(max(VStar(testedColumn, testedColumn), 0));

        if isfinite(seStar) && seStar > 0
            tStar = betaStar(testedColumn) / seStar;
            exceed = exceed + double(abs(tStar) >= abs(observedT));
            usable = usable + 1;
        end
    end

    p = (1 + exceed) / (1 + usable);
end

function T = equivalence_test(modelName, termName, estimate, se, df, margin)

    tLower = (estimate + margin) / se;
    tUpper = (estimate - margin) / se;
    pLower = 1 - tcdf(tLower, max(df, 1));
    pUpper = tcdf(tUpper, max(df, 1));
    pTost = max(pLower, pUpper);
    crit90 = tinv(0.95, max(df, 1));
    ci90Lo = estimate - crit90 * se;
    ci90Hi = estimate + crit90 * se;

    T = table();
    T.model_name = string(modelName);
    T.term = string(termName);
    T.estimate = estimate;
    T.se_cluster = se;
    T.margin_log_points = margin;
    T.margin_multiplier_ratio = exp(margin);
    T.ci90_lo = ci90Lo;
    T.ci90_hi = ci90Hi;
    T.p_tost = pTost;
    T.equivalent_at_5pct = pTost < 0.05;
end

function T = conditional_effects(modelName, outcome, beta, V, jQ, jInteraction, df)

    stateValues = [-1; 0; 1];
    n = numel(stateValues);
    estimate = nan(n, 1);
    se = nan(n, 1);
    ci95Lo = nan(n, 1);
    ci95Hi = nan(n, 1);
    relativeFactor = nan(n, 1);
    crit = tinv(0.975, max(df, 1));

    for i = 1:n
        L = zeros(numel(beta), 1);
        L(jQ) = 1;
        L(jInteraction) = stateValues(i);
        estimate(i) = L' * beta;
        se(i) = sqrt(max(L' * V * L, 0));
        ci95Lo(i) = estimate(i) - crit * se(i);
        ci95Hi(i) = estimate(i) + crit * se(i);
        if contains(string(outcome), "log")
            relativeFactor(i) = exp(estimate(i)) - 1;
        end
    end

    T = table();
    T.model_name = repmat(string(modelName), n, 1);
    T.outcome = repmat(string(outcome), n, 1);
    T.pre_state_z = stateValues;
    T.effect_per_unit_shock_energy = estimate;
    T.se = se;
    T.ci95_lo = ci95Lo;
    T.ci95_hi = ci95Hi;
    T.implied_relative_change = relativeFactor;
end

function T = format_dates_for_write(T)

    vars = string(T.Properties.VariableNames);

    for v = vars
        if isdatetime(T.(v))
            if contains(lower(v), "datetime") || contains(lower(v), "time")
                T.(v) = string(T.(v), 'yyyy-MM-dd HH:mm:ss');
            else
                T.(v) = string(T.(v), 'yyyy-MM-dd');
            end
        end
    end
end
