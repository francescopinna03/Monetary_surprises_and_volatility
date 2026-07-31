function Phase_component_contrasts()
%PHASE_COMPONENT_CONTRASTS Step 24 paired PR-PC transmission tests.
%
% Primary inference compares the full quadratic shock-response surface in the
% rotation-invariant policy-indicator/equity basis. Median-rotation MP and CBI
% contrasts are secondary and must survive rotation and leave-top-k audits.

    projectRoot = Get_project_root();
    Require_time_alignment_manifest(projectRoot);
    Require_window_semantics_manifest(projectRoot);

    analysisDir = fullfile(projectRoot, 'Output', 'analysis');
    phaseDir = fullfile(projectRoot, 'Output', 'phase_counterfactuals');
    step23Dir = fullfile(projectRoot, 'Output', 'component_sufficiency');
    outputDir = fullfile(projectRoot, 'Output', 'phase_component_contrasts');
    if exist(outputDir, 'dir') ~= 7; mkdir(outputDir); end

    files = struct();
    files.pr = fullfile(phaseDir, 'phase_counterfactual_pr_event_rows.csv');
    files.pc = fullfile(phaseDir, 'phase_counterfactual_pc_event_rows.csv');
    files.me = fullfile(phaseDir, 'phase_counterfactual_me_event_rows.csv');
    files.components = fullfile(analysisDir, 'shock_components_by_event.csv');
    files.rotations = fullfile(analysisDir, ...
        'shock_components_rotation_sensitivity.csv');
    files.step23Decision = fullfile(step23Dir, 'step23_decision.csv');
    files.step23Manifest = fullfile(step23Dir, 'step23_manifest.csv');
    fileNames = string(struct2cell(files));
    for f = fileNames'
        if exist(f, 'file') ~= 2
            error('STEP24_INPUT_MISSING: required input not found: %s', f);
        end
    end
    validate_step23(files.step23Decision, files.step23Manifest);

    cfg = struct();
    cfg.seed = 24026;
    cfg.bootstrapRep = parse_draw_count(getenv('PHASE_COMPONENT_CONTRAST_DRAWS'), 999);
    cfg.outcomes = ["abnormal_log_BV", "abnormal_log_RV"];
    cfg.primaryOutcome = "abnormal_log_BV";
    cfg.robustnessOutcome = "abnormal_log_RV";
    cfg.states = [-1, 0, 1];
    cfg.topK = [0, 1, 3, 5];
    cfg.componentTerms = ["q_mp", "q_cbi", "q_mp_cbi", ...
        "q_mp_x_pre", "q_cbi_x_pre", "q_mp_cbi_x_pre"];
    cfg.reducedTerms = ["q_policy", "q_equity", "q_policy_equity", ...
        "q_policy_x_pre", "q_equity_x_pre", "q_policy_equity_x_pre"];
    rng(cfg.seed, 'twister');

    C = load_components(files.components);
    rotations = load_rotations(files.rotations);
    PR = add_reduced_form(load_event_rows(files.pr), C, "PR");
    PC = add_reduced_form(load_event_rows(files.pc), C, "PC");
    ME = add_reduced_form(load_event_rows(files.me), C, "ME");

    reducedPredictors = [cfg.reducedTerms(1:3), "pre_state_z", ...
        cfg.reducedTerms(4:6), "regime_hike", "root_gg"];
    componentPredictors = [cfg.componentTerms(1:3), "pre_state_z", ...
        cfg.componentTerms(4:6), "regime_hike", "root_gg"];

    coefficientCells = {};
    reducedCells = {};
    contrastCells = {};
    bootstrapCells = {};
    topKCells = {};
    rotationCells = {};
    meCells = {};

    for outcome = cfg.outcomes
        % Rotation-invariant reduced-form surface: primary phase test.
        Sraw = build_stacked(PR, PC, outcome, reducedPredictors, "pooled", NaT(0, 1));
        rawFit = Step23_cluster_ols(Sraw.y, Sraw.X, Sraw.clusters);
        coefficientCells{end + 1, 1} = coefficient_table( ...
            rawFit, Sraw.term_names, "REDUCED_FORM", outcome, "pooled"); %#ok<AGROW>
        Rraw = phase_equality_matrix(Sraw.term_names, cfg.reducedTerms);
        if outcome == cfg.primaryOutcome
            rawFamily = "reduced_form_primary";
        else
            rawFamily = "reduced_form_robustness";
        end
        [rawRow, rawDraws] = wald_row(rawFit, Sraw, Rraw, ...
            "REDUCED_FORM", outcome, "pooled", ...
            "JOINT_PHASE_SHOCK_SURFACE", rawFamily, true, cfg);
        reducedCells{end + 1, 1} = rawRow; %#ok<AGROW>
        bootstrapCells{end + 1, 1} = bootstrap_table(rawDraws, ...
            "REDUCED_FORM", outcome, "JOINT_PHASE_SHOCK_SURFACE"); %#ok<AGROW>

        for root = ["fx", "gg"]
            predictors = reducedPredictors(reducedPredictors ~= "root_gg");
            Sr = build_stacked(PR, PC, outcome, predictors, root, NaT(0, 1));
            fitr = Step23_cluster_ols(Sr.y, Sr.X, Sr.clusters);
            Rr = phase_equality_matrix(Sr.term_names, cfg.reducedTerms);
            row = wald_row(fitr, Sr, Rr, "REDUCED_FORM", outcome, root, ...
                "JOINT_PHASE_SHOCK_SURFACE", "asset_diagnostic", false, cfg);
            reducedCells{end + 1, 1} = row; %#ok<AGROW>
        end

        totalRanking = rank_component_energy(PR, PC, "TOTAL");
        for k = cfg.topK
            excluded = top_dates(totalRanking, k);
            Sk = build_stacked(PR, PC, outcome, reducedPredictors, ...
                "pooled", excluded);
            fitk = Step23_cluster_ols(Sk.y, Sk.X, Sk.clusters);
            Rk = phase_equality_matrix(Sk.term_names, cfg.reducedTerms);
            testk = Step24_wald_test(fitk, Rk);
            topKCells{end + 1, 1} = sensitivity_row( ...
                "REDUCED_FORM", outcome, "JOINT_PHASE_SHOCK_SURFACE", ...
                "TOTAL", k, fitk.G, NaN, testk.p_value); %#ok<AGROW>
        end

        % Median JK rotation: secondary component attribution.
        Sc = build_stacked(PR, PC, outcome, componentPredictors, ...
            "pooled", NaT(0, 1));
        componentFit = Step23_cluster_ols(Sc.y, Sc.X, Sc.clusters);
        coefficientCells{end + 1, 1} = coefficient_table( ...
            componentFit, Sc.term_names, "MP_CBI_MEDIAN", outcome, "pooled"); %#ok<AGROW>

        for component = ["MP", "CBI"]
            levelId = "PC_MINUS_PR_" + component + "_STATE_0";
            Rlevel = phase_component_R(Sc.term_names, component, 0);
            [levelRow, levelDraws] = wald_row(componentFit, Sc, Rlevel, ...
                "MP_CBI_MEDIAN", outcome, "pooled", levelId, ...
                "component_phase_primary", true, cfg);
            contrastCells{end + 1, 1} = levelRow; %#ok<AGROW>
            bootstrapCells{end + 1, 1} = bootstrap_table(levelDraws, ...
                "MP_CBI_MEDIAN", outcome, levelId); %#ok<AGROW>

            slopeId = "PC_MINUS_PR_" + component + "_STATE_SLOPE";
            Rslope = phase_component_slope_R(Sc.term_names, component);
            [slopeRow, slopeDraws] = wald_row(componentFit, Sc, Rslope, ...
                "MP_CBI_MEDIAN", outcome, "pooled", slopeId, ...
                "component_phase_primary", true, cfg);
            contrastCells{end + 1, 1} = slopeRow; %#ok<AGROW>
            bootstrapCells{end + 1, 1} = bootstrap_table(slopeDraws, ...
                "MP_CBI_MEDIAN", outcome, slopeId); %#ok<AGROW>

            for state = cfg.states(cfg.states ~= 0)
                profileId = "PC_MINUS_PR_" + component + "_STATE_" + ...
                    signed_label(state);
                Rprofile = phase_component_R(Sc.term_names, component, state);
                row = wald_row(componentFit, Sc, Rprofile, ...
                    "MP_CBI_MEDIAN", outcome, "pooled", profileId, ...
                    "state_profile_diagnostic", false, cfg);
                contrastCells{end + 1, 1} = row; %#ok<AGROW>
            end

            ranking = rank_component_energy(PR, PC, component);
            for k = cfg.topK
                excluded = top_dates(ranking, k);
                Sk = build_stacked(PR, PC, outcome, componentPredictors, ...
                    "pooled", excluded);
                fitk = Step23_cluster_ols(Sk.y, Sk.X, Sk.clusters);
                for contrastType = ["LEVEL", "SLOPE"]
                    if contrastType == "LEVEL"
                        Rk = phase_component_R(Sk.term_names, component, 0);
                        contrastId = levelId;
                    else
                        Rk = phase_component_slope_R(Sk.term_names, component);
                        contrastId = slopeId;
                    end
                    testk = Step24_wald_test(fitk, Rk);
                    estimate = Rk * fitk.beta;
                    topKCells{end + 1, 1} = sensitivity_row( ...
                        "MP_CBI_MEDIAN", outcome, contrastId, component, ...
                        k, fitk.G, estimate, testk.p_value); %#ok<AGROW>
                end
            end
        end

        for phase = ["PR", "PC"]
            for state = cfg.states
                contrastId = phase + "_CBI_MINUS_MP_STATE_" + signed_label(state);
                Rwithin = within_phase_component_R( ...
                    Sc.term_names, phase, state);
                row = wald_row(componentFit, Sc, Rwithin, ...
                    "MP_CBI_MEDIAN", outcome, "pooled", contrastId, ...
                    "within_phase_diagnostic", false, cfg);
                contrastCells{end + 1, 1} = row; %#ok<AGROW>
            end
        end

        for root = ["fx", "gg"]
            predictors = componentPredictors(componentPredictors ~= "root_gg");
            Sr = build_stacked(PR, PC, outcome, predictors, root, NaT(0, 1));
            fitr = Step23_cluster_ols(Sr.y, Sr.X, Sr.clusters);
            for component = ["MP", "CBI"]
                contrastId = "PC_MINUS_PR_" + component + "_STATE_0";
                Rr = phase_component_R(Sr.term_names, component, 0);
                row = wald_row(fitr, Sr, Rr, "MP_CBI_MEDIAN", outcome, ...
                    root, contrastId, "asset_diagnostic", false, cfg);
                contrastCells{end + 1, 1} = row; %#ok<AGROW>
            end
        end

        quantiles = unique(rotations.rotation_quantile);
        for q = quantiles'
            PRq = apply_rotation(PR, rotations, "PR", q);
            PCq = apply_rotation(PC, rotations, "PC", q);
            Sq = build_stacked(PRq, PCq, outcome, componentPredictors, ...
                "pooled", NaT(0, 1));
            fitq = Step23_cluster_ols(Sq.y, Sq.X, Sq.clusters);
            Rjoint = phase_equality_matrix(Sq.term_names, cfg.componentTerms);
            joint = Step24_wald_test(fitq, Rjoint);
            rotationCells{end + 1, 1} = rotation_row(outcome, q, ...
                "JOINT_PHASE_SHOCK_SURFACE", NaN, joint.p_value); %#ok<AGROW>
            for component = ["MP", "CBI"]
                for contrastType = ["LEVEL", "SLOPE"]
                    if contrastType == "LEVEL"
                        Rq = phase_component_R(Sq.term_names, component, 0);
                        contrastId = "PC_MINUS_PR_" + component + "_STATE_0";
                    else
                        Rq = phase_component_slope_R(Sq.term_names, component);
                        contrastId = "PC_MINUS_PR_" + component + "_STATE_SLOPE";
                    end
                    testq = Step24_wald_test(fitq, Rq);
                    rotationCells{end + 1, 1} = rotation_row( ...
                        outcome, q, contrastId, Rq * fitq.beta, testq.p_value); %#ok<AGROW>
                end
            end
        end

        for root = ["pooled", "fx", "gg"]
            meCells{end + 1, 1} = me_benchmark(PR, PC, ME, outcome, root); %#ok<AGROW>
        end
    end

    coefficients = vertcat(coefficientCells{:});
    reducedTests = vertcat(reducedCells{:});
    contrasts = vertcat(contrastCells{:});
    bootstrapDraws = vertcat(bootstrapCells{:});
    topKSensitivity = vertcat(topKCells{:});
    rotationSensitivity = vertcat(rotationCells{:});
    meBenchmark = vertcat(meCells{:});

    reducedTests.p_holm = nan(height(reducedTests), 1);
    reducedTests.p_wild_holm = nan(height(reducedTests), 1);
    mainRaw = ismember(reducedTests.family, ...
        ["reduced_form_primary", "reduced_form_robustness"]);
    reducedTests.p_holm(mainRaw) = reducedTests.p_value(mainRaw);
    reducedTests.p_wild_holm(mainRaw) = reducedTests.p_wild_cluster(mainRaw);

    primaryComponent = contrasts.family == "component_phase_primary";
    contrasts.p_holm = nan(height(contrasts), 1);
    contrasts.p_wild_holm = nan(height(contrasts), 1);
    contrasts.p_holm(primaryComponent) = Step23_holm_adjust( ...
        contrasts.p_value(primaryComponent));
    contrasts.p_wild_holm(primaryComponent) = Step23_holm_adjust( ...
        contrasts.p_wild_cluster(primaryComponent));

    decision = build_decision(reducedTests, contrasts, ...
        topKSensitivity, rotationSensitivity, cfg);

    writetable(coefficients, fullfile(outputDir, 'step24_coefficients.csv'));
    writetable(reducedTests, fullfile(outputDir, 'step24_reduced_form_tests.csv'));
    writetable(contrasts, fullfile(outputDir, 'step24_component_contrasts.csv'));
    writetable(bootstrapDraws, fullfile(outputDir, 'step24_wild_bootstrap.csv'));
    writetable(topKSensitivity, fullfile(outputDir, 'step24_leave_top_k.csv'));
    writetable(rotationSensitivity, fullfile(outputDir, ...
        'step24_rotation_sensitivity.csv'));
    writetable(meBenchmark, fullfile(outputDir, 'step24_me_benchmark.csv'));
    writetable(decision, fullfile(outputDir, 'step24_decision.csv'));
    writetable(build_manifest(fileNames, cfg), fullfile(outputDir, ...
        'step24_manifest.csv'));

    fprintf('\n================ STEP 24 PHASE-COMPONENT CONTRASTS ================\n');
    fprintf('Bootstrap draws : %d\n', cfg.bootstrapRep);
    disp(decision(:, {'test_id', 'median_or_primary_pass', ...
        'rotation_pass', 'leave_top_k_pass', 'recommendation'}));
    fprintf('Output directory: %s\n', outputDir);
    fprintf('===================================================================\n');
end

function T = load_event_rows(filePath)
    T = readtable(filePath, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "root_code", "abnormal_log_BV", ...
        "abnormal_log_RV", "q_mp", "q_cbi", "q_mp_cbi", ...
        "pre_state_z", "q_mp_x_pre", "q_cbi_x_pre", ...
        "q_mp_cbi_x_pre", "regime_hike", "root_gg"];
    assert_columns(T, required, filePath);
    T.event_date = Parse_date_flexible(T.event_date);
    T.root_code = lower(string(T.root_code));
end

function C = load_components(filePath)
    C = readtable(filePath, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "window", "policy_indicator_10bp", ...
        "STOXX50", "estimation_sample", "in_project_sample"];
    assert_columns(C, required, filePath);
    C.event_date = Parse_date_flexible(C.event_date);
    C.window = upper(string(C.window));
    C.estimation_sample = to_logical(C.estimation_sample);
    C.in_project_sample = to_logical(C.in_project_sample);
end

function R = load_rotations(filePath)
    R = readtable(filePath, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "window", "rotation_quantile", "MP", "CBI"];
    assert_columns(R, required, filePath);
    R.event_date = Parse_date_flexible(R.event_date);
    R.window = upper(string(R.window));
end

function T = add_reduced_form(T, C, phase)
    keep = C.window == phase & C.estimation_sample & C.in_project_sample;
    S = C(keep, ["event_date", "policy_indicator_10bp", "STOXX50"]);
    [~, first] = unique(S.event_date, 'stable');
    S = S(first, :);
    T = innerjoin(T, S, 'Keys', 'event_date');
    policy = T.policy_indicator_10bp;
    equity = T.STOXX50;
    T.q_policy = policy .^ 2;
    T.q_equity = equity .^ 2;
    T.q_policy_equity = 2 * policy .* equity;
    T.q_policy_x_pre = T.q_policy .* T.pre_state_z;
    T.q_equity_x_pre = T.q_equity .* T.pre_state_z;
    T.q_policy_equity_x_pre = T.q_policy_equity .* T.pre_state_z;
end

function S = build_stacked(PR, PC, outcome, predictors, root, excludedDates)
    if root ~= "pooled"
        PR = PR(PR.root_code == root, :);
        PC = PC(PC.root_code == root, :);
    end
    if ~isempty(excludedDates)
        PR = PR(~ismember(PR.event_date, excludedDates), :);
        PC = PC(~ismember(PC.event_date, excludedDates), :);
    end
    prMask = finite_variables(PR, [outcome, predictors]);
    pcMask = finite_variables(PC, [outcome, predictors]);
    PR = PR(prMask, :);
    PC = PC(pcMask, :);
    prKey = string(PR.event_date, 'yyyy-MM-dd') + "|" + PR.root_code;
    pcKey = string(PC.event_date, 'yyyy-MM-dd') + "|" + PC.root_code;
    if numel(unique(prKey)) ~= numel(prKey) || numel(unique(pcKey)) ~= numel(pcKey)
        error('STEP24_DUPLICATE_PAIR: event-root rows must be unique.');
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
    S.n_pairs = height(PR);
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

function R = phase_component_R(termNames, component, state)
    component = lower(component);
    R = zeros(1, numel(termNames));
    R(termNames == "PC_q_" + component) = 1;
    R(termNames == "PC_q_" + component + "_x_pre") = state;
    R(termNames == "PR_q_" + component) = -1;
    R(termNames == "PR_q_" + component + "_x_pre") = -state;
end

function R = phase_component_slope_R(termNames, component)
    component = lower(component);
    R = zeros(1, numel(termNames));
    R(termNames == "PC_q_" + component + "_x_pre") = 1;
    R(termNames == "PR_q_" + component + "_x_pre") = -1;
end

function R = within_phase_component_R(termNames, phase, state)
    R = zeros(1, numel(termNames));
    R(termNames == phase + "_q_cbi") = 1;
    R(termNames == phase + "_q_cbi_x_pre") = state;
    R(termNames == phase + "_q_mp") = -1;
    R(termNames == phase + "_q_mp_x_pre") = -state;
end

function [row, draws] = wald_row(fit, S, R, basis, outcome, root, ...
        contrastId, family, runWild, cfg)
    test = Step24_wald_test(fit, R);
    draws = nan(0, 1);
    pWild = NaN;
    if runWild
        [pWild, draws] = Step24_wild_wald( ...
            S.y, S.X, S.clusters, R, cfg.bootstrapRep);
    end
    estimate = NaN;
    se = NaN;
    tstat = NaN;
    if size(R, 1) == 1
        estimate = R * fit.beta;
        se = sqrt(max(R * fit.V * R', 0));
        tstat = estimate / se;
    end
    row = table();
    row.basis = basis;
    row.outcome = outcome;
    row.root_sample = root;
    row.contrast_id = contrastId;
    row.family = family;
    row.estimate = estimate;
    row.se_cluster = se;
    row.t_stat = tstat;
    row.wald_f = test.f_statistic;
    row.df1 = test.df1;
    row.df2 = test.df2;
    row.p_value = test.p_value;
    row.p_wild_cluster = pWild;
    row.n_obs = fit.n;
    row.n_clusters = fit.G;
end

function T = coefficient_table(fit, termNames, basis, outcome, root)
    T = table();
    T.basis = repmat(basis, numel(fit.beta), 1);
    T.outcome = repmat(outcome, numel(fit.beta), 1);
    T.root_sample = repmat(root, numel(fit.beta), 1);
    T.term = termNames;
    T.beta = fit.beta;
    T.se_cluster = fit.se;
    T.t_stat = fit.tstat;
    T.p_value = fit.pval;
    T.n_obs = repmat(fit.n, numel(fit.beta), 1);
    T.n_clusters = repmat(fit.G, numel(fit.beta), 1);
    T.r2 = repmat(fit.r2, numel(fit.beta), 1);
end

function T = bootstrap_table(draws, basis, outcome, contrastId)
    T = table();
    T.basis = repmat(basis, numel(draws), 1);
    T.outcome = repmat(outcome, numel(draws), 1);
    T.contrast_id = repmat(contrastId, numel(draws), 1);
    T.draw = (1:numel(draws))';
    T.wald_f = draws;
end

function ranking = rank_component_energy(PR, PC, component)
    [datesPr, firstPr] = unique(PR.event_date, 'stable');
    [datesPc, firstPc] = unique(PC.event_date, 'stable');
    [dates, ia, ib] = intersect(datesPr, datesPc, 'stable');
    if component == "TOTAL"
        energy = PR.q_mp(firstPr(ia)) + PR.q_cbi(firstPr(ia)) + ...
            PC.q_mp(firstPc(ib)) + PC.q_cbi(firstPc(ib));
    else
        variable = "q_" + lower(component);
        energy = PR.(variable)(firstPr(ia)) + PC.(variable)(firstPc(ib));
    end
    ranking = table(dates, energy, 'VariableNames', {'event_date', 'energy'});
    ranking = sortrows(ranking, 'energy', 'descend');
end

function dates = top_dates(ranking, k)
    k = min(k, height(ranking));
    dates = ranking.event_date(1:k);
end

function row = sensitivity_row(basis, outcome, contrastId, ranking, ...
        k, clusters, estimate, pValue)
    row = table();
    row.basis = basis;
    row.outcome = outcome;
    row.contrast_id = contrastId;
    row.ranking_component = ranking;
    row.excluded_top_events = k;
    row.n_clusters = clusters;
    row.estimate = estimate;
    row.p_value = pValue;
end

function T = apply_rotation(T, rotations, phase, quantile)
    keep = rotations.window == phase & ...
        abs(rotations.rotation_quantile - quantile) < 1e-12;
    S = rotations(keep, ["event_date", "MP", "CBI"]);
    mpIndex = find(string(S.Properties.VariableNames) == "MP", 1);
    cbiIndex = find(string(S.Properties.VariableNames) == "CBI", 1);
    S.Properties.VariableNames{mpIndex} = 'rotation_MP';
    S.Properties.VariableNames{cbiIndex} = 'rotation_CBI';
    T = innerjoin(T, S, 'Keys', 'event_date');
    mp = T.rotation_MP / 0.10;
    cbi = T.rotation_CBI / 0.10;
    T.q_mp = mp .^ 2;
    T.q_cbi = cbi .^ 2;
    T.q_mp_cbi = 2 * mp .* cbi;
    T.q_mp_x_pre = T.q_mp .* T.pre_state_z;
    T.q_cbi_x_pre = T.q_cbi .* T.pre_state_z;
    T.q_mp_cbi_x_pre = T.q_mp_cbi .* T.pre_state_z;
end

function row = rotation_row(outcome, quantile, contrastId, estimate, pValue)
    row = table();
    row.outcome = outcome;
    row.rotation_quantile = quantile;
    row.contrast_id = contrastId;
    row.estimate = estimate;
    row.p_value = pValue;
end

function T = me_benchmark(PR, PC, ME, outcome, root)
    if root ~= "pooled"
        PR = PR(PR.root_code == root, :);
        PC = PC(PC.root_code == root, :);
        ME = ME(ME.root_code == root, :);
    end
    keyPr = string(PR.event_date, 'yyyy-MM-dd') + "|" + PR.root_code;
    keyPc = string(PC.event_date, 'yyyy-MM-dd') + "|" + PC.root_code;
    keyMe = string(ME.event_date, 'yyyy-MM-dd') + "|" + ME.root_code;
    [common, ia, ib] = intersect(keyPr, keyPc, 'stable');
    [~, iab, ic] = intersect(common, keyMe, 'stable');
    ia = ia(iab);
    ib = ib(iab);
    pr = PR.(outcome)(ia);
    pc = PC.(outcome)(ib);
    me = ME.(outcome)(ic);
    ok = isfinite(pr) & isfinite(pc) & isfinite(me);
    pr = pr(ok); pc = pc(ok); me = me(ok);
    T = table();
    T.outcome = outcome;
    T.root_sample = root;
    T.n_rows = numel(me);
    T.correlation_me_pr = safe_correlation(me, pr);
    T.correlation_me_pc = safe_correlation(me, pc);
    T.correlation_me_pr_plus_pc = safe_correlation(me, pr + pc);
    T.mean_me_minus_pr = mean(me - pr);
    T.mean_me_minus_pc = mean(me - pc);
end

function D = build_decision(reduced, contrasts, topK, rotation, cfg)
    rows = {};
    raw = reduced(reduced.family == "reduced_form_primary", :);
    rawTop = topK(topK.basis == "REDUCED_FORM" & ...
        topK.outcome == cfg.primaryOutcome & topK.excluded_top_events > 0, :);
    primaryPass = height(raw) == 1 && ...
        all(raw.p_holm <= 0.05 & raw.p_wild_holm <= 0.05);
    topPass = ~isempty(rawTop) && all(rawTop.p_value <= 0.05);
    row = table();
    row.test_id = "REDUCED_FORM_PHASE_HETEROGENEITY";
    row.median_or_primary_pass = primaryPass;
    row.rotation_pass = true;
    row.leave_top_k_pass = topPass;
    row.robust_claim = primaryPass && topPass;
    if row.robust_claim
        row.recommendation = "phase_response_surfaces_differ";
    else
        row.recommendation = "phase_heterogeneity_not_established";
    end
    rows{end + 1, 1} = row;

    rv = reduced(reduced.family == "reduced_form_robustness", :);
    rvTop = topK(topK.basis == "REDUCED_FORM" & ...
        topK.outcome == cfg.robustnessOutcome & topK.excluded_top_events > 0, :);
    rvPass = height(rv) == 1 && ...
        all(rv.p_value <= 0.05 & rv.p_wild_cluster <= 0.05);
    row = table();
    row.test_id = "REDUCED_FORM_RV_CONFIRMATION";
    row.median_or_primary_pass = rvPass;
    row.rotation_pass = true;
    row.leave_top_k_pass = ~isempty(rvTop) && all(rvTop.p_value <= 0.05);
    row.robust_claim = row.median_or_primary_pass && row.leave_top_k_pass;
    if row.robust_claim
        row.recommendation = "rv_confirms_phase_heterogeneity";
    else
        row.recommendation = "rv_does_not_confirm_primary_bv";
    end
    rows{end + 1, 1} = row;

    primary = contrasts(contrasts.family == "component_phase_primary", :);
    ids = unique(primary.contrast_id, 'stable');
    for id = ids'
        m = primary(primary.contrast_id == id, :);
        r = rotation(rotation.contrast_id == id, :);
        k = topK(topK.contrast_id == id & topK.excluded_top_events > 0, :);
        medianPass = height(m) == numel(cfg.outcomes) && ...
            all(m.p_holm <= 0.05 & m.p_wild_holm <= 0.05);
        medianSigns = sign(m.estimate);
        rotationPassByOutcome = false(numel(cfg.outcomes), 1);
        topPassByOutcome = false(numel(cfg.outcomes), 1);
        for j = 1:numel(cfg.outcomes)
            rr = r(r.outcome == cfg.outcomes(j), :);
            kk = k(k.outcome == cfg.outcomes(j), :);
            targetSign = medianSigns(m.outcome == cfg.outcomes(j));
            rotationPassByOutcome(j) = ~isempty(rr) && ...
                all(sign(rr.estimate) == targetSign & rr.p_value <= 0.05);
            topPassByOutcome(j) = ~isempty(kk) && ...
                all(sign(kk.estimate) == targetSign & kk.p_value <= 0.05);
        end
        row = table();
        row.test_id = id;
        row.median_or_primary_pass = medianPass;
        row.rotation_pass = all(rotationPassByOutcome);
        row.leave_top_k_pass = all(topPassByOutcome);
        row.robust_claim = row.median_or_primary_pass && ...
            row.rotation_pass && row.leave_top_k_pass;
        if row.robust_claim
            row.recommendation = "component_phase_contrast_robust";
        else
            row.recommendation = "component_attribution_partial";
        end
        rows{end + 1, 1} = row;
    end
    D = vertcat(rows{:});
end

function manifest = build_manifest(inputFiles, cfg)
    here = fileparts(which('Phase_component_contrasts'));
    hashes = strings(numel(inputFiles), 1);
    for i = 1:numel(inputFiles); hashes(i) = File_sha256(inputFiles(i)); end
    names = ["schema_version"; "created_utc"; "primary_basis"; ...
        "secondary_basis"; "outcomes"; "bootstrap_draws"; "seed"; ...
        "pairing"; "primary_outcome"; "robustness_outcome"; ...
        "primary_multiplicity"; "component_robustness"; ...
        "input_files"; "input_sha256"; "code_commit"; "script_sha256"];
    values = ["step24_v1"; ...
        string(datetime('now', 'TimeZone', 'UTC'), 'yyyy-MM-dd''T''HH:mm:ssXXX'); ...
        "policy-indicator/equity full quadratic surface"; ...
        "median-rotation MP/CBI with identified-set diagnostics"; ...
        strjoin(cfg.outcomes, "|"); string(cfg.bootstrapRep); string(cfg.seed); ...
        "exact event-date x root pairs; event-clustered inference"; ...
        cfg.primaryOutcome; cfg.robustnessOutcome; ...
        "single pre-existing primary BV surface test; RV separate"; ...
        "Holm + wild cluster + full rotation grid + leave-top-1/3/5"; ...
        strjoin(inputFiles, "|"); strjoin(hashes, "|"); ...
        current_git_commit(here); ...
        File_sha256(fullfile(here, 'Phase_component_contrasts.m'))];
    manifest = table(names, values, 'VariableNames', {'name', 'value'});
end

function validate_step23(decisionFile, manifestFile)
    D = readtable(decisionFile, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    if height(D) ~= 2 || any(D.recommendation ~= ...
            "retain_mp_cbi_primary_pc2_diagnostic")
        error('STEP24_STEP23_DECISION: Step 23 did not retain primary MP-CBI.');
    end
    M = readtable(manifestFile, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    schema = M.value(M.name == "schema_version");
    draws = str2double(M.value(M.name == "bootstrap_draws"));
    if numel(schema) ~= 1 || schema ~= "step23_v1" || draws ~= 999
        error('STEP24_STEP23_MANIFEST: final 999-draw Step-23 manifest required.');
    end
end

function mask = finite_variables(T, variables)
    mask = true(height(T), 1);
    for v = variables
        x = T.(v);
        if ~isnumeric(x) && ~islogical(x); x = str2double(string(x)); end
        mask = mask & isfinite(double(x));
    end
end

function value = safe_correlation(x, y)
    ok = isfinite(x) & isfinite(y);
    if sum(ok) < 3 || std(x(ok)) == 0 || std(y(ok)) == 0
        value = NaN;
    else
        C = corrcoef(x(ok), y(ok)); value = C(1, 2);
    end
end

function label = signed_label(value)
    if value < 0; label = "MINUS1";
    elseif value > 0; label = "PLUS1";
    else; label = "0";
    end
end

function assert_columns(T, required, source)
    missing = required(~ismember(required, string(T.Properties.VariableNames)));
    if ~isempty(missing)
        error('STEP24_COLUMNS: %s is missing %s.', source, strjoin(missing, ', '));
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
        error('PHASE_COMPONENT_CONTRAST_DRAWS must be an integer of at least 19.');
    end
end

function commit = current_git_commit(codePath)
    [status, result] = system(sprintf( ...
        'git -C "%s" rev-parse HEAD 2>/dev/null', codePath));
    if status == 0; commit = strtrim(string(result));
    else; commit = "unavailable";
    end
end
