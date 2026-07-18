%% STEP 20: SPECTRAL TEST OF ANNOUNCEMENT RISK ROTATION.
%
% The previous counterfactual stages show that squared monetary surprises do
% not robustly explain abnormal post-release volatility.  They also reveal a
% stable cross-asset contrast: post-release variation is relatively larger in
% Euro Bund futures (root gg) than in Euro Stoxx 50 futures (root fx).
%
% This script turns that contrast into a pre-declared matrix experiment.  For
% every date on which both roots are observed, it reconstructs ten paired
% five-minute returns before and after the scheduled release clock and forms
% the standardized realized second-moment matrices
%
%       Q_pre(d)  = mean_m r_pre(d,m)  r_pre(d,m)'
%       Q_post(d) = mean_m r_post(d,m) r_post(d,m)'.
%
% Returns are scaled once, using non-ECB dates only, so that the equity and
% bond diagonal elements are expressed in comparable normal-volatility units.
% The date-level change D(d) = Q_post(d) - Q_pre(d) is compared with ten
% paired non-event dates having the same scheduled-clock regime and weekday,
% matched on the pre-window covariance matrix, slow volatility and calendar
% proximity.  The average abnormal matrix A is then decomposed spectrally.
%
% Under the additive one-shock null, with an unchanged background covariance,
%
%       A = sigma_u^2 b b'
%
% is positive semidefinite and has rank at most one.  A significantly positive
% largest eigenvalue together with a significantly negative smallest
% eigenvalue rejects that null and is consistent with risk creation in one
% cross-asset direction and uncertainty resolution in another.
%
% Inference is deliberately date-level.  A nonparametric event bootstrap
% reports confidence intervals.  Matched placebos draw a pseudo-event from
% every event's own control set and compare it with the remaining controls.
% The script does not use the realized monetary-surprise magnitude to form the
% matrix or the matches; q_target is carried to the output only for secondary
% mechanism and support checks.

clear; clc;

% Step 20 is an incremental analysis: it only needs the cleaned bars and
% the Step-18 window panel under Output/.  When the runner supplies an
% explicit ECONOMETRICS_DATA_ROOT, use it directly instead of requiring the
% full replication package (and, in particular, a Raw/ directory).
projectRoot = getenv('ECONOMETRICS_DATA_ROOT');
if isempty(projectRoot)
    projectRoot = Get_project_root();
elseif exist(fullfile(projectRoot, 'Output'), 'dir') ~= 7
    error(['ECONOMETRICS_DATA_ROOT does not contain Output/: %s. ' ...
        'Pass the project directory that contains Output/analysis and Output/cleaned.'], ...
        projectRoot);
end

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
cleanDir = fullfile(projectRoot, 'Output', 'cleaned');
windowFile = fullfile(analysisDir, 'announcement_counterfactual_windows.csv');

if exist(windowFile, 'file') ~= 2
    error('Required Step-18 input not found: %s', windowFile);
end

cfg = struct();
cfg.barMinutes = 5;
cfg.preEndpoints = -50:5:-5;
cfg.postEndpoints = 0:5:45;
cfg.minPairedReturns = 8;
cfg.nMatches = 10;
cfg.matchMaxYears = 2;
cfg.calendarWeight = 0.20;
cfg.bootstrapRep = 999;
cfg.placeboRep = 999;
cfg.seed = 20260718;

drawOverride = str2double(getenv('ANNOUNCEMENT_ROTATION_DRAWS'));
if isfinite(drawOverride) && drawOverride >= 19
    cfg.bootstrapRep = floor(drawOverride);
    cfg.placeboRep = floor(drawOverride);
end

rng(cfg.seed, 'twister');

W = load_window_panel(windowFile);
[P, returnStore] = build_paired_return_panel(W, cleanDir, cfg);

if isempty(P)
    error('No paired FX/GG dates with sufficient exact-grid returns were found.');
end

[P, scaleFx, scaleGg] = standardize_and_build_matrices(P, returnStore);
P = add_matching_features(P);

eventMask = P.is_event;
controlMask = ~P.is_event;

if sum(eventMask) < 30 || sum(controlMask) < 100
    error('Insufficient paired event/control dates: events=%d, controls=%d.', sum(eventMask), sum(controlMask));
end

[matchedRows, matchSets] = construct_matched_abnormal_matrices(P, cfg);

if isempty(matchedRows)
    error('No event retained a valid paired non-event match set.');
end

[summaryTable, observed] = summarize_observed_matrix(matchedRows, scaleFx, scaleGg);
bootstrapTable = bootstrap_spectrum(matchedRows, observed, cfg);
placeboTable = matched_placebo_spectrum(P, matchedRows, matchSets, observed, cfg);
leaveOneOutTable = leave_one_event_out_spectrum(matchedRows);
summaryTable = append_inference(summaryTable, bootstrapTable, placeboTable, ...
    leaveOneOutTable, observed, cfg);

dateFile = fullfile(analysisDir, 'announcement_rotation_date_matrices.csv');
matchedFile = fullfile(analysisDir, 'announcement_rotation_matched_rows.csv');
summaryFile = fullfile(analysisDir, 'announcement_rotation_summary.csv');
bootstrapFile = fullfile(analysisDir, 'announcement_rotation_bootstrap.csv');
placeboFile = fullfile(analysisDir, 'announcement_rotation_placebo.csv');
leaveOneOutFile = fullfile(analysisDir, 'announcement_rotation_leave_one_out.csv');

writetable(format_dates_for_write(P), dateFile);
writetable(format_dates_for_write(matchedRows), matchedFile);
writetable(summaryTable, summaryFile);
writetable(bootstrapTable, bootstrapFile);
writetable(placeboTable, placeboFile);
writetable(format_dates_for_write(leaveOneOutTable), leaveOneOutFile);

fprintf('\n================ ANNOUNCEMENT RISK ROTATION ================\n');
fprintf('Paired eligible dates          : %d\n', height(P));
fprintf('Paired ECB dates               : %d\n', sum(P.is_event));
fprintf('Matched ECB dates              : %d\n', height(matchedRows));
fprintf('Control-only return scales     : fx %.6g, gg %.6g\n', scaleFx, scaleGg);
fprintf('Abnormal matrix [fx, gg]       : [% .4f % .4f; % .4f % .4f]\n', ...
    observed.A(1, 1), observed.A(1, 2), observed.A(2, 1), observed.A(2, 2));
fprintf('Eigenvalues                    : lambda+ % .4f, lambda- % .4f\n', ...
    observed.lambdaPlus, observed.lambdaMinus);
fprintf('Positive eigenvector [fx, gg]  : [% .4f, % .4f]\n', observed.vPlus(1), observed.vPlus(2));
fprintf('Negative eigenvector [fx, gg]  : [% .4f, % .4f]\n', observed.vMinus(1), observed.vMinus(2));
fprintf('Summary                        : %s\n', summaryFile);
fprintf('Leave-one-event-out spectrum   : %s\n', leaveOneOutFile);
fprintf('============================================================\n');


function W = load_window_panel(filePath)

    W = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    required = ["trade_date", "root_code", "file_name_clean", "pseudo_pr_datetime", ...
        "is_event", "window_eligible", "clock_late", "weekday_number", "year_number"];
    missing = required(~ismember(required, string(W.Properties.VariableNames)));

    if ~isempty(missing)
        error('Step-18 window panel is missing: %s', strjoin(missing, ', '));
    end

    W.trade_date = Parse_date_flexible(W.trade_date);
    W.pseudo_pr_datetime = Parse_datetime_flexible(W.pseudo_pr_datetime);
    W.root_code = lower(string(W.root_code));
    W.file_name_clean = string(W.file_name_clean);

    numericVars = ["is_event", "window_eligible", "clock_late", "weekday_number", ...
        "year_number", "slow5_log_rv", "q_target", "shock_target_10bp", ...
        "regime_hike", "pre_state_z"];

    for v = numericVars
        if ismember(v, string(W.Properties.VariableNames)) && ...
                ~isnumeric(W.(v)) && ~islogical(W.(v))
            W.(v) = str2double(W.(v));
        end
    end

    W = W(~isnat(W.trade_date) & ~isnat(W.pseudo_pr_datetime), :);
    W = W(ismember(W.root_code, ["fx", "gg"]) & W.window_eligible == 1, :);
    W = sortrows(W, {'trade_date', 'root_code'});
end


function [P, store] = build_paired_return_panel(W, cleanDir, cfg)

    dates = unique(W.trade_date);
    rows = cell(numel(dates), 1);
    store = cell(numel(dates), 1);
    fileCache = containers.Map('KeyType', 'char', 'ValueType', 'any');

    for d = 1:numel(dates)
        X = W(W.trade_date == dates(d), :);
        fx = X(X.root_code == "fx", :);
        gg = X(X.root_code == "gg", :);

        if height(fx) ~= 1 || height(gg) ~= 1
            continue;
        end

        if fx.pseudo_pr_datetime(1) ~= gg.pseudo_pr_datetime(1)
            continue;
        end

        [Cfx, fileCache] = cached_clean_file(fullfile(cleanDir, fx.file_name_clean(1)), fileCache);
        [Cgg, fileCache] = cached_clean_file(fullfile(cleanDir, gg.file_name_clean(1)), fileCache);

        if isempty(Cfx) || isempty(Cgg)
            continue;
        end

        pseudoTime = fx.pseudo_pr_datetime(1);
        preGrid = pseudoTime + minutes(cfg.preEndpoints);
        postGrid = pseudoTime + minutes(cfg.postEndpoints);
        rFxPre = returns_on_grid(Cfx, preGrid, cfg.barMinutes);
        rGgPre = returns_on_grid(Cgg, preGrid, cfg.barMinutes);
        rFxPost = returns_on_grid(Cfx, postGrid, cfg.barMinutes);
        rGgPost = returns_on_grid(Cgg, postGrid, cfg.barMinutes);

        validPre = isfinite(rFxPre) & isfinite(rGgPre);
        validPost = isfinite(rFxPost) & isfinite(rGgPost);

        if sum(validPre) < cfg.minPairedReturns || sum(validPost) < cfg.minPairedReturns
            continue;
        end

        R = table();
        R.trade_date = dates(d);
        R.pseudo_pr_datetime = pseudoTime;
        R.is_event = logical(fx.is_event(1));
        R.clock_late = fx.clock_late(1);
        R.weekday_number = fx.weekday_number(1);
        R.year_number = fx.year_number(1);
        R.regime_hike = optional_scalar(fx, "regime_hike");
        R.q_target = optional_scalar(fx, "q_target");
        if ~isfinite(R.q_target)
            shock = optional_scalar(fx, "shock_target_10bp");
            R.q_target = shock .^ 2;
        end
        R.pre_state_fx = optional_scalar(fx, "pre_state_z");
        R.pre_state_gg = optional_scalar(gg, "pre_state_z");
        R.slow_fx = optional_scalar(fx, "slow5_log_rv");
        R.slow_gg = optional_scalar(gg, "slow5_log_rv");
        R.n_pre_pairs = sum(validPre);
        R.n_post_pairs = sum(validPost);
        R.file_fx = fx.file_name_clean(1);
        R.file_gg = gg.file_name_clean(1);

        S = struct();
        S.fxPre = rFxPre(validPre);
        S.ggPre = rGgPre(validPre);
        S.fxPost = rFxPost(validPost);
        S.ggPost = rGgPost(validPost);

        rows{d} = R;
        store{d} = S;
    end

    keep = ~cellfun(@isempty, rows);
    P = vertcat(rows{keep});
    store = store(keep);

    if ~isempty(P)
        P.store_index = transpose(1:height(P));
        P = sortrows(P, 'trade_date');
        store = store(P.store_index);
        P.store_index = transpose(1:height(P));
    end
end


function [C, cache] = cached_clean_file(filePath, cache)

    key = char(filePath);
    if isKey(cache, key)
        C = cache(key);
        return;
    end

    if exist(filePath, 'file') ~= 2
        C = table();
        cache(key) = C;
        return;
    end

    T = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    if ~all(ismember(["Time", "Latest"], string(T.Properties.VariableNames)))
        C = table();
        cache(key) = C;
        return;
    end

    T.Time = Parse_datetime_flexible(T.Time);
    if ~isnumeric(T.Latest); T.Latest = str2double(T.Latest); end

    C = table(T.Time, T.Latest, 'VariableNames', {'bar_time', 'price'});
    C = C(~isnat(C.bar_time) & isfinite(C.price) & C.price > 0, :);
    C = sortrows(C, 'bar_time');
    [~, uniqueLoc] = unique(C.bar_time, 'last');
    C = C(sort(uniqueLoc), :);
    cache(key) = C;
end


function r = returns_on_grid(C, endpoints, barMinutes)

    endpoints = endpoints(:);
    previous = endpoints - minutes(barMinutes);
    [hasNow, nowLoc] = ismember(endpoints, C.bar_time);
    [hasLag, lagLoc] = ismember(previous, C.bar_time);
    valid = hasNow & hasLag;
    r = nan(numel(endpoints), 1);

    if any(valid)
        idx = find(valid);
        pNow = C.price(nowLoc(valid));
        pLag = C.price(lagLoc(valid));
        good = isfinite(pNow) & isfinite(pLag) & pNow > 0 & pLag > 0;
        r(idx(good)) = log(pNow(good)) - log(pLag(good));
    end
end


function [P, scaleFx, scaleGg] = standardize_and_build_matrices(P, store)

    control = find(~P.is_event);
    fxValues = [];
    ggValues = [];

    for j = transpose(control)
        S = store{P.store_index(j)};
        fxValues = [fxValues; S.fxPre; S.fxPost]; %#ok<AGROW>
        ggValues = [ggValues; S.ggPre; S.ggPost]; %#ok<AGROW>
    end

    scaleFx = sqrt(mean(fxValues .^ 2, 'omitnan'));
    scaleGg = sqrt(mean(ggValues .^ 2, 'omitnan'));

    if ~isfinite(scaleFx) || ~isfinite(scaleGg) || scaleFx <= 0 || scaleGg <= 0
        error('Control-only return scales are invalid.');
    end

    matrixVars = ["qpre_11", "qpre_12", "qpre_22", "qpost_11", "qpost_12", ...
        "qpost_22", "d_11", "d_12", "d_22"];
    for v = matrixVars; P.(v) = nan(height(P), 1); end

    for j = 1:height(P)
        S = store{P.store_index(j)};
        pre = [S.fxPre ./ scaleFx, S.ggPre ./ scaleGg];
        post = [S.fxPost ./ scaleFx, S.ggPost ./ scaleGg];
        Qpre = (pre' * pre) ./ size(pre, 1);
        Qpost = (post' * post) ./ size(post, 1);
        D = Qpost - Qpre;
        P.qpre_11(j) = Qpre(1, 1);
        P.qpre_12(j) = Qpre(1, 2);
        P.qpre_22(j) = Qpre(2, 2);
        P.qpost_11(j) = Qpost(1, 1);
        P.qpost_12(j) = Qpost(1, 2);
        P.qpost_22(j) = Qpost(2, 2);
        P.d_11(j) = D(1, 1);
        P.d_12(j) = D(1, 2);
        P.d_22(j) = D(2, 2);
    end
end


function P = add_matching_features(P)

    P.feature_log_fx_pre = log(max(P.qpre_11, realmin));
    P.feature_log_gg_pre = log(max(P.qpre_22, realmin));
    P.feature_pre_corr = P.qpre_12 ./ sqrt(max(P.qpre_11 .* P.qpre_22, realmin));
    P.feature_pre_corr = min(max(P.feature_pre_corr, -0.999), 0.999);
    P.feature_pre_corr = atanh(P.feature_pre_corr);

    features = ["feature_log_fx_pre", "feature_log_gg_pre", "feature_pre_corr", "slow_fx", "slow_gg"];
    control = ~P.is_event;

    for v = features
        values = P.(v);
        mu = mean(values(control), 'omitnan');
        sd = std(values(control), 0, 'omitnan');
        if ~isfinite(sd) || sd <= 0; sd = 1; end
        values = (values - mu) ./ sd;
        values(~isfinite(values)) = 0;
        P.("match_" + v) = values;
    end
end


function [M, matchSets] = construct_matched_abnormal_matrices(P, cfg)

    eventIdx = find(P.is_event);
    controlIdx = find(~P.is_event);
    featureNames = ["match_feature_log_fx_pre", "match_feature_log_gg_pre", ...
        "match_feature_pre_corr", "match_slow_fx", "match_slow_gg"];
    featureMatrix = P{:, cellstr(featureNames)};
    rows = cell(numel(eventIdx), 1);
    matchSets = cell(numel(eventIdx), 1);

    for j = 1:numel(eventIdx)
        e = eventIdx(j);
        yearDistance = abs(P.year_number(controlIdx) - P.year_number(e));
        matchRule = "clock_weekday_two_year";
        eligible = controlIdx(P.clock_late(controlIdx) == P.clock_late(e) & ...
            P.weekday_number(controlIdx) == P.weekday_number(e) & ...
            yearDistance <= cfg.matchMaxYears);

        if numel(eligible) < cfg.nMatches
            matchRule = "clock_two_year";
            eligible = controlIdx(P.clock_late(controlIdx) == P.clock_late(e) & ...
                yearDistance <= cfg.matchMaxYears);
        end

        if numel(eligible) < cfg.nMatches
            matchRule = "clock_weekday_all_years";
            eligible = controlIdx(P.clock_late(controlIdx) == P.clock_late(e) & ...
                P.weekday_number(controlIdx) == P.weekday_number(e));
        end

        if numel(eligible) < cfg.nMatches
            matchRule = "clock_all_years";
            eligible = controlIdx(P.clock_late(controlIdx) == P.clock_late(e));
        end

        if isempty(eligible)
            continue;
        end

        delta = featureMatrix(eligible, :) - featureMatrix(e, :);
        distance = sum(delta .^ 2, 2) + cfg.calendarWeight .* ...
            ((P.year_number(eligible) - P.year_number(e)) ./ 5) .^ 2;
        [distance, order] = sort(distance, 'ascend');
        take = min(cfg.nMatches, numel(order));
        matches = eligible(order(1:take));
        matchSets{j} = matches;

        eventD = matrix_from_row(P, e, "d");
        controlD = mean_matrix(P, matches, "d");
        A = eventD - controlD;

        R = table();
        R.trade_date = P.trade_date(e);
        R.event_index = e;
        R.n_matches = take;
        R.match_rule = matchRule;
        R.match_dates = strjoin(string(P.trade_date(matches), 'yyyy-MM-dd'), '|');
        R.mean_match_distance = mean(distance(1:take), 'omitnan');
        R.mean_match_year_gap = mean(abs(P.year_number(matches) - P.year_number(e)), 'omitnan');
        R.q_target = P.q_target(e);
        R.regime_hike = P.regime_hike(e);
        R.event_d11 = eventD(1, 1);
        R.event_d12 = eventD(1, 2);
        R.event_d22 = eventD(2, 2);
        R.control_d11 = controlD(1, 1);
        R.control_d12 = controlD(1, 2);
        R.control_d22 = controlD(2, 2);
        R.abnormal_11 = A(1, 1);
        R.abnormal_12 = A(1, 2);
        R.abnormal_22 = A(2, 2);
        R.rotation_gg_minus_fx = A(2, 2) - A(1, 1);
        rows{j} = R;
    end

    keep = ~cellfun(@isempty, rows);
    M = vertcat(rows{keep});
    matchSets = matchSets(keep);
end


function [S, observed] = summarize_observed_matrix(M, scaleFx, scaleGg)

    A = [mean(M.abnormal_11, 'omitnan'), mean(M.abnormal_12, 'omitnan'); ...
        mean(M.abnormal_12, 'omitnan'), mean(M.abnormal_22, 'omitnan')];
    observed = spectral_decomposition(A);
    observed.rotation = A(2, 2) - A(1, 1);

    metric = ["n_events"; "control_scale_fx"; "control_scale_gg"; ...
        "A_fx_fx"; "A_fx_gg"; "A_gg_gg"; "trace_A"; "determinant_A"; ...
        "lambda_plus"; "lambda_minus"; "vplus_fx"; "vplus_gg"; ...
        "vminus_fx"; "vminus_gg"; "mean_rotation_gg_minus_fx"];
    value = [height(M); scaleFx; scaleGg; A(1, 1); A(1, 2); A(2, 2); ...
        trace(A); det(A); observed.lambdaPlus; observed.lambdaMinus; ...
        observed.vPlus(1); observed.vPlus(2); observed.vMinus(1); observed.vMinus(2); ...
        observed.rotation];
    S = table(metric, value);
end


function B = bootstrap_spectrum(M, observed, cfg)

    n = height(M);
    lambdaPlus = nan(cfg.bootstrapRep, 1);
    lambdaMinus = nan(cfg.bootstrapRep, 1);
    vplusFx = nan(cfg.bootstrapRep, 1);
    vplusGg = nan(cfg.bootstrapRep, 1);
    vminusFx = nan(cfg.bootstrapRep, 1);
    vminusGg = nan(cfg.bootstrapRep, 1);
    AfxFx = nan(cfg.bootstrapRep, 1);
    AfxGg = nan(cfg.bootstrapRep, 1);
    AggGg = nan(cfg.bootstrapRep, 1);
    rotation = nan(cfg.bootstrapRep, 1);

    for b = 1:cfg.bootstrapRep
        idx = randi(n, n, 1);
        A = [mean(M.abnormal_11(idx)), mean(M.abnormal_12(idx)); ...
            mean(M.abnormal_12(idx)), mean(M.abnormal_22(idx))];
        sp = spectral_decomposition(A);
        if dot(sp.vPlus, observed.vPlus) < 0; sp.vPlus = -sp.vPlus; end
        if dot(sp.vMinus, observed.vMinus) < 0; sp.vMinus = -sp.vMinus; end
        lambdaPlus(b) = sp.lambdaPlus;
        lambdaMinus(b) = sp.lambdaMinus;
        vplusFx(b) = sp.vPlus(1);
        vplusGg(b) = sp.vPlus(2);
        vminusFx(b) = sp.vMinus(1);
        vminusGg(b) = sp.vMinus(2);
        AfxFx(b) = A(1, 1);
        AfxGg(b) = A(1, 2);
        AggGg(b) = A(2, 2);
        rotation(b) = A(2, 2) - A(1, 1);
    end

    B = table((1:cfg.bootstrapRep)', lambdaPlus, lambdaMinus, vplusFx, vplusGg, ...
        vminusFx, vminusGg, AfxFx, AfxGg, AggGg, rotation, ...
        'VariableNames', {'draw', 'lambda_plus', 'lambda_minus', ...
        'vplus_fx', 'vplus_gg', 'vminus_fx', 'vminus_gg', ...
        'A_fx_fx', 'A_fx_gg', 'A_gg_gg', 'rotation_gg_minus_fx'});
    B.observed_lambda_plus = repmat(observed.lambdaPlus, height(B), 1);
    B.observed_lambda_minus = repmat(observed.lambdaMinus, height(B), 1);
end


function R = matched_placebo_spectrum(P, M, matchSets, observed, cfg)

    lambdaPlus = nan(cfg.placeboRep, 1);
    lambdaMinus = nan(cfg.placeboRep, 1);
    rotation = nan(cfg.placeboRep, 1);

    for b = 1:cfg.placeboRep
        a11 = nan(height(M), 1);
        a12 = nan(height(M), 1);
        a22 = nan(height(M), 1);

        for j = 1:height(M)
            matches = matchSets{j};
            chosenLoc = randi(numel(matches));
            chosen = matches(chosenLoc);
            remaining = matches;
            remaining(chosenLoc) = [];

            if isempty(remaining)
                remaining = matches;
            end

            pseudoEvent = matrix_from_row(P, chosen, "d");
            pseudoControl = mean_matrix(P, remaining, "d");
            A = pseudoEvent - pseudoControl;
            a11(j) = A(1, 1);
            a12(j) = A(1, 2);
            a22(j) = A(2, 2);
        end

        Abar = [mean(a11, 'omitnan'), mean(a12, 'omitnan'); ...
            mean(a12, 'omitnan'), mean(a22, 'omitnan')];
        sp = spectral_decomposition(Abar);
        lambdaPlus(b) = sp.lambdaPlus;
        lambdaMinus(b) = sp.lambdaMinus;
        rotation(b) = Abar(2, 2) - Abar(1, 1);
    end

    R = table((1:cfg.placeboRep)', lambdaPlus, lambdaMinus, rotation, ...
        'VariableNames', {'draw', 'lambda_plus', 'lambda_minus', 'rotation_gg_minus_fx'});
    R.observed_lambda_plus = repmat(observed.lambdaPlus, height(R), 1);
    R.observed_lambda_minus = repmat(observed.lambdaMinus, height(R), 1);
end


function L = leave_one_event_out_spectrum(M)

    n = height(M);
    L = table();
    L.excluded_trade_date = M.trade_date;
    L.excluded_q_target = M.q_target;
    L.lambda_plus = nan(n, 1);
    L.lambda_minus = nan(n, 1);
    L.rotation_gg_minus_fx = nan(n, 1);
    L.A_fx_fx = nan(n, 1);
    L.A_fx_gg = nan(n, 1);
    L.A_gg_gg = nan(n, 1);

    for j = 1:n
        keep = true(n, 1);
        keep(j) = false;
        A = [mean(M.abnormal_11(keep), 'omitnan'), mean(M.abnormal_12(keep), 'omitnan'); ...
            mean(M.abnormal_12(keep), 'omitnan'), mean(M.abnormal_22(keep), 'omitnan')];
        sp = spectral_decomposition(A);
        L.lambda_plus(j) = sp.lambdaPlus;
        L.lambda_minus(j) = sp.lambdaMinus;
        L.rotation_gg_minus_fx(j) = A(2, 2) - A(1, 1);
        L.A_fx_fx(j) = A(1, 1);
        L.A_fx_gg(j) = A(1, 2);
        L.A_gg_gg(j) = A(2, 2);
    end
end


function S = append_inference(S, B, P, L, observed, cfg)

    ciPlus = quantile(B.lambda_plus, [0.025, 0.975]);
    ciMinus = quantile(B.lambda_minus, [0.025, 0.975]);
    ciAfxFx = quantile(B.A_fx_fx, [0.025, 0.975]);
    ciAfxGg = quantile(B.A_fx_gg, [0.025, 0.975]);
    ciAggGg = quantile(B.A_gg_gg, [0.025, 0.975]);
    ciRotation = quantile(B.rotation_gg_minus_fx, [0.025, 0.975]);
    ciVplusFx = quantile(B.vplus_fx, [0.025, 0.975]);
    ciVplusGg = quantile(B.vplus_gg, [0.025, 0.975]);
    ciVminusFx = quantile(B.vminus_fx, [0.025, 0.975]);
    ciVminusGg = quantile(B.vminus_gg, [0.025, 0.975]);
    pPositive = (1 + sum(P.lambda_plus >= observed.lambdaPlus)) / (cfg.placeboRep + 1);
    pNegative = (1 + sum(P.lambda_minus <= observed.lambdaMinus)) / (cfg.placeboRep + 1);
    pJoint = (1 + sum(P.lambda_plus >= observed.lambdaPlus & ...
        P.lambda_minus <= observed.lambdaMinus)) / (cfg.placeboRep + 1);
    pRotation = (1 + sum(P.rotation_gg_minus_fx >= observed.rotation)) / (cfg.placeboRep + 1);
    bootstrapIndefinite = mean(B.lambda_plus > 0 & B.lambda_minus < 0);
    looIndefinite = mean(L.lambda_plus > 0 & L.lambda_minus < 0);

    extraMetric = ["lambda_plus_ci95_lo"; "lambda_plus_ci95_hi"; ...
        "lambda_minus_ci95_lo"; "lambda_minus_ci95_hi"; ...
        "A_fx_fx_ci95_lo"; "A_fx_fx_ci95_hi"; ...
        "A_fx_gg_ci95_lo"; "A_fx_gg_ci95_hi"; ...
        "A_gg_gg_ci95_lo"; "A_gg_gg_ci95_hi"; ...
        "rotation_ci95_lo"; "rotation_ci95_hi"; ...
        "vplus_fx_ci95_lo"; "vplus_fx_ci95_hi"; ...
        "vplus_gg_ci95_lo"; "vplus_gg_ci95_hi"; ...
        "vminus_fx_ci95_lo"; "vminus_fx_ci95_hi"; ...
        "vminus_gg_ci95_lo"; "vminus_gg_ci95_hi"; ...
        "p_placebo_lambda_plus"; "p_placebo_lambda_minus"; ...
        "p_placebo_joint_indefinite"; "p_placebo_rotation_positive"; ...
        "bootstrap_share_indefinite"; "loo_share_indefinite"; ...
        "loo_lambda_plus_min"; "loo_lambda_plus_max"; ...
        "loo_lambda_minus_min"; "loo_lambda_minus_max"; ...
        "loo_rotation_min"; "loo_rotation_max"; ...
        "bootstrap_draws"; "placebo_draws"];
    extraValue = [ciPlus(1); ciPlus(2); ciMinus(1); ciMinus(2); ...
        ciAfxFx(1); ciAfxFx(2); ciAfxGg(1); ciAfxGg(2); ...
        ciAggGg(1); ciAggGg(2); ciRotation(1); ciRotation(2); ...
        ciVplusFx(1); ciVplusFx(2); ciVplusGg(1); ciVplusGg(2); ...
        ciVminusFx(1); ciVminusFx(2); ciVminusGg(1); ciVminusGg(2); ...
        pPositive; pNegative; pJoint; pRotation; bootstrapIndefinite; looIndefinite; ...
        min(L.lambda_plus); max(L.lambda_plus); min(L.lambda_minus); max(L.lambda_minus); ...
        min(L.rotation_gg_minus_fx); max(L.rotation_gg_minus_fx); ...
        cfg.bootstrapRep; cfg.placeboRep];
    S = [S; table(extraMetric, extraValue, 'VariableNames', {'metric', 'value'})];
end


function sp = spectral_decomposition(A)

    A = (A + A') ./ 2;
    [V, L] = eig(A, 'vector');
    [values, order] = sort(real(L), 'descend');
    V = real(V(:, order));
    vPlus = orient_vector(V(:, 1), 2);
    vMinus = orient_vector(V(:, end), 1);
    sp = struct('A', A, 'lambdaPlus', values(1), 'lambdaMinus', values(end), ...
        'vPlus', vPlus, 'vMinus', vMinus);
end


function v = orient_vector(v, anchor)

    if v(anchor) < 0
        v = -v;
    end
end


function A = matrix_from_row(P, idx, prefix)

    values11 = P.(prefix + "_11");
    values12 = P.(prefix + "_12");
    values22 = P.(prefix + "_22");
    a11 = values11(idx);
    a12 = values12(idx);
    a22 = values22(idx);
    A = [a11, a12; a12, a22];
end


function A = mean_matrix(P, idx, prefix)

    values11 = P.(prefix + "_11");
    values12 = P.(prefix + "_12");
    values22 = P.(prefix + "_22");
    a11 = mean(values11(idx), 'omitnan');
    a12 = mean(values12(idx), 'omitnan');
    a22 = mean(values22(idx), 'omitnan');
    A = [a11, a12; a12, a22];
end


function x = optional_scalar(T, varName)

    if ismember(varName, string(T.Properties.VariableNames))
        values = T.(varName);
        x = values(1);
        if isstring(x); x = str2double(x); end
    else
        x = NaN;
    end
end


function T = format_dates_for_write(T)

    names = string(T.Properties.VariableNames);
    for v = names
        if isdatetime(T.(v))
            if contains(lower(v), "datetime")
                T.(v) = string(T.(v), 'yyyy-MM-dd HH:mm:ss');
            else
                T.(v) = string(T.(v), 'yyyy-MM-dd');
            end
        end
    end
end
