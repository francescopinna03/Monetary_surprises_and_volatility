function Long_horizon_phase_attribution()
%LONG_HORIZON_PHASE_ATTRIBUTION Step 26 official-factor attribution.
%
% The ABGMR Target/Timing/Forward-Guidance/QE factors are reconstructed from
% the full seven-maturity EA-MPD curve.  Their information incremental to the
% Step-25 policy/equity plane is then tested in the paired PR-PC volatility
% system.  Named attribution requires wild-cluster, grouped OOS, leave-top-k
% and generated-factor leave-one-out stability evidence.

    projectRoot = Get_project_root();
    Require_time_alignment_manifest(projectRoot);
    Require_window_semantics_manifest(projectRoot);

    analysisDir = fullfile(projectRoot, 'Output', 'analysis');
    phaseDir = fullfile(projectRoot, 'Output', 'phase_counterfactuals');
    step25Dir = fullfile(projectRoot, 'Output', 'invariant_phase_attribution');
    outputDir = fullfile(projectRoot, 'Output', 'long_horizon_attribution');
    if exist(outputDir, 'dir') ~= 7; mkdir(outputDir); end

    files = struct();
    files.eampd = Locate_first_existing({ ...
        fullfile(projectRoot, 'Raw', 'EA_MPD', 'Dataset_EA-MPD.xlsx'); ...
        fullfile(projectRoot, 'Raw', 'EA_MPD', 'Dataset_EA_MPD.xlsx'); ...
        fullfile(projectRoot, 'Raw', 'EA_MPD', 'EA-MPD.xlsx'); ...
        fullfile(projectRoot, 'Raw', 'EA_MPD', 'EA_MPD.xlsx')});
    files.components = fullfile(analysisDir, 'shock_components_by_event.csv');
    files.pr = fullfile(phaseDir, 'phase_counterfactual_pr_event_rows.csv');
    files.pc = fullfile(phaseDir, 'phase_counterfactual_pc_event_rows.csv');
    files.step25Decision = fullfile(step25Dir, 'step25_decision.csv');
    files.step25Manifest = fullfile(step25Dir, 'step25_manifest.csv');
    fileNames = string(struct2cell(files));
    for f = fileNames'
        if strlength(f) == 0 || exist(f, 'file') ~= 2
            error('STEP26_INPUT_MISSING: required input not found: %s', f);
        end
    end
    validate_step25(files.step25Decision, files.step25Manifest);

    cfg = struct();
    cfg.seed = 26020;
    cfg.bootstrapRep = parse_draw_count(getenv('LONG_HORIZON_ATTRIBUTION_DRAWS'), 999);
    cfg.primaryOutcome = "abnormal_log_BV";
    cfg.robustnessOutcome = "abnormal_log_RV";
    cfg.outcomes = [cfg.primaryOutcome, cfg.robustnessOutcome];
    cfg.factorStart = datetime(2002, 1, 2);
    cfg.preCrisisEnd = datetime(2008, 8, 7);
    cfg.excludedDates = datetime([2001, 2008, 2008], [9, 10, 11], [17, 8, 6])';
    cfg.topK = [0, 1, 3, 5];
    cfg.stabilityCorrelation = 0.90;
    cfg.stabilityRelativeDelta = 0.25;
    cfg.stabilityLoadingCosine = 0.90;
    cfg.gapAttenuationThreshold = 0.50;
    rng(cfg.seed, 'twister');

    C = load_components(files.components);
    [factorRows, factorLoadings, factorAudit, factorLoo, ...
        factorStability, constructionPass] = construct_factors( ...
        files.eampd, C, cfg);
    [PR, prExtra, prResidualAudit] = prepare_phase( ...
        files.pr, C, factorRows, "PR");
    [PC, pcExtra, pcResidualAudit] = prepare_phase( ...
        files.pc, C, factorRows, "PC");
    residualAudit = [prResidualAudit; pcResidualAudit];

    testCells = {};
    oosCells = {};
    drawCells = {};
    topKCells = {};
    beforeRms = NaN;
    afterRms = NaN;

    for outcome = cfg.outcomes
        S = build_stacked(PR, PC, outcome, prExtra, pcExtra, NaT(0, 1));
        if rank(S.X) < size(S.X, 2) || rank(S.Xbase) < size(S.Xbase, 2)
            error(['STEP26_MODEL_RANK: the paired extended design is rank ' ...
                'deficient for %s (%d/%d).'], outcome, rank(S.X), size(S.X, 2));
        end

        baseFit = Step23_cluster_ols(S.y, S.Xbase, S.clusters);
        Rbefore = phase_gap_R(S.base_term_names);
        Sb = S;
        Sb.X = S.Xbase;
        Sb.term_names = S.base_term_names;
        before = wald_row(baseFit, Sb, Rbefore, outcome, ...
            "BASE_PHASE_GAP_BEFORE_EXTENSION", "phase_gap", cfg);
        testCells{end + 1, 1} = before; %#ok<AGROW>

        fullFit = Step23_cluster_ols(S.y, S.X, S.clusters);
        Rafter = phase_gap_R(S.term_names);
        after = wald_row(fullFit, S, Rafter, outcome, ...
            "BASE_PHASE_GAP_AFTER_EXTENSION", "phase_gap", cfg);
        testCells{end + 1, 1} = after; %#ok<AGROW>

        Rjoint = selector_R(S.term_names, startsWith(S.term_names, "PRX_") | ...
            startsWith(S.term_names, "PCX_"));
        joint = wald_row(fullFit, S, Rjoint, outcome, ...
            "LONG_CURVE_JOINT_INCREMENT", "long_curve_joint", cfg);
        testCells{end + 1, 1} = joint; %#ok<AGROW>

        [oosJoint, drawsJoint] = oos_row(S, S.Xbase, S.X, outcome, ...
            "LONG_CURVE_JOINT_INCREMENT", cfg);
        oosCells{end + 1, 1} = oosJoint; %#ok<AGROW>
        drawCells{end + 1, 1} = drawsJoint; %#ok<AGROW>

        components = ["TARGET", "TIMING", "FG", "QE"];
        for component = components
            columns = component_columns(S.term_names, component);
            Rcomponent = selector_R(S.term_names, columns);
            componentId = component + "_UNIQUE_INCREMENT";
            row = wald_row(fullFit, S, Rcomponent, outcome, ...
                componentId, "named_component", cfg);
            row.component = component;
            testCells{end + 1, 1} = row; %#ok<AGROW>

            Xwithout = S.X(:, ~columns);
            [oosComponent, drawsComponent] = oos_row(S, Xwithout, ...
                S.X, outcome, componentId, cfg);
            oosComponent.component = component;
            drawsComponent.component(:) = component;
            oosCells{end + 1, 1} = oosComponent; %#ok<AGROW>
            drawCells{end + 1, 1} = drawsComponent; %#ok<AGROW>
        end

        if outcome == cfg.primaryOutcome
            beforeRms = before.effect_rms;
            afterRms = after.effect_rms;
            ranking = rank_factor_energy(PR, PC);
            for k = cfg.topK
                excluded = ranking.event_date(1:min(k, height(ranking)));
                Sk = build_stacked(PR, PC, outcome, prExtra, pcExtra, excluded);
                fitk = Step23_cluster_ols(Sk.y, Sk.X, Sk.clusters);
                RjointK = selector_R(Sk.term_names, ...
                    startsWith(Sk.term_names, "PRX_") | ...
                    startsWith(Sk.term_names, "PCX_"));
                RgapK = phase_gap_R(Sk.term_names);
                topKCells{end + 1, 1} = top_k_row(fitk, RjointK, ...
                    k, "LONG_CURVE_JOINT_INCREMENT"); %#ok<AGROW>
                gapRow = top_k_row(fitk, RgapK, k, ...
                    "BASE_PHASE_GAP_AFTER_EXTENSION");
                gapRow.effect_rms = phase_gap_rms(fitk, Sk, RgapK);
                topKCells{end + 1, 1} = gapRow; %#ok<AGROW>
                for component = components
                    Rk = selector_R(Sk.term_names, ...
                        component_columns(Sk.term_names, component));
                    topKCells{end + 1, 1} = top_k_row(fitk, Rk, k, ...
                        component + "_UNIQUE_INCREMENT"); %#ok<AGROW>
                end
            end
        end
    end

    tests = harmonise_component_column(vertcat(testCells{:}));
    oos = harmonise_component_column(vertcat(oosCells{:}));
    oosDraws = harmonise_component_column(vertcat(drawCells{:}));
    topKSensitivity = vertcat(topKCells{:});

    tests.p_holm = nan(height(tests), 1);
    tests.p_wild_holm = nan(height(tests), 1);
    for outcome = cfg.outcomes
        family = tests.outcome == outcome & tests.family == "named_component";
        tests.p_holm(family) = Step23_holm_adjust(tests.p_value(family));
        tests.p_wild_holm(family) = Step23_holm_adjust( ...
            tests.p_wild_cluster(family));
    end

    decision = build_decision(tests, oos, topKSensitivity, ...
        factorStability, constructionPass, beforeRms, afterRms, cfg);

    write_dates(factorRows, fullfile(outputDir, 'step26_factors_by_event.csv'));
    writetable(factorLoadings, fullfile(outputDir, 'step26_factor_loadings.csv'));
    writetable(factorAudit, fullfile(outputDir, 'step26_factor_audit.csv'));
    write_dates(factorLoo, fullfile(outputDir, 'step26_factor_loo.csv'));
    writetable(factorStability, fullfile(outputDir, 'step26_factor_stability.csv'));
    writetable(residualAudit, fullfile(outputDir, 'step26_residualization.csv'));
    writetable(tests, fullfile(outputDir, 'step26_tests.csv'));
    writetable(oos, fullfile(outputDir, 'step26_oos.csv'));
    writetable(oosDraws, fullfile(outputDir, 'step26_oos_bootstrap.csv'));
    writetable(topKSensitivity, fullfile(outputDir, 'step26_leave_top_k.csv'));
    writetable(decision, fullfile(outputDir, 'step26_decision.csv'));
    writetable(build_manifest(fileNames, cfg), fullfile(outputDir, ...
        'step26_manifest.csv'));

    fprintf('\n================ STEP 26 LONG-HORIZON ATTRIBUTION ================\n');
    fprintf('Bootstrap draws : %d\n', cfg.bootstrapRep);
    fprintf('Official factors: PR Target; PC Timing, FG, QE\n');
    fprintf('Gap RMS ratio   : %.3f\n', afterRms / max(beforeRms, eps));
    disp(decision(:, {'test_id', 'status', 'recommendation'}));
    fprintf('Output directory: %s\n', outputDir);
    fprintf('===================================================================\n');
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

function [rows, loadings, audit, loo, stability, certified] = ...
        construct_factors(filePath, C, cfg)
    sheets = ["Press Release Window", "Press Conference Window"];
    phases = ["PR", "PC"];
    rowCells = cell(2, 1);
    loadingCells = cell(2, 1);
    auditCells = {};
    looCells = cell(2, 1);

    available = string(sheetnames(filePath));
    for sheet = sheets
        if ~any(strcmpi(strtrim(available), sheet))
            error('STEP26_SHEET_MISSING: required sheet "%s" not found.', sheet);
        end
    end

    for h = 1:2
        phase = phases(h);
        source = read_long_window(filePath, sheets(h));
        [distinctDates, ~, groups] = unique(source.event_date);
        counts = accumarray(groups, 1);
        if any(counts > 1)
            duplicates = distinctDates(counts > 1);
            error('STEP26_DUPLICATE_DATES: %s contains %s.', phase, ...
                strjoin(string(duplicates, 'yyyy-MM-dd'), ', '));
        end
        excluded = ismember(source.event_date, cfg.excludedDates);
        fitSample = source.event_date >= cfg.factorStart & ~excluded & ...
            all(isfinite(source.X), 2);
        [fitScores, fit] = Step26_abgmr_factors(source.X(fitSample, :), ...
            source.event_date(fitSample), phase, cfg.preCrisisEnd);
        scores = nan(height(source.table), size(fitScores, 2));
        scores(fitSample, :) = fitScores;

        projectDates = unique(C.event_date(C.window == phase & ...
            C.estimation_sample & C.in_project_sample));
        missingProject = projectDates(~ismember(projectDates, ...
            source.event_date(fitSample)));
        if ~isempty(missingProject)
            error('STEP26_PROJECT_COVERAGE: %s is missing factor data for %s.', ...
                phase, strjoin(string(missingProject, 'yyyy-MM-dd'), ', '));
        end

        R = table();
        R.event_date = source.event_date(fitSample);
        R.window = repmat(phase, sum(fitSample), 1);
        R.target = nan(sum(fitSample), 1);
        R.timing = nan(sum(fitSample), 1);
        R.fg = nan(sum(fitSample), 1);
        R.qe = nan(sum(fitSample), 1);
        if phase == "PR"; R.target = fitScores(:, 1);
        else
            R.timing = fitScores(:, 1);
            R.fg = fitScores(:, 2);
            R.qe = fitScores(:, 3);
        end
        R.uses_bund_proxy = source.uses_bund(fitSample);
        R.factor_estimation_sample = true(sum(fitSample), 1);
        R.in_project_sample = ismember(R.event_date, projectDates);
        rowCells{h} = R;

        loadingCells{h} = loading_table(fit, phase);
        auditCells = [auditCells; fit_audit(fit, phase, source, ...
            fitSample, R.in_project_sample)]; %#ok<AGROW>

        targetRows = find(fitSample & ismember(source.event_date, projectDates));
        looPhase = cell(numel(targetRows) * numel(fit.factor_names), 1);
        cursor = 0;
        for r = targetRows'
            training = fitSample;
            training(r) = false;
            [~, fitLoo] = Step26_abgmr_factors(source.X(training, :), ...
                source.event_date(training), phase, cfg.preCrisisEnd);
            applied = Step26_apply_abgmr_fit(source.X(r, :), fitLoo);
            fullValue = scores(r, :);
            for j = 1:numel(fit.factor_names)
                cursor = cursor + 1;
                L = table();
                L.event_date = source.event_date(r);
                L.window = phase;
                L.factor = fit.factor_names(j);
                L.full_sample_value = fullValue(j);
                L.leave_one_out_value = applied(j);
                L.delta = applied(j) - fullValue(j);
                L.loading_cosine = cosine_similarity( ...
                    fit.loadings(:, j), fitLoo.loadings(:, j));
                looPhase{cursor} = L;
            end
        end
        looCells{h} = vertcat(looPhase{:});
    end

    rows = vertcat(rowCells{:});
    loadings = vertcat(loadingCells{:});
    audit = vertcat(auditCells{:});
    loo = vertcat(looCells{:});
    stability = summarise_stability(loo, cfg);
    restrictions = audit.metric == "max_anchor_error" | ...
        audit.metric == "max_zero_1m_loading";
    restrictionValues = audit.value(restrictions);
    restrictionValues = restrictionValues(isfinite(restrictionValues));
    certified = ~isempty(restrictionValues) && ...
        all(restrictionValues <= 1e-8) && ...
        all(stability.stability_pass) && ...
        all(audit.value(audit.metric == "n_project_rows") > 0);
end

function source = read_long_window(filePath, sheet)
    T = readtable(filePath, 'Sheet', sheet, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    names = string(T.Properties.VariableNames);
    normal = normalise_names(names);
    dateName = find_name(names, normal, ["date", "event_date", "meeting_date"], true);
    dates = Parse_date_flexible(T.(dateName));

    shortCandidates = { ["ois_1m", "ois1m"], ["ois_3m", "ois3m"], ...
        ["ois_6m", "ois6m"], ["ois_1y", "ois1y"] };
    X = nan(height(T), 7);
    for j = 1:4
        name = find_name(names, normal, shortCandidates{j}, true);
        X(:, j) = to_numeric(T.(name));
    end
    longMaturities = ["2y", "5y", "10y"];
    usesBund = false(height(T), 1);
    for j = 1:3
        maturity = longMaturities(j);
        oisName = find_name(names, normal, ...
            ["ois_" + maturity, "ois" + maturity, ...
            "ois_" + erase(maturity, "y")], true);
        bundName = find_name(names, normal, ...
            ["de" + maturity, "de_" + maturity, ...
            "de" + erase(maturity, "y")], true);
        ois = to_numeric(T.(oisName));
        bund = to_numeric(T.(bundName));
        fallback = ~isfinite(ois) & isfinite(bund);
        ois(fallback) = bund(fallback);
        X(:, 4 + j) = ois;
        usesBund = usesBund | fallback;
    end
    keep = ~isnat(dates);
    source = struct();
    source.table = T(keep, :);
    source.event_date = dates(keep);
    source.X = X(keep, :);
    source.uses_bund = usesBund(keep);
end

function T = loading_table(fit, phase)
    n = numel(fit.factor_names) * numel(fit.maturity_names);
    T = table('Size', [n, 7], 'VariableTypes', ...
        {'string', 'string', 'string', 'double', 'logical', 'logical', 'double'}, ...
        'VariableNames', {'window', 'factor', 'maturity', 'loading', ...
        'normalisation_anchor', 'zero_1m_restriction', 'pca_explained_share'});
    cursor = 0;
    for j = 1:numel(fit.factor_names)
        for m = 1:numel(fit.maturity_names)
            cursor = cursor + 1;
            T.window(cursor) = phase;
            T.factor(cursor) = fit.factor_names(j);
            T.maturity(cursor) = fit.maturity_names(m);
            T.loading(cursor) = fit.loadings(m, j);
            T.normalisation_anchor(cursor) = m == fit.anchor_rows(j);
            T.zero_1m_restriction(cursor) = phase == "PC" && m == 1 && j > 1;
            T.pca_explained_share(cursor) = fit.explained(j);
        end
    end
end

function cells = fit_audit(fit, phase, source, fitSample, inProject)
    metrics = ["n_source_rows", "n_factor_rows", "n_project_rows", ...
        "bund_proxy_share_factor", "bund_proxy_share_project", ...
        "pc1_explained_share", "pc2_explained_share", ...
        "pc3_explained_share", "reconstruction_r2", ...
        "max_anchor_error", "max_zero_1m_loading", ...
        "qe_pre_second_moment", "fg_pre_second_moment"];
    projectSource = fitSample;
    factorIndices = find(fitSample);
    projectSource(factorIndices(~inProject)) = false;
    values = [height(source.table), sum(fitSample), sum(inProject), ...
        mean(source.uses_bund(fitSample)), ...
        safe_mean(source.uses_bund(projectSource)), ...
        fit.explained(1), fit.explained(2), fit.explained(3), ...
        fit.reconstruction_r2, fit.max_anchor_error, ...
        fit.max_zero_1m_loading, fit.qe_pre_second_moment, ...
        fit.fg_pre_second_moment];
    cells = cell(numel(metrics), 1);
    for j = 1:numel(metrics)
        A = table();
        A.window = phase;
        A.metric = metrics(j);
        A.value = values(j);
        cells{j} = A;
    end
end

function S = summarise_stability(loo, cfg)
    windows = unique(loo.window, 'stable');
    cells = {};
    for window = windows'
        factors = unique(loo.factor(loo.window == window), 'stable');
        for factor = factors'
            mask = loo.window == window & loo.factor == factor;
            full = loo.full_sample_value(mask);
            delta = loo.delta(mask);
            scale = std(full);
            correlation = safe_correlation(full, loo.leave_one_out_value(mask));
            medianRelative = median(abs(delta)) / max(scale, eps);
            p95Relative = prctile(abs(delta), 95) / max(scale, eps);
            minCosine = min(loo.loading_cosine(mask));
            pass = correlation >= cfg.stabilityCorrelation && ...
                medianRelative <= cfg.stabilityRelativeDelta && ...
                minCosine >= cfg.stabilityLoadingCosine;
            R = table();
            R.window = window;
            R.factor = factor;
            R.n_events = sum(mask);
            R.full_loo_correlation = correlation;
            R.median_abs_delta_sd = medianRelative;
            R.p95_abs_delta_sd = p95Relative;
            R.min_loading_cosine = minCosine;
            R.stability_pass = pass;
            cells{end + 1, 1} = R; %#ok<AGROW>
        end
    end
    S = vertcat(cells{:});
end

function [T, extraTerms, audit] = prepare_phase(eventFile, C, F, phase)
    E = readtable(eventFile, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "root_code", "abnormal_log_BV", ...
        "abnormal_log_RV", "pre_state_z", "regime_hike", "root_gg"];
    assert_columns(E, required, eventFile);
    E.event_date = Parse_date_flexible(E.event_date);
    E.root_code = lower(string(E.root_code));

    keepC = C.window == phase & C.estimation_sample & C.in_project_sample;
    S = C(keepC, ["event_date", "policy_indicator_10bp", "STOXX50"]);
    [~, first] = unique(S.event_date, 'stable');
    S = S(first, :);
    factorNames = phase_factor_names(phase);
    keepF = F.window == phase & F.in_project_sample;
    FS = F(keepF, ["event_date", lower(factorNames)]);
    S = innerjoin(S, FS, 'Keys', 'event_date');
    if isempty(S)
        error('STEP26_NO_FACTOR_MATCHES: no matched factor rows for %s.', phase);
    end

    auditCells = cell(numel(factorNames), 1);
    for j = 1:numel(factorNames)
        factor = lower(factorNames(j));
        y = double(S.(factor)) / 10;
        X = [ones(height(S), 1), double(S.policy_indicator_10bp)];
        beta = X \ y;
        residual = y - X * beta;
        residualName = "r_" + factor;
        S.(residualName) = residual;
        A = table();
        A.window = phase;
        A.factor = upper(factor);
        A.n_events = height(S);
        A.intercept = beta(1);
        A.policy_slope = beta(2);
        A.residual_sd = std(residual);
        A.spanning_r2 = 1 - sum(residual .^ 2) / ...
            sum((y - mean(y)) .^ 2);
        auditCells{j} = A;
    end
    audit = vertcat(auditCells{:});

    T = innerjoin(E, S, 'Keys', 'event_date');
    if isempty(T)
        error('STEP26_NO_EVENT_MATCHES: no event rows for phase %s.', phase);
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
    [T, extraTerms] = add_factor_terms(T, lower(factorNames));
end

function [T, terms] = add_factor_terms(T, factors)
    levelTerms = strings(0, 1);
    for factor = factors
        r = double(T.("r_" + factor));
        names = ["q_" + factor, "q_policy_" + factor, ...
            "q_equity_" + factor];
        T.(names(1)) = r .^ 2;
        T.(names(2)) = 2 * double(T.policy_indicator_10bp) .* r;
        T.(names(3)) = 2 * double(T.STOXX50) .* r;
        levelTerms = [levelTerms; names']; %#ok<AGROW>
    end
    for i = 1:numel(factors)
        for j = i+1:numel(factors)
            name = "q_" + factors(i) + "_" + factors(j);
            T.(name) = 2 * double(T.("r_" + factors(i))) .* ...
                double(T.("r_" + factors(j)));
            levelTerms(end + 1, 1) = name; %#ok<AGROW>
        end
    end
    stateTerms = levelTerms + "_x_pre";
    for j = 1:numel(levelTerms)
        T.(stateTerms(j)) = double(T.(levelTerms(j))) .* double(T.pre_state_z);
    end
    terms = [levelTerms; stateTerms];
end

function S = build_stacked(PR, PC, outcome, prExtra, pcExtra, excludedDates)
    basePredictors = ["q_policy", "q_equity", "q_policy_equity", ...
        "pre_state_z", "q_policy_x_pre", "q_equity_x_pre", ...
        "q_policy_equity_x_pre", "regime_hike", "root_gg"];
    if ~isempty(excludedDates)
        PR = PR(~ismember(PR.event_date, excludedDates), :);
        PC = PC(~ismember(PC.event_date, excludedDates), :);
    end
    prRequired = [string(outcome(:)); basePredictors(:); prExtra(:)];
    pcRequired = [string(outcome(:)); basePredictors(:); pcExtra(:)];
    PR = PR(finite_variables(PR, prRequired), :);
    PC = PC(finite_variables(PC, pcRequired), :);
    prKey = string(PR.event_date, 'yyyy-MM-dd') + "|" + PR.root_code;
    pcKey = string(PC.event_date, 'yyyy-MM-dd') + "|" + PC.root_code;
    if numel(unique(prKey)) ~= numel(prKey) || ...
            numel(unique(pcKey)) ~= numel(pcKey)
        error('STEP26_DUPLICATE_PAIR: event-root rows must be unique.');
    end
    [~, ia, ib] = intersect(prKey, pcKey, 'stable');
    PR = PR(ia, :);
    PC = PC(ib, :);
    if numel(ia) < 30
        error('STEP26_TOO_FEW_PAIRS: at least 30 paired event-root rows are required.');
    end

    Xpr = design_matrix(PR, basePredictors);
    Xpc = design_matrix(PC, basePredictors);
    zPr = zeros(size(Xpr));
    zPc = zeros(size(Xpc));
    XprExtra = design_matrix_no_intercept(PR, prExtra);
    XpcExtra = design_matrix_no_intercept(PC, pcExtra);
    S = struct();
    S.Xbase = [Xpr, zPr; zPc, Xpc];
    Xextra = [XprExtra, zeros(size(Xpr, 1), size(XpcExtra, 2)); ...
        zeros(size(Xpc, 1), size(XprExtra, 2)), XpcExtra];
    S.X = [S.Xbase, Xextra];
    S.y = [double(PR.(outcome)); double(PC.(outcome))];
    S.clusters = [string(PR.event_date, 'yyyy-MM-dd'); ...
        string(PC.event_date, 'yyyy-MM-dd')];
    baseNames = ["Intercept", basePredictors];
    S.base_term_names = ["PR_" + baseNames, "PC_" + baseNames]';
    S.term_names = [S.base_term_names; "PRX_" + prExtra; "PCX_" + pcExtra];
    shockTerms = ["q_policy", "q_equity", "q_policy_equity", ...
        "q_policy_x_pre", "q_equity_x_pre", "q_policy_equity_x_pre"];
    S.base_shock_profile = [double(PR{:, shockTerms}); double(PC{:, shockTerms})];
end

function X = design_matrix(T, predictors)
    X = [ones(height(T), 1), design_matrix_no_intercept(T, predictors)];
end

function X = design_matrix_no_intercept(T, predictors)
    X = zeros(height(T), numel(predictors));
    for j = 1:numel(predictors); X(:, j) = double(T.(predictors(j))); end
end

function R = phase_gap_R(termNames)
    terms = ["q_policy", "q_equity", "q_policy_equity", ...
        "q_policy_x_pre", "q_equity_x_pre", "q_policy_equity_x_pre"];
    R = zeros(numel(terms), numel(termNames));
    for j = 1:numel(terms)
        R(j, termNames == "PR_" + terms(j)) = -1;
        R(j, termNames == "PC_" + terms(j)) = 1;
    end
end

function columns = component_columns(termNames, component)
    component = lower(string(component));
    prefix = conditional_text(component == "target", "PRX_", "PCX_");
    columns = startsWith(termNames, prefix) & contains(termNames, component);
    if ~any(columns)
        error('STEP26_COMPONENT_COLUMNS: no columns found for %s.', component);
    end
end

function R = selector_R(termNames, columns)
    indices = find(columns);
    if isempty(indices); error('STEP26_EMPTY_RESTRICTION: no selected coefficients.'); end
    R = zeros(numel(indices), numel(termNames));
    for j = 1:numel(indices); R(j, indices(j)) = 1; end
end

function row = wald_row(fit, S, R, outcome, testId, family, cfg)
    test = Step24_wald_test(fit, R);
    [pWild, ~] = Step24_wild_wald(S.y, S.X, S.clusters, R, cfg.bootstrapRep);
    row = table();
    row.outcome = outcome;
    row.test_id = string(testId);
    row.family = string(family);
    row.component = "";
    row.wald_f = test.f_statistic;
    row.df1 = test.df1;
    row.df2 = test.df2;
    row.p_value = test.p_value;
    row.p_wild_cluster = pWild;
    row.effect_rms = NaN;
    if family == "phase_gap"
        row.effect_rms = phase_gap_rms(fit, S, R);
    end
    row.n_obs = fit.n;
    row.n_clusters = fit.G;
    row.rank = fit.rank;
    row.n_coefficients = fit.k;
end

function value = phase_gap_rms(fit, S, R)
    delta = R * fit.beta;
    value = sqrt(mean((S.base_shock_profile * delta) .^ 2));
end

function [row, drawsTable] = oos_row(S, Xbase, Xcandidate, outcome, testId, cfg)
    [summary, loss] = Step23_grouped_oos(S.y, Xbase, Xcandidate, S.clusters);
    [boot, draws] = Step23_paired_bootstrap(loss, cfg.bootstrapRep);
    row = table();
    row.outcome = outcome;
    row.test_id = string(testId);
    row.component = "";
    row.n_obs = summary.n_obs;
    row.n_clusters = summary.n_clusters;
    row.mse_base = summary.mse_base;
    row.mse_candidate = summary.mse_candidate;
    row.loss_improvement = summary.loss_improvement;
    row.oos_improvement_pct = summary.oos_improvement_pct;
    row.bootstrap_ci95_lo = boot.ci95_lo;
    row.bootstrap_ci95_hi = boot.ci95_hi;
    row.bootstrap_p_one_sided = boot.p_one_sided_improvement;
    drawsTable = table();
    drawsTable.outcome = repmat(outcome, numel(draws), 1);
    drawsTable.test_id = repmat(string(testId), numel(draws), 1);
    drawsTable.component = repmat("", numel(draws), 1);
    drawsTable.draw = (1:numel(draws))';
    drawsTable.loss_improvement = draws;
end

function row = top_k_row(fit, R, k, testId)
    test = Step24_wald_test(fit, R);
    row = table();
    row.excluded_top_events = k;
    row.test_id = string(testId);
    row.p_value = test.p_value;
    row.wald_f = test.f_statistic;
    row.effect_rms = NaN;
    row.n_clusters = fit.G;
end

function ranking = rank_factor_energy(PR, PC)
    [~, firstPr] = unique(PR.event_date, 'stable');
    [~, firstPc] = unique(PC.event_date, 'stable');
    A = table();
    A.event_date = PR.event_date(firstPr);
    A.energy_pr = double(PR.r_target(firstPr)) .^ 2;
    B = table();
    B.event_date = PC.event_date(firstPc);
    B.energy_pc = double(PC.r_timing(firstPc)) .^ 2 + ...
        double(PC.r_fg(firstPc)) .^ 2 + double(PC.r_qe(firstPc)) .^ 2;
    ranking = innerjoin(A, B, 'Keys', 'event_date');
    ranking.total_energy = ranking.energy_pr + ranking.energy_pc;
    ranking = sortrows(ranking, 'total_energy', 'descend');
end

function D = build_decision(tests, oos, topK, stability, ...
        constructionPass, beforeRms, afterRms, cfg)
    rows = cell(10, 1);
    rows{1} = decision_row("OFFICIAL_FACTOR_CONSTRUCTION", ...
        pass_status(constructionPass), conditional_text(constructionPass, ...
        "abgmr_restrictions_and_generated_factor_stability_certified", ...
        "official_factor_construction_or_stability_failed"), constructionPass);

    before = test_record(tests, cfg.primaryOutcome, ...
        "BASE_PHASE_GAP_BEFORE_EXTENSION");
    after = test_record(tests, cfg.primaryOutcome, ...
        "BASE_PHASE_GAP_AFTER_EXTENSION");
    joint = test_record(tests, cfg.primaryOutcome, ...
        "LONG_CURVE_JOINT_INCREMENT");
    jointOos = oos_record(oos, cfg.primaryOutcome, ...
        "LONG_CURVE_JOINT_INCREMENT");
    jointInference = joint.p_value <= 0.05 && joint.p_wild_cluster <= 0.05;
    jointPrediction = jointOos.bootstrap_ci95_lo > 0 && ...
        jointOos.bootstrap_p_one_sided <= 0.05;
    rows{2} = decision_row("LONG_CURVE_INCREMENTAL_BLOCK", ...
        pass_status(jointInference && jointPrediction), ...
        joint_recommendation(jointInference, jointPrediction), ...
        jointInference && jointPrediction);

    attenuation = afterRms / max(beforeRms, eps);
    afterNotDetected = after.p_value > 0.05 && after.p_wild_cluster > 0.05;
    attenuated = attenuation <= cfg.gapAttenuationThreshold;
    rows{3} = decision_row("BASE_PHASE_GAP_AFTER_LONG_CURVE", ...
        pass_status(afterNotDetected && attenuated), ...
        conditional_text(afterNotDetected && attenuated, ...
        "base_phase_gap_attenuated_below_preregistered_threshold", ...
        "base_phase_gap_persists_or_is_not_materially_attenuated"), ...
        afterNotDetected && attenuated);

    topMask = topK.excluded_top_events > 0;
    topJoint = topMask & topK.test_id == "LONG_CURVE_JOINT_INCREMENT";
    topGap = topMask & topK.test_id == "BASE_PHASE_GAP_AFTER_EXTENSION";
    topPass = all(topK.p_value(topJoint) <= 0.05) && ...
        all(topK.p_value(topGap) > 0.05);
    globalPass = constructionPass && before.p_value <= 0.05 && ...
        before.p_wild_cluster <= 0.05 && ...
        jointInference && jointPrediction && afterNotDetected && attenuated && topPass;
    rows{4} = decision_row("LONG_CURVE_ACCOUNTS_FOR_PHASE_GAP", ...
        pass_status(globalPass), conditional_text(globalPass, ...
        "long_curve_block_robustly_accounts_for_pr_pc_gap", ...
        "long_curve_attribution_is_partial_or_not_predictively_robust"), globalPass);

    components = ["TARGET", "TIMING", "FG", "QE"];
    componentPass = false(numel(components), 1);
    for j = 1:numel(components)
        component = components(j);
        test = test_record(tests, cfg.primaryOutcome, ...
            component + "_UNIQUE_INCREMENT");
        prediction = oos_record(oos, cfg.primaryOutcome, ...
            component + "_UNIQUE_INCREMENT");
        phase = conditional_text(component == "TARGET", "PR", "PC");
        stable = stability.window == phase & stability.factor == component;
        stablePass = sum(stable) == 1 && stability.stability_pass(stable);
        top = topMask & topK.test_id == component + "_UNIQUE_INCREMENT";
        componentPass(j) = test.p_holm <= 0.05 && ...
            test.p_wild_holm <= 0.05 && prediction.bootstrap_ci95_lo > 0 && ...
            prediction.bootstrap_p_one_sided <= 0.05 && ...
            all(topK.p_value(top) <= 0.05) && stablePass;
        rows{4 + j} = decision_row(component + "_ATTRIBUTION", ...
            pass_status(componentPass(j)), conditional_text(componentPass(j), ...
            lower(component) + "_has_robust_unique_incremental_content", ...
            lower(component) + "_unique_attribution_not_established"), ...
            componentPass(j));
    end

    single = globalPass && sum(componentPass) == 1;
    if single
        singleRecommendation = "single_component_" + ...
            lower(components(componentPass)) + "_attribution_supported";
    elseif globalPass && sum(componentPass) > 1
        singleRecommendation = "multiple_policy_curve_components_contribute";
    else
        singleRecommendation = "single_named_component_not_identified";
    end
    rows{9} = decision_row("SINGLE_OFFICIAL_COMPONENT_DOMINANCE", ...
        pass_status(single), singleRecommendation, single);
    rows{10} = decision_row("STRUCTURAL_MP_CBI_BOUNDARY", ...
        "diagnostic_only", ...
        "official_curve_factors_do_not_by_themselves_separate_mp_from_cbi", false);
    D = vertcat(rows{:});
end

function text = joint_recommendation(inference, prediction)
    if inference && prediction
        text = "long_curve_block_survives_in_sample_and_grouped_oos";
    elseif inference
        text = "long_curve_block_is_in_sample_only";
    elseif prediction
        text = "predictive_gain_without_cluster_robust_block_evidence";
    else
        text = "no_robust_incremental_long_curve_evidence";
    end
end

function row = decision_row(testId, status, recommendation, robust)
    row = table();
    row.test_id = string(testId);
    row.status = string(status);
    row.recommendation = string(recommendation);
    row.robust_claim = logical(robust);
end

function row = test_record(T, outcome, testId)
    mask = T.outcome == outcome & T.test_id == testId;
    if sum(mask) ~= 1; error('STEP26_TEST_RECORD: expected one row for %s.', testId); end
    row = T(mask, :);
end

function row = oos_record(T, outcome, testId)
    mask = T.outcome == outcome & T.test_id == testId;
    if sum(mask) ~= 1; error('STEP26_OOS_RECORD: expected one row for %s.', testId); end
    row = T(mask, :);
end

function names = phase_factor_names(phase)
    if phase == "PR"; names = "TARGET";
    else; names = ["TIMING", "FG", "QE"];
    end
end

function T = harmonise_component_column(T)
    if ~ismember("component", string(T.Properties.VariableNames))
        T.component = repmat("", height(T), 1);
    end
end

function D = validate_step25(decisionFile, manifestFile)
    D = readtable(decisionFile, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    assert_columns(D, ["test_id", "status", "recommendation"], decisionFile);
    required = ["BV_MEAN_AND_STATE_BLOCKS", "MP_LIKE_GEOMETRIC_DIRECTION", ...
        "EXACT_MP_CBI_POINT_ATTRIBUTION", "SHORT_CURVE_OMITTED_COMPONENTS", ...
        "LONG_HORIZON_TARGET_TIMING_FG_QE"];
    if any(~ismember(required, D.test_id)) || ...
            D.status(D.test_id == "BV_MEAN_AND_STATE_BLOCKS") ~= "pass" || ...
            D.status(D.test_id == "MP_LIKE_GEOMETRIC_DIRECTION") ~= "pass" || ...
            D.status(D.test_id == "EXACT_MP_CBI_POINT_ATTRIBUTION") ~= "fail" || ...
            D.status(D.test_id == "SHORT_CURVE_OMITTED_COMPONENTS") ~= "not_supported" || ...
            D.status(D.test_id == "LONG_HORIZON_TARGET_TIMING_FG_QE") ~= "not_tested"
        error('STEP26_STEP25_DECISION: final Step-25 partial-attribution state required.');
    end
    M = readtable(manifestFile, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    assert_columns(M, ["name", "value"], manifestFile);
    schema = M.value(M.name == "schema_version");
    draws = str2double(M.value(M.name == "bootstrap_draws"));
    if numel(schema) ~= 1 || schema ~= "step25_v1" || draws ~= 999
        error('STEP26_STEP25_MANIFEST: final 999-draw step25_v1 manifest required.');
    end
end

function manifest = build_manifest(inputFiles, cfg)
    here = fileparts(which('Long_horizon_phase_attribution'));
    hashes = strings(numel(inputFiles), 1);
    for i = 1:numel(inputFiles); hashes(i) = File_sha256(inputFiles(i)); end
    names = ["schema_version"; "created_utc"; "primary_outcome"; ...
        "robustness_outcome"; "factor_method"; "factor_maturities"; ...
        "factor_sample_start"; "pre_crisis_end"; "official_exclusions"; ...
        "incrementalisation"; "bootstrap_draws"; "seed"; ...
        "gap_attenuation_threshold"; "structural_boundary"; ...
        "method_source"; "replication_source"; "input_files"; ...
        "input_sha256"; "code_commit"; "script_sha256"];
    values = ["step26_v1"; ...
        string(datetime('now', 'TimeZone', 'UTC'), 'yyyy-MM-dd''T''HH:mm:ssXXX'); ...
        cfg.primaryOutcome; cfg.robustnessOutcome; ...
        "ABGMR centered unstandardised PCA and constrained orthonormal rotation"; ...
        "1M|3M|6M|1Y|2Y|5Y|10Y with German-yield fallback"; ...
        string(cfg.factorStart, 'yyyy-MM-dd'); ...
        string(cfg.preCrisisEnd, 'yyyy-MM-dd'); ...
        strjoin(string(cfg.excludedDates, 'yyyy-MM-dd'), '|'); ...
        "official factors residualised on Step-22 policy indicator before quadratic augmentation"; ...
        string(cfg.bootstrapRep); string(cfg.seed); ...
        string(cfg.gapAttenuationThreshold); ...
        "Target/Timing/FG/QE are curve signals, not a structural MP-CBI separation"; ...
        "https://www.ecb.europa.eu/pub/pdf/scpwps/ecb.wp2281~3303fd281b.en.pdf"; ...
        "https://www.bilkent.edu.tr/~refet/ABGMR_replication_files.zip"; ...
        strjoin(inputFiles, '|'); strjoin(hashes, '|'); ...
        current_git_commit(here); ...
        File_sha256(fullfile(here, 'Long_horizon_phase_attribution.m'))];
    manifest = table(names, values, 'VariableNames', {'name', 'value'});
end

function name = find_name(names, normal, candidates, required)
    name = "";
    for candidate = candidates
        hit = find(normal == candidate, 1);
        if ~isempty(hit); name = names(hit); return; end
    end
    if required
        error('STEP26_COLUMNS: missing one of %s.', strjoin(candidates, ', '));
    end
end

function normal = normalise_names(names)
    normal = lower(strtrim(names));
    normal = regexprep(normal, '[^a-z0-9]+', '_');
    normal = regexprep(normal, '_+', '_');
    normal = regexprep(normal, '^_|_$', '');
end

function x = to_numeric(x)
    if ~isnumeric(x); x = str2double(string(x)); end
    x = double(x(:));
end

function mask = finite_variables(T, variables)
    variables = string(variables(:));
    mask = true(height(T), 1);
    for j = 1:numel(variables)
        v = variables(j);
        x = T.(v);
        if ~isnumeric(x) && ~islogical(x); x = str2double(string(x)); end
        mask = mask & isfinite(double(x));
    end
end

function assert_columns(T, required, source)
    missing = required(~ismember(required, string(T.Properties.VariableNames)));
    if ~isempty(missing)
        error('STEP26_COLUMNS: %s is missing %s.', source, strjoin(missing, ', '));
    end
end

function x = to_logical(x)
    if islogical(x); return; end
    if isnumeric(x); x = x ~= 0; return; end
    x = ismember(lower(strtrim(string(x))), ["1", "true", "yes"]);
end

function value = cosine_similarity(a, b)
    value = (a' * b) / max(norm(a) * norm(b), eps);
end

function value = safe_correlation(a, b)
    if numel(a) < 2 || std(a) <= 0 || std(b) <= 0; value = NaN;
    else
        R = corrcoef(a, b);
        value = R(1, 2);
    end
end

function value = safe_mean(x)
    if isempty(x); value = NaN; else; value = mean(x); end
end

function value = pass_status(flag)
    if flag; value = "pass"; else; value = "fail"; end
end

function value = conditional_text(flag, yesValue, noValue)
    if flag; value = string(yesValue); else; value = string(noValue); end
end

function count = parse_draw_count(raw, fallback)
    if strlength(string(raw)) == 0; count = fallback;
    else; count = str2double(string(raw));
    end
    if ~isfinite(count) || count < 19 || count ~= floor(count)
        error('LONG_HORIZON_ATTRIBUTION_DRAWS must be an integer of at least 19.');
    end
end

function write_dates(T, path)
    if ismember('event_date', T.Properties.VariableNames)
        T.event_date.Format = 'yyyy-MM-dd';
    end
    writetable(T, path);
end

function commit = current_git_commit(codePath)
    [status, result] = system(sprintf( ...
        'git -C "%s" rev-parse HEAD 2>/dev/null', codePath));
    if status == 0; commit = strtrim(string(result));
    else; commit = "unavailable";
    end
end
