function Component_sufficiency_analysis()
%COMPONENT_SUFFICIENCY_ANALYSIS Step 23 MP-CBI spanning diagnostics.
%
% The analysis asks whether curve information beyond the broad MP-CBI pair
% improves abnormal-volatility models. PR and PC are the decision phases;
% ME is descriptive. PC2 is the only candidate refinement. PC2-PC4 energy
% and target/path models remain diagnostics and cannot change the decision.

    projectRoot = Get_project_root();
    Require_time_alignment_manifest(projectRoot);
    Require_window_semantics_manifest(projectRoot);

    analysisDir = fullfile(projectRoot, 'Output', 'analysis');
    phaseDir = fullfile(projectRoot, 'Output', 'phase_counterfactuals');
    outputDir = fullfile(projectRoot, 'Output', 'component_sufficiency');
    if exist(outputDir, 'dir') ~= 7
        mkdir(outputDir);
    end

    componentsFile = fullfile(analysisDir, 'shock_components_by_event.csv');
    rotationFile = fullfile(analysisDir, ...
        'shock_components_rotation_sensitivity.csv');
    required = [string(componentsFile); string(rotationFile)];
    for phase = ["PR", "PC", "ME"]
        required(end + 1, 1) = fullfile(phaseDir, ...
            "phase_counterfactual_" + lower(phase) + "_event_rows.csv"); %#ok<AGROW>
    end
    for f = required'
        if exist(f, 'file') ~= 2
            error('STEP23_INPUT_MISSING: required input not found: %s', f);
        end
    end

    cfg = struct();
    cfg.seed = 23026;
    cfg.bootstrapRep = parse_draw_count(getenv('COMPONENT_SUFFICIENCY_DRAWS'), 999);
    cfg.phases = ["PR", "PC", "ME"];
    cfg.decisionPhases = ["PR", "PC"];
    cfg.outcomes = ["abnormal_log_BV", "abnormal_log_RV"];
    cfg.topK = [0, 1, 3, 5];
    cfg.rotationOosTolerance = 1e-8;
    rng(cfg.seed, 'twister');

    components = load_components(componentsFile);
    rotations = load_rotations(rotationFile);

    modelCells = {};
    oosCells = {};
    bootstrapCells = {};
    rotationCells = {};
    topKCells = {};
    supportCells = {};

    for phase = cfg.phases
        eventFile = fullfile(phaseDir, ...
            "phase_counterfactual_" + lower(phase) + "_event_rows.csv");
        T = prepare_phase_table(eventFile, components, phase);
        supportCells{end + 1, 1} = component_support(T, phase); %#ok<AGROW>

        for outcome = cfg.outcomes
            [M, O, eventLoss] = compare_model(T, phase, outcome, "PC2");
            [boot, draws] = Step23_paired_bootstrap(eventLoss, cfg.bootstrapRep);
            O.bootstrap_draws = boot.bootstrap_draws;
            O.bootstrap_ci95_lo = boot.ci95_lo;
            O.bootstrap_ci95_hi = boot.ci95_hi;
            O.bootstrap_p_one_sided = boot.p_one_sided_improvement;
            modelCells{end + 1, 1} = M; %#ok<AGROW>
            oosCells{end + 1, 1} = O; %#ok<AGROW>

            B = table();
            B.phase = repmat(phase, numel(draws), 1);
            B.outcome = repmat(outcome, numel(draws), 1);
            B.candidate = repmat("PC2", numel(draws), 1);
            B.draw = (1:numel(draws))';
            B.loss_improvement = draws;
            bootstrapCells{end + 1, 1} = B; %#ok<AGROW>

            for diagnostic = ["PC234", "TARGET_PATH"]
                [Md, Od] = compare_model(T, phase, outcome, diagnostic);
                modelCells{end + 1, 1} = Md; %#ok<AGROW>
                oosCells{end + 1, 1} = Od; %#ok<AGROW>
            end

            if ismember(phase, cfg.decisionPhases)
                for k = cfg.topK
                    Tk = exclude_top_pc2_dates(T, k);
                    [Mk, Ok] = compare_model(Tk, phase, outcome, "PC2");
                    K = table();
                    K.phase = phase;
                    K.outcome = outcome;
                    K.excluded_top_pc2_events = k;
                    K.n_clusters = Ok.n_clusters;
                    K.delta_r2 = Mk.delta_r2;
                    K.block_p_value = Mk.block_p_value;
                    K.oos_improvement_pct = Ok.oos_improvement_pct;
                    topKCells{end + 1, 1} = K; %#ok<AGROW>
                end
            end
        end

        if ismember(phase, cfg.decisionPhases)
            quantiles = unique(rotations.rotation_quantile(rotations.window == phase));
            for q = quantiles'
                Tq = apply_rotation(T, rotations, phase, q);
                for outcome = cfg.outcomes
                    [Mr, Or] = compare_model(Tq, phase, outcome, "PC2");
                    R = table();
                    R.phase = phase;
                    R.outcome = outcome;
                    R.rotation_quantile = q;
                    R.rotation_angle_radians = rotation_angle(rotations, phase, q);
                    R.mp_correlation_to_median = rotation_correlation( ...
                        rotations, phase, q, "MP");
                    R.cbi_correlation_to_median = rotation_correlation( ...
                        rotations, phase, q, "CBI");
                    R.delta_r2 = Mr.delta_r2;
                    R.block_p_value = Mr.block_p_value;
                    R.oos_improvement_pct = Or.oos_improvement_pct;
                    rotationCells{end + 1, 1} = R; %#ok<AGROW>
                end
            end
        end
    end

    modelComparison = vertcat(modelCells{:});
    oosComparison = vertcat(oosCells{:});
    bootstrapDraws = vertcat(bootstrapCells{:});
    rotationSensitivity = vertcat(rotationCells{:});
    topKSensitivity = vertcat(topKCells{:});
    support = vertcat(supportCells{:});

    modelComparison.p_holm_primary_family = nan(height(modelComparison), 1);
    primaryFamily = modelComparison.candidate == "PC2" & ...
        ismember(modelComparison.phase, cfg.decisionPhases) & ...
        ismember(modelComparison.outcome, cfg.outcomes);
    modelComparison.p_holm_primary_family(primaryFamily) = ...
        Step23_holm_adjust(modelComparison.block_p_value(primaryFamily));

    decision = build_decision(modelComparison, oosComparison, ...
        rotationSensitivity, topKSensitivity, cfg);

    writetable(modelComparison, fullfile(outputDir, ...
        'step23_model_comparison.csv'));
    writetable(oosComparison, fullfile(outputDir, ...
        'step23_oos_comparison.csv'));
    writetable(bootstrapDraws, fullfile(outputDir, ...
        'step23_oos_bootstrap.csv'));
    writetable(rotationSensitivity, fullfile(outputDir, ...
        'step23_rotation_sensitivity.csv'));
    writetable(topKSensitivity, fullfile(outputDir, ...
        'step23_leave_top_k.csv'));
    writetable(support, fullfile(outputDir, 'step23_component_support.csv'));
    writetable(decision, fullfile(outputDir, 'step23_decision.csv'));

    manifest = build_manifest(required, cfg);
    writetable(manifest, fullfile(outputDir, 'step23_manifest.csv'));

    fprintf('\n================ STEP 23 COMPONENT SUFFICIENCY ================\n');
    fprintf('Bootstrap draws : %d\n', cfg.bootstrapRep);
    fprintf('Decision phases : PR, PC\n');
    fprintf('Descriptive     : ME, PC2-PC4 energy, target/path alternative\n');
    disp(decision(:, {'phase', 'in_sample_pass', 'oos_bootstrap_pass', ...
        'rotation_pass', 'leave_top_k_pass', 'recommendation'}));
    fprintf('Output directory: %s\n', outputDir);
    fprintf('================================================================\n');
end

function C = load_components(filePath)
    C = readtable(filePath, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "window", "curve_PC2_z", "curve_PC3_z", ...
        "curve_PC4_z", "target_proxy_10bp", "path_slope_proxy_10bp", ...
        "estimation_sample", "in_project_sample"];
    assert_columns(C, required, 'shock_components_by_event.csv');
    C.event_date = Parse_date_flexible(C.event_date);
    C.window = upper(string(C.window));
    C.estimation_sample = to_logical(C.estimation_sample);
    C.in_project_sample = to_logical(C.in_project_sample);
end

function R = load_rotations(filePath)
    R = readtable(filePath, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "window", "rotation_quantile", ...
        "rotation_angle_radians", "MP", "CBI"];
    assert_columns(R, required, 'shock_components_rotation_sensitivity.csv');
    R.event_date = Parse_date_flexible(R.event_date);
    R.window = upper(string(R.window));
end

function T = prepare_phase_table(eventFile, C, phase)
    E = readtable(eventFile, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    base = ["event_date", "q_mp", "q_cbi", "q_mp_cbi", ...
        "pre_state_z", "q_mp_x_pre", "q_cbi_x_pre", ...
        "q_mp_cbi_x_pre", "regime_hike", "root_gg", ...
        "abnormal_log_BV", "abnormal_log_RV"];
    assert_columns(E, base, char(phase + " event rows"));
    E.event_date = Parse_date_flexible(E.event_date);

    keep = C.window == phase & C.estimation_sample & C.in_project_sample;
    variables = ["event_date", "curve_PC2_z", "curve_PC3_z", ...
        "curve_PC4_z", "target_proxy_10bp", "path_slope_proxy_10bp"];
    S = C(keep, variables);
    [dates, first] = unique(S.event_date, 'stable');
    if numel(dates) ~= height(S)
        S = S(first, :);
    end
    T = innerjoin(E, S, 'Keys', 'event_date');
    if isempty(T)
        error('STEP23_NO_MATCHES: no component matches for phase %s.', phase);
    end

    T.q_pc2 = T.curve_PC2_z .^ 2;
    T.q_pc2_x_pre = T.q_pc2 .* T.pre_state_z;
    T.q_pc234 = T.curve_PC2_z .^ 2 + T.curve_PC3_z .^ 2 + ...
        T.curve_PC4_z .^ 2;
    T.q_pc234_x_pre = T.q_pc234 .* T.pre_state_z;
    T.q_target = T.target_proxy_10bp .^ 2;
    T.q_path = T.path_slope_proxy_10bp .^ 2;
    T.q_target_path = 2 * T.target_proxy_10bp .* T.path_slope_proxy_10bp;
    T.q_target_x_pre = T.q_target .* T.pre_state_z;
    T.q_path_x_pre = T.q_path .* T.pre_state_z;
    T.q_target_path_x_pre = T.q_target_path .* T.pre_state_z;
end

function [M, O, eventLoss] = compare_model(T, phase, outcome, candidate)
    base = ["q_mp", "q_cbi", "q_mp_cbi", "pre_state_z", ...
        "q_mp_x_pre", "q_cbi_x_pre", "q_mp_cbi_x_pre", ...
        "regime_hike", "root_gg"];
    switch candidate
        case "PC2"
            extra = ["q_pc2", "q_pc2_x_pre"];
            candidateVariables = [base, extra];
            nested = true;
        case "PC234"
            extra = ["q_pc234", "q_pc234_x_pre"];
            candidateVariables = [base, extra];
            nested = true;
        case "TARGET_PATH"
            extra = strings(0, 1);
            candidateVariables = ["q_target", "q_path", "q_target_path", ...
                "pre_state_z", "q_target_x_pre", "q_path_x_pre", ...
                "q_target_path_x_pre", "regime_hike", "root_gg"];
            nested = false;
        otherwise
            error('STEP23_CANDIDATE: unknown candidate %s.', candidate);
    end

    required = unique([outcome, base, candidateVariables]);
    mask = finite_variables(T, required);
    y = T.(outcome)(mask);
    Xbase = design_matrix(T(mask, :), base);
    Xcandidate = design_matrix(T(mask, :), candidateVariables);
    clusters = string(T.event_date(mask), 'yyyy-MM-dd');
    baseFit = Step23_cluster_ols(y, Xbase, clusters);
    candidateFit = Step23_cluster_ols(y, Xcandidate, clusters);

    blockStatistic = NaN;
    blockP = NaN;
    extraBeta = [NaN; NaN];
    extraSe = [NaN; NaN];
    if nested
        columns = (size(Xcandidate, 2) - numel(extra) + 1):size(Xcandidate, 2);
        b = candidateFit.beta(columns);
        V = candidateFit.V(columns, columns);
        blockStatistic = b' * pinv(V) * b;
        blockP = 1 - fcdf(blockStatistic / numel(columns), ...
            numel(columns), max(candidateFit.G - 1, 1));
        extraBeta = b;
        extraSe = candidateFit.se(columns);
    end

    M = table();
    M.phase = phase;
    M.outcome = outcome;
    M.candidate = candidate;
    M.n_obs = candidateFit.n;
    M.n_clusters = candidateFit.G;
    M.rank_base = baseFit.rank;
    M.rank_candidate = candidateFit.rank;
    M.base_r2 = baseFit.r2;
    M.candidate_r2 = candidateFit.r2;
    M.delta_r2 = candidateFit.r2 - baseFit.r2;
    M.extra_level_beta = extraBeta(1);
    M.extra_level_se = extraSe(1);
    M.extra_state_beta = extraBeta(2);
    M.extra_state_se = extraSe(2);
    M.block_statistic = blockStatistic;
    M.block_df = numel(extra);
    M.block_p_value = blockP;

    [oos, eventLoss] = Step23_grouped_oos( ...
        y, Xbase, Xcandidate, clusters);
    O = table();
    O.phase = phase;
    O.outcome = outcome;
    O.candidate = candidate;
    O.n_obs = oos.n_obs;
    O.n_clusters = oos.n_clusters;
    O.mse_base = oos.mse_base;
    O.mse_candidate = oos.mse_candidate;
    O.loss_improvement = oos.loss_improvement;
    O.oos_improvement_pct = oos.oos_improvement_pct;
    O.bootstrap_draws = NaN;
    O.bootstrap_ci95_lo = NaN;
    O.bootstrap_ci95_hi = NaN;
    O.bootstrap_p_one_sided = NaN;
end

function X = design_matrix(T, variables)
    X = ones(height(T), 1);
    for v = variables
        X = [X, double(T.(v))]; %#ok<AGROW>
    end
end

function mask = finite_variables(T, variables)
    mask = true(height(T), 1);
    for v = variables
        x = T.(v);
        if ~isnumeric(x) && ~islogical(x)
            x = str2double(string(x));
        end
        mask = mask & isfinite(double(x));
    end
end

function Tk = exclude_top_pc2_dates(T, k)
    [dates, first] = unique(T.event_date, 'stable');
    energy = T.q_pc2(first);
    [~, order] = sort(energy, 'descend');
    k = min(k, numel(order));
    excluded = dates(order(1:k));
    Tk = T(~ismember(T.event_date, excluded), :);
end

function Tq = apply_rotation(T, R, phase, quantile)
    keep = R.window == phase & abs(R.rotation_quantile - quantile) < 1e-12;
    S = R(keep, ["event_date", "MP", "CBI"]);
    S.Properties.VariableNames{'MP'} = 'rotation_MP';
    S.Properties.VariableNames{'CBI'} = 'rotation_CBI';
    Tq = innerjoin(T, S, 'Keys', 'event_date');
    mp = Tq.rotation_MP / 0.10;
    cbi = Tq.rotation_CBI / 0.10;
    Tq.q_mp = mp .^ 2;
    Tq.q_cbi = cbi .^ 2;
    Tq.q_mp_cbi = 2 * mp .* cbi;
    Tq.q_mp_x_pre = Tq.q_mp .* Tq.pre_state_z;
    Tq.q_cbi_x_pre = Tq.q_cbi .* Tq.pre_state_z;
    Tq.q_mp_cbi_x_pre = Tq.q_mp_cbi .* Tq.pre_state_z;
end

function angle = rotation_angle(R, phase, quantile)
    x = R.rotation_angle_radians(R.window == phase & ...
        abs(R.rotation_quantile - quantile) < 1e-12);
    angle = x(1);
end

function value = rotation_correlation(R, phase, quantile, component)
    A = R(R.window == phase & abs(R.rotation_quantile - quantile) < 1e-12, ...
        ["event_date", component]);
    B = R(R.window == phase & abs(R.rotation_quantile - 0.5) < 1e-12, ...
        ["event_date", component]);
    componentIndex = find(string(B.Properties.VariableNames) == component, 1);
    B.Properties.VariableNames{componentIndex} = 'median_component';
    J = innerjoin(A, B, 'Keys', 'event_date');
    if height(J) < 3
        value = NaN;
    else
        C = corrcoef(J.(component), J.median_component);
        value = C(1, 2);
    end
end

function S = component_support(T, phase)
    [~, first] = unique(T.event_date, 'stable');
    U = T(first, :);
    variables = ["q_mp", "q_cbi", "q_pc2"];
    cells = cell(numel(variables), 1);
    for j = 1:numel(variables)
        x = max(double(U.(variables(j))), 0);
        total = sum(x);
        sorted = sort(x, 'descend');
        row = table();
        row.phase = phase;
        row.component_energy = variables(j);
        row.n_events = numel(x);
        row.total_energy = total;
        row.top1_share = sum(sorted(1:min(1, numel(sorted)))) / total;
        row.top5_share = sum(sorted(1:min(5, numel(sorted)))) / total;
        row.top10_share = sum(sorted(1:min(10, numel(sorted)))) / total;
        cells{j} = row;
    end
    S = vertcat(cells{:});
end

function D = build_decision(M, O, R, K, cfg)
    rows = cell(numel(cfg.decisionPhases), 1);
    for i = 1:numel(cfg.decisionPhases)
        phase = cfg.decisionPhases(i);
        m = M(M.phase == phase & M.candidate == "PC2" & ...
            ismember(M.outcome, cfg.outcomes), :);
        o = O(O.phase == phase & O.candidate == "PC2" & ...
            ismember(O.outcome, cfg.outcomes), :);
        r = R(R.phase == phase & ismember(R.outcome, cfg.outcomes), :);
        k = K(K.phase == phase & K.excluded_top_pc2_events > 0 & ...
            ismember(K.outcome, cfg.outcomes), :);

        inSamplePass = height(m) == numel(cfg.outcomes) && ...
            all(m.p_holm_primary_family <= 0.05);
        oosPass = height(o) == numel(cfg.outcomes) && ...
            all(o.oos_improvement_pct > 0 & o.bootstrap_p_one_sided <= 0.05);

        rotationRanges = nan(numel(cfg.outcomes), 1);
        topKPassByOutcome = false(numel(cfg.outcomes), 1);
        for j = 1:numel(cfg.outcomes)
            rr = r(r.outcome == cfg.outcomes(j), :);
            rotationRanges(j) = max(rr.oos_improvement_pct) - ...
                min(rr.oos_improvement_pct);
            kk = k(k.outcome == cfg.outcomes(j), :);
            topKPassByOutcome(j) = ~isempty(kk) && all(kk.oos_improvement_pct > 0);
        end
        rotationPass = all(rotationRanges <= cfg.rotationOosTolerance);
        topKPass = all(topKPassByOutcome);
        promote = inSamplePass && oosPass && rotationPass && topKPass;

        row = table();
        row.phase = phase;
        row.in_sample_pass = inSamplePass;
        row.oos_bootstrap_pass = oosPass;
        row.rotation_pass = rotationPass;
        row.leave_top_k_pass = topKPass;
        row.maximum_rotation_oos_range = max(rotationRanges);
        row.promote_pc2_secondary_refinement = promote;
        if promote
            row.recommendation = "promote_pc2_as_secondary_refinement";
        else
            row.recommendation = "retain_mp_cbi_primary_pc2_diagnostic";
        end
        rows{i} = row;
    end
    D = vertcat(rows{:});
end

function manifest = build_manifest(requiredFiles, cfg)
    here = fileparts(which('Component_sufficiency_analysis'));
    names = ["schema_version"; "created_utc"; "decision_phases"; ...
        "descriptive_phase"; "primary_candidate"; "diagnostic_candidates"; ...
        "outcomes"; "bootstrap_draws"; "seed"; ...
        "multiplicity_adjustment"; "oos_scheme"; "promotion_rule"; ...
        "input_files"; "input_sha256"; "code_commit"; "script_sha256"];
    hashes = strings(numel(requiredFiles), 1);
    for i = 1:numel(requiredFiles)
        hashes(i) = File_sha256(requiredFiles(i));
    end
    values = ["step23_v1"; ...
        string(datetime('now', 'TimeZone', 'UTC'), 'yyyy-MM-dd''T''HH:mm:ssXXX'); ...
        "PR|PC"; "ME"; "PC2 energy and state interaction"; ...
        "PC2-PC4 energy|target-path alternative"; ...
        strjoin(cfg.outcomes, "|"); string(cfg.bootstrapRep); string(cfg.seed); ...
        "Holm across PR/PC x BV/RV PC2 block tests"; ...
        "leave-one-event-out; paired event bootstrap of fixed cross-fitted losses"; ...
        "Holm + OOS bootstrap + rotation-invariance audit + leave-top-k must all pass"; ...
        strjoin(requiredFiles, "|"); strjoin(hashes, "|"); ...
        current_git_commit(here); ...
        File_sha256(fullfile(here, 'Component_sufficiency_analysis.m'))];
    manifest = table(names, values, 'VariableNames', {'name', 'value'});
end

function count = parse_draw_count(raw, fallback)
    count = str2double(string(raw));
    if strlength(string(raw)) == 0
        count = fallback;
    end
    if ~isfinite(count) || count < 19 || count ~= floor(count)
        error('COMPONENT_SUFFICIENCY_DRAWS must be an integer of at least 19.');
    end
end

function assert_columns(T, required, source)
    missing = required(~ismember(required, string(T.Properties.VariableNames)));
    if ~isempty(missing)
        error('STEP23_COLUMNS: %s is missing %s.', source, strjoin(missing, ', '));
    end
end

function x = to_logical(x)
    if islogical(x)
        return;
    end
    if isnumeric(x)
        x = x ~= 0;
        return;
    end
    s = lower(strtrim(string(x)));
    x = ismember(s, ["1", "true", "yes"]);
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
