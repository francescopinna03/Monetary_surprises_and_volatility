%% STEP 19: VALIDATION OF THE ANNOUNCEMENT COUNTERFACTUAL.
%
% This script stress-tests Step 18 without modifying any Step-18 output.
% It conditions on the root-day windows already constructed in
% announcement_counterfactual_windows.csv and implements five diagnostics:
%
%   1. a one-stage stacked event-versus-control regression;
%   2. a stratified date bootstrap of both counterfactual stages;
%   3. nearest-neighbour event/control matching and matched placebos;
%   4. explicit shock-energy support and collinearity diagnostics;
%   5. leave-top-k-event sensitivity for every primary specification.
%
% The pre-declared inferential hierarchy is:
%   - null-imposed wild-date-cluster p-values for stacked and matched models;
%   - percentile intervals from the full two-stage bootstrap;
%   - matched-control placebo probabilities;
%   - equivalence tests with a log(1.25) margin;
%   - stability after removal of the largest shock-energy dates.
%
% All generated files use the prefix announcement_validation_.

clear; clc;

projectRoot = Get_project_root();
analysisDir = fullfile(projectRoot, 'Output', 'analysis');
windowFile = fullfile(analysisDir, 'announcement_counterfactual_windows.csv');

if exist(windowFile, 'file') ~= 2
    error('Required Step-18 input not found: %s', windowFile);
end

cfg = struct();
cfg.seed = 20260718;
cfg.wildRep = 999;
cfg.twoStageBootstrapRep = 999;
cfg.placeboRep = 999;
cfg.equivalenceLogMargin = log(1.25);
cfg.matchK = 10;
cfg.matchMaxYears = 2;
cfg.matchTimeScaleYears = 2;
cfg.leaveTopK = 10;
cfg.leaveWildK = [0, 1, 2, 3, 5];
cfg.minimumEventClusters = 30;

drawOverride = str2double(getenv('ANNOUNCEMENT_VALIDATION_DRAWS'));
if isfinite(drawOverride) && drawOverride >= 19
    drawOverride = floor(drawOverride);
    cfg.wildRep = drawOverride;
    cfg.twoStageBootstrapRep = drawOverride;
    cfg.placeboRep = drawOverride;
end

rng(cfg.seed, 'twister');

W = load_validation_panel(windowFile);
W = prepare_validation_variables(W);
specs = validation_specs();

fprintf('\n================ COUNTERFACTUAL VALIDATION ================\n');
fprintf('Root-day rows                  : %d\n', height(W));
fprintf('Eligible control root-days     : %d\n', sum(~W.is_event & W.window_eligible));
fprintf('Eligible event root-days       : %d\n', sum(W.is_event & W.window_eligible));
fprintf('Wild/bootstrap/placebo draws   : %d / %d / %d\n', cfg.wildRep, cfg.twoStageBootstrapRep, cfg.placeboRep);

fprintf('\n[19.A] One-stage stacked models.\n');
[stackedCoef, stackedSummary, stackedEquivalence] = run_stacked_models(W, specs, cfg);

fprintf('\n[19.B] Full two-stage date bootstrap.\n');
twoStageBootstrap = run_two_stage_bootstrap(W, specs, cfg);

fprintf('\n[19.C] Matched controls and matched-placebo inference.\n');
[matchedEvent, matchedRows, matchSets] = construct_matched_counterfactuals(W, cfg);
[matchedCoef, matchedSummary, matchedEquivalence] = run_matched_models(matchedEvent, specs, cfg);
matchedPlacebo = run_matched_placebos(W, matchedEvent, matchSets, specs, matchedCoef, cfg);

fprintf('\n[19.D] Shock-energy support diagnostics.\n');
[supportByEvent, supportSummary] = build_support_diagnostics(W);

fprintf('\n[19.E] Leave-top-k sensitivity.\n');
leaveTopK = run_leave_top_k(W, specs, cfg);

equivalenceCells = {};
if ~isempty(stackedEquivalence); equivalenceCells{end + 1, 1} = stackedEquivalence; end
if ~isempty(matchedEquivalence); equivalenceCells{end + 1, 1} = matchedEquivalence; end
equivalence = vertcat_or_empty(equivalenceCells);

outputs = struct();
outputs.stackedCoef = fullfile(analysisDir, 'announcement_validation_stacked_coefficients.csv');
outputs.stackedSummary = fullfile(analysisDir, 'announcement_validation_stacked_summary.csv');
outputs.twoStageBootstrap = fullfile(analysisDir, 'announcement_validation_two_stage_bootstrap.csv');
outputs.matchedRows = fullfile(analysisDir, 'announcement_validation_matched_rows.csv');
outputs.matchedCoef = fullfile(analysisDir, 'announcement_validation_matched_coefficients.csv');
outputs.matchedSummary = fullfile(analysisDir, 'announcement_validation_matched_summary.csv');
outputs.matchedPlacebo = fullfile(analysisDir, 'announcement_validation_matched_placebo.csv');
outputs.supportByEvent = fullfile(analysisDir, 'announcement_validation_support_by_event.csv');
outputs.supportSummary = fullfile(analysisDir, 'announcement_validation_support_summary.csv');
outputs.leaveTopK = fullfile(analysisDir, 'announcement_validation_leave_top_k.csv');
outputs.equivalence = fullfile(analysisDir, 'announcement_validation_equivalence.csv');

writetable(stackedCoef, outputs.stackedCoef);
writetable(stackedSummary, outputs.stackedSummary);
writetable(twoStageBootstrap, outputs.twoStageBootstrap);
writetable(format_dates_for_write(matchedRows), outputs.matchedRows);
writetable(matchedCoef, outputs.matchedCoef);
writetable(matchedSummary, outputs.matchedSummary);
writetable(matchedPlacebo, outputs.matchedPlacebo);
writetable(format_dates_for_write(supportByEvent), outputs.supportByEvent);
writetable(supportSummary, outputs.supportSummary);
writetable(leaveTopK, outputs.leaveTopK);
writetable(equivalence, outputs.equivalence);

fprintf('\nValidation outputs written to %s\n', analysisDir);
fprintf('Stacked key coefficients       : %s\n', outputs.stackedCoef);
fprintf('Two-stage bootstrap            : %s\n', outputs.twoStageBootstrap);
fprintf('Matched placebo                : %s\n', outputs.matchedPlacebo);
fprintf('Support diagnostics            : %s\n', outputs.supportSummary);
fprintf('Leave-top-k                    : %s\n', outputs.leaveTopK);
fprintf('============================================================\n');

if ~isempty(stackedCoef)
    keyMask = contains(stackedCoef.term, "event_q") | stackedCoef.term == "event_state";
    disp(stackedCoef(keyMask, {'model_name', 'term', 'beta', 'se_cluster', 'p_value', 'p_wild_cluster', 'ci95_lo', 'ci95_hi'}));
end


function W = load_validation_panel(filePath)

    W = readtable(filePath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    required = ["trade_date", "root_code", "is_event", "window_eligible", ...
        "log_BV_pre", "log_BV_post", "log_RV_pre", "log_RV_post", ...
        "jump_share_pre", "jump_share_post", "slow5_log_rv", ...
        "clock_late", "weekday_number", "month_number", "year_number", ...
        "shock_target_10bp", "target_pca_10bp", "path_pca_10bp", "regime_hike"];
    missing = required(~ismember(required, string(W.Properties.VariableNames)));

    if ~isempty(missing)
        error('Step-18 window panel is missing: %s', strjoin(missing, ', '));
    end

    W.trade_date = Parse_date_flexible(W.trade_date);
    W.root_code = lower(string(W.root_code));

    numericVars = setdiff(required, ["trade_date", "root_code"]);
    optionalNumeric = ["abnormal_log_BV", "abnormal_log_RV", "abnormal_jump_share"];
    numericVars = unique([numericVars, optionalNumeric]);

    for v = numericVars
        if ismember(v, string(W.Properties.VariableNames)) && ~isnumeric(W.(v)) && ~islogical(W.(v))
            W.(v) = str2double(W.(v));
        end
    end

    W.is_event = logical(W.is_event);
    W.window_eligible = logical(W.window_eligible);
    W = W(~isnat(W.trade_date) & ismember(W.root_code, ["fx", "gg"]), :);
    W = sortrows(W, {'trade_date', 'root_code'});
end


function W = prepare_validation_variables(W)

    W = standardize_pre_state(W);
    W.q_target = W.shock_target_10bp .^ 2;
    W.q_target_x_pre = W.q_target .* W.pre_state_z;
    W.q_factor = W.target_pca_10bp .^ 2 + W.path_pca_10bp .^ 2;
    W.q_factor_x_pre = W.q_factor .* W.pre_state_z;

    if ~ismember("root_gg", string(W.Properties.VariableNames))
        W.root_gg = double(W.root_code == "gg");
    else
        W.root_gg = double(W.root_code == "gg");
    end
end


function T = standardize_pre_state(T)

    T.pre_state_z = nan(height(T), 1);
    roots = ["fx", "gg"];

    for rootCode = roots
        rootMask = T.root_code == rootCode;
        controlMask = rootMask & ~T.is_event & T.window_eligible & isfinite(T.log_BV_pre);
        mu = mean(T.log_BV_pre(controlMask), 'omitnan');
        sigma = std(T.log_BV_pre(controlMask), 0, 'omitnan');

        if isfinite(sigma) && sigma > 0
            T.pre_state_z(rootMask) = (T.log_BV_pre(rootMask) - mu) ./ sigma;
        end
    end
end


function specs = validation_specs()

    specs = struct('id', {}, 'postOutcome', {}, 'preVar', {}, 'abnormal', {}, ...
        'matched', {}, 'q', {}, 'interaction', {}, 'root', {});

    specs(end + 1) = make_spec("TARGET_BV_pooled", "log_BV_post", "log_BV_pre", "abnormal_log_BV", "matched_abnormal_log_BV", "q_target", "q_target_x_pre", "pooled");
    specs(end + 1) = make_spec("TARGET_RV_pooled", "log_RV_post", "log_RV_pre", "abnormal_log_RV", "matched_abnormal_log_RV", "q_target", "q_target_x_pre", "pooled");
    specs(end + 1) = make_spec("TARGET_JUMP_pooled", "jump_share_post", "jump_share_pre", "abnormal_jump_share", "matched_abnormal_jump_share", "q_target", "q_target_x_pre", "pooled");
    specs(end + 1) = make_spec("FACTOR_BV_pooled", "log_BV_post", "log_BV_pre", "abnormal_log_BV", "matched_abnormal_log_BV", "q_factor", "q_factor_x_pre", "pooled");
    specs(end + 1) = make_spec("TARGET_BV_fx", "log_BV_post", "log_BV_pre", "abnormal_log_BV", "matched_abnormal_log_BV", "q_target", "q_target_x_pre", "fx");
    specs(end + 1) = make_spec("TARGET_BV_gg", "log_BV_post", "log_BV_pre", "abnormal_log_BV", "matched_abnormal_log_BV", "q_target", "q_target_x_pre", "gg");
end


function s = make_spec(id, postOutcome, preVar, abnormal, matched, q, interaction, root)

    s = struct('id', string(id), 'postOutcome', string(postOutcome), ...
        'preVar', string(preVar), 'abnormal', string(abnormal), ...
        'matched', string(matched), 'q', string(q), ...
        'interaction', string(interaction), 'root', string(root));
end


function [coefficientTable, summaryTable, equivalenceTable] = run_stacked_models(W, specs, cfg)

    coefficientCells = {};
    summaryCells = {};
    equivalenceCells = {};

    for s = 1:numel(specs)
        spec = specs(s);
        fprintf('  stacked model %d/%d: %s\n', s, numel(specs), spec.id);
        [y, X, terms, clusters, sampleInfo] = stacked_design(W, spec);

        if isempty(y) || sampleInfo.n_event_clusters < cfg.minimumEventClusters || rank(X) < size(X, 2)
            warning('Skipping stacked model %s: insufficient events or rank.', spec.id);
            continue;
        end

        [beta, V, se, tstat, pval, G, r2, adjR2] = cluster_ols_core(y, X, clusters);
        pWild = nan(numel(beta), 1);
        keyTerms = ["event_" + spec.q, "event_" + spec.interaction];
        eventTermMask = startsWith(terms, "event_");
        eventDf = max(sampleInfo.n_event_clusters - 1, 1);
        pval(eventTermMask) = 2 * tcdf(-abs(tstat(eventTermMask)), eventDf);

        for keyTerm = keyTerms
            j = find(terms == keyTerm, 1);
            if ~isempty(j)
                pWild(j) = wild_cluster_pvalue(y, X, clusters, j, tstat(j), cfg.wildRep);
            end
        end

        crit = repmat(tinv(0.975, max(G - 1, 1)), numel(beta), 1);
        crit(eventTermMask) = tinv(0.975, eventDf);
        C = table();
        C.model_name = repmat("STACKED_" + spec.id, numel(beta), 1);
        C.outcome = repmat(spec.postOutcome, numel(beta), 1);
        C.term = terms;
        C.beta = beta;
        C.se_cluster = se;
        C.t_stat = tstat;
        C.p_value = pval;
        C.p_wild_cluster = pWild;
        C.ci95_lo = beta - crit .* se;
        C.ci95_hi = beta + crit .* se;
        C.n_obs = repmat(numel(y), numel(beta), 1);
        C.n_clusters = repmat(G, numel(beta), 1);
        C.r2 = repmat(r2, numel(beta), 1);
        coefficientCells{end + 1, 1} = C;

        M = table();
        M.model_name = "STACKED_" + spec.id;
        M.outcome = spec.postOutcome;
        M.root_sample = spec.root;
        M.n_obs = numel(y);
        M.n_control_obs = sampleInfo.n_control_obs;
        M.n_event_obs = sampleInfo.n_event_obs;
        M.n_clusters = G;
        M.n_event_clusters = sampleInfo.n_event_clusters;
        M.n_parameters = size(X, 2);
        M.rank_design = rank(X);
        M.r2 = r2;
        M.adj_r2 = adjR2;
        summaryCells{end + 1, 1} = M;

        jInteraction = find(terms == "event_" + spec.interaction, 1);
        if ~isempty(jInteraction) && contains(spec.postOutcome, "log")
            equivalenceCells{end + 1, 1} = equivalence_row("stacked", "STACKED_" + spec.id, ...
                terms(jInteraction), beta(jInteraction), se(jInteraction), eventDf, cfg.equivalenceLogMargin);
        end
    end

    coefficientTable = vertcat_or_empty(coefficientCells);
    summaryTable = vertcat_or_empty(summaryCells);
    equivalenceTable = vertcat_or_empty(equivalenceCells);
end


function [y, X, terms, clusters, info] = stacked_design(W, spec)

    rootMask = true(height(W), 1);
    if spec.root ~= "pooled"
        rootMask = W.root_code == spec.root;
    end

    baseFinite = finite_variables(W, [spec.postOutcome, spec.preVar, "slow5_log_rv", "pre_state_z"]);
    eventFinite = ~W.is_event | finite_variables(W, [spec.q, "regime_hike"]);
    mask = rootMask & W.window_eligible & baseFinite & eventFinite;
    T = W(mask, :);

    if isempty(T)
        y = []; X = []; terms = strings(0, 1); clusters = strings(0, 1);
        info = struct('n_control_obs', 0, 'n_event_obs', 0, 'n_event_clusters', 0);
        return;
    end

    y = T.(spec.postOutcome);
    roots = ["fx", "gg"];
    if spec.root ~= "pooled"
        roots = spec.root;
    end

    baseTermCount = 21;
    Xnormal = zeros(height(T), baseTermCount * numel(roots));
    normalTerms = strings(baseTermCount * numel(roots), 1);

    for r = 1:numel(roots)
        rootCode = roots(r);
        rows = T.root_code == rootCode;
        train = rows & ~T.is_event;

        if sum(train) < 100
            y = []; X = []; terms = strings(0, 1); clusters = strings(0, 1);
            info = struct('n_control_obs', 0, 'n_event_obs', 0, 'n_event_clusters', 0);
            return;
        end

        meta = normal_design_meta(T, train, spec.preVar);
        Xroot = normal_design(T, rows, spec.preVar, meta);
        block = (r - 1) * baseTermCount + (1:baseTermCount);
        Xnormal(rows, block) = Xroot;
        normalTerms(block) = normal_term_names(spec.preVar, rootCode + "_normal_");
    end

    event = double(T.is_event);
    q = zeros(height(T), 1);
    q(T.is_event) = T.(spec.q)(T.is_event);
    stateEvent = event .* T.pre_state_z;
    qState = q .* T.pre_state_z;
    hike = zeros(height(T), 1);
    hike(T.is_event) = T.regime_hike(T.is_event);

    if spec.root == "pooled"
        Xevent = [event, event .* T.root_gg, q, stateEvent, qState, hike];
        eventTerms = ["event_intercept"; "event_root_gg"; "event_" + spec.q; ...
            "event_state"; "event_" + spec.interaction; "event_regime_hike"];
    else
        Xevent = [event, q, stateEvent, qState, hike];
        eventTerms = ["event_intercept"; "event_" + spec.q; ...
            "event_state"; "event_" + spec.interaction; "event_regime_hike"];
    end

    X = [Xnormal, Xevent];
    terms = [normalTerms; eventTerms];
    clusters = string(T.trade_date, 'yyyy-MM-dd');
    info = struct();
    info.n_control_obs = sum(~T.is_event);
    info.n_event_obs = sum(T.is_event);
    info.n_event_clusters = numel(unique(T.trade_date(T.is_event)));
end


function meta = normal_design_meta(T, mask, preVar)

    meta.preCenter = mean(T.(preVar)(mask), 'omitnan');
    meta.slowCenter = mean(T.slow5_log_rv(mask), 'omitnan');
    meta.trendOrigin = min(T.trade_date(mask));
    rawTrend = days(T.trade_date(mask) - meta.trendOrigin);
    meta.trendCenter = mean(rawTrend, 'omitnan');
end


function [X, terms] = normal_design(T, mask, preVar, meta)

    pre = T.(preVar)(mask) - meta.preCenter;
    slow = T.slow5_log_rv(mask) - meta.slowCenter;
    trend = days(T.trade_date(mask) - meta.trendOrigin) - meta.trendCenter;
    trend = trend ./ 365.25;
    X = [ones(sum(mask), 1), pre, pre .^ 2, slow, T.clock_late(mask), trend];
    terms = normal_term_names(preVar, "");

    weekdayBase = 5;
    for d = 2:6
        if d == weekdayBase; continue; end
        X = [X, double(T.weekday_number(mask) == d)];
    end

    for m = 2:12
        X = [X, double(T.month_number(mask) == m)];
    end
end


function terms = normal_term_names(preVar, prefix)

    terms = ["Intercept"; preVar + "_centered"; preVar + "_centered_sq"; ...
        "slow5_log_rv_centered"; "clock_late"; "time_trend_years"];
    for d = [2, 3, 4, 6]
        terms(end + 1, 1) = "weekday_" + string(d);
    end
    for m = 2:12
        terms(end + 1, 1) = "month_" + string(m);
    end
    terms = prefix + terms;
end


function resultTable = run_two_stage_bootstrap(W, specs, cfg)

    nSpecs = numel(specs);
    original = nan(nSpecs, 2);
    draws = nan(cfg.twoStageBootstrapRep, nSpecs, 2);

    for s = 1:nSpecs
        [beta, terms] = two_stage_point(W, specs(s));
        original(s, 1) = coefficient_by_name(beta, terms, specs(s).q);
        original(s, 2) = coefficient_by_name(beta, terms, specs(s).interaction);
    end

    controlGroups = date_index_cells(W, ~W.is_event);
    eventGroups = date_index_cells(W, W.is_event);

    for b = 1:cfg.twoStageBootstrapRep
        controlDraw = randi(numel(controlGroups), numel(controlGroups), 1);
        eventDraw = randi(numel(eventGroups), numel(eventGroups), 1);
        bootRows = [sample_group_rows(controlGroups, controlDraw); sample_group_rows(eventGroups, eventDraw)];
        B = W(bootRows, :);
        B = prepare_validation_variables(B);

        for s = 1:nSpecs
            [beta, terms] = two_stage_point(B, specs(s));
            draws(b, s, 1) = coefficient_by_name(beta, terms, specs(s).q);
            draws(b, s, 2) = coefficient_by_name(beta, terms, specs(s).interaction);
        end

        if mod(b, 100) == 0 || b == cfg.twoStageBootstrapRep
            fprintf('  two-stage bootstrap %d/%d\n', b, cfg.twoStageBootstrapRep);
        end
    end

    cells = {};
    for s = 1:nSpecs
        termNames = [specs(s).q, specs(s).interaction];
        for j = 1:2
            d = squeeze(draws(:, s, j));
            d = d(isfinite(d));
            R = table();
            R.method = "two_stage_date_bootstrap";
            R.model_name = "BOOTSTRAP_" + specs(s).id;
            R.outcome = specs(s).abnormal;
            R.term = termNames(j);
            R.beta_original = original(s, j);
            R.bootstrap_se = std(d, 0, 'omitnan');
            if isempty(d)
                R.ci95_lo = NaN;
                R.ci95_hi = NaN;
                R.p_bootstrap_two_sided = NaN;
                R.probability_positive = NaN;
            else
                R.ci95_lo = prctile(d, 2.5);
                R.ci95_hi = prctile(d, 97.5);
                pLo = (1 + sum(d <= 0)) / (1 + numel(d));
                pHi = (1 + sum(d >= 0)) / (1 + numel(d));
                R.p_bootstrap_two_sided = min(1, 2 * min(pLo, pHi));
                R.probability_positive = mean(d > 0);
            end
            R.n_usable = numel(d);
            R.n_requested = cfg.twoStageBootstrapRep;
            cells{end + 1, 1} = R;
        end
    end

    resultTable = vertcat_or_empty(cells);
end


function [beta, terms] = two_stage_point(W, spec)

    W = prepare_validation_variables(W);
    abnormal = nan(height(W), 1);
    roots = ["fx", "gg"];

    for rootCode = roots
        rootMask = W.root_code == rootCode;
        train = rootMask & ~W.is_event & W.window_eligible & ...
            finite_variables(W, [spec.postOutcome, spec.preVar, "slow5_log_rv"]);
        predict = rootMask & W.is_event & W.window_eligible & ...
            finite_variables(W, [spec.postOutcome, spec.preVar, "slow5_log_rv"]);

        if sum(train) < 100 || sum(predict) == 0
            continue;
        end

        meta = normal_design_meta(W, train, spec.preVar);
        Xtrain = normal_design(W, train, spec.preVar, meta);
        Xpredict = normal_design(W, predict, spec.preVar, meta);
        normalBeta = Xtrain \ W.(spec.postOutcome)(train);
        abnormal(predict) = W.(spec.postOutcome)(predict) - Xpredict * normalBeta;
    end

    W.validation_abnormal = abnormal;
    [y, X, terms] = event_design(W, "validation_abnormal", spec);

    if isempty(y) || rank(X) < size(X, 2)
        beta = nan(numel(terms), 1);
    else
        beta = X \ y;
    end
end


function [y, X, terms, clusters, mask] = event_design(T, outcomeVar, spec)

    rootMask = true(height(T), 1);
    if spec.root ~= "pooled"
        rootMask = T.root_code == spec.root;
    end

    rhs = [spec.q, "pre_state_z", spec.interaction, "regime_hike"];
    if spec.root == "pooled"
        rhs(end + 1) = "root_gg";
    end

    mask = T.is_event & T.window_eligible & rootMask & finite_variables(T, [outcomeVar, rhs]);
    y = T.(outcomeVar)(mask);
    X = ones(sum(mask), 1);
    terms = "Intercept";

    for v = rhs
        X = [X, T.(v)(mask)];
        terms(end + 1, 1) = v;
    end

    clusters = string(T.trade_date(mask), 'yyyy-MM-dd');
end


function [fit, coefficientTable] = fit_event_inference(T, outcomeVar, spec, modelName, wildRep)

    [y, X, terms, clusters] = event_design(T, outcomeVar, spec);
    fit = struct('ok', false, 'beta', [], 'V', [], 'se', [], 'tstat', [], ...
        'pval', [], 'G', 0, 'r2', NaN, 'adjR2', NaN, 'terms', terms, 'n', numel(y));
    coefficientTable = table();

    if isempty(y) || rank(X) < size(X, 2)
        return;
    end

    [beta, V, se, tstat, pval, G, r2, adjR2] = cluster_ols_core(y, X, clusters);
    pWild = nan(numel(beta), 1);

    if wildRep > 0
        for targetTerm = [spec.q, spec.interaction]
            j = find(terms == targetTerm, 1);
            if ~isempty(j)
                pWild(j) = wild_cluster_pvalue(y, X, clusters, j, tstat(j), wildRep);
            end
        end
    end

    crit = tinv(0.975, max(G - 1, 1));
    coefficientTable = table();
    coefficientTable.model_name = repmat(string(modelName), numel(beta), 1);
    coefficientTable.outcome = repmat(string(outcomeVar), numel(beta), 1);
    coefficientTable.term = terms;
    coefficientTable.beta = beta;
    coefficientTable.se_cluster = se;
    coefficientTable.t_stat = tstat;
    coefficientTable.p_value = pval;
    coefficientTable.p_wild_cluster = pWild;
    coefficientTable.ci95_lo = beta - crit .* se;
    coefficientTable.ci95_hi = beta + crit .* se;
    coefficientTable.n_obs = repmat(numel(y), numel(beta), 1);
    coefficientTable.n_clusters = repmat(G, numel(beta), 1);
    coefficientTable.r2 = repmat(r2, numel(beta), 1);

    fit.ok = true;
    fit.beta = beta;
    fit.V = V;
    fit.se = se;
    fit.tstat = tstat;
    fit.pval = pval;
    fit.G = G;
    fit.r2 = r2;
    fit.adjR2 = adjR2;
    fit.terms = terms;
    fit.n = numel(y);
end


function groups = date_index_cells(T, mask)

    rows = find(mask);
    [G, ~] = findgroups(T.trade_date(mask));
    nGroups = max(G);
    groups = cell(nGroups, 1);
    for g = 1:nGroups
        groups{g} = rows(G == g);
    end
end


function rows = sample_group_rows(groups, draw)

    lengths = cellfun(@numel, groups(draw));
    rows = zeros(sum(lengths), 1);
    cursor = 1;
    for j = 1:numel(draw)
        source = groups{draw(j)};
        destination = cursor:(cursor + numel(source) - 1);
        rows(destination) = source;
        cursor = cursor + numel(source);
    end
end


function value = coefficient_by_name(beta, terms, termName)

    j = find(terms == termName, 1);
    if isempty(j) || numel(beta) < j
        value = NaN;
    else
        value = beta(j);
    end
end


function [E, matchedRows, matchSets] = construct_matched_counterfactuals(W, cfg)

    E = W(W.is_event, :);
    E.matched_abnormal_log_BV = nan(height(E), 1);
    E.matched_abnormal_log_RV = nan(height(E), 1);
    E.matched_abnormal_jump_share = nan(height(E), 1);

    outcomes = ["log_BV_post", "log_RV_post", "jump_share_post"];
    preVars = ["log_BV_pre", "log_RV_pre", "jump_share_pre"];
    matchedVars = ["matched_abnormal_log_BV", "matched_abnormal_log_RV", "matched_abnormal_jump_share"];
    rowCells = {};
    matchSets = struct();

    for o = 1:numel(outcomes)
        outcome = outcomes(o);
        preVar = preVars(o);
        matchedVar = matchedVars(o);
        setCell = cell(height(E), 1);

        for i = 1:height(E)
            eventRow = E(i, :);
            candidateMask = ~W.is_event & W.window_eligible & ...
                W.root_code == eventRow.root_code & ...
                W.clock_late == eventRow.clock_late & ...
                W.weekday_number == eventRow.weekday_number & ...
                finite_variables(W, [outcome, preVar, "slow5_log_rv", "pre_state_z"]);

            eventFinite = finite_variables(eventRow, [outcome, preVar, "slow5_log_rv", "pre_state_z"]);
            if ~eventFinite
                continue;
            end

            timeGapYears = abs(days(W.trade_date - eventRow.trade_date)) ./ 365.25;
            localMask = candidateMask & timeGapYears <= cfg.matchMaxYears;
            candidates = find(localMask);
            if numel(candidates) < cfg.matchK
                candidates = find(candidateMask);
            end
            if numel(candidates) < 2
                continue;
            end

            rootControls = ~W.is_event & W.window_eligible & W.root_code == eventRow.root_code & isfinite(W.slow5_log_rv);
            slowScale = std(W.slow5_log_rv(rootControls), 0, 'omitnan');
            if ~isfinite(slowScale) || slowScale <= 0
                slowScale = 1;
            end

            stateGap = W.pre_state_z(candidates) - eventRow.pre_state_z;
            slowGapZ = (W.slow5_log_rv(candidates) - eventRow.slow5_log_rv) ./ slowScale;
            calendarGap = timeGapYears(candidates) ./ cfg.matchTimeScaleYears;
            distance = stateGap .^ 2 + slowGapZ .^ 2 + calendarGap .^ 2;
            [~, order] = sort(distance, 'ascend');
            k = min(cfg.matchK, numel(order));
            selected = candidates(order(1:k));
            setCell{i} = selected;

            matchedMean = mean(W.(outcome)(selected), 'omitnan');
            abnormal = eventRow.(outcome) - matchedMean;
            E.(matchedVar)(i) = abnormal;

            R = table();
            R.trade_date = eventRow.trade_date;
            R.root_code = eventRow.root_code;
            R.outcome = outcome;
            R.observed_post = eventRow.(outcome);
            R.matched_control_mean = matchedMean;
            R.matched_abnormal = abnormal;
            R.n_matches = k;
            R.mean_abs_state_gap = mean(abs(stateGap(order(1:k))), 'omitnan');
            R.mean_abs_slow_gap_z = mean(abs(slowGapZ(order(1:k))), 'omitnan');
            R.max_calendar_gap_years = max(timeGapYears(selected));
            R.pre_state_z = eventRow.pre_state_z;
            R.q_target = eventRow.q_target;
            R.q_factor = eventRow.q_factor;
            R.regime_hike = eventRow.regime_hike;
            rowCells{end + 1, 1} = R;
        end

        matchSets.(char(outcome)) = setCell;
    end

    matchedRows = vertcat_or_empty(rowCells);
end


function [coefficientTable, summaryTable, equivalenceTable] = run_matched_models(E, specs, cfg)

    coefficientCells = {};
    summaryCells = {};
    equivalenceCells = {};

    for s = 1:numel(specs)
        spec = specs(s);
        modelName = "MATCHED_" + spec.id;
        fprintf('  matched model %d/%d: %s\n', s, numel(specs), spec.id);
        [fit, C] = fit_event_inference(E, spec.matched, spec, modelName, cfg.wildRep);

        if ~fit.ok || fit.G < cfg.minimumEventClusters
            warning('Skipping matched model %s.', spec.id);
            continue;
        end

        coefficientCells{end + 1, 1} = C;
        M = table();
        M.model_name = modelName;
        M.outcome = spec.matched;
        M.root_sample = spec.root;
        M.n_obs = fit.n;
        M.n_clusters = fit.G;
        M.n_parameters = numel(fit.beta);
        M.rank_design = numel(fit.beta);
        M.r2 = fit.r2;
        M.adj_r2 = fit.adjR2;
        summaryCells{end + 1, 1} = M;

        jInteraction = find(fit.terms == spec.interaction, 1);
        if ~isempty(jInteraction) && contains(spec.postOutcome, "log")
            equivalenceCells{end + 1, 1} = equivalence_row("matched", modelName, ...
                spec.interaction, fit.beta(jInteraction), fit.se(jInteraction), fit.G - 1, cfg.equivalenceLogMargin);
        end
    end

    coefficientTable = vertcat_or_empty(coefficientCells);
    summaryTable = vertcat_or_empty(summaryCells);
    equivalenceTable = vertcat_or_empty(equivalenceCells);
end


function placeboTable = run_matched_placebos(W, E, matchSets, specs, matchedCoef, cfg)

    resultCells = {};

    for s = 1:numel(specs)
        spec = specs(s);
        sets = matchSets.(char(spec.postOutcome));
        placeboDraws = nan(cfg.placeboRep, 2);
        termNames = [spec.q, spec.interaction];
        modelName = "MATCHED_" + spec.id;

        observed = nan(1, 2);
        for j = 1:2
            row = matchedCoef.model_name == modelName & matchedCoef.term == termNames(j);
            if any(row)
                observed(j) = matchedCoef.beta(find(row, 1));
            end
        end

        for b = 1:cfg.placeboRep
            P = E;
            pseudoOutcome = nan(height(P), 1);
            pseudoState = nan(height(P), 1);

            for i = 1:height(P)
                selected = sets{i};
                if numel(selected) < 2
                    continue;
                end
                chosenPosition = randi(numel(selected));
                chosen = selected(chosenPosition);
                other = selected;
                other(chosenPosition) = [];
                pseudoOutcome(i) = W.(spec.postOutcome)(chosen) - mean(W.(spec.postOutcome)(other), 'omitnan');
                pseudoState(i) = W.pre_state_z(chosen);
            end

            P.placebo_outcome = pseudoOutcome;
            P.pre_state_z = pseudoState;
            P.q_target_x_pre = P.q_target .* P.pre_state_z;
            P.q_factor_x_pre = P.q_factor .* P.pre_state_z;
            [y, X, terms] = event_design(P, "placebo_outcome", spec);

            if ~isempty(y) && rank(X) == size(X, 2)
                beta = X \ y;
                placeboDraws(b, 1) = coefficient_by_name(beta, terms, spec.q);
                placeboDraws(b, 2) = coefficient_by_name(beta, terms, spec.interaction);
            end
        end

        for j = 1:2
            d = placeboDraws(:, j);
            d = d(isfinite(d));
            R = table();
            R.model_name = "PLACEBO_" + spec.id;
            R.outcome = spec.matched;
            R.term = termNames(j);
            R.observed_beta = observed(j);
            if isempty(d) || ~isfinite(observed(j))
                R.placebo_mean = NaN;
                R.placebo_sd = NaN;
                R.placebo_ci95_lo = NaN;
                R.placebo_ci95_hi = NaN;
                R.p_placebo_two_sided = NaN;
            else
                R.placebo_mean = mean(d, 'omitnan');
                R.placebo_sd = std(d, 0, 'omitnan');
                R.placebo_ci95_lo = prctile(d, 2.5);
                R.placebo_ci95_hi = prctile(d, 97.5);
                R.p_placebo_two_sided = (1 + sum(abs(d) >= abs(observed(j)))) / (1 + numel(d));
            end
            R.n_usable = numel(d);
            R.n_requested = cfg.placeboRep;
            resultCells{end + 1, 1} = R;
        end

        fprintf('  matched placebo %d/%d: %s\n', s, numel(specs), spec.id);
    end

    placeboTable = vertcat_or_empty(resultCells);
end


function [byEvent, summary] = build_support_diagnostics(W)

    E = W(W.is_event & isfinite(W.q_target), :);
    eventDates = unique(E.trade_date);
    cells = {};

    for i = 1:numel(eventDates)
        d = eventDates(i);
        rows = E.trade_date == d;
        sub = E(rows, :);
        R = table();
        R.trade_date = d;
        R.shock_target_10bp = first_finite(sub.shock_target_10bp);
        R.q_target = first_finite(sub.q_target);
        R.q_factor = first_finite(sub.q_factor);
        R.regime_hike = first_finite(sub.regime_hike);
        R.mean_pre_state_z = mean(sub.pre_state_z, 'omitnan');
        R.fx_pre_state_z = first_finite(sub.pre_state_z(sub.root_code == "fx"));
        R.gg_pre_state_z = first_finite(sub.pre_state_z(sub.root_code == "gg"));
        R.n_roots = height(sub);
        cells{end + 1, 1} = R;
    end

    byEvent = vertcat_or_empty(cells);
    byEvent = sortrows(byEvent, 'q_target', 'descend');
    byEvent.energy_rank = transpose(1:height(byEvent));
    totalQ = sum(byEvent.q_target, 'omitnan');
    totalQ2 = sum(byEvent.q_target .^ 2, 'omitnan');
    byEvent.q_share = byEvent.q_target ./ totalQ;
    byEvent.q_cumulative_share = cumsum(byEvent.q_share);
    byEvent.q_squared_share = byEvent.q_target .^ 2 ./ totalQ2;
    byEvent.q_squared_cumulative_share = cumsum(byEvent.q_squared_share);
    byEvent.pooled_bv_leverage = event_leverage_by_date(W, byEvent.trade_date);

    q = byEvent.q_target;
    positiveQ = q(q > 0);
    [vifQ, vifInteraction, corrQI] = q_state_collinearity(W);

    summary = table();
    summary.n_event_dates = height(byEvent);
    summary.share_zero_q = mean(q == 0);
    summary.q_median = median(q, 'omitnan');
    summary.q_p95 = prctile(q, 95);
    summary.q_max = max(q);
    summary.q_max_to_positive_median = max(q) ./ median(positiveQ, 'omitnan');
    summary.top1_share_q = sum(q(1:min(1, numel(q)))) ./ totalQ;
    summary.top2_share_q = sum(q(1:min(2, numel(q)))) ./ totalQ;
    summary.top3_share_q = sum(q(1:min(3, numel(q)))) ./ totalQ;
    summary.top1_share_q_squared = sum(q(1:min(1, numel(q))) .^ 2) ./ totalQ2;
    summary.top2_share_q_squared = sum(q(1:min(2, numel(q))) .^ 2) ./ totalQ2;
    summary.top3_share_q_squared = sum(q(1:min(3, numel(q))) .^ 2) ./ totalQ2;
    summary.corr_q_q_x_state = corrQI;
    summary.vif_q = vifQ;
    summary.vif_q_x_state = vifInteraction;
end


function leverage = event_leverage_by_date(W, requestedDates)

    leverage = nan(numel(requestedDates), 1);
    if ~ismember("abnormal_log_BV", string(W.Properties.VariableNames))
        return;
    end

    spec = make_spec("TEMP", "log_BV_post", "log_BV_pre", "abnormal_log_BV", ...
        "matched_abnormal_log_BV", "q_target", "q_target_x_pre", "pooled");
    [y, X, ~, ~, mask] = event_design(W, "abnormal_log_BV", spec); %#ok<ASGLU>
    if isempty(X) || rank(X) < size(X, 2)
        return;
    end

    XtXi = pinv(X' * X);
    rowLeverage = sum((X * XtXi) .* X, 2);
    dates = W.trade_date(mask);

    for i = 1:numel(requestedDates)
        leverage(i) = sum(rowLeverage(dates == requestedDates(i)), 'omitnan');
    end
end


function [vifQ, vifInteraction, correlation] = q_state_collinearity(W)

    required = ["q_target", "pre_state_z", "q_target_x_pre", "regime_hike", "root_gg"];
    mask = W.is_event & W.window_eligible & finite_variables(W, required);
    X = [W.q_target(mask), W.pre_state_z(mask), W.q_target_x_pre(mask), W.regime_hike(mask), W.root_gg(mask)];
    correlation = corr(X(:, 1), X(:, 3), 'Rows', 'complete');
    vifQ = auxiliary_vif(X, 1);
    vifInteraction = auxiliary_vif(X, 3);
end


function vif = auxiliary_vif(X, column)

    y = X(:, column);
    Z = X(:, setdiff(1:size(X, 2), column));
    Z = [ones(size(Z, 1), 1), Z];
    beta = Z \ y;
    residual = y - Z * beta;
    tss = sum((y - mean(y)) .^ 2);
    r2 = 1 - sum(residual .^ 2) / tss;
    vif = 1 / max(1 - r2, eps);
end


function resultTable = run_leave_top_k(W, specs, cfg)

    cells = {};

    for s = 1:numel(specs)
        spec = specs(s);
        fprintf('  leave-top-k model %d/%d: %s\n', s, numel(specs), spec.id);
        if ~ismember(spec.abnormal, string(W.Properties.VariableNames))
            continue;
        end

        [rankedDates, rankedEnergy] = ranked_event_energy(W, spec.q);
        maxK = min(cfg.leaveTopK, numel(rankedDates) - cfg.minimumEventClusters);

        for k = 0:maxK
            dropDates = rankedDates(1:k);
            keep = ~W.is_event | ~ismember(W.trade_date, dropDates);
            T = W(keep, :);
            wildRep = 0;
            if ismember(k, cfg.leaveWildK)
                wildRep = cfg.wildRep;
            end
            [fit, C] = fit_event_inference(T, spec.abnormal, spec, "LEAVE_TOP_" + spec.id, wildRep);
            if ~fit.ok
                continue;
            end

            for termName = [spec.q, spec.interaction]
                row = C.term == termName;
                if ~any(row)
                    continue;
                end
                R = C(find(row, 1), :);
                R.k_removed = k;
                if k == 0
                    R.removed_dates = "";
                    R.largest_removed_energy = NaN;
                else
                    R.removed_dates = strjoin(string(dropDates, 'yyyy-MM-dd'), ';');
                    R.largest_removed_energy = rankedEnergy(1);
                end
                if k < numel(rankedEnergy)
                    R.largest_retained_energy = rankedEnergy(k + 1);
                else
                    R.largest_retained_energy = NaN;
                end
                cells{end + 1, 1} = R;
            end
        end
    end

    resultTable = vertcat_or_empty(cells);
end


function [dates, energy] = ranked_event_energy(W, qVar)

    E = W(W.is_event & isfinite(W.(qVar)), :);
    uniqueDates = unique(E.trade_date);
    energy = nan(numel(uniqueDates), 1);
    for i = 1:numel(uniqueDates)
        energy(i) = first_finite(E.(qVar)(E.trade_date == uniqueDates(i)));
    end
    [energy, order] = sort(energy, 'descend');
    dates = uniqueDates(order);
end


function value = first_finite(x)

    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = x(1);
    end
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

    if ~isfinite(observedT) || B <= 0
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
    n = numel(y);
    k = size(X, 2);
    XtXi = pinv(X' * X);
    correction = (G / max(G - 1, 1)) * ((n - 1) / max(n - k, 1));
    clusterMap = sparse(clusterId, transpose(1:n), 1, G, n);
    exceed = 0;
    usable = 0;

    for b = 1:B
        weights = 2 * (rand(G, 1) >= 0.5) - 1;
        yStar = fitted0 + residual0 .* weights(clusterId);
        betaStar = XtXi * (X' * yStar);
        residualStar = yStar - X * betaStar;
        score = clusterMap * (X .* residualStar);
        meat = score' * score;
        VStar = correction * XtXi * meat * XtXi;
        seStar = sqrt(max(VStar(testedColumn, testedColumn), 0));
        if isfinite(seStar) && seStar > 0
            tStar = betaStar(testedColumn) / seStar;
            exceed = exceed + double(abs(tStar) >= abs(observedT));
            usable = usable + 1;
        end
    end

    p = (1 + exceed) / (1 + usable);
end


function T = equivalence_row(method, modelName, termName, estimate, se, df, margin)

    tLower = (estimate + margin) / se;
    tUpper = (estimate - margin) / se;
    pLower = 1 - tcdf(tLower, max(df, 1));
    pUpper = tcdf(tUpper, max(df, 1));
    pTost = max(pLower, pUpper);
    crit90 = tinv(0.95, max(df, 1));

    T = table();
    T.method = string(method);
    T.model_name = string(modelName);
    T.term = string(termName);
    T.estimate = estimate;
    T.se_cluster = se;
    T.margin_log_points = margin;
    T.margin_multiplier_ratio = exp(margin);
    T.ci90_lo = estimate - crit90 * se;
    T.ci90_hi = estimate + crit90 * se;
    T.p_tost = pTost;
    T.equivalent_at_5pct = pTost < 0.05;
end


function mask = finite_variables(T, vars)

    mask = true(height(T), 1);
    available = string(T.Properties.VariableNames);
    for v = vars
        if ~ismember(v, available)
            mask(:) = false;
            return;
        end
        x = T.(v);
        if isstring(x) || iscellstr(x)
            x = str2double(x);
        end
        mask = mask & isfinite(x);
    end
end


function T = vertcat_or_empty(cells)

    if isempty(cells)
        T = table();
    else
        T = vertcat(cells{:});
    end
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
