projectRoot = Get_project_root();

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
panelFile = fullfile(analysisDir, 'pr_bns_component_panel.csv');

cfg = struct();
cfg.outcomes = ["asinh_BV_PR", "asinh_PR_rv"];
cfg.maxLag = 3;
cfg.bootstrapRep = 999;
cfg.blockLength = 5;
cfg.minTrainEvents = 45;
cfg.forecastModels = ["M1_tension", "M2_full"];
cfg.alphaGrid = [0.50, 0.60, 0.65, 0.70];
cfg.dBounds = [-0.45, 0.75];
cfg.minSeriesLength = 30;
cfg.minUsableObs = 60;

if ~isfile(panelFile)
    error('Input file not found: %s', panelFile);
end

T = readtable(panelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

requiredCore = ["event_date", "root_code", "shock_target_10bp"];
missingCore = requiredCore(~ismember(requiredCore, string(T.Properties.VariableNames)));

if ~isempty(missingCore)
    error('Missing required variables: %s', strjoin(missingCore, ', '));
end

T.event_date = parse_date_flex(T.event_date);
T.root_code = lower(strtrim(string(T.root_code)));

candidateNumeric = [ cfg.outcomes, "shock_target_10bp", "root_gg", "regime_hike", "state_pre_rv_z", "state_pre_rsvneg_z", "ma3_target_10bp_z", "T_e", "P_e", "target_x_hike", "target_x_preRV", "target_x_preRSVneg", "target_x_memory", "target_x_T", "target_x_P" ];

for v = unique(candidateNumeric, 'stable')
    if ismember(v, string(T.Properties.VariableNames)) && ~isnumeric(T.(v))
        T.(v) = str2double(string(T.(v)));
    end
end

T = T(~isnat(T.event_date) & T.root_code ~= "", :);
T = sortrows(T, {'event_date', 'root_code'});

if ~ismember("root_gg", string(T.Properties.VariableNames))
    T.root_gg = double(T.root_code == "gg");
end

T = ensure_interaction(T, "target_x_hike",      "shock_target_10bp", "regime_hike");
T = ensure_interaction(T, "target_x_preRV",     "shock_target_10bp", "state_pre_rv_z");
T = ensure_interaction(T, "target_x_preRSVneg", "shock_target_10bp", "state_pre_rsvneg_z");
T = ensure_interaction(T, "target_x_memory",    "shock_target_10bp", "ma3_target_10bp_z");
T = ensure_interaction(T, "target_x_T",         "shock_target_10bp", "T_e");
T = ensure_interaction(T, "target_x_P",         "shock_target_10bp", "P_e");

availableOutcomes = cfg.outcomes(ismember(cfg.outcomes, string(T.Properties.VariableNames)));

if isempty(availableOutcomes)
    error('None of the requested outcomes is present in %s.', panelFile);
end

for yName = availableOutcomes
    if ~isnumeric(T.(yName))
        T.(yName) = str2double(string(T.(yName)));
    end
end

specs = struct('name', {}, 'rhs', {}, 'description', {});

rhsM0 = ["shock_target_10bp", "root_gg"];
specs(end + 1) = make_spec( "M0_mean", rhsM0, "Average shock response with asset-family indicator");

rhsM1 = ["shock_target_10bp", "state_pre_rv_z", "target_x_preRV", "root_gg"];

assert_variables(T, rhsM1, "M1_tension");

specs(end + 1) = make_spec( "M1_tension", rhsM1, "Shock response conditioned on pre-announcement realized-volatility tension");

rhsM2 = "shock_target_10bp";

stateBlocks = {
    ["regime_hike",          "target_x_hike"];
    ["state_pre_rv_z",       "target_x_preRV"];
    ["state_pre_rsvneg_z",   "target_x_preRSVneg"];
    ["ma3_target_10bp_z",    "target_x_memory"];
    ["T_e",                  "target_x_T"];
    ["P_e",                  "target_x_P"]
};

for b = 1:numel(stateBlocks)
    blockVars = stateBlocks{b};

    blockUsable = true;

    for v = blockVars
        blockUsable = blockUsable && usable_numeric_variable(T, v, cfg.minUsableObs);
    end

    if all(ismember(blockVars, string(T.Properties.VariableNames))) && blockUsable
        rhsM2 = [rhsM2, blockVars];
    else
        warning('M2_full omits block [%s]. Variables absent or insufficiently populated.', strjoin(blockVars, ', '));
    end
end

rhsM2 = unique([rhsM2, "root_gg"], 'stable');

specs(end + 1) = make_spec( "M2_full", rhsM2, "Available full contemporaneous state and shock interactions");

specTable = specification_table(specs);
writetable(specTable, fullfile(analysisDir, 'quasimarkov_model_specifications.csv'));

disp(specTable);

crossfitCells = cell(numel(availableOutcomes) * numel(specs), 1);
cc = 0;

for iy = 1:numel(availableOutcomes)
    outcome = availableOutcomes(iy);

    for is = 1:numel(specs)
        cc = cc + 1;
        fprintf('Cross-fitting %s | %s\n', outcome, specs(is).name);

        crossfitCells{cc} = leave_one_event_out( T, outcome, specs(is), cfg);
    end
end

crossfitRows = vertcat(crossfitCells{:});
crossfitRows = sortrows(crossfitRows, {'outcome', 'model_name', 'event_date', 'root_code'});

crossfitOut = crossfitRows;
crossfitOut.event_date = string(crossfitOut.event_date, 'yyyy-MM-dd');

writetable(crossfitOut, fullfile(analysisDir, 'quasimarkov_crossfit_residuals.csv'));

historyCells = {};

for iy = 1:numel(availableOutcomes)
    outcome = availableOutcomes(iy);

    for is = 1:numel(specs)
        modelName = specs(is).name;

        for root = unique(crossfitRows.root_code)'
            sub = crossfitRows( crossfitRows.outcome == outcome & crossfitRows.model_name == modelName & crossfitRows.root_code == root, :);

            sub = sortrows(sub, 'event_date');

            if height(sub) < cfg.minSeriesLength
                continue;
            end

            for K = 1:cfg.maxLag
                historyCells{end + 1, 1} = history_test( sub, outcome, modelName, root, K, "residual_lags", cfg);

                historyCells{end + 1, 1} = history_test( sub, outcome, modelName, root, K, "extended_history", cfg);
            end
        end
    end
end

if isempty(historyCells)
    historyResults = empty_history_table();
else
    historyResults = vertcat(historyCells{:});
    historyResults = sortrows(historyResults, {'outcome', 'model_name', 'root_code', 'test_type', 'lag_order'});
end

writetable(historyResults, fullfile(analysisDir, 'quasimarkov_history_tests.csv'));

forecastCells = {};

for iy = 1:numel(availableOutcomes)
    outcome = availableOutcomes(iy);
    P = add_forecast_history(T, outcome);

    for modelName = cfg.forecastModels
        idxSpec = find(string({specs.name}) == modelName, 1);

        if isempty(idxSpec)
            warning('Forecast model %s is not available.', modelName);
            continue;
        end

        fprintf('Expanding forecast %s | %s\n', outcome, modelName);

        forecastCells{end + 1, 1} = expanding_forecast( P, outcome, specs(idxSpec), cfg);
    end
end

if isempty(forecastCells)
    forecastRows = empty_forecast_rows();
    forecastSummary = empty_forecast_summary();
else
    forecastRows = vertcat(forecastCells{:});
    forecastRows = sortrows(forecastRows, {'outcome', 'state_model', 'event_date', 'root_code'});

    forecastSummary = summarize_forecasts(forecastRows, cfg);
end

forecastRowsOut = forecastRows;

if ~isempty(forecastRowsOut) && ismember("event_date", string(forecastRowsOut.Properties.VariableNames))
    forecastRowsOut.event_date = string(forecastRowsOut.event_date, 'yyyy-MM-dd');
end

writetable(forecastRowsOut, fullfile(analysisDir, 'quasimarkov_forecast_rows.csv'));

writetable(forecastSummary, fullfile(analysisDir, 'quasimarkov_forecast_summary.csv'));

lwCells = {};

for iy = 1:numel(availableOutcomes)
    outcome = availableOutcomes(iy);

    for root = unique(T.root_code)'
        rawMask = T.root_code == root & isfinite(T.(outcome));
        rawTbl = T(rawMask, {'event_date', 'root_code', char(outcome)});
        rawTbl = sortrows(rawTbl, 'event_date');

        xRaw = rawTbl.(outcome);

        lwCells{end + 1, 1} = local_whittle_grid( xRaw, outcome, "RAW", root, "raw_outcome", cfg);

        for is = 1:numel(specs)
            sub = crossfitRows( crossfitRows.outcome == outcome & crossfitRows.model_name == specs(is).name & crossfitRows.root_code == root, :);

            sub = sortrows(sub, 'event_date');

            lwCells{end + 1, 1} = local_whittle_grid( sub.residual_cf, outcome, specs(is).name, root, "crossfit_residual", cfg);
        end
    end
end

if isempty(lwCells)
    lwResults = empty_lw_table();
else
    lwResults = vertcat(lwCells{:});
    lwResults = sortrows(lwResults, {'outcome', 'root_code', 'series_type', 'model_name', 'alpha'});
end

writetable(lwResults, fullfile(analysisDir, 'quasimarkov_local_whittle.csv'));

fprintf('\n================ QUASI-MARKOV DIAGNOSTICS ================\n');
fprintf('Cross-fitted residual rows : %d\n', height(crossfitRows));
fprintf('History-test rows          : %d\n', height(historyResults));
fprintf('Forecast rows              : %d\n', height(forecastRows));
fprintf('Forecast-summary rows      : %d\n', height(forecastSummary));
fprintf('Local-Whittle rows         : %d\n', height(lwResults));
fprintf('Output directory           : %s\n', analysisDir);
fprintf('==========================================================\n');

if ~isempty(historyResults)
    disp(historyResults(:, { 'outcome', 'model_name', 'root_code', 'test_type', 'lag_order', 'f_stat', 'p_classical', 'p_block_wild'}));
end

if ~isempty(forecastSummary)
    disp(forecastSummary(:, { 'outcome', 'state_model', 'root_code', 'mse_state', 'mse_state_history', 'delta_mse', 'ci_low', 'ci_high', 'prob_delta_positive'}));
end

function s = make_spec(name, rhs, description)

    s = struct();
    s.name = string(name);
    s.rhs = string(rhs);
    s.description = string(description);
end

function S = specification_table(specs)

    n = numel(specs);
    model_name = strings(n, 1);
    rhs = strings(n, 1);
    description = strings(n, 1);
    n_regressors = nan(n, 1);

    for j = 1:n
        model_name(j) = specs(j).name;
        rhs(j) = strjoin(specs(j).rhs, " + ");
        description(j) = specs(j).description;
        n_regressors(j) = numel(specs(j).rhs);
    end

    S = table(model_name, rhs, description, n_regressors);
end

function assert_variables(T, vars, label)

    missing = vars(~ismember(vars, string(T.Properties.VariableNames)));

    if ~isempty(missing)
        error('%s requires missing variables: %s', label, strjoin(missing, ', '));
    end
end

function tf = usable_numeric_variable(T, varName, minObs)

    tf = false;

    if ~ismember(varName, string(T.Properties.VariableNames))
        return;
    end

    x = T.(varName);

    if ~isnumeric(x)
        return;
    end

    x = x(isfinite(x));

    tf = numel(x) >= minObs && std(x, 0, 'omitnan') > 0;
end

function T = ensure_interaction(T, interactionName, shockName, stateName)

    vars = string(T.Properties.VariableNames);

    if ismember(interactionName, vars)
        if ~isnumeric(T.(interactionName))
            T.(interactionName) = str2double(string(T.(interactionName)));
        end
        return;
    end

    if ismember(shockName, vars) && ismember(stateName, vars)
        shock = T.(shockName);
        state = T.(stateName);

        if ~isnumeric(shock)
            shock = str2double(string(shock));
        end

        if ~isnumeric(state)
            state = str2double(string(state));
        end

        T.(interactionName) = shock .* state;
    end
end

function R = leave_one_event_out(T, outcome, spec, cfg)

    rhs = spec.rhs;
    assert_variables(T, [outcome, rhs], spec.name);

    complete = complete_case_mask(T, [outcome, rhs]);
    complete = complete & ~isnat(T.event_date) & T.root_code ~= "";

    dates = unique(T.event_date(complete));
    dates = sort(dates);

    R = empty_crossfit_table();

    for j = 1:numel(dates)
        d = dates(j);

        testMask = complete & T.event_date == d;
        trainMask = complete & T.event_date ~= d;

        nTest = sum(testMask);
        nTrain = sum(trainMask);
        nTrainEvents = numel(unique(T.event_date(trainMask)));

        if nTest == 0 || nTrain == 0
            continue;
        end

        [XTrain, ~] = design_matrix(T, trainMask, rhs);
        [XTest, ~] = design_matrix(T, testMask, rhs);

        yTrain = T.(outcome)(trainMask);
        yTest = T.(outcome)(testMask);

        k = size(XTrain, 2);
        rankX = rank(XTrain);
        rankDeficient = rankX < k;

        if nTrain <= k
            warning('%s | %s | %s: too few training observations.', outcome, spec.name, string(d, 'yyyy-MM-dd'));
            continue;
        end

        beta = pinv(XTrain) * yTrain;
        yHat = XTest * beta;
        residual = yTest - yHat;

        n = nTest;

        tmp = table();
        tmp.event_date = repmat(d, n, 1);
        tmp.root_code = T.root_code(testMask);
        tmp.outcome = repmat(string(outcome), n, 1);
        tmp.model_name = repmat(spec.name, n, 1);
        tmp.observed_y = yTest;
        tmp.fitted_cf = yHat;
        tmp.residual_cf = residual;
        tmp.shock_target_10bp = get_numeric_or_nan(T, "shock_target_10bp", testMask);
        tmp.state_pre_rv_z = get_numeric_or_nan(T, "state_pre_rv_z", testMask);
        tmp.state_pre_rsvneg_z = get_numeric_or_nan(T, "state_pre_rsvneg_z", testMask);
        tmp.n_train_obs = repmat(nTrain, n, 1);
        tmp.n_train_events = repmat(nTrainEvents, n, 1);
        tmp.n_parameters = repmat(k, n, 1);
        tmp.rank_x = repmat(rankX, n, 1);
        tmp.rank_deficient = repmat(rankDeficient, n, 1);

        R = [R; tmp];
    end

    if isempty(R)
        warning('No cross-fitted residuals produced for %s | %s.', outcome, spec.name);
    end

    cfg = cfg;
end

function mask = complete_case_mask(T, vars)

    mask = true(height(T), 1);

    for v = string(vars)
        x = T.(v);

        if isnumeric(x)
            mask = mask & isfinite(x);
        elseif isdatetime(x)
            mask = mask & ~isnat(x);
        else
            x = string(x);
            mask = mask & ~ismissing(x) & strlength(strtrim(x)) > 0;
        end
    end
end

function [X, termNames] = design_matrix(T, mask, rhs)

    n = sum(mask);
    X = ones(n, 1);
    termNames = "Intercept";

    for v = rhs
        x = T.(v);

        if ~isnumeric(x)
            x = str2double(string(x));
        end

        X = [X, x(mask)];
        termNames(end + 1, 1) = v;
    end
end

function x = get_numeric_or_nan(T, varName, mask)

    if ismember(varName, string(T.Properties.VariableNames))
        x = T.(varName);

        if ~isnumeric(x)
            x = str2double(string(x));
        end

        x = x(mask);
    else
        x = nan(sum(mask), 1);
    end
end

function out = history_test(sub, outcome, modelName, root, K, testType, cfg)

    sub = sortrows(sub, 'event_date');

    y = sub.residual_cf;
    shock = sub.shock_target_10bp;
    preRV = sub.state_pre_rv_z;

    if testType == "residual_lags"
        sequenceMask = isfinite(y);
    else
        sequenceMask = isfinite(y) & isfinite(shock) & isfinite(preRV);
    end

    dates = sub.event_date(sequenceMask);
    y = y(sequenceMask);
    shock = shock(sequenceMask);
    preRV = preRV(sequenceMask);

    [Y, Z, termNames, validRows] = build_history_design( y, shock, preRV, K, testType);

    datesUsed = dates(validRows);

    [Fstat, pClassical, nObs, q, k] = joint_f_test(Y, Z);

    if isfinite(Fstat)
        pBoot = block_wild_history_pvalue( y, shock, preRV, K, testType, Fstat, cfg.bootstrapRep, cfg.blockLength);
    else
        pBoot = NaN;
    end

    if numel(datesUsed) >= 2
        gaps = days(diff(datesUsed));
        medianGap = median(gaps, 'omitnan');
    else
        medianGap = NaN;
    end

    out = table();
    out.outcome = string(outcome);
    out.model_name = string(modelName);
    out.root_code = string(root);
    out.test_type = string(testType);
    out.lag_order = K;
    out.tested_terms = strjoin(termNames, " + ");
    out.n_obs = nObs;
    out.n_restrictions = q;
    out.n_parameters = k;
    out.f_stat = Fstat;
    out.p_classical = pClassical;
    out.p_block_wild = pBoot;
    out.bootstrap_rep = cfg.bootstrapRep;
    out.block_length = cfg.blockLength;
    out.median_calendar_gap_days = medianGap;
end

function [Y, Z, termNames, validRows] = build_history_design(y, shock, preRV, K, testType)

    n = numel(y);

    if n <= K
        Y = [];
        Z = [];
        termNames = strings(0, 1);
        validRows = false(n, 1);
        return;
    end

    Yfull = y;
    Zfull = [];
    termNames = strings(0, 1);

    for lag = 1:K
        Zfull = [Zfull, lag_vector(y, lag)];
        termNames(end + 1, 1) = "residual_lag" + string(lag);
    end

    if testType == "extended_history"
        for lag = 1:K
            Zfull = [Zfull, lag_vector(shock, lag)];
            termNames(end + 1, 1) = "shock_lag" + string(lag);
        end

        for lag = 1:K
            Zfull = [Zfull, lag_vector(preRV, lag)];
            termNames(end + 1, 1) = "preRV_lag" + string(lag);
        end
    end

    validRows = isfinite(Yfull) & all(isfinite(Zfull), 2);
    Y = Yfull(validRows);
    Z = Zfull(validRows, :);
end

function xlag = lag_vector(x, L)

    x = x(:);
    xlag = nan(size(x));

    if numel(x) > L
        xlag((L + 1):end) = x(1:(end - L));
    end
end

function [Fstat, pValue, n, q, k] = joint_f_test(Y, Z)

    Y = Y(:);
    n = numel(Y);
    q = size(Z, 2);
    k = q + 1;

    if n <= k || q == 0 || rank([ones(n, 1), Z]) < k
        Fstat = NaN;
        pValue = NaN;
        return;
    end

    X = [ones(n, 1), Z];
    beta = X \ Y;
    u = Y - X * beta;

    rssU = u' * u;
    uR = Y - mean(Y, 'omitnan');
    rssR = uR' * uR;

    df2 = n - k;

    if rssU <= 0 || df2 <= 0
        Fstat = NaN;
        pValue = NaN;
        return;
    end

    Fstat = max(((rssR - rssU) / q) / (rssU / df2), 0);
    pValue = 1 - fcdf(Fstat, q, df2);
end

function pBoot = block_wild_history_pvalue( y, shock, preRV, K, testType, Fobs, B, blockLength)

    y = y(:);
    shock = shock(:);
    preRV = preRV(:);

    n = numel(y);

    if n <= K + 5 || ~isfinite(Fobs)
        pBoot = NaN;
        return;
    end

    mu = mean(y, 'omitnan');
    u0 = y - mu;

    Fboot = nan(B, 1);

    for b = 1:B
        mult = block_rademacher(n, blockLength);
        yStar = mu + u0 .* mult;

        [Yb, Zb] = build_history_design( yStar, shock, preRV, K, testType);

        [Fb, ~] = joint_f_test(Yb, Zb);
        Fboot(b) = Fb;
    end

    valid = isfinite(Fboot);

    if ~any(valid)
        pBoot = NaN;
    else
        pBoot = (1 + sum(Fboot(valid) >= Fobs)) / (1 + sum(valid));
    end
end

function mult = block_rademacher(n, blockLength)

    nBlocks = ceil(n / blockLength);
    signs = 2 * double(rand(nBlocks, 1) >= 0.5) - 1;
    mult = repelem(signs, blockLength);
    mult = mult(1:n);

    if blockLength > 1
        shift = randi([0, blockLength - 1], 1, 1);
        mult = circshift(mult, shift);
    end
end

function P = add_forecast_history(T, outcome)

    P = sortrows(T, {'root_code', 'event_date'});

    P.hist_y_lag1 = nan(height(P), 1);
    P.hist_y_lag2 = nan(height(P), 1);
    P.hist_shock_lag1 = nan(height(P), 1);
    P.hist_shock_lag2 = nan(height(P), 1);
    P.hist_preRV_lag1 = nan(height(P), 1);

    roots = unique(P.root_code);

    for r = roots'
        idx = find(P.root_code == r);
        idx = idx(~isnat(P.event_date(idx)));

        [~, order] = sort(P.event_date(idx));
        idx = idx(order);

        y = P.(outcome)(idx);
        shock = P.shock_target_10bp(idx);

        if ismember("state_pre_rv_z", string(P.Properties.VariableNames))
            preRV = P.state_pre_rv_z(idx);
        else
            preRV = nan(numel(idx), 1);
        end

        P.hist_y_lag1(idx) = lag_vector(y, 1);
        P.hist_y_lag2(idx) = lag_vector(y, 2);
        P.hist_shock_lag1(idx) = lag_vector(shock, 1);
        P.hist_shock_lag2(idx) = lag_vector(shock, 2);
        P.hist_preRV_lag1(idx) = lag_vector(preRV, 1);
    end
end

function F = expanding_forecast(P, outcome, stateSpec, cfg)

    historyRhs = [ "hist_y_lag1", "hist_y_lag2", "hist_shock_lag1", "hist_shock_lag2", "hist_preRV_lag1" ];

    rhsState = stateSpec.rhs;
    rhsHistory = unique([rhsState, historyRhs], 'stable');

    assert_variables(P, [outcome, rhsHistory], "expanding_forecast_" + stateSpec.name);

    commonMask = complete_case_mask(P, [outcome, rhsHistory]);
    commonMask = commonMask & ~isnat(P.event_date) & P.root_code ~= "";

    dates = unique(P.event_date(commonMask));
    dates = sort(dates);

    F = empty_forecast_rows();

    for j = 1:numel(dates)
        forecastDate = dates(j);
        priorEvents = dates(dates < forecastDate);

        if numel(priorEvents) < cfg.minTrainEvents
            continue;
        end

        trainMask = commonMask & P.event_date < forecastDate;
        testMask = commonMask & P.event_date == forecastDate;

        if ~any(testMask)
            continue;
        end

        [XStateTrain, ~] = design_matrix(P, trainMask, rhsState);
        [XStateTest, ~] = design_matrix(P, testMask, rhsState);

        [XHistTrain, ~] = design_matrix(P, trainMask, rhsHistory);
        [XHistTest, ~] = design_matrix(P, testMask, rhsHistory);

        yTrain = P.(outcome)(trainMask);
        yTest = P.(outcome)(testMask);

        kState = size(XStateTrain, 2);
        kHist = size(XHistTrain, 2);

        if size(XStateTrain, 1) <= kState || size(XHistTrain, 1) <= kHist
            continue;
        end

        betaState = pinv(XStateTrain) * yTrain;
        betaHistory = pinv(XHistTrain) * yTrain;

        predState = XStateTest * betaState;
        predHistory = XHistTest * betaHistory;

        errState = yTest - predState;
        errHistory = yTest - predHistory;

        n = numel(yTest);

        tmp = table();
        tmp.event_date = repmat(forecastDate, n, 1);
        tmp.root_code = P.root_code(testMask);
        tmp.outcome = repmat(string(outcome), n, 1);
        tmp.state_model = repmat(stateSpec.name, n, 1);
        tmp.observed_y = yTest;
        tmp.pred_state = predState;
        tmp.pred_state_history = predHistory;
        tmp.sqerr_state = errState .^ 2;
        tmp.sqerr_state_history = errHistory .^ 2;
        tmp.loss_diff = tmp.sqerr_state - tmp.sqerr_state_history;
        tmp.n_train_obs = repmat(sum(trainMask), n, 1);
        tmp.n_train_events = repmat(numel(priorEvents), n, 1);
        tmp.k_state = repmat(kState, n, 1);
        tmp.k_state_history = repmat(kHist, n, 1);

        F = [F; tmp];
    end
end

function S = summarize_forecasts(F, cfg)

    if isempty(F)
        S = empty_forecast_summary();
        return;
    end

    outcomes = unique(F.outcome);
    models = unique(F.state_model);
    rootsObserved = unique(F.root_code);
    groupNames = [rootsObserved; "pooled"];

    rows = {};

    for outcome = outcomes'
        for model = models'
            for root = groupNames'
                mask = F.outcome == outcome & F.state_model == model;

                if root ~= "pooled"
                    mask = mask & F.root_code == root;
                end

                G = F(mask, :);

                if isempty(G)
                    continue;
                end

                mseState = mean(G.sqerr_state, 'omitnan');
                mseHistory = mean(G.sqerr_state_history, 'omitnan');
                delta = mseState - mseHistory;

                eventKey = string(G.event_date, 'yyyy-MM-dd');
                [g, eventNames] = findgroups(eventKey);
                eventDiff = splitapply(@(x) mean(x, 'omitnan'), G.loss_diff, g);

                boot = circular_block_bootstrap_mean( eventDiff, cfg.bootstrapRep, cfg.blockLength);

                validBoot = boot(isfinite(boot));

                if isempty(validBoot)
                    ciLow = NaN;
                    ciHigh = NaN;
                    probPositive = NaN;
                else
                    ci = quantile(validBoot, [0.025, 0.975]);
                    ciLow = ci(1);
                    ciHigh = ci(2);
                    probPositive = mean(validBoot > 0);
                end

                rows(end + 1, 1:13) = { outcome, model, root, height(G), numel(eventNames), mseState, mseHistory, delta, ciLow, ciHigh, probPositive, cfg.bootstrapRep, cfg.blockLength };
            end
        end
    end

    S = cell2table(rows, 'VariableNames', { 'outcome', 'state_model', 'root_code', 'n_forecast_rows', 'n_forecast_events', 'mse_state', 'mse_state_history', 'delta_mse', 'ci_low', 'ci_high', 'prob_delta_positive', 'bootstrap_rep', 'block_length' });
end

function bootMeans = circular_block_bootstrap_mean(x, B, blockLength)

    x = x(:);
    x = x(isfinite(x));
    n = numel(x);

    bootMeans = nan(B, 1);

    if n == 0
        return;
    end

    nBlocks = ceil(n / blockLength);

    for b = 1:B
        sample = nan(nBlocks * blockLength, 1);
        pos = 1;

        for j = 1:nBlocks
            start = randi(n);

            for h = 0:(blockLength - 1)
                idx = mod(start - 1 + h, n) + 1;
                sample(pos) = x(idx);
                pos = pos + 1;
            end
        end

        sample = sample(1:n);
        bootMeans(b) = mean(sample, 'omitnan');
    end
end

function L = local_whittle_grid(x, outcome, modelName, root, seriesType, cfg)

    x = x(:);
    x = x(isfinite(x));
    n = numel(x);

    rows = cell(numel(cfg.alphaGrid), 12);

    for ia = 1:numel(cfg.alphaGrid)
        alpha = cfg.alphaGrid(ia);

        if n < cfg.minSeriesLength
            dHat = NaN;
            obj = NaN;
            m = NaN;
            se = NaN;
            ciLow = NaN;
            ciHigh = NaN;
        else
            [dHat, ~, m] = local_whittle_estimate( x, alpha, cfg.dBounds);

            se = 1 / (2 * sqrt(m));
            ciLow = dHat - 1.96 * se;
            ciHigh = dHat + 1.96 * se;
        end

        rows(ia, :) = { string(outcome), string(modelName), string(root), string(seriesType), alpha, n, m, dHat, dHat + 0.5, se, ciLow, ciHigh };
    end

    L = cell2table(rows, 'VariableNames', { 'outcome', 'model_name', 'root_code', 'series_type', 'alpha', 'n_obs', 'm_frequencies', 'd_hat', 'H_hat', 'asymptotic_se', 'ci_low', 'ci_high' });

end

function [dHat, objectiveValue, m] = local_whittle_estimate(x, alpha, dBounds)

    x = x(:);
    x = x - mean(x, 'omitnan');
    n = numel(x);

    m = floor(n ^ alpha);
    m = max(m, 5);
    m = min(m, floor((n - 1) / 2));

    if m < 2 || std(x, 0, 'omitnan') == 0
        dHat = NaN;
        objectiveValue = NaN;
        return;
    end

    fftX = fft(x);
    j = (1:m)';
    lambda = 2 * pi * j / n;
    periodogram = (abs(fftX(j + 1)) .^ 2) / (2 * pi * n);
    periodogram = max(periodogram, realmin);

    objective = @(d) log(mean((lambda .^ (2 * d)) .* periodogram)) - 2 * d * mean(log(lambda));

    options = optimset('Display', 'off', 'TolX', 1e-8);
    [dHat, objectiveValue] = fminbnd( objective, dBounds(1), dBounds(2), options);
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

    x = string(x);
    dt = NaT(size(x));

    formats = [ "yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd HH:mm:ss", "dd-MMM-yyyy" ];

    for f = formats
        remaining = isnat(dt) & ~ismissing(x) & strlength(strtrim(x)) > 0;

        if ~any(remaining)
            break;
        end

        try
            parsed = datetime(x(remaining), 'InputFormat', f);
            dt(remaining) = dateshift(parsed, 'start', 'day');
        catch

        end
    end

    remaining = isnat(dt) & ~ismissing(x) & strlength(strtrim(x)) > 0;

    if any(remaining)
        for j = find(remaining)'
            try
                dt(j) = dateshift(datetime(x(j)), 'start', 'day');
            catch
                dt(j) = NaT;
            end
        end
    end
end

function T = empty_crossfit_table()

    T = table( NaT(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), false(0, 1), 'VariableNames', { 'event_date', 'root_code', 'outcome', 'model_name', 'observed_y', 'fitted_cf', 'residual_cf', 'shock_target_10bp', 'state_pre_rv_z', 'state_pre_rsvneg_z', 'n_train_obs', 'n_train_events', 'n_parameters', 'rank_x', 'rank_deficient' });
end

function T = empty_history_table()

    T = table( strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), nan(0, 1), strings(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), 'VariableNames', { 'outcome', 'model_name', 'root_code', 'test_type', 'lag_order', 'tested_terms', 'n_obs', 'n_restrictions', 'n_parameters', 'f_stat', 'p_classical', 'p_block_wild', 'bootstrap_rep', 'block_length', 'median_calendar_gap_days' });
end

function T = empty_forecast_rows()

    T = table( NaT(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), 'VariableNames', { 'event_date', 'root_code', 'outcome', 'state_model', 'observed_y', 'pred_state', 'pred_state_history', 'sqerr_state', 'sqerr_state_history', 'loss_diff', 'n_train_obs', 'n_train_events', 'k_state', 'k_state_history' });
end

function T = empty_forecast_summary()

    T = table( strings(0, 1), strings(0, 1), strings(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), 'VariableNames', { 'outcome', 'state_model', 'root_code', 'n_forecast_rows', 'n_forecast_events', 'mse_state', 'mse_state_history', 'delta_mse', 'ci_low', 'ci_high', 'prob_delta_positive', 'bootstrap_rep', 'block_length' });
end

function T = empty_lw_table()

    T = table( strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), nan(0, 1), 'VariableNames', { 'outcome', 'model_name', 'root_code', 'series_type', 'alpha', 'n_obs', 'm_frequencies', 'd_hat', 'H_hat', 'asymptotic_se', 'ci_low', 'ci_high' });
end
