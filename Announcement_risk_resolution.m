%% STEP 21: BIAS-ADJUSTED TEST OF ANNOUNCEMENT RISK RESOLUTION.
%
% Step 20 rejects the positive-semidefinite additive-shock restriction through
% a precisely estimated negative eigenvalue.  Its positive eigenvalue is not
% identified.  Step 21 therefore asks a narrower, confirmatory question:
% does the negative eigenvalue survive common-support trimming and a
% leave-year-out correction for normal pre/post second-moment continuation?
%
% Immutable input:
%   Output/analysis/announcement_rotation_date_matrices.csv
%
% The nuisance model is fitted only on non-event dates.  Every bootstrap draw
% resamples event and control dates separately and re-estimates feature
% scaling, common support, the nuisance model, matching and the spectrum.  See
% STEP21_PROTOCOL.md for the locked specification and decision rule.

clear; clc;

projectRoot = getenv('ECONOMETRICS_DATA_ROOT');
if isempty(projectRoot)
    projectRoot = Get_project_root();
elseif exist(fullfile(projectRoot, 'Output'), 'dir') ~= 7
    error('ECONOMETRICS_DATA_ROOT does not contain Output/: %s', projectRoot);
end
Require_time_alignment_manifest(projectRoot);

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
inputFile = fullfile(analysisDir, 'announcement_rotation_date_matrices.csv');

if exist(inputFile, 'file') ~= 2
    error('Required Step-20 input not found: %s', inputFile);
end

cfg = struct();
cfg.seed = 20260719;
cfg.nMatches = 10;
cfg.matchMaxYears = 2;
cfg.calendarWeight = 0.20;
cfg.supportQuantiles = [0.01, 0.99];
cfg.caliperQuantile = 0.95;
cfg.caliperReferenceMax = 400;
cfg.ridgeScale = 1e-6;
cfg.minEvents = 30;
cfg.minRetentionShare = 0.80;
cfg.minUsableBootstrapShare = 0.95;

mode = lower(string(getenv('ANNOUNCEMENT_RESOLUTION_MODE')));
if mode == ""; mode = "final"; end
if ~ismember(mode, ["smoke", "final"])
    error('ANNOUNCEMENT_RESOLUTION_MODE must be smoke or final.');
end

drawOverride = str2double(getenv('ANNOUNCEMENT_RESOLUTION_DRAWS'));
if mode == "smoke"
    cfg.bootstrapRep = 49;
    cfg.placeboRep = 49;
    if isfinite(drawOverride); cfg.bootstrapRep = floor(drawOverride); cfg.placeboRep = floor(drawOverride); end
    if cfg.bootstrapRep < 19
        error('Smoke mode requires at least 19 draws.');
    end
else
    cfg.bootstrapRep = 999;
    cfg.placeboRep = 999;
    if isfinite(drawOverride); cfg.bootstrapRep = floor(drawOverride); cfg.placeboRep = floor(drawOverride); end
    if cfg.bootstrapRep < 999
        error('Final mode refuses fewer than 999 draws.');
    end
end

outputDir = fullfile(analysisDir, "step21_" + mode);
if exist(outputDir, 'dir') ~= 7; mkdir(outputDir); end

P = load_date_panel(inputFile);
if sum(P.is_event) < cfg.minEvents || sum(~P.is_event) < 100
    error('Insufficient Step-20 dates: events=%d, controls=%d.', sum(P.is_event), sum(~P.is_event));
end

scenarioNames = ["full", "exclude_2020", "exclude_2020_2021"];
summaryCells = cell(numel(scenarioNames), 1);
eventCells = cell(numel(scenarioNames), 1);
supportCells = cell(numel(scenarioNames), 1);
balanceCells = cell(numel(scenarioNames), 1);
modelCells = cell(numel(scenarioNames), 1);
bootstrapCells = cell(numel(scenarioNames), 1);
placeboCells = cell(numel(scenarioNames), 1);

fprintf('\n================ ANNOUNCEMENT RISK RESOLUTION ================\n');
fprintf('Mode / draws                  : %s / %d\n', mode, cfg.bootstrapRep);
fprintf('Immutable Step-20 rows        : %d\n', height(P));

for s = 1:numel(scenarioNames)
    scenario = scenarioNames(s);
    Ps = apply_scenario(P, scenario);
    fprintf('\n[21.%d] Scenario %s: events=%d, controls=%d\n', ...
        s, scenario, sum(Ps.is_event), sum(~Ps.is_event));

    fit = estimate_resolution(Ps, cfg, true);
    if ~fit.success
        error('Observed Step-21 estimator failed for %s: %s', scenario, fit.failureReason);
    end

    B = bootstrap_resolution(Ps, cfg, scenario, cfg.seed + 10000 * s);
    R = placebo_resolution(fit, cfg, scenario, cfg.seed + 500000 + 10000 * s);
    S = summarize_scenario(scenario, fit, B, R, cfg);

    E = fit.eventRows;
    E.scenario = repmat(scenario, height(E), 1);
    E = movevars(E, 'scenario', 'Before', 1);

    U = fit.supportRows;
    U.scenario = repmat(scenario, height(U), 1);
    U = movevars(U, 'scenario', 'Before', 1);

    L = fit.balance;
    L.scenario = repmat(scenario, height(L), 1);
    L = movevars(L, 'scenario', 'Before', 1);

    D = fit.modelDiagnostics;
    D.scenario = repmat(scenario, height(D), 1);
    D = movevars(D, 'scenario', 'Before', 1);

    summaryCells{s} = S;
    eventCells{s} = E;
    supportCells{s} = U;
    balanceCells{s} = L;
    modelCells{s} = D;
    bootstrapCells{s} = B;
    placeboCells{s} = R;

    fprintf('Retained events               : %d / %d\n', fit.nRetained, fit.nInputEvents);
    fprintf('Bias-adjusted matrix          : [% .4f % .4f; % .4f % .4f]\n', ...
        fit.observed.A(1,1), fit.observed.A(1,2), fit.observed.A(2,1), fit.observed.A(2,2));
    fprintf('Eigenvalues                   : lambda+ % .4f, lambda- % .4f\n', ...
        fit.observed.lambdaPlus, fit.observed.lambdaMinus);
end

summaryTable = vertcat(summaryCells{:});
eventTable = vertcat(eventCells{:});
supportTable = vertcat(supportCells{:});
balanceTable = vertcat(balanceCells{:});
modelTable = vertcat(modelCells{:});
bootstrapTable = vertcat(bootstrapCells{:});
placeboTable = vertcat(placeboCells{:});
decisionTable = make_decision_table(summaryTable, mode, cfg);
manifestTable = make_manifest(inputFile, outputDir, mode, cfg, decisionTable);

summaryFile = fullfile(outputDir, 'announcement_resolution_summary.csv');
decisionFile = fullfile(outputDir, 'announcement_resolution_decision.csv');
eventFile = fullfile(outputDir, 'announcement_resolution_event_rows.csv');
supportFile = fullfile(outputDir, 'announcement_resolution_support_by_event.csv');
balanceFile = fullfile(outputDir, 'announcement_resolution_balance.csv');
modelFile = fullfile(outputDir, 'announcement_resolution_model_diagnostics.csv');
bootstrapFile = fullfile(outputDir, 'announcement_resolution_bootstrap.csv');
placeboFile = fullfile(outputDir, 'announcement_resolution_placebo.csv');
manifestFile = fullfile(outputDir, 'announcement_resolution_manifest.csv');

writetable(summaryTable, summaryFile);
writetable(decisionTable, decisionFile);
writetable(format_dates_for_write(eventTable), eventFile);
writetable(format_dates_for_write(supportTable), supportFile);
writetable(balanceTable, balanceFile);
writetable(modelTable, modelFile);
writetable(bootstrapTable, bootstrapFile);
writetable(placeboTable, placeboFile);
writetable(manifestTable, manifestFile);

overall = decisionTable(decisionTable.criterion == "overall_final_decision", :);
fprintf('\nDecision status               : %s\n', overall.status(1));
fprintf('Summary                       : %s\n', summaryFile);
fprintf('Decision                      : %s\n', decisionFile);
fprintf('Manifest                      : %s\n', manifestFile);
fprintf('==============================================================\n');


function P = load_date_panel(filePath)

    P = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    required = ["trade_date", "is_event", "clock_late", "weekday_number", ...
        "year_number", "slow_fx", "slow_gg", "qpre_11", "qpre_12", ...
        "qpre_22", "d_11", "d_12", "d_22"];
    missing = required(~ismember(required, string(P.Properties.VariableNames)));
    if ~isempty(missing)
        error('Step-20 date matrix is missing: %s', strjoin(missing, ', '));
    end

    if ~ismember("pseudo_pr_datetime_utc", string(P.Properties.VariableNames))
        error('Step-20 date matrix predates the UTC correction: rerun Announcement_risk_rotation.');
    end

    P.trade_date = Parse_date_flexible(P.trade_date);
    numericVars = required(required ~= "trade_date");
    optionalNumeric = ["regime_hike", "q_target", "pre_state_fx", "pre_state_gg"];
    numericVars = [numericVars, optionalNumeric(ismember(optionalNumeric, string(P.Properties.VariableNames)))];

    for v = numericVars
        if ~isnumeric(P.(v)) && ~islogical(P.(v))
            P.(v) = str2double(P.(v));
        end
    end

    P.is_event = logical(P.is_event);
    P.feature_log_fx_pre = log(max(P.qpre_11, realmin));
    P.feature_log_gg_pre = log(max(P.qpre_22, realmin));
    rho = P.qpre_12 ./ sqrt(max(P.qpre_11 .* P.qpre_22, realmin));
    rho = min(max(rho, -0.999), 0.999);
    P.feature_pre_corr = atanh(rho);

    valid = ~isnat(P.trade_date) & isfinite(P.year_number) & ...
        isfinite(P.clock_late) & isfinite(P.weekday_number) & ...
        isfinite(P.d_11) & isfinite(P.d_12) & isfinite(P.d_22) & ...
        isfinite(P.feature_log_fx_pre) & isfinite(P.feature_log_gg_pre) & ...
        isfinite(P.feature_pre_corr);
    P = P(valid, :);
    P.source_id = transpose(1:height(P));
    P = sortrows(P, 'trade_date');
end


function P = apply_scenario(P, scenario)

    switch scenario
        case "full"
            keep = true(height(P), 1);
        case "exclude_2020"
            keep = P.year_number ~= 2020;
        case "exclude_2020_2021"
            keep = ~ismember(P.year_number, [2020, 2021]);
        otherwise
            error('Unknown scenario: %s', scenario);
    end
    P = P(keep, :);
end


function fit = estimate_resolution(P, cfg, collectDetails)

    fit = struct('success', false, 'failureReason', "not_estimated");
    fit.nInputEvents = sum(P.is_event);

    [Xz, featureNames] = standardize_features(P);
    [muHat, modelDiagnostics] = crossfit_control_continuation(P, Xz, cfg);
    Y = [P.d_11, P.d_12, P.d_22];
    residual = Y - muHat;
    caliper = estimate_distance_caliper(P, Xz, cfg);

    [eventRows, supportRows, matchSets, retainedEventIdx] = ...
        match_bias_adjusted_events(P, Xz, Y, muHat, residual, caliper, cfg);

    if height(eventRows) < cfg.minEvents
        fit.failureReason = "fewer_than_minimum_retained_events";
        return;
    end

    A = [mean(eventRows.corrected_11), mean(eventRows.corrected_12); ...
        mean(eventRows.corrected_12), mean(eventRows.corrected_22)];
    observed = spectral_decomposition(A);
    observed.rotation = A(2,2) - A(1,1);

    if collectDetails
        balance = matching_balance(P, Xz, retainedEventIdx, matchSets, featureNames);
    else
        balance = table();
    end

    fit.success = true;
    fit.failureReason = "";
    fit.P = P;
    fit.Xz = Xz;
    fit.muHat = muHat;
    fit.residual = residual;
    fit.eventRows = eventRows;
    fit.supportRows = supportRows;
    fit.matchSets = matchSets;
    fit.retainedEventIdx = retainedEventIdx;
    fit.observed = observed;
    fit.balance = balance;
    fit.modelDiagnostics = modelDiagnostics;
    fit.caliper = caliper;
    fit.nRetained = height(eventRows);
end


function [Xz, featureNames] = standardize_features(P)

    featureNames = ["log_fx_pre", "log_gg_pre", "fisher_pre_corr", "slow_fx", "slow_gg"];
    X = [P.feature_log_fx_pre, P.feature_log_gg_pre, P.feature_pre_corr, P.slow_fx, P.slow_gg];
    control = ~P.is_event;

    for j = 1:size(X, 2)
        xControl = X(control, j);
        med = median(xControl, 'omitnan');
        if ~isfinite(med); med = 0; end
        X(~isfinite(X(:,j)), j) = med;
        mu = mean(X(control,j));
        sd = std(X(control,j), 0);
        if ~isfinite(sd) || sd <= 0; sd = 1; end
        X(:,j) = (X(:,j) - mu) ./ sd;
    end
    Xz = X;
end


function [muHat, diagnostics] = crossfit_control_continuation(P, Xz, cfg)

    Z = nuisance_design(P, Xz);
    Y = [P.d_11, P.d_12, P.d_22];
    control = ~P.is_event;
    linearHat = nan(height(P), 3);
    baselineHat = nan(height(P), 3);
    years = unique(P.year_number);

    for y = transpose(years)
        predict = P.year_number == y;
        train = control & P.year_number ~= y;
        if sum(train) < size(Z,2) + 10
            train = control;
        end
        beta = ridge_fit(Z(train,:), Y(train,:), cfg.ridgeScale);
        linearHat(predict,:) = Z(predict,:) * beta;
        baselineHat(predict,:) = repmat(mean(Y(train,:),1),sum(predict),1);
    end

    missing = any(~isfinite(linearHat), 2) | any(~isfinite(baselineHat),2);
    if any(missing)
        beta = ridge_fit(Z(control,:), Y(control,:), cfg.ridgeScale);
        linearHat(missing,:) = Z(missing,:) * beta;
        baselineHat(missing,:) = repmat(mean(Y(control,:),1),sum(missing),1);
    end

    outcome = ["d_11"; "d_12"; "d_22"];
    linear_leave_year_out_r2 = nan(3,1);
    shrinkage_weight = nan(3,1);
    cv_r2 = nan(3,1);
    muHat = nan(height(P),3);
    for j = 1:3
        deltaControl = linearHat(control,j) - baselineHat(control,j);
        targetControl = Y(control,j) - baselineHat(control,j);
        denomWeight = sum(deltaControl.^2);
        if isfinite(denomWeight) && denomWeight > 0
            alpha = sum(targetControl .* deltaControl) ./ denomWeight;
            alpha = min(max(alpha,0),1);
        else
            alpha = 0;
        end
        shrinkage_weight(j) = alpha;
        muHat(:,j) = baselineHat(:,j) + alpha .* (linearHat(:,j) - baselineHat(:,j));

        linearErr = Y(control,j) - linearHat(control,j);
        err = Y(control,j) - muHat(control,j);
        denom = sum((Y(control,j) - mean(Y(control,j))).^2);
        if denom > 0
            linear_leave_year_out_r2(j) = 1 - sum(linearErr.^2) ./ denom;
            cv_r2(j) = 1 - sum(err.^2) ./ denom;
        end
    end
    diagnostics = table(outcome, linear_leave_year_out_r2, shrinkage_weight, cv_r2, ...
        repmat(sum(control),3,1), ...
        repmat(size(Z,2),3,1), repmat(cfg.ridgeScale,3,1), ...
        'VariableNames', {'outcome','linear_leave_year_out_r2','shrinkage_weight', ...
        'leave_year_out_r2','n_control','n_design_columns','ridge_scale'});
end


function Z = nuisance_design(P, Xz)

    n = height(P);
    control = ~P.is_event;
    yearMu = mean(P.year_number(control));
    yearSd = std(P.year_number(control));
    if ~isfinite(yearSd) || yearSd <= 0; yearSd = 1; end
    yearZ = (P.year_number - yearMu) ./ yearSd;
    weekdayDummies = [P.weekday_number == 3, P.weekday_number == 4, ...
        P.weekday_number == 5, P.weekday_number == 6];

    Z = [ones(n,1), Xz, double(P.clock_late), ...
        double(weekdayDummies), yearZ, yearZ.^2];
end


function beta = ridge_fit(X, Y, ridgeScale)

    G = X' * X;
    p = size(G,1);
    lambda = ridgeScale .* max(trace(G) ./ max(p,1), 1);
    penalty = eye(p);
    penalty(1,1) = 0;
    H = G + lambda .* penalty;
    rhs = X' * Y;
    if rcond(H) < 1e-12
        beta = pinv(H) * rhs;
    else
        beta = H \ rhs;
    end
end


function caliper = estimate_distance_caliper(P, Xz, cfg)

    control = find(~P.is_event);
    [~, uniqueLoc] = unique(P.source_id(control), 'stable');
    reference = control(uniqueLoc);
    if numel(reference) > cfg.caliperReferenceMax
        loc = unique(round(linspace(1, numel(reference), cfg.caliperReferenceMax)));
        reference = reference(loc);
    end

    kth = nan(numel(reference),1);
    for j = 1:numel(reference)
        i = reference(j);
        eligible = control(P.clock_late(control) == P.clock_late(i) & ...
            P.weekday_number(control) == P.weekday_number(i) & ...
            abs(P.year_number(control) - P.year_number(i)) <= cfg.matchMaxYears & ...
            P.source_id(control) ~= P.source_id(i));
        if numel(eligible) < cfg.nMatches; continue; end
        delta = Xz(eligible,:) - Xz(i,:);
        distance = sum(delta.^2,2) + cfg.calendarWeight .* ...
            ((P.year_number(eligible) - P.year_number(i))./5).^2;
        distance = sort(distance, 'ascend');
        kth(j) = distance(cfg.nMatches);
    end

    kth = kth(isfinite(kth));
    if isempty(kth)
        error('Could not calibrate the common-support distance caliper.');
    end
    caliper = quantile(kth, cfg.caliperQuantile);
end


function [E, U, matchSets, retainedEventIdx] = match_bias_adjusted_events(P, Xz, Y, muHat, residual, caliper, cfg)

    eventIdx = find(P.is_event);
    controlIdx = find(~P.is_event);
    rows = cell(numel(eventIdx),1);
    matchCells = cell(numel(eventIdx),1);
    inBox = false(numel(eventIdx),1);
    nCandidates = zeros(numel(eventIdx),1);
    nWithin = zeros(numel(eventIdx),1);
    retained = false(numel(eventIdx),1);
    reason = strings(numel(eventIdx),1);
    nearestDistance = nan(numel(eventIdx),1);
    tenthDistance = nan(numel(eventIdx),1);

    for j = 1:numel(eventIdx)
        e = eventIdx(j);
        clockControls = controlIdx(P.clock_late(controlIdx) == P.clock_late(e));
        lo = quantile(Xz(clockControls,:), cfg.supportQuantiles(1), 1);
        hi = quantile(Xz(clockControls,:), cfg.supportQuantiles(2), 1);
        inBox(j) = all(Xz(e,:) >= lo & Xz(e,:) <= hi);
        if ~inBox(j)
            reason(j) = "outside_quantile_box";
            continue;
        end

        eligible = controlIdx(P.clock_late(controlIdx) == P.clock_late(e) & ...
            P.weekday_number(controlIdx) == P.weekday_number(e) & ...
            abs(P.year_number(controlIdx) - P.year_number(e)) <= cfg.matchMaxYears);
        nCandidates(j) = numel(eligible);
        if numel(eligible) < cfg.nMatches
            reason(j) = "fewer_than_ten_exact_candidates";
            continue;
        end

        delta = Xz(eligible,:) - Xz(e,:);
        distance = sum(delta.^2,2) + cfg.calendarWeight .* ...
            ((P.year_number(eligible) - P.year_number(e))./5).^2;
        [distance, order] = sort(distance, 'ascend');
        nearestDistance(j) = distance(1);
        tenthDistance(j) = distance(cfg.nMatches);
        within = order(distance <= caliper);
        nWithin(j) = numel(within);
        if numel(within) < cfg.nMatches
            reason(j) = "distance_caliper";
            continue;
        end

        matches = eligible(within(1:cfg.nMatches));
        raw = Y(e,:) - mean(Y(matches,:),1);
        corrected = residual(e,:) - mean(residual(matches,:),1);
        biasCorrection = raw - corrected;

        R = table();
        R.trade_date = P.trade_date(e);
        R.event_index = e;
        R.n_matches = cfg.nMatches;
        R.match_dates = strjoin(string(P.trade_date(matches),'yyyy-MM-dd'),'|');
        R.nearest_distance = nearestDistance(j);
        R.tenth_distance = tenthDistance(j);
        R.event_d11 = Y(e,1); R.event_d12 = Y(e,2); R.event_d22 = Y(e,3);
        R.control_d11 = mean(Y(matches,1)); R.control_d12 = mean(Y(matches,2)); R.control_d22 = mean(Y(matches,3));
        R.raw_11 = raw(1); R.raw_12 = raw(2); R.raw_22 = raw(3);
        R.predicted_event_11 = muHat(e,1); R.predicted_event_12 = muHat(e,2); R.predicted_event_22 = muHat(e,3);
        R.bias_correction_11 = biasCorrection(1); R.bias_correction_12 = biasCorrection(2); R.bias_correction_22 = biasCorrection(3);
        R.corrected_11 = corrected(1); R.corrected_12 = corrected(2); R.corrected_22 = corrected(3);
        R.rotation_gg_minus_fx = corrected(3) - corrected(1);
        rows{j} = R;
        matchCells{j} = matches;
        retained(j) = true;
        reason(j) = "retained";
    end

    U = table(P.trade_date(eventIdx), eventIdx, inBox, nCandidates, nWithin, ...
        repmat(caliper,numel(eventIdx),1), nearestDistance, tenthDistance, retained, reason, ...
        'VariableNames', {'trade_date','event_index','inside_quantile_box','n_exact_candidates', ...
        'n_within_caliper','distance_caliper','nearest_distance','tenth_distance','retained','reason'});

    if any(retained)
        E = vertcat(rows{retained});
        matchSets = matchCells(retained);
        retainedEventIdx = eventIdx(retained);
    else
        E = table();
        matchSets = {};
        retainedEventIdx = [];
    end
end


function L = matching_balance(P, Xz, eventIdx, matchSets, featureNames)

    control = ~P.is_event;
    matchedMean = nan(numel(eventIdx), size(Xz,2));
    for j = 1:numel(eventIdx)
        matchedMean(j,:) = mean(Xz(matchSets{j},:),1);
    end
    eventMean = mean(Xz(eventIdx,:),1);
    unmatchedMean = mean(Xz(control,:),1);
    matchedControlMean = mean(matchedMean,1);
    controlSd = std(Xz(control,:),0,1);
    controlSd(~isfinite(controlSd) | controlSd <= 0) = 1;
    smdBefore = (eventMean - unmatchedMean) ./ controlSd;
    smdAfter = (eventMean - matchedControlMean) ./ controlSd;

    L = table(featureNames(:), eventMean(:), unmatchedMean(:), matchedControlMean(:), ...
        smdBefore(:), smdAfter(:), ...
        'VariableNames', {'feature','event_mean','unmatched_control_mean','matched_control_mean', ...
        'smd_before','smd_after'});
end


function B = bootstrap_resolution(P, cfg, scenario, seed)

    rng(seed, 'twister');
    eventBase = find(P.is_event);
    controlBase = find(~P.is_event);
    nEvent = numel(eventBase);
    nControl = numel(controlBase);

    draw = transpose(1:cfg.bootstrapRep);
    usable = false(cfg.bootstrapRep,1);
    failure_reason = strings(cfg.bootstrapRep,1);
    n_events_retained = nan(cfg.bootstrapRep,1);
    A_fx_fx = nan(cfg.bootstrapRep,1); A_fx_gg = nan(cfg.bootstrapRep,1); A_gg_gg = nan(cfg.bootstrapRep,1);
    lambda_plus = nan(cfg.bootstrapRep,1); lambda_minus = nan(cfg.bootstrapRep,1);
    vplus_fx = nan(cfg.bootstrapRep,1); vplus_gg = nan(cfg.bootstrapRep,1);
    vminus_fx = nan(cfg.bootstrapRep,1); vminus_gg = nan(cfg.bootstrapRep,1);
    rotation_gg_minus_fx = nan(cfg.bootstrapRep,1);

    progressEvery = max(1, floor(cfg.bootstrapRep/10));
    for b = 1:cfg.bootstrapRep
        idxEvent = eventBase(randi(nEvent,nEvent,1));
        idxControl = controlBase(randi(nControl,nControl,1));
        Pb = P([idxEvent; idxControl],:);
        try
            fit = estimate_resolution(Pb, cfg, false);
            if ~fit.success
                failure_reason(b) = fit.failureReason;
            else
                sp = fit.observed;
                usable(b) = true;
                n_events_retained(b) = fit.nRetained;
                A_fx_fx(b) = sp.A(1,1); A_fx_gg(b) = sp.A(1,2); A_gg_gg(b) = sp.A(2,2);
                lambda_plus(b) = sp.lambdaPlus; lambda_minus(b) = sp.lambdaMinus;
                vplus_fx(b) = sp.vPlus(1); vplus_gg(b) = sp.vPlus(2);
                vminus_fx(b) = sp.vMinus(1); vminus_gg(b) = sp.vMinus(2);
                rotation_gg_minus_fx(b) = sp.A(2,2) - sp.A(1,1);
            end
        catch ME
            failure_reason(b) = string(ME.identifier);
            if failure_reason(b) == ""; failure_reason(b) = "bootstrap_exception"; end
        end

        if mod(b,progressEvery) == 0 || b == cfg.bootstrapRep
            fprintf('  %s bootstrap %d/%d\n', scenario, b, cfg.bootstrapRep);
        end
    end

    B = table(repmat(scenario,cfg.bootstrapRep,1), draw, usable, failure_reason, ...
        n_events_retained, A_fx_fx, A_fx_gg, A_gg_gg, lambda_plus, lambda_minus, ...
        vplus_fx, vplus_gg, vminus_fx, vminus_gg, rotation_gg_minus_fx, ...
        'VariableNames', {'scenario','draw','usable','failure_reason','n_events_retained', ...
        'A_fx_fx','A_fx_gg','A_gg_gg','lambda_plus','lambda_minus', ...
        'vplus_fx','vplus_gg','vminus_fx','vminus_gg','rotation_gg_minus_fx'});
end


function R = placebo_resolution(fit, cfg, scenario, seed)

    rng(seed, 'twister');
    draw = transpose(1:cfg.placeboRep);
    lambda_plus = nan(cfg.placeboRep,1);
    lambda_minus = nan(cfg.placeboRep,1);
    rotation_gg_minus_fx = nan(cfg.placeboRep,1);

    for b = 1:cfg.placeboRep
        a = nan(fit.nRetained,3);
        for j = 1:fit.nRetained
            matches = fit.matchSets{j};
            chosenLoc = randi(numel(matches));
            chosen = matches(chosenLoc);
            remaining = matches;
            remaining(chosenLoc) = [];
            a(j,:) = fit.residual(chosen,:) - mean(fit.residual(remaining,:),1);
        end
        A = [mean(a(:,1)),mean(a(:,2));mean(a(:,2)),mean(a(:,3))];
        sp = spectral_decomposition(A);
        lambda_plus(b) = sp.lambdaPlus;
        lambda_minus(b) = sp.lambdaMinus;
        rotation_gg_minus_fx(b) = A(2,2) - A(1,1);
    end

    R = table(repmat(scenario,cfg.placeboRep,1), draw, lambda_plus, lambda_minus, ...
        rotation_gg_minus_fx, 'VariableNames', ...
        {'scenario','draw','lambda_plus','lambda_minus','rotation_gg_minus_fx'});
end


function S = summarize_scenario(scenario, fit, B, R, cfg)

    usable = B.usable;
    ciPlus = safe_quantile(B.lambda_plus(usable), [0.025,0.975]);
    ciMinus = safe_quantile(B.lambda_minus(usable), [0.025,0.975]);
    ci11 = safe_quantile(B.A_fx_fx(usable), [0.025,0.975]);
    ci12 = safe_quantile(B.A_fx_gg(usable), [0.025,0.975]);
    ci22 = safe_quantile(B.A_gg_gg(usable), [0.025,0.975]);
    ciRotation = safe_quantile(B.rotation_gg_minus_fx(usable), [0.025,0.975]);
    pNegative = (1 + sum(R.lambda_minus <= fit.observed.lambdaMinus)) ./ (height(R)+1);
    pRotation = (1 + sum(R.rotation_gg_minus_fx >= fit.observed.rotation)) ./ (height(R)+1);

    metric = ["n_events_input";"n_events_retained";"retention_share";"distance_caliper"; ...
        "control_cv_r2_d11";"control_cv_r2_d12";"control_cv_r2_d22"; ...
        "A_fx_fx";"A_fx_gg";"A_gg_gg";"lambda_plus";"lambda_minus"; ...
        "vplus_fx";"vplus_gg";"vminus_fx";"vminus_gg";"rotation_gg_minus_fx"; ...
        "lambda_plus_ci95_lo";"lambda_plus_ci95_hi"; ...
        "lambda_minus_ci95_lo";"lambda_minus_ci95_hi"; ...
        "A_fx_fx_ci95_lo";"A_fx_fx_ci95_hi";"A_fx_gg_ci95_lo";"A_fx_gg_ci95_hi"; ...
        "A_gg_gg_ci95_lo";"A_gg_gg_ci95_hi";"rotation_ci95_lo";"rotation_ci95_hi"; ...
        "p_placebo_lambda_minus";"p_placebo_rotation_positive"; ...
        "bootstrap_draws_requested";"bootstrap_draws_usable";"bootstrap_usable_share"];
    A = fit.observed.A;
    value = [fit.nInputEvents;fit.nRetained;fit.nRetained/fit.nInputEvents;fit.caliper; ...
        fit.modelDiagnostics.leave_year_out_r2;A(1,1);A(1,2);A(2,2); ...
        fit.observed.lambdaPlus;fit.observed.lambdaMinus;fit.observed.vPlus(1);fit.observed.vPlus(2); ...
        fit.observed.vMinus(1);fit.observed.vMinus(2);fit.observed.rotation; ...
        ciPlus(1);ciPlus(2);ciMinus(1);ciMinus(2);ci11(1);ci11(2);ci12(1);ci12(2); ...
        ci22(1);ci22(2);ciRotation(1);ciRotation(2);pNegative;pRotation; ...
        cfg.bootstrapRep;sum(usable);mean(usable)];
    S = table(repmat(scenario,numel(metric),1),metric,value, ...
        'VariableNames', {'scenario','metric','value'});
end


function D = make_decision_table(S, mode, cfg)

    fullUpper = summary_value(S,"full","lambda_minus_ci95_hi");
    no2020Upper = summary_value(S,"exclude_2020","lambda_minus_ci95_hi");
    fullRetention = summary_value(S,"full","retention_share");
    no2020Retention = summary_value(S,"exclude_2020","retention_share");
    fullUsable = summary_value(S,"full","bootstrap_usable_share");
    no2020Usable = summary_value(S,"exclude_2020","bootstrap_usable_share");

    criterion = ["full_lambda_minus_upper_below_zero";"exclude_2020_lambda_minus_upper_below_zero"; ...
        "full_retention_at_least_80pct";"exclude_2020_retention_at_least_80pct"; ...
        "full_bootstrap_usable_at_least_95pct";"exclude_2020_bootstrap_usable_at_least_95pct"];
    scenario = ["full";"exclude_2020";"full";"exclude_2020";"full";"exclude_2020"];
    value = [fullUpper;no2020Upper;fullRetention;no2020Retention;fullUsable;no2020Usable];
    threshold = ["< 0";"< 0";">= 0.80";">= 0.80";">= 0.95";">= 0.95"];
    passed = [fullUpper<0;no2020Upper<0;fullRetention>=cfg.minRetentionShare; ...
        no2020Retention>=cfg.minRetentionShare;fullUsable>=cfg.minUsableBootstrapShare; ...
        no2020Usable>=cfg.minUsableBootstrapShare];
    binding = true(6,1);
    evaluated = repmat(mode=="final",6,1);
    status = repmat("COMPONENT",6,1);

    if mode == "smoke"
        overallStatus = "SMOKE_ONLY";
        overallPassed = false;
        overallEvaluated = false;
    elseif all(passed)
        overallStatus = "PASS_RISK_RESOLUTION";
        overallPassed = true;
        overallEvaluated = true;
    else
        overallStatus = "FAIL_RISK_RESOLUTION";
        overallPassed = false;
        overallEvaluated = true;
    end

    D = table(criterion,scenario,value,threshold,passed,binding,evaluated,status);
    overall = table("overall_final_decision","joint",double(overallPassed),"all binding gates", ...
        overallPassed,true,overallEvaluated,overallStatus, ...
        'VariableNames', D.Properties.VariableNames);
    D = [D;overall];
end


function M = make_manifest(inputFile, outputDir, mode, cfg, D)

    inputInfo = dir(inputFile);
    overall = D(D.criterion=="overall_final_decision",:);
    key = ["step";"mode";"seed";"bootstrap_draws";"placebo_draws";"n_matches"; ...
        "match_max_years";"calendar_weight";"support_quantile_low";"support_quantile_high"; ...
        "caliper_quantile";"ridge_scale";"nuisance_predictive_guard";"minimum_retention_share"; ...
        "minimum_usable_bootstrap_share";"git_sha";"matlab_version"; ...
        "input_file";"input_file_bytes";"input_file_sha256";"output_directory"; ...
        "generated_at";"decision_status"];
    value = ["21";mode;string(cfg.seed);string(cfg.bootstrapRep);string(cfg.placeboRep); ...
        string(cfg.nMatches);string(cfg.matchMaxYears);string(cfg.calendarWeight); ...
        string(cfg.supportQuantiles(1));string(cfg.supportQuantiles(2));string(cfg.caliperQuantile); ...
        string(cfg.ridgeScale);"control_oos_convex_shrink_to_fold_mean"; ...
        string(cfg.minRetentionShare);string(cfg.minUsableBootstrapShare); ...
        string(getenv('STEP21_GIT_SHA'));string(version());string(inputFile);string(inputInfo.bytes); ...
        file_sha256(inputFile);string(outputDir);string(datetime('now'),'yyyy-MM-dd HH:mm:ss'); ...
        overall.status(1)];
    M = table(key,value);
end


function value = summary_value(S, scenario, metric)

    row = S.scenario==scenario & S.metric==metric;
    if sum(row)~=1; error('Summary metric not unique: %s / %s',scenario,metric); end
    value = S.value(row);
end


function q = safe_quantile(x, probabilities)

    x = x(isfinite(x));
    if isempty(x); q = [NaN,NaN]; else; q = quantile(x,probabilities); end
end


function sp = spectral_decomposition(A)

    A = (A+A')./2;
    [V,L] = eig(A,'vector');
    [values,order] = sort(real(L),'descend');
    V = real(V(:,order));
    vPlus = orient_vector(V(:,1),2);
    vMinus = orient_vector(V(:,end),1);
    sp = struct('A',A,'lambdaPlus',values(1),'lambdaMinus',values(end), ...
        'vPlus',vPlus,'vMinus',vMinus);
end


function v = orient_vector(v, anchor)

    if v(anchor)<0; v=-v; end
end


function hash = file_sha256(filePath)

    escaped = strrep(char(filePath),'"','\"');
    [status,out] = system(sprintf('shasum -a 256 "%s"',escaped));
    if status==0
        pieces = split(strtrim(string(out)));
        hash = pieces(1);
    else
        hash = "unavailable";
    end
end


function T = format_dates_for_write(T)

    names = string(T.Properties.VariableNames);
    for v = names
        if isdatetime(T.(v))
            T.(v) = string(T.(v),'yyyy-MM-dd HH:mm:ss');
        end
    end
end
