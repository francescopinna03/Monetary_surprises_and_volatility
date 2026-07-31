function Rank_one_feasibility()
%RANK_ONE_FEASIBILITY Step 27, module A: calibrated rank-one gate.
%
% Module A is logically prior to any jump-detectability frontier.  It fits a
% common-direction rank-one null to the Step-25 PR-PC quadratic gap and uses
% a null-imposed pairs/wild event bootstrap to ask whether the observed
% second mode and direction instability are unusual under that null.
%
% No point vector v_MP is used.  The reference direction is estimated inside
% every sample; MP-like remains the Step-25 opposite-sign sector restriction.

    projectRoot = Get_project_root();
    Require_time_alignment_manifest(projectRoot);
    Require_window_semantics_manifest(projectRoot);

    analysisDir = fullfile(projectRoot, 'Output', 'analysis');
    phaseDir = fullfile(projectRoot, 'Output', 'phase_counterfactuals');
    step25Dir = fullfile(projectRoot, 'Output', 'invariant_phase_attribution');
    step26Dir = fullfile(projectRoot, 'Output', 'long_horizon_attribution');
    drawCount = parse_draw_count(getenv('RANK_ONE_FEASIBILITY_DRAWS'), 999);
    if drawCount == 999
        outputDir = fullfile(projectRoot, 'Output', 'rank_one_feasibility');
    else
        outputDir = fullfile(projectRoot, 'Output', 'rank_one_feasibility_smoke');
    end
    if exist(outputDir, 'dir') ~= 7; mkdir(outputDir); end

    files = struct();
    files.pr = fullfile(phaseDir, 'phase_counterfactual_pr_event_rows.csv');
    files.pc = fullfile(phaseDir, 'phase_counterfactual_pc_event_rows.csv');
    files.components = fullfile(analysisDir, 'shock_components_by_event.csv');
    files.step25Decision = fullfile(step25Dir, 'step25_decision.csv');
    files.step25Manifest = fullfile(step25Dir, 'step25_manifest.csv');
    files.step26Decision = fullfile(step26Dir, 'step26_decision.csv');
    files.step26Manifest = fullfile(step26Dir, 'step26_manifest.csv');
    fileNames = string(struct2cell(files));
    for j = 1:numel(fileNames)
        if exist(fileNames(j), 'file') ~= 2
            error('STEP27A_INPUT_MISSING: required input not found: %s', ...
                fileNames(j));
        end
    end
    validate_predecessors(files);

    cfg = struct();
    cfg.seed = 27020;
    cfg.bootstrapRep = drawCount;
    cfg.outcome = "abnormal_log_BV";
    cfg.states = [-1, 0, 1];
    cfg.topK = [0, 1, 3, 5];
    cfg.alpha = 0.05;
    cfg.coarseDegrees = 5;
    rng(cfg.seed, 'twister');

    C = load_components(files.components);
    PR = prepare_phase(load_event_rows(files.pr), C, "PR");
    PC = prepare_phase(load_event_rows(files.pc), C, "PC");
    predictors = ["q_policy", "q_equity", "q_policy_equity", ...
        "pre_state_z", "q_policy_x_pre", "q_equity_x_pre", ...
        "q_policy_equity_x_pre", "regime_hike", "root_gg"];
    levelTerms = ["q_policy", "q_equity", "q_policy_equity"];
    slopeTerms = ["q_policy_x_pre", "q_equity_x_pre", ...
        "q_policy_equity_x_pre"];
    ranking = total_energy_ranking(PR, PC);

    calibrationCells = cell(numel(cfg.topK), 1);
    geometryCells = cell(numel(cfg.topK), 1);
    nullFitCells = cell(numel(cfg.topK), 1);
    drawCells = cell(numel(cfg.topK), 1);

    for j = 1:numel(cfg.topK)
        topK = cfg.topK(j);
        excluded = ranking.event_date(1:min(topK, height(ranking)));
        S = build_stacked(PR, PC, cfg.outcome, predictors, excluded);
        unrestricted = Step23_cluster_ols(S.y, S.X, S.clusters);
        Rlevel = phase_equality_matrix(S.term_names, levelTerms);
        Rslope = phase_equality_matrix(S.term_names, slopeTerms);
        shockCovariance = pooled_shock_covariance(S.pr, S.pc);

        nullFit = Step27_rank_one_null_fit(S.y, S.X, S.term_names, ...
            shockCovariance, cfg.coarseDegrees);
        deltaLevel = Rlevel * unrestricted.beta;
        deltaSlope = Rslope * unrestricted.beta;
        [point, geometry] = Step27_rank_statistics(deltaLevel, deltaSlope, ...
            shockCovariance, cfg.states, nullFit.reference_direction);
        geometry.outcome = repmat(cfg.outcome, height(geometry), 1);
        geometry.excluded_top_events = repmat(topK, height(geometry), 1);
        geometry.n_clusters = repmat(unrestricted.G, height(geometry), 1);
        geometry = movevars(geometry, ...
            {'outcome', 'excluded_top_events', 'n_clusters'}, 'Before', 1);

        draws = bootstrap_null(S, Rlevel, Rslope, nullFit, cfg, topK);
        calibration = calibration_rows(point, draws, cfg, topK);
        nullRow = null_fit_row(nullFit, unrestricted, shockCovariance, topK);

        calibrationCells{j} = calibration;
        geometryCells{j} = geometry;
        nullFitCells{j} = nullRow;
        drawCells{j} = draws;
    end

    calibration = vertcat(calibrationCells{:});
    geometry = vertcat(geometryCells{:});
    nullFits = vertcat(nullFitCells{:});
    bootstrapDraws = vertcat(drawCells{:});

    calibration.p_holm_scope = nan(height(calibration), 1);
    primary = calibration.excluded_top_events == 0;
    robustness = calibration.excluded_top_events > 0;
    calibration.p_holm_scope(primary) = ...
        Step23_holm_adjust(calibration.p_value(primary));
    calibration.p_holm_scope(robustness) = ...
        Step23_holm_adjust(calibration.p_value(robustness));
    calibration.reject_rank_one = ...
        calibration.p_holm_scope <= cfg.alpha;

    decision = build_decision(calibration, geometry, cfg);
    manifest = build_manifest(fileNames, cfg);

    writetable(calibration, fullfile(outputDir, ...
        'step27a_rank_calibration.csv'));
    writetable(geometry, fullfile(outputDir, ...
        'step27a_observed_geometry.csv'));
    writetable(nullFits, fullfile(outputDir, ...
        'step27a_null_fits.csv'));
    writetable(bootstrapDraws, fullfile(outputDir, ...
        'step27a_null_bootstrap.csv'));
    writetable(decision, fullfile(outputDir, 'step27a_decision.csv'));
    writetable(manifest, fullfile(outputDir, 'step27a_manifest.csv'));

    gate = decision(decision.test_id == "MODULE_A_RANK_GATE", :);
    fprintf('\n================ STEP 27A RANK CALIBRATION ================\n');
    fprintf('Bootstrap draws : %d per leave-top-k sample\n', cfg.bootstrapRep);
    fprintf('Reference       : jointly estimated common direction; MP is a sector\n');
    disp(calibration(:, {'excluded_top_events', 'statistic_id', ...
        'observed_value', 'p_value', 'p_holm_scope', 'reject_rank_one'}));
    disp(decision(:, {'test_id', 'status', 'recommendation'}));
    if cfg.bootstrapRep ~= 999
        fprintf('Module B status : not evaluated; smoke test only\n');
    elseif gate.status == "pass"
        fprintf('Module B status : eligible, not run\n');
    else
        fprintf('Module B status : blocked; reopen rank specification\n');
    end
    fprintf('Output directory: %s\n', outputDir);
    fprintf('===========================================================\n');
end

function draws = bootstrap_null(S, Rlevel, Rslope, nullFit, cfg, topK)
    [clusterNames, ~, clusterId] = unique(S.clusters, 'stable');
    G = numel(clusterNames);
    sourceRows = cell(G, 1);
    for g = 1:G
        sourceRows{g} = find(clusterId == g);
    end
    [prShock, pcShock] = shocks_by_cluster(S.pr, S.pc, clusterNames);

    rows = cell(cfg.bootstrapRep, 1);
    for b = 1:cfg.bootstrapRep
        sample = randi(G, G, 1);
        wildWeights = 2 * (rand(G, 1) >= 0.5) - 1;
        sampledRows = cell(G, 1);
        sampledWeights = cell(G, 1);
        for g = 1:G
            idx = sourceRows{sample(g)};
            sampledRows{g} = idx;
            sampledWeights{g} = repmat(wildWeights(g), numel(idx), 1);
        end
        rowIndex = vertcat(sampledRows{:});
        weightsStar = vertcat(sampledWeights{:});
        Xstar = S.X(rowIndex, :);
        ystar = nullFit.fitted(rowIndex) + ...
            nullFit.residual(rowIndex) .* weightsStar;
        shockCovarianceStar = cov([prShock(sample, :); pcShock(sample, :)], 0);

        betaStar = Xstar \ ystar;
        nullStar = Step27_rank_one_null_fit(ystar, Xstar, S.term_names, ...
            shockCovarianceStar, cfg.coarseDegrees);
        deltaLevel = Rlevel * betaStar;
        deltaSlope = Rslope * betaStar;
        [stat, ~] = Step27_rank_statistics(deltaLevel, deltaSlope, ...
            shockCovarianceStar, cfg.states, nullStar.reference_direction);

        row = table();
        row.excluded_top_events = topK;
        row.draw = b;
        row.max_abs_secondary = stat.max_abs_secondary;
        row.max_secondary_share = stat.max_secondary_share;
        row.max_direction_deviation_degrees = ...
            stat.max_direction_deviation_degrees;
        row.all_states_mp_like = stat.all_states_mp_like;
        row.all_leading_negative = stat.all_leading_negative;
        row.reference_policy_direction = nullStar.reference_direction(1);
        row.reference_equity_direction = nullStar.reference_direction(2);
        row.reference_angle_degrees = nullStar.reference_angle_degrees;
        row.reference_sector = nullStar.reference_sector;
        rows{b} = row;
    end
    draws = vertcat(rows{:});
end

function T = calibration_rows(point, draws, cfg, topK)
    ids = ["MAX_ABS_SECONDARY_EIGENVALUE"; ...
        "MAX_SECONDARY_ABSOLUTE_SHARE"; ...
        "MAX_COMMON_DIRECTION_DEVIATION"];
    observed = [point.max_abs_secondary; point.max_secondary_share; ...
        point.max_direction_deviation_degrees];
    drawVariables = ["max_abs_secondary"; "max_secondary_share"; ...
        "max_direction_deviation_degrees"];
    T = table();
    T.excluded_top_events = repmat(topK, 3, 1);
    T.scope = repmat(conditional_text(topK == 0, ...
        "primary_full_sample", "leave_top_k_robustness"), 3, 1);
    T.statistic_id = ids;
    T.observed_value = observed;
    T.null_q95 = nan(3, 1);
    T.p_value = nan(3, 1);
    T.bootstrap_draws = repmat(cfg.bootstrapRep, 3, 1);
    for j = 1:3
        values = double(draws.(drawVariables(j)));
        values = values(isfinite(values));
        T.null_q95(j) = quantile(values, 0.95);
        T.p_value(j) = (1 + sum(values >= observed(j))) / ...
            (1 + numel(values));
    end
end

function row = null_fit_row(nullFit, unrestricted, shockCovariance, topK)
    row = table();
    row.excluded_top_events = topK;
    row.n_clusters = unrestricted.G;
    row.unrestricted_sse = unrestricted.residual' * unrestricted.residual;
    row.rank_one_null_sse = nullFit.sse;
    row.sse_ratio = nullFit.sse / row.unrestricted_sse;
    row.reference_policy_direction = nullFit.reference_direction(1);
    row.reference_equity_direction = nullFit.reference_direction(2);
    row.reference_angle_degrees = nullFit.reference_angle_degrees;
    row.reference_sector = nullFit.reference_sector;
    row.level_amplitude = nullFit.level_amplitude;
    row.slope_amplitude = nullFit.slope_amplitude;
    row.shock_variance_policy = shockCovariance(1, 1);
    row.shock_variance_equity = shockCovariance(2, 2);
    row.shock_covariance = shockCovariance(1, 2);
end

function D = build_decision(calibration, geometry, cfg)
    if cfg.bootstrapRep ~= 999
        rows = cell(5, 1);
        rows{1} = decision_row("REFERENCE_DIRECTION_DEFINITION", "pass", ...
            "mp_is_sign_restricted_sector_and_common_direction_is_jointly_reestimated", true);
        rows{2} = decision_row("FULL_SAMPLE_RANK_ONE_NULL", ...
            "not_evaluated_smoke_only", "run_final_999_draw_rank_calibration", false);
        rows{3} = decision_row("LEAVE_TOP_K_RANK_STABILITY", ...
            "not_evaluated_smoke_only", "run_final_999_draw_rank_calibration", false);
        rows{4} = decision_row("MODULE_A_RANK_GATE", ...
            "not_evaluated_smoke_only", "run_final_999_draw_rank_calibration", false);
        rows{5} = decision_row("MODULE_B_JUMP_FRONTIER", ...
            "not_evaluated_smoke_only", "final_module_a_required", false);
        D = vertcat(rows{:});
        D.alpha = repmat(cfg.alpha, height(D), 1);
        return;
    end

    primaryCalibration = calibration.excluded_top_events == 0;
    robustCalibration = calibration.excluded_top_events > 0;
    primaryGeometry = geometry.excluded_top_events == 0;
    robustGeometry = geometry.excluded_top_events > 0;

    primaryPass = ~any(calibration.reject_rank_one(primaryCalibration)) && ...
        all(geometry.sector(primaryGeometry) == "MP_LIKE") && ...
        all(geometry.leading_eigenvalue(primaryGeometry) < 0);
    robustnessPass = ~any(calibration.reject_rank_one(robustCalibration)) && ...
        all(geometry.sector(robustGeometry) == "MP_LIKE") && ...
        all(geometry.leading_eigenvalue(robustGeometry) < 0);
    gatePass = primaryPass && robustnessPass;

    rows = cell(5, 1);
    rows{1} = decision_row("REFERENCE_DIRECTION_DEFINITION", "pass", ...
        "mp_is_sign_restricted_sector_and_common_direction_is_jointly_reestimated", true);
    rows{2} = decision_row("FULL_SAMPLE_RANK_ONE_NULL", ...
        pass_status(primaryPass), conditional_text(primaryPass, ...
        "rank_one_not_rejected_by_calibrated_triad", ...
        "rank_one_rejected_or_mp_direction_not_preserved"), primaryPass);
    rows{3} = decision_row("LEAVE_TOP_K_RANK_STABILITY", ...
        pass_status(robustnessPass), conditional_text(robustnessPass, ...
        "rank_one_admissibility_survives_top_1_3_5_exclusions", ...
        "rank_one_admissibility_fails_top_k_robustness"), robustnessPass);
    rows{4} = decision_row("MODULE_A_RANK_GATE", pass_status(gatePass), ...
        conditional_text(gatePass, ...
        "rank_one_is_admissible_not_established", ...
        "reopen_rank_question_and_do_not_run_module_b"), gatePass);
    if gatePass
        rows{5} = decision_row("MODULE_B_JUMP_FRONTIER", "eligible_not_run", ...
            "freeze_module_b_design_before_execution", false);
    else
        rows{5} = decision_row("MODULE_B_JUMP_FRONTIER", "blocked", ...
            "module_a_failed_frontier_is_not_well_posed_under_rank_one", false);
    end
    D = vertcat(rows{:});
    D.alpha = repmat(cfg.alpha, height(D), 1);
end

function row = decision_row(testId, status, recommendation, robustClaim)
    row = table(string(testId), string(status), string(recommendation), ...
        logical(robustClaim), 'VariableNames', ...
        {'test_id', 'status', 'recommendation', 'robust_claim'});
end

function validate_predecessors(files)
    M25 = readtable(files.step25Manifest, 'Delimiter', ',', ...
        'TextType', 'string', 'VariableNamingRule', 'preserve');
    assert_columns(M25, ["name", "value"], files.step25Manifest);
    schema25 = M25.value(M25.name == "schema_version");
    draws25 = str2double(M25.value(M25.name == "bootstrap_draws"));
    if numel(schema25) ~= 1 || schema25 ~= "step25_v1" || ...
            numel(draws25) ~= 1 || draws25 ~= 999
        error('STEP27A_STEP25_MANIFEST: final 999-draw step25_v1 required.');
    end
    D25 = readtable(files.step25Decision, 'Delimiter', ',', ...
        'TextType', 'string', 'VariableNamingRule', 'preserve');
    assert_columns(D25, ["test_id", "status", "recommendation"], ...
        files.step25Decision);
    mp = D25.test_id == "MP_LIKE_GEOMETRIC_DIRECTION";
    dominance = D25.test_id == "SINGLE_DIRECTION_DOMINANCE";
    if sum(mp) ~= 1 || D25.status(mp) ~= "pass" || ...
            D25.recommendation(mp) ~= "mp_like_direction_set_identified" || ...
            sum(dominance) ~= 1 || D25.status(dominance) ~= "fail" || ...
            D25.recommendation(dominance) ~= ...
                "mp_like_dominant_but_rank_one_not_established"
        error(['STEP27A_STEP25_DECISION: MP-like direction plus unresolved ' ...
            'rank-one status required.']);
    end

    M26 = readtable(files.step26Manifest, 'Delimiter', ',', ...
        'TextType', 'string', 'VariableNamingRule', 'preserve');
    assert_columns(M26, ["name", "value"], files.step26Manifest);
    schema26 = M26.value(M26.name == "schema_version");
    draws26 = str2double(M26.value(M26.name == "bootstrap_draws"));
    if numel(schema26) ~= 1 || schema26 ~= "step26_v1" || ...
            numel(draws26) ~= 1 || draws26 ~= 999
        error('STEP27A_STEP26_MANIFEST: final 999-draw step26_v1 required.');
    end
    D26 = readtable(files.step26Decision, 'Delimiter', ',', ...
        'TextType', 'string', 'VariableNamingRule', 'preserve');
    assert_columns(D26, ["test_id", "status", "recommendation"], ...
        files.step26Decision);
    construction = D26.test_id == "OFFICIAL_FACTOR_CONSTRUCTION";
    longBlock = D26.test_id == "LONG_CURVE_INCREMENTAL_BLOCK";
    named = D26.test_id == "SINGLE_OFFICIAL_COMPONENT_DOMINANCE";
    if sum(construction) ~= 1 || D26.status(construction) ~= "pass" || ...
            sum(longBlock) ~= 1 || D26.status(longBlock) ~= "fail" || ...
            sum(named) ~= 1 || D26.status(named) ~= "fail"
        error(['STEP27A_STEP26_DECISION: certified factors and failed robust ' ...
            'long-curve attribution required.']);
    end
end

function T = load_event_rows(filePath)
    T = readtable(filePath, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "root_code", "abnormal_log_BV", ...
        "pre_state_z", "regime_hike", "root_gg", "q_mp", "q_cbi"];
    assert_columns(T, required, filePath);
    T.event_date = Parse_date_flexible(T.event_date);
    T.root_code = lower(string(T.root_code));
    numeric = ["abnormal_log_BV", "pre_state_z", "regime_hike", ...
        "root_gg", "q_mp", "q_cbi"];
    for j = 1:numel(numeric)
        if ~isnumeric(T.(numeric(j))) && ~islogical(T.(numeric(j)))
            T.(numeric(j)) = str2double(string(T.(numeric(j))));
        end
    end
end

function C = load_components(filePath)
    C = readtable(filePath, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "window", "policy_indicator_10bp", ...
        "STOXX50", "estimation_sample", "in_project_sample"];
    assert_columns(C, required, filePath);
    C.event_date = Parse_date_flexible(C.event_date);
    C.window = upper(string(C.window));
    numeric = ["policy_indicator_10bp", "STOXX50"];
    for j = 1:numel(numeric)
        if ~isnumeric(C.(numeric(j)))
            C.(numeric(j)) = str2double(string(C.(numeric(j))));
        end
    end
    C.estimation_sample = to_logical(C.estimation_sample);
    C.in_project_sample = to_logical(C.in_project_sample);
end

function T = prepare_phase(T, C, phase)
    keep = C.window == phase & C.estimation_sample & C.in_project_sample;
    variables = ["event_date", "policy_indicator_10bp", "STOXX50"];
    S = C(keep, variables);
    [~, first] = unique(S.event_date, 'stable');
    S = S(first, :);
    T = innerjoin(T, S, 'Keys', 'event_date');
    if isempty(T)
        error('STEP27A_NO_MATCHES: no component matches for phase %s.', phase);
    end
    policy = double(T.policy_indicator_10bp);
    equity = double(T.STOXX50);
    state = double(T.pre_state_z);
    T.q_policy = policy .^ 2;
    T.q_equity = equity .^ 2;
    T.q_policy_equity = 2 * policy .* equity;
    T.q_policy_x_pre = T.q_policy .* state;
    T.q_equity_x_pre = T.q_equity .* state;
    T.q_policy_equity_x_pre = T.q_policy_equity .* state;
end

function S = build_stacked(PR, PC, outcome, predictors, excludedDates)
    if ~isempty(excludedDates)
        PR = PR(~ismember(PR.event_date, excludedDates), :);
        PC = PC(~ismember(PC.event_date, excludedDates), :);
    end
    PR = PR(finite_variables(PR, [outcome, predictors]), :);
    PC = PC(finite_variables(PC, [outcome, predictors]), :);
    prKey = string(PR.event_date, 'yyyy-MM-dd') + "|" + PR.root_code;
    pcKey = string(PC.event_date, 'yyyy-MM-dd') + "|" + PC.root_code;
    if numel(unique(prKey)) ~= numel(prKey) || ...
            numel(unique(pcKey)) ~= numel(pcKey)
        error('STEP27A_DUPLICATE_PAIR: event-root rows must be unique.');
    end
    [~, ia, ib] = intersect(prKey, pcKey, 'stable');
    PR = PR(ia, :);
    PC = PC(ib, :);
    Xpr = design_matrix(PR, predictors);
    Xpc = design_matrix(PC, predictors);
    zerosBlock = zeros(size(Xpr));
    S = struct();
    S.X = [Xpr, zerosBlock; zerosBlock, Xpc];
    S.y = [double(PR.(outcome)); double(PC.(outcome))];
    S.clusters = [string(PR.event_date, 'yyyy-MM-dd'); ...
        string(PC.event_date, 'yyyy-MM-dd')];
    terms = ["Intercept", predictors];
    S.term_names = ["PR_" + terms, "PC_" + terms]';
    S.pr = PR;
    S.pc = PC;
end

function X = design_matrix(T, predictors)
    X = ones(height(T), 1);
    for j = 1:numel(predictors)
        X = [X, double(T.(predictors(j)))]; %#ok<AGROW>
    end
end

function R = phase_equality_matrix(termNames, terms)
    R = zeros(numel(terms), numel(termNames));
    for j = 1:numel(terms)
        R(j, termNames == "PR_" + terms(j)) = -1;
        R(j, termNames == "PC_" + terms(j)) = 1;
    end
end

function covariance = pooled_shock_covariance(PR, PC)
    [~, firstPr] = unique(PR.event_date, 'stable');
    [~, firstPc] = unique(PC.event_date, 'stable');
    values = [PR{firstPr, {'policy_indicator_10bp', 'STOXX50'}}; ...
        PC{firstPc, {'policy_indicator_10bp', 'STOXX50'}}];
    values = double(values);
    values = values(all(isfinite(values), 2), :);
    covariance = cov(values, 0);
end

function [prShock, pcShock] = shocks_by_cluster(PR, PC, clusterNames)
    prDates = string(PR.event_date, 'yyyy-MM-dd');
    pcDates = string(PC.event_date, 'yyyy-MM-dd');
    prShock = nan(numel(clusterNames), 2);
    pcShock = nan(numel(clusterNames), 2);
    for g = 1:numel(clusterNames)
        pr = unique(double(PR{prDates == clusterNames(g), ...
            {'policy_indicator_10bp', 'STOXX50'}}), 'rows');
        pc = unique(double(PC{pcDates == clusterNames(g), ...
            {'policy_indicator_10bp', 'STOXX50'}}), 'rows');
        if size(pr, 1) ~= 1 || size(pc, 1) ~= 1 || ...
                any(~isfinite(pr), 'all') || any(~isfinite(pc), 'all')
            error('STEP27A_SHOCK_CLUSTER: shocks must be unique within event %s.', ...
                clusterNames(g));
        end
        prShock(g, :) = pr;
        pcShock(g, :) = pc;
    end
end

function ranking = total_energy_ranking(PR, PC)
    [datesPr, firstPr] = unique(PR.event_date, 'stable');
    [datesPc, firstPc] = unique(PC.event_date, 'stable');
    [dates, ia, ib] = intersect(datesPr, datesPc, 'stable');
    energy = double(PR.q_mp(firstPr(ia))) + double(PR.q_cbi(firstPr(ia))) + ...
        double(PC.q_mp(firstPc(ib))) + double(PC.q_cbi(firstPc(ib)));
    ranking = table(dates, energy, 'VariableNames', {'event_date', 'energy'});
    ranking = sortrows(ranking, 'energy', 'descend');
end

function manifest = build_manifest(inputFiles, cfg)
    here = fileparts(which('Rank_one_feasibility'));
    hashes = strings(numel(inputFiles), 1);
    for j = 1:numel(inputFiles)
        hashes(j) = File_sha256(inputFiles(j));
    end
    scripts = ["Rank_one_feasibility.m", "Step27_rank_one_null_fit.m", ...
        "Step27_rank_statistics.m", "Rank_one_feasibility_self_test.m"];
    scriptHashes = strings(numel(scripts), 1);
    for j = 1:numel(scripts)
        scriptHashes(j) = File_sha256(fullfile(here, scripts(j)));
    end
    names = ["schema_version"; "created_utc"; "module"; ...
        "primary_outcome"; "states"; "leave_top_k"; "bootstrap_draws"; ...
        "seed"; "alpha"; "rank_null"; "reference_direction"; ...
        "mp_definition"; "bootstrap_design"; "calibration_statistics"; ...
        "multiplicity"; "module_b_rule"; "input_files"; "input_sha256"; ...
        "code_commit"; "script_files"; "script_sha256"];
    values = ["step27a_v1"; ...
        string(datetime('now', 'TimeZone', 'UTC'), ...
            'yyyy-MM-dd''T''HH:mm:ssXXX'); ...
        "A_rank_calibration_only"; cfg.outcome; ...
        strjoin(string(cfg.states), "|"); strjoin(string(cfg.topK), "|"); ...
        string(cfg.bootstrapRep); string(cfg.seed); string(cfg.alpha); ...
        "common_direction_rank_one_gap_with_linear_state_amplitude"; ...
        "jointly_profiled_in_each_observed_and_bootstrap_sample"; ...
        "opposite_sign_policy_equity_sector_not_point_vector"; ...
        "null_imposed_event_pairs_resampling_plus_event_wild_signs_with_shock_covariance_reestimated"; ...
        "max_abs_lambda2|max_secondary_absolute_share|max_projective_deviation_from_common_direction"; ...
        "Holm within full-sample triad and within nine leave-top-k tests"; ...
        "B is blocked on A failure and never runs automatically"; ...
        strjoin(inputFiles, "|"); strjoin(hashes, "|"); ...
        current_git_commit(here); strjoin(scripts, "|"); ...
        strjoin(scriptHashes, "|")];
    manifest = table(names, values, 'VariableNames', {'name', 'value'});
end

function mask = finite_variables(T, variables)
    variables = string(variables(:));
    mask = true(height(T), 1);
    for j = 1:numel(variables)
        x = T.(variables(j));
        if ~isnumeric(x) && ~islogical(x)
            x = str2double(string(x));
        end
        mask = mask & isfinite(double(x));
    end
end

function assert_columns(T, required, source)
    missing = required(~ismember(required, string(T.Properties.VariableNames)));
    if ~isempty(missing)
        error('STEP27A_COLUMNS: %s is missing %s.', source, ...
            strjoin(missing, ', '));
    end
end

function x = to_logical(x)
    if islogical(x); return; end
    if isnumeric(x); x = x ~= 0; return; end
    x = ismember(lower(strtrim(string(x))), ["1", "true", "yes"]);
end

function count = parse_draw_count(raw, fallback)
    if strlength(string(raw)) == 0
        count = fallback;
    else
        count = str2double(string(raw));
    end
    if ~isfinite(count) || count < 19 || count ~= floor(count)
        error('RANK_ONE_FEASIBILITY_DRAWS must be an integer of at least 19.');
    end
end

function status = pass_status(pass)
    status = conditional_text(pass, "pass", "fail");
end

function value = conditional_text(condition, ifTrue, ifFalse)
    if condition
        value = string(ifTrue);
    else
        value = string(ifFalse);
    end
end

function commit = current_git_commit(codePath)
    [status, result] = system(sprintf( ...
        'git -C "%s" rev-parse HEAD 2>/dev/null', codePath));
    if status == 0
        commit = strtrim(string(result));
    else
        commit = "unavailable";
    end
end
