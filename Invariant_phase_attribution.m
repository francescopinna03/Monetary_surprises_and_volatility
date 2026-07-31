function Invariant_phase_attribution()
%INVARIANT_PHASE_ATTRIBUTION Step 25 attribution of the PR-PC phase gap.
%
% The primary diagnostic eigendecomposes the PR-PC difference between the
% rotation-invariant policy/equity quadratic response matrices.  It identifies
% an MP-like or CBI-like sector without selecting one JK rotation.  Median-JK,
% poor-man sign splits and residual short-curve components are falsification
% exercises and cannot by themselves create a point-identified component claim.

    projectRoot = Get_project_root();
    Require_time_alignment_manifest(projectRoot);
    Require_window_semantics_manifest(projectRoot);

    analysisDir = fullfile(projectRoot, 'Output', 'analysis');
    phaseDir = fullfile(projectRoot, 'Output', 'phase_counterfactuals');
    step24Dir = fullfile(projectRoot, 'Output', 'phase_component_contrasts');
    outputDir = fullfile(projectRoot, 'Output', 'invariant_phase_attribution');
    if exist(outputDir, 'dir') ~= 7; mkdir(outputDir); end

    files = struct();
    files.pr = fullfile(phaseDir, 'phase_counterfactual_pr_event_rows.csv');
    files.pc = fullfile(phaseDir, 'phase_counterfactual_pc_event_rows.csv');
    files.components = fullfile(analysisDir, 'shock_components_by_event.csv');
    files.step24Decision = fullfile(step24Dir, 'step24_decision.csv');
    files.step24Manifest = fullfile(step24Dir, 'step24_manifest.csv');
    fileNames = string(struct2cell(files));
    for f = fileNames'
        if exist(f, 'file') ~= 2
            error('STEP25_INPUT_MISSING: required input not found: %s', f);
        end
    end
    step24Decision = validate_step24(files.step24Decision, files.step24Manifest);

    cfg = struct();
    cfg.seed = 25020;
    cfg.bootstrapRep = parse_draw_count(getenv('INVARIANT_ATTRIBUTION_DRAWS'), 999);
    cfg.outcomes = ["abnormal_log_BV", "abnormal_log_RV"];
    cfg.primaryOutcome = "abnormal_log_BV";
    cfg.robustnessOutcome = "abnormal_log_RV";
    cfg.states = [-1, 0, 1];
    cfg.topK = [0, 1, 3, 5];
    cfg.sectorProbability = 0.95;
    cfg.dominanceThreshold = 0.80;
    rng(cfg.seed, 'twister');

    C = load_components(files.components);
    PR = prepare_phase(load_event_rows(files.pr), C, "PR");
    PC = prepare_phase(load_event_rows(files.pc), C, "PC");

    reducedPredictors = ["q_policy", "q_equity", "q_policy_equity", ...
        "pre_state_z", "q_policy_x_pre", "q_equity_x_pre", ...
        "q_policy_equity_x_pre", "regime_hike", "root_gg"];
    levelTerms = ["q_policy", "q_equity", "q_policy_equity"];
    slopeTerms = ["q_policy_x_pre", "q_equity_x_pre", ...
        "q_policy_equity_x_pre"];

    blockCells = {};
    geometryCells = {};
    geometryDrawCells = {};
    geometrySummaryCells = {};
    topKCells = {};
    auxiliaryCells = {};

    for outcome = cfg.outcomes
        S = build_stacked(PR, PC, outcome, reducedPredictors, NaT(0, 1));
        fit = Step23_cluster_ols(S.y, S.X, S.clusters);
        Rlevel = phase_equality_matrix(S.term_names, levelTerms);
        Rslope = phase_equality_matrix(S.term_names, slopeTerms);
        Rfull = [Rlevel; Rslope];

        blockCells{end + 1, 1} = block_row(fit, S, Rlevel, outcome, ...
            "MEAN_SURFACE", "primary_decomposition", cfg); %#ok<AGROW>
        blockCells{end + 1, 1} = block_row(fit, S, Rslope, outcome, ...
            "STATE_SLOPE_SURFACE", "primary_decomposition", cfg); %#ok<AGROW>
        blockCells{end + 1, 1} = block_row(fit, S, Rfull, outcome, ...
            "FULL_SURFACE", "inherited_omnibus", cfg); %#ok<AGROW>

        deltaLevel = Rlevel * fit.beta;
        deltaSlope = Rslope * fit.beta;
        shockCovariance = pooled_shock_covariance(S.pr, S.pc);
        pointRows = geometry_rows(outcome, 0, fit.G, deltaLevel, ...
            deltaSlope, shockCovariance, cfg.states);
        geometryCells{end + 1, 1} = pointRows; %#ok<AGROW>

        draws = bootstrap_geometry(S, Rlevel, Rslope, ...
            shockCovariance, outcome, cfg);
        geometryDrawCells{end + 1, 1} = draws; %#ok<AGROW>
        geometrySummaryCells{end + 1, 1} = summarise_geometry( ...
            pointRows, draws, cfg); %#ok<AGROW>

        ranking = total_energy_ranking(S.pr, S.pc);
        for k = cfg.topK
            excluded = ranking.event_date(1:min(k, height(ranking)));
            Sk = build_stacked(PR, PC, outcome, reducedPredictors, excluded);
            fitk = Step23_cluster_ols(Sk.y, Sk.X, Sk.clusters);
            RlevelK = phase_equality_matrix(Sk.term_names, levelTerms);
            RslopeK = phase_equality_matrix(Sk.term_names, slopeTerms);
            topKCells{end + 1, 1} = geometry_rows(outcome, k, fitk.G, ...
                RlevelK * fitk.beta, RslopeK * fitk.beta, ...
                shockCovariance, cfg.states); %#ok<AGROW>
        end

        auxiliaryCells = [auxiliaryCells; ...
            median_component_blocks(PR, PC, outcome, cfg); ...
            poor_man_blocks(PR, PC, outcome, cfg); ...
            omitted_component_blocks(PR, PC, outcome, cfg)]; %#ok<AGROW>
    end

    blocks = vertcat(blockCells{:});
    geometry = vertcat(geometryCells{:});
    geometryDraws = vertcat(geometryDrawCells{:});
    geometrySummary = vertcat(geometrySummaryCells{:});
    topKSensitivity = vertcat(topKCells{:});
    auxiliary = vertcat(auxiliaryCells{:});

    blocks.p_holm = nan(height(blocks), 1);
    blocks.p_wild_holm = nan(height(blocks), 1);
    primary = blocks.outcome == cfg.primaryOutcome & ...
        blocks.family == "primary_decomposition";
    blocks.p_holm(primary) = Step23_holm_adjust(blocks.p_value(primary));
    blocks.p_wild_holm(primary) = Step23_holm_adjust( ...
        blocks.p_wild_cluster(primary));

    auxiliary.p_holm = nan(height(auxiliary), 1);
    auxiliary.p_wild_holm = nan(height(auxiliary), 1);
    for family = unique(auxiliary.family, 'stable')'
        mask = auxiliary.family == family;
        auxiliary.p_holm(mask) = Step23_holm_adjust(auxiliary.p_value(mask));
        auxiliary.p_wild_holm(mask) = Step23_holm_adjust( ...
            auxiliary.p_wild_cluster(mask));
    end

    decision = build_decision(blocks, geometrySummary, topKSensitivity, ...
        auxiliary, step24Decision, cfg);

    writetable(blocks, fullfile(outputDir, 'step25_phase_blocks.csv'));
    writetable(geometry, fullfile(outputDir, 'step25_geometry.csv'));
    writetable(geometryDraws, fullfile(outputDir, ...
        'step25_geometry_bootstrap.csv'));
    writetable(geometrySummary, fullfile(outputDir, ...
        'step25_geometry_summary.csv'));
    writetable(topKSensitivity, fullfile(outputDir, ...
        'step25_leave_top_k.csv'));
    writetable(auxiliary, fullfile(outputDir, ...
        'step25_auxiliary_attribution.csv'));
    writetable(decision, fullfile(outputDir, 'step25_decision.csv'));
    writetable(build_manifest(fileNames, cfg), fullfile(outputDir, ...
        'step25_manifest.csv'));

    fprintf('\n================ STEP 25 INVARIANT ATTRIBUTION ================\n');
    fprintf('Bootstrap draws : %d\n', cfg.bootstrapRep);
    disp(decision(:, {'test_id', 'status', 'recommendation'}));
    fprintf('Output directory: %s\n', outputDir);
    fprintf('================================================================\n');
end

function T = load_event_rows(filePath)
    T = readtable(filePath, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "root_code", "abnormal_log_BV", ...
        "abnormal_log_RV", "pre_state_z", "regime_hike", "root_gg", ...
        "q_mp", "q_cbi", "q_mp_cbi", "q_mp_x_pre", ...
        "q_cbi_x_pre", "q_mp_cbi_x_pre"];
    assert_columns(T, required, filePath);
    T.event_date = Parse_date_flexible(T.event_date);
    T.root_code = lower(string(T.root_code));
end

function C = load_components(filePath)
    C = readtable(filePath, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "window", "policy_indicator_10bp", ...
        "STOXX50", "curve_PC2_z", "curve_PC3_z", "curve_PC4_z", ...
        "MP_pm", "CBI_pm", "estimation_sample", "in_project_sample"];
    assert_columns(C, required, filePath);
    C.event_date = Parse_date_flexible(C.event_date);
    C.window = upper(string(C.window));
    C.estimation_sample = to_logical(C.estimation_sample);
    C.in_project_sample = to_logical(C.in_project_sample);
end

function T = prepare_phase(T, C, phase)
    keep = C.window == phase & C.estimation_sample & C.in_project_sample;
    variables = ["event_date", "policy_indicator_10bp", "STOXX50", ...
        "curve_PC2_z", "curve_PC3_z", "curve_PC4_z", "MP_pm", "CBI_pm"];
    S = C(keep, variables);
    [~, first] = unique(S.event_date, 'stable');
    S = S(first, :);
    T = innerjoin(T, S, 'Keys', 'event_date');
    if isempty(T)
        error('STEP25_NO_MATCHES: no component matches for phase %s.', phase);
    end

    policy = T.policy_indicator_10bp;
    equity = T.STOXX50;
    state = T.pre_state_z;
    T.q_policy = policy .^ 2;
    T.q_equity = equity .^ 2;
    T.q_policy_equity = 2 * policy .* equity;
    T.q_policy_x_pre = T.q_policy .* state;
    T.q_equity_x_pre = T.q_equity .* state;
    T.q_policy_equity_x_pre = T.q_policy_equity .* state;

    pc2 = T.curve_PC2_z;
    T.q_pc2 = pc2 .^ 2;
    T.q_policy_pc2 = 2 * policy .* pc2;
    T.q_equity_pc2 = 2 * equity .* pc2;
    T.q_pc2_x_pre = T.q_pc2 .* state;
    T.q_policy_pc2_x_pre = T.q_policy_pc2 .* state;
    T.q_equity_pc2_x_pre = T.q_equity_pc2 .* state;
    T.q_residual_curve = T.curve_PC2_z .^ 2 + ...
        T.curve_PC3_z .^ 2 + T.curve_PC4_z .^ 2;
    T.q_residual_curve_x_pre = T.q_residual_curve .* state;

    T.q_mp_pm = (T.MP_pm / 0.10) .^ 2;
    T.q_cbi_pm = (T.CBI_pm / 0.10) .^ 2;
    T.q_mp_pm_x_pre = T.q_mp_pm .* state;
    T.q_cbi_pm_x_pre = T.q_cbi_pm .* state;
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
        error('STEP25_DUPLICATE_PAIR: event-root rows must be unique.');
    end
    [~, ia, ib] = intersect(prKey, pcKey, 'stable');
    PR = PR(ia, :);
    PC = PC(ib, :);
    Xpr = design_matrix(PR, predictors);
    Xpc = design_matrix(PC, predictors);
    zerosBlock = zeros(size(Xpr));
    S = struct();
    S.X = [Xpr, zerosBlock; zerosBlock, Xpc];
    S.y = [PR.(outcome); PC.(outcome)];
    S.clusters = [string(PR.event_date, 'yyyy-MM-dd'); ...
        string(PC.event_date, 'yyyy-MM-dd')];
    terms = ["Intercept", predictors];
    S.term_names = ["PR_" + terms, "PC_" + terms]';
    S.pr = PR;
    S.pc = PC;
end

function X = design_matrix(T, predictors)
    X = ones(height(T), 1);
    for v = predictors
        X = [X, double(T.(v))]; %#ok<AGROW>
    end
end

function R = phase_equality_matrix(termNames, terms)
    R = zeros(numel(terms), numel(termNames));
    for j = 1:numel(terms)
        R(j, termNames == "PR_" + terms(j)) = -1;
        R(j, termNames == "PC_" + terms(j)) = 1;
    end
end

function row = block_row(fit, S, R, outcome, blockId, family, cfg)
    test = Step24_wald_test(fit, R);
    [pWild, ~] = Step24_wild_wald( ...
        S.y, S.X, S.clusters, R, cfg.bootstrapRep);
    row = table();
    row.outcome = outcome;
    row.block_id = blockId;
    row.family = family;
    row.wald_f = test.f_statistic;
    row.df1 = test.df1;
    row.df2 = test.df2;
    row.p_value = test.p_value;
    row.p_wild_cluster = pWild;
    row.n_obs = fit.n;
    row.n_clusters = fit.G;
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

function T = geometry_rows(outcome, topK, clusters, deltaLevel, ...
        deltaSlope, shockCovariance, states)
    cells = cell(numel(states), 1);
    for j = 1:numel(states)
        G = Step25_phase_geometry(deltaLevel, deltaSlope, ...
            shockCovariance, states(j));
        row = table();
        row.outcome = outcome;
        row.excluded_top_events = topK;
        row.state = states(j);
        row.n_clusters = clusters;
        row.leading_eigenvalue = G.leading_eigenvalue;
        row.secondary_eigenvalue = G.secondary_eigenvalue;
        row.leading_absolute_share = G.leading_absolute_share;
        row.policy_direction = G.policy_direction;
        row.equity_direction = G.equity_direction;
        row.angle_degrees = G.angle_degrees;
        row.sector = G.sector;
        cells{j} = row;
    end
    T = vertcat(cells{:});
end

function D = bootstrap_geometry(S, Rlevel, Rslope, shockCovariance, ...
        outcome, cfg)
    [clusterNames, ~, clusterId] = unique(S.clusters, 'stable');
    G = numel(clusterNames);
    k = size(S.X, 2);
    xx = cell(G, 1);
    xy = cell(G, 1);
    for g = 1:G
        idx = clusterId == g;
        xx{g} = S.X(idx, :)' * S.X(idx, :);
        xy{g} = S.X(idx, :)' * S.y(idx);
    end

    cells = cell(cfg.bootstrapRep * numel(cfg.states), 1);
    cursor = 0;
    for b = 1:cfg.bootstrapRep
        sample = randi(G, G, 1);
        sumXX = zeros(k, k);
        sumXY = zeros(k, 1);
        for g = 1:G
            sumXX = sumXX + xx{sample(g)};
            sumXY = sumXY + xy{sample(g)};
        end
        beta = pinv(sumXX) * sumXY;
        deltaLevel = Rlevel * beta;
        deltaSlope = Rslope * beta;
        for state = cfg.states
            cursor = cursor + 1;
            geom = Step25_phase_geometry(deltaLevel, deltaSlope, ...
                shockCovariance, state);
            row = table();
            row.outcome = outcome;
            row.draw = b;
            row.state = state;
            row.leading_eigenvalue = geom.leading_eigenvalue;
            row.secondary_eigenvalue = geom.secondary_eigenvalue;
            row.leading_absolute_share = geom.leading_absolute_share;
            row.angle_degrees = geom.angle_degrees;
            row.sector = geom.sector;
            cells{cursor} = row;
        end
    end
    D = vertcat(cells{:});
end

function T = summarise_geometry(points, draws, cfg)
    cells = cell(numel(cfg.states), 1);
    for j = 1:numel(cfg.states)
        state = cfg.states(j);
        p = points(points.state == state, :);
        d = draws(draws.state == state, :);
        row = table();
        row.outcome = p.outcome;
        row.state = state;
        row.leading_eigenvalue = p.leading_eigenvalue;
        row.leading_eigen_ci_low = quantile(d.leading_eigenvalue, 0.025);
        row.leading_eigen_ci_high = quantile(d.leading_eigenvalue, 0.975);
        row.leading_absolute_share = p.leading_absolute_share;
        row.share_ci_low = quantile(d.leading_absolute_share, 0.025);
        row.share_ci_high = quantile(d.leading_absolute_share, 0.975);
        row.probability_share_above_80 = mean( ...
            d.leading_absolute_share >= cfg.dominanceThreshold);
        row.angle_degrees = p.angle_degrees;
        row.angle_ci_low = quantile(d.angle_degrees, 0.025);
        row.angle_ci_high = quantile(d.angle_degrees, 0.975);
        row.probability_mp_sector = mean(d.sector == "MP_LIKE");
        row.probability_cbi_sector = mean(d.sector == "CBI_LIKE");
        cells{j} = row;
    end
    T = vertcat(cells{:});
end

function ranking = total_energy_ranking(PR, PC)
    [datesPr, firstPr] = unique(PR.event_date, 'stable');
    [datesPc, firstPc] = unique(PC.event_date, 'stable');
    [dates, ia, ib] = intersect(datesPr, datesPc, 'stable');
    energy = PR.q_mp(firstPr(ia)) + PR.q_cbi(firstPr(ia)) + ...
        PC.q_mp(firstPc(ib)) + PC.q_cbi(firstPc(ib));
    ranking = table(dates, energy, 'VariableNames', {'event_date', 'energy'});
    ranking = sortrows(ranking, 'energy', 'descend');
end

function cells = median_component_blocks(PR, PC, outcome, cfg)
    predictors = ["q_mp", "q_cbi", "q_mp_cbi", "pre_state_z", ...
        "q_mp_x_pre", "q_cbi_x_pre", "q_mp_cbi_x_pre", ...
        "regime_hike", "root_gg"];
    S = build_stacked(PR, PC, outcome, predictors, NaT(0, 1));
    fit = Step23_cluster_ols(S.y, S.X, S.clusters);
    definitions = {
        "MP", ["q_mp", "q_mp_x_pre"];
        "CBI", ["q_cbi", "q_cbi_x_pre"];
        "MP_CBI_CROSS", ["q_mp_cbi", "q_mp_cbi_x_pre"]};
    cells = cell(size(definitions, 1), 1);
    for j = 1:size(definitions, 1)
        R = phase_equality_matrix(S.term_names, definitions{j, 2});
        cells{j} = auxiliary_row(fit, S, R, outcome, ...
            "MEDIAN_JK", definitions{j, 1}, "median_component_blocks", cfg);
    end
end

function cells = poor_man_blocks(PR, PC, outcome, cfg)
    predictors = ["q_mp_pm", "q_cbi_pm", "pre_state_z", ...
        "q_mp_pm_x_pre", "q_cbi_pm_x_pre", "regime_hike", "root_gg"];
    S = build_stacked(PR, PC, outcome, predictors, NaT(0, 1));
    fit = Step23_cluster_ols(S.y, S.X, S.clusters);
    definitions = {
        "MP", ["q_mp_pm", "q_mp_pm_x_pre"];
        "CBI", ["q_cbi_pm", "q_cbi_pm_x_pre"]};
    cells = cell(size(definitions, 1), 1);
    for j = 1:size(definitions, 1)
        R = phase_equality_matrix(S.term_names, definitions{j, 2});
        cells{j} = auxiliary_row(fit, S, R, outcome, ...
            "POOR_MAN_SIGN", definitions{j, 1}, "poor_man_blocks", cfg);
    end
end

function cells = omitted_component_blocks(PR, PC, outcome, cfg)
    pc2Predictors = ["q_policy", "q_equity", "q_policy_equity", ...
        "q_pc2", "q_policy_pc2", "q_equity_pc2", "pre_state_z", ...
        "q_policy_x_pre", "q_equity_x_pre", ...
        "q_policy_equity_x_pre", "q_pc2_x_pre", ...
        "q_policy_pc2_x_pre", "q_equity_pc2_x_pre", ...
        "regime_hike", "root_gg"];
    pc2Terms = ["q_pc2", "q_policy_pc2", "q_equity_pc2", ...
        "q_pc2_x_pre", "q_policy_pc2_x_pre", "q_equity_pc2_x_pre"];
    S = build_stacked(PR, PC, outcome, pc2Predictors, NaT(0, 1));
    fit = Step23_cluster_ols(S.y, S.X, S.clusters);
    R = phase_equality_matrix(S.term_names, pc2Terms);
    cells = cell(2, 1);
    cells{1} = auxiliary_row(fit, S, R, outcome, "SHORT_CURVE", ...
        "PC2_FULL_QUADRATIC_BLOCK", "omitted_short_curve", cfg);

    residualPredictors = ["q_policy", "q_equity", "q_policy_equity", ...
        "q_residual_curve", "pre_state_z", "q_policy_x_pre", ...
        "q_equity_x_pre", "q_policy_equity_x_pre", ...
        "q_residual_curve_x_pre", "regime_hike", "root_gg"];
    residualTerms = ["q_residual_curve", "q_residual_curve_x_pre"];
    S = build_stacked(PR, PC, outcome, residualPredictors, NaT(0, 1));
    fit = Step23_cluster_ols(S.y, S.X, S.clusters);
    R = phase_equality_matrix(S.term_names, residualTerms);
    cells{2} = auxiliary_row(fit, S, R, outcome, "SHORT_CURVE", ...
        "PC2_PC4_RESIDUAL_ENERGY", "omitted_short_curve", cfg);
end

function row = auxiliary_row(fit, S, R, outcome, basis, blockId, family, cfg)
    test = Step24_wald_test(fit, R);
    [pWild, ~] = Step24_wild_wald( ...
        S.y, S.X, S.clusters, R, cfg.bootstrapRep);
    row = table();
    row.outcome = outcome;
    row.basis = basis;
    row.block_id = blockId;
    row.family = family;
    row.wald_f = test.f_statistic;
    row.df1 = test.df1;
    row.p_value = test.p_value;
    row.p_wild_cluster = pWild;
    row.n_clusters = fit.G;
end

function D = build_decision(blocks, summary, topK, auxiliary, step24, cfg)
    rows = cell(7, 1);
    primaryBlocks = blocks.outcome == cfg.primaryOutcome & ...
        blocks.family == "primary_decomposition";
    blockPass = sum(primaryBlocks) == 2 && ...
        all(blocks.p_holm(primaryBlocks) <= 0.05 & ...
        blocks.p_wild_holm(primaryBlocks) <= 0.05);
    rows{1} = decision_row("BV_MEAN_AND_STATE_BLOCKS", ...
        pass_status(blockPass), conditional_text(blockPass, ...
        "both_bv_blocks_survive_holm_and_wild_cluster", ...
        "phase_gap_not_separable_into_robust_bv_blocks"));

    primaryGeometry = summary.outcome == cfg.primaryOutcome;
    primaryTop = topK.outcome == cfg.primaryOutcome & ...
        topK.excluded_top_events > 0;
    geometryPass = sum(primaryGeometry) == numel(cfg.states) && ...
        sum(primaryTop) == 3 * numel(cfg.states) && ...
        all(summary.probability_mp_sector(primaryGeometry) >= ...
        cfg.sectorProbability) && ...
        all(summary.leading_eigen_ci_high(primaryGeometry) < 0) && ...
        all(topK.sector(primaryTop) == "MP_LIKE") && ...
        all(topK.leading_eigenvalue(primaryTop) < 0);
    rows{2} = decision_row("MP_LIKE_GEOMETRIC_DIRECTION", ...
        pass_status(geometryPass), conditional_text(geometryPass, ...
        "mp_like_direction_set_identified", ...
        "dominant_sector_not_stable"));

    dominancePass = all(summary.probability_share_above_80( ...
        primaryGeometry) >= cfg.sectorProbability);
    rows{3} = decision_row("SINGLE_DIRECTION_DOMINANCE", ...
        pass_status(dominancePass), conditional_text(dominancePass, ...
        "phase_gap_effectively_rank_one", ...
        "mp_like_dominant_but_rank_one_not_established"));

    rvGeometry = summary.outcome == cfg.robustnessOutcome;
    rvDirectional = all(summary.angle_degrees(rvGeometry) < 0) && ...
        all(summary.leading_eigen_ci_high(rvGeometry) < 0);
    rvSectorStrong = all(summary.probability_mp_sector(rvGeometry) >= ...
        cfg.sectorProbability);
    rvStep24 = step24.test_id == "REDUCED_FORM_RV_CONFIRMATION";
    rvOmnibus = any(rvStep24 & step24.robust_claim);
    if rvDirectional && ~rvOmnibus
        if rvSectorStrong
            rvRecommendation = "rv_direction_matches_bv_but_omnibus_does_not_confirm";
        else
            rvRecommendation = "rv_point_direction_matches_bv_but_sector_or_omnibus_is_not_robust";
        end
        rvStatus = "diagnostic_only";
    elseif rvDirectional && rvOmnibus
        rvRecommendation = "rv_confirms_direction_and_omnibus";
        rvStatus = "pass";
    else
        rvRecommendation = "rv_does_not_support_direction";
        rvStatus = "fail";
    end
    rows{4} = decision_row("RV_DIRECTIONAL_ALIGNMENT", rvStatus, rvRecommendation);

    poorMp = auxiliary.family == "poor_man_blocks" & ...
        auxiliary.block_id == "MP";
    poorCbi = auxiliary.family == "poor_man_blocks" & ...
        auxiliary.block_id == "CBI";
    step24Mp = startsWith(step24.test_id, "PC_MINUS_PR_MP_");
    step24Cbi = startsWith(step24.test_id, "PC_MINUS_PR_CBI_");
    mpExact = sum(poorMp) == numel(cfg.outcomes) && ...
        all(auxiliary.p_wild_holm(poorMp) <= 0.05) && ...
        sum(step24Mp) == 2 && all(step24.robust_claim(step24Mp));
    cbiExact = sum(poorCbi) == numel(cfg.outcomes) && ...
        all(auxiliary.p_wild_holm(poorCbi) <= 0.05) && ...
        sum(step24Cbi) == 2 && all(step24.robust_claim(step24Cbi));
    exactPass = mpExact || cbiExact;
    rows{5} = decision_row("EXACT_MP_CBI_POINT_ATTRIBUTION", ...
        pass_status(exactPass), conditional_text(exactPass, ...
        "exact_component_attribution_supported", ...
        "set_identified_not_point_identified"));

    omitted = auxiliary.family == "omitted_short_curve";
    omittedEvidence = any(auxiliary.p_holm(omitted) <= 0.05 & ...
        auxiliary.p_wild_holm(omitted) <= 0.05);
    if omittedEvidence
        omittedStatus = "evidence_found";
        omittedRecommendation = "short_curve_extension_required";
    else
        omittedStatus = "not_supported";
        omittedRecommendation = "no_short_curve_omitted_component_evidence";
    end
    rows{6} = decision_row("SHORT_CURVE_OMITTED_COMPONENTS", ...
        omittedStatus, omittedRecommendation);
    rows{7} = decision_row("LONG_HORIZON_TARGET_TIMING_FG_QE", ...
        "not_tested", "extend_ea_mpd_beyond_1y_before_excluding_omitted_components");
    D = vertcat(rows{:});
end

function row = decision_row(testId, status, recommendation)
    row = table();
    row.test_id = string(testId);
    row.status = string(status);
    row.recommendation = string(recommendation);
end

function value = pass_status(flag)
    if flag; value = "pass"; else; value = "fail"; end
end

function value = conditional_text(flag, yesValue, noValue)
    if flag; value = string(yesValue); else; value = string(noValue); end
end

function D = validate_step24(decisionFile, manifestFile)
    D = readtable(decisionFile, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["test_id", "robust_claim", "recommendation"];
    assert_columns(D, required, decisionFile);
    D.robust_claim = to_logical(D.robust_claim);
    primary = D.test_id == "REDUCED_FORM_PHASE_HETEROGENEITY";
    components = startsWith(D.test_id, "PC_MINUS_PR_");
    if sum(primary) ~= 1 || ~D.robust_claim(primary) || ...
            D.recommendation(primary) ~= "phase_response_surfaces_differ" || ...
            sum(components) ~= 4 || any(D.robust_claim(components))
        error('STEP25_STEP24_DECISION: final partial-attribution decision required.');
    end
    M = readtable(manifestFile, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    assert_columns(M, ["name", "value"], manifestFile);
    schema = M.value(M.name == "schema_version");
    draws = str2double(M.value(M.name == "bootstrap_draws"));
    if numel(schema) ~= 1 || schema ~= "step24_v1" || draws ~= 999
        error('STEP25_STEP24_MANIFEST: final 999-draw step24_v1 manifest required.');
    end
end

function manifest = build_manifest(inputFiles, cfg)
    here = fileparts(which('Invariant_phase_attribution'));
    hashes = strings(numel(inputFiles), 1);
    for i = 1:numel(inputFiles); hashes(i) = File_sha256(inputFiles(i)); end
    names = ["schema_version"; "created_utc"; "primary_outcome"; ...
        "robustness_outcome"; "geometry"; "states"; "bootstrap_draws"; ...
        "seed"; "sector_probability_threshold"; "dominance_threshold"; ...
        "point_identification_boundary"; "unexamined_components"; ...
        "input_files"; "input_sha256"; "code_commit"; "script_sha256"];
    values = ["step25_v1"; ...
        string(datetime('now', 'TimeZone', 'UTC'), 'yyyy-MM-dd''T''HH:mm:ssXXX'); ...
        cfg.primaryOutcome; cfg.robustnessOutcome; ...
        "generalised eigenvectors of pooled-covariance-standardised PR-PC quadratic gap"; ...
        strjoin(string(cfg.states), "|"); string(cfg.bootstrapRep); ...
        string(cfg.seed); string(cfg.sectorProbability); ...
        string(cfg.dominanceThreshold); ...
        "MP-like sector is set attribution; exact JK MP/CBI remains rotation dependent"; ...
        "OIS maturities beyond 1Y and official Target/Timing/FG/QE factors"; ...
        strjoin(inputFiles, "|"); strjoin(hashes, "|"); ...
        current_git_commit(here); ...
        File_sha256(fullfile(here, 'Invariant_phase_attribution.m'))];
    manifest = table(names, values, 'VariableNames', {'name', 'value'});
end

function mask = finite_variables(T, variables)
    mask = true(height(T), 1);
    for v = variables
        x = T.(v);
        if ~isnumeric(x) && ~islogical(x); x = str2double(string(x)); end
        mask = mask & isfinite(double(x));
    end
end

function assert_columns(T, required, source)
    missing = required(~ismember(required, string(T.Properties.VariableNames)));
    if ~isempty(missing)
        error('STEP25_COLUMNS: %s is missing %s.', source, strjoin(missing, ', '));
    end
end

function x = to_logical(x)
    if islogical(x); return; end
    if isnumeric(x); x = x ~= 0; return; end
    x = ismember(lower(strtrim(string(x))), ["1", "true", "yes"]);
end

function count = parse_draw_count(raw, fallback)
    if strlength(string(raw)) == 0; count = fallback;
    else; count = str2double(string(raw));
    end
    if ~isfinite(count) || count < 19 || count ~= floor(count)
        error('INVARIANT_ATTRIBUTION_DRAWS must be an integer of at least 19.');
    end
end

function commit = current_git_commit(codePath)
    [status, result] = system(sprintf( ...
        'git -C "%s" rev-parse HEAD 2>/dev/null', codePath));
    if status == 0; commit = strtrim(string(result));
    else; commit = "unavailable";
    end
end
