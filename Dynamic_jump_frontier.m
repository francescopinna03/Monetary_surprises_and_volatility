function Dynamic_jump_frontier()
%DYNAMIC_JUMP_FRONTIER Step 27, module B: pre-estimation power frontier.
%
% This module is conditional on the final pass of Module A.  It never tests
% the observed conference jump.  It calibrates the smallest relative jump
% detectable at alternative-specific 5% size and 80% power under a frozen rank-one
% dynamic operator.  Shock and risk directions are re-estimated inside each
% meeting-block bootstrap draw using information not affected by the
% injected post-conference signal.

    projectRoot = Get_project_root();
    Require_time_alignment_manifest(projectRoot);
    Require_window_semantics_manifest(projectRoot);

    cfg = frozen_configuration();
    cfg.bootstrapRep = parse_draw_count(getenv('DYNAMIC_JUMP_FRONTIER_DRAWS'), 999);
    if cfg.bootstrapRep == 999
        outputDir = fullfile(projectRoot, 'Output', 'dynamic_jump_frontier');
    else
        outputDir = fullfile(projectRoot, 'Output', 'dynamic_jump_frontier_smoke');
    end
    if exist(outputDir, 'dir') ~= 7; mkdir(outputDir); end
    rng(cfg.seed, 'twister');

    files = required_files(projectRoot);
    validate_module_a_gate(files.step27aDecision, files.step27aManifest);
    validate_files(files);

    [scaleFx, scaleGg] = load_control_scales(files.rotationSummary);
    eventFeatures = load_event_features(files.components, files.prRows, files.pcRows);
    dynamic = build_dynamic_panel(files.phaseReturns, eventFeatures, ...
        scaleFx, scaleGg, cfg);
    aggregate = build_aggregate_package(files.prRows, files.pcRows, ...
        files.components, dynamic.events, cfg);

    observedShock = fit_aggregate_null(aggregate, cfg.coarseShockDegrees);
    [zPr, zPc] = projected_energies(observedShock.coefficient_direction, ...
        dynamic.events.pr_shock, dynamic.events.pc_shock);
    innovation = cross_year_innovation(zPr, zPc, dynamic.events, cfg);
    [observedPsi, observedPreFit] = estimate_pre_risk_direction( ...
        dynamic.rows, dynamic.y, zPr, cfg);
    [X0, alternatives, designInfo] = full_design(dynamic.rows, zPr, ...
        innovation, observedPsi, cfg);
    [Q0, designRank] = full_qr(X0);
    beta0 = X0 \ dynamic.y;
    fitted0 = X0 * beta0;
    residual0 = dynamic.y - fitted0;
    baselineNorm = observedPreFit.operator_rms_norm;
    if ~isfinite(baselineNorm) || baselineNorm <= cfg.minimumOperatorNorm
        error(['STEP27B_BASELINE_OPERATOR: the pre-PC rank-one operator norm ' ...
            'is numerically zero, so a relative jump frontier is undefined.']);
    end
    dynamic = attach_null_fit(dynamic, fitted0, residual0);

    observed = observed_null_row(dynamic, aggregate, observedShock, ...
        observedPsi, baselineNorm, designRank, scaleFx, scaleGg, cfg);
    designTable = design_table(cfg);

    nAlt = numel(cfg.alternatives);
    nRho = numel(cfg.rhoGrid);
    nSigns = numel(cfg.signs);
    nullStatistics = nan(cfg.bootstrapRep, nAlt);
    powerStatistics = nan(cfg.bootstrapRep, nAlt, nRho, nSigns);
    drawDiagnostics = cell(cfg.bootstrapRep, 1);

    for b = 1:cfg.bootstrapRep
        sample = randi(height(dynamic.events), height(dynamic.events), 1);
        wild = 2 * (rand(height(dynamic.events), 1) >= 0.5) - 1;
        try
            shockDraw = resampled_shock_mode(aggregate, dynamic.events, ...
                sample, wild, cfg);
            draw = resample_dynamic(dynamic, sample, wild);
            [zPrDraw, zPcDraw] = projected_energies( ...
                shockDraw.coefficient_direction, draw.events.pr_shock, ...
                draw.events.pc_shock);
            innovationDraw = cross_year_innovation(zPrDraw, zPcDraw, ...
                draw.events, cfg);
            psiDraw = estimate_pre_risk_direction(draw.rows, draw.y0, ...
                zPrDraw, cfg);
            [Xdraw, gDraw] = full_design(draw.rows, zPrDraw, ...
                innovationDraw, psiDraw, cfg);
            [Qdraw, rankDraw] = full_qr(Xdraw);
            gResidual = residualize_alternatives(gDraw, Qdraw);

            for a = 1:nAlt
                nullStatistics(b, a) = Step27b_partial_statistic( ...
                    draw.y0, Qdraw, gResidual(:, a));
            end

            [zPrTruth, ~] = projected_energies( ...
                observedShock.coefficient_direction, draw.events.pr_shock, ...
                draw.events.pc_shock);
            for a = 1:nAlt
                for r = 1:nRho
                    rho = cfg.rhoGrid(r);
                    for s = 1:nSigns
                        signal = injected_signal(draw.rows, zPrTruth, ...
                            observedPsi, baselineNorm, ...
                            cfg.alternatives(a), rho, cfg.signs(s), cfg);
                        yPower = draw.y0 + signal;
                        powerStatistics(b, a, r, s) = ...
                            Step27b_partial_statistic(yPower, Qdraw, ...
                            gResidual(:, a));
                    end
                end
            end

            D = table();
            D.draw = b;
            D.valid = true;
            D.sample_unique_events = numel(unique(sample));
            D.shock_angle_degrees = shockDraw.reference_angle_degrees;
            D.risk_angle_degrees = rad2deg(observed_projective_angle(psiDraw));
            D.design_rank = rankDraw;
            D.error_message = "";
            drawDiagnostics{b} = D;
        catch ME
            D = table();
            D.draw = b;
            D.valid = false;
            D.sample_unique_events = numel(unique(sample));
            D.shock_angle_degrees = NaN;
            D.risk_angle_degrees = NaN;
            D.design_rank = NaN;
            D.error_message = string(ME.identifier) + ": " + string(ME.message);
            drawDiagnostics{b} = D;
        end
    end
    diagnostics = vertcat(drawDiagnostics{:});
    validShare = mean(diagnostics.valid);
    if validShare < cfg.minimumValidDrawShare
        firstErrors = diagnostics.error_message(~diagnostics.valid);
        firstErrors = firstErrors(1:min(3, numel(firstErrors)));
        error('STEP27B_TOO_MANY_INVALID_DRAWS: valid share %.3f. %s', ...
            validShare, strjoin(firstErrors, ' | '));
    end

    [nullDraws, powerDraws, powerGrid, frontier] = summarize_frontier( ...
        nullStatistics, powerStatistics, diagnostics.valid, cfg);
    decision = build_decision(frontier, cfg);
    manifest = build_manifest(files, cfg, dynamic, aggregate, observed);

    writetable(designTable, fullfile(outputDir, 'step27b_frozen_design.csv'));
    writetable(observed, fullfile(outputDir, 'step27b_observed_null.csv'));
    writetable(nullDraws, fullfile(outputDir, 'step27b_null_bootstrap.csv'));
    writetable(powerDraws, fullfile(outputDir, 'step27b_power_draws.csv'));
    writetable(powerGrid, fullfile(outputDir, 'step27b_power_grid.csv'));
    writetable(frontier, fullfile(outputDir, 'step27b_frontier.csv'));
    writetable(decision, fullfile(outputDir, 'step27b_decision.csv'));
    writetable(diagnostics, fullfile(outputDir, 'step27b_draw_diagnostics.csv'));
    writetable(manifest, fullfile(outputDir, 'step27b_manifest.csv'));

    fprintf('\n================ STEP 27B JUMP FRONTIER ================\n');
    fprintf('Bootstrap draws       : %d\n', cfg.bootstrapRep);
    fprintf('Eligible events       : %d\n', height(dynamic.events));
    fprintf('Dynamic contributions : %d\n', height(dynamic.rows));
    fprintf('Valid draw share      : %.3f\n', validShare);
    fprintf('Observed shock sector : %s at %.2f degrees\n', ...
        observedShock.reference_sector, observedShock.reference_angle_degrees);
    fprintf('Pre-PC risk angle     : %.2f degrees\n', ...
        rad2deg(observed_projective_angle(observedPsi)));
    fprintf('Baseline operator norm: %.6g\n', baselineNorm);
    disp(frontier(:, {'alternative', 'frontier_rho', ...
        'frontier_rotation_degrees', 'frontier_status'}));
    disp(decision(:, {'test_id', 'status', 'recommendation'}));
    if cfg.bootstrapRep ~= 999
        fprintf('Inference status       : smoke only; no feasibility decision\n');
    end
    fprintf('Output directory       : %s\n', outputDir);
    fprintf('========================================================\n');
end

function cfg = frozen_configuration()
    cfg = struct();
    cfg.seed = 27030;
    cfg.alpha = 0.05;
    cfg.targetPower = 0.80;
    cfg.feasibleRho = 0.50;
    cfg.rhoGrid = [0.10, 0.20, 0.30, 0.40, 0.50, 0.75, 1.00];
    cfg.signs = [-1, 1];
    cfg.alternatives = ["INTENSITY", "REACTIVATION", "RISK_ROTATION"];
    cfg.preContributionTimes = [-20, -15, -10, -5];
    cfg.postContributionTimes = 10:5:45;
    cfg.allContributionTimes = [cfg.preContributionTimes, ...
        cfg.postContributionTimes];
    cfg.minimumPreContributions = 4;
    cfg.minimumPostContributions = 8;
    cfg.minimumEvents = 80;
    cfg.coarseShockDegrees = 5;
    cfg.coarseRiskDegrees = 5;
    cfg.minimumOperatorNorm = 1e-8;
    cfg.minimumValidDrawShare = 0.95;
end

function files = required_files(projectRoot)
    files = struct();
    files.phaseReturns = fullfile(projectRoot, 'Output', 'phase_windows', ...
        'phase_window_returns.csv');
    files.rotationSummary = fullfile(projectRoot, 'Output', 'analysis', ...
        'announcement_rotation_summary.csv');
    files.components = fullfile(projectRoot, 'Output', 'analysis', ...
        'shock_components_by_event.csv');
    files.prRows = fullfile(projectRoot, 'Output', 'phase_counterfactuals', ...
        'phase_counterfactual_pr_event_rows.csv');
    files.pcRows = fullfile(projectRoot, 'Output', 'phase_counterfactuals', ...
        'phase_counterfactual_pc_event_rows.csv');
    files.step27aDecision = fullfile(projectRoot, 'Output', ...
        'rank_one_feasibility', 'step27a_decision.csv');
    files.step27aManifest = fullfile(projectRoot, 'Output', ...
        'rank_one_feasibility', 'step27a_manifest.csv');
end

function validate_files(files)
    names = string(fieldnames(files));
    for j = 1:numel(names)
        path = string(files.(names(j)));
        if exist(path, 'file') ~= 2
            error('STEP27B_INPUT_MISSING: required input not found: %s', path);
        end
    end
end

function validate_module_a_gate(decisionFile, manifestFile)
    D = readtable(decisionFile, 'TextType', 'string', ...
        'Delimiter', ',', 'ReadVariableNames', true, ...
        'VariableNamingRule', 'preserve', 'ReadRowNames', false);
    M = readtable(manifestFile, 'TextType', 'string', ...
        'Delimiter', ',', 'ReadVariableNames', true, ...
        'VariableNamingRule', 'preserve', 'ReadRowNames', false);
    if ~all(ismember(["test_id", "status", "recommendation"], ...
            string(D.Properties.VariableNames)))
        error('STEP27B_GATE_SCHEMA: invalid Module-A decision schema.');
    end
    gate = D.test_id == "MODULE_A_RANK_GATE";
    next = D.test_id == "MODULE_B_JUMP_FRONTIER";
    if sum(gate) ~= 1 || D.status(gate) ~= "pass" || ...
            D.recommendation(gate) ~= "rank_one_is_admissible_not_established" || ...
            sum(next) ~= 1 || D.status(next) ~= "eligible_not_run"
        error('STEP27B_GATE_BLOCKED: final Module A does not authorize Module B.');
    end
    draws = manifest_value(M, "bootstrap_draws");
    schema = manifest_value(M, "schema_version");
    if schema ~= "step27a_v1" || str2double(draws) ~= 999
        error('STEP27B_GATE_MANIFEST: final 999-draw step27a_v1 is required.');
    end
end

function value = manifest_value(M, name)
    value = Step27b_manifest_value(M, name);
end

function [scaleFx, scaleGg] = load_control_scales(filePath)
    T = readtable(filePath, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    if ~all(ismember(["metric", "value"], string(T.Properties.VariableNames)))
        error('STEP27B_SCALE_SCHEMA: invalid Step-20 rotation summary.');
    end
    T.metric = string(T.metric);
    if ~isnumeric(T.value); T.value = str2double(string(T.value)); end
    scaleFx = unique(T.value(T.metric == "control_scale_fx"));
    scaleGg = unique(T.value(T.metric == "control_scale_gg"));
    if numel(scaleFx) ~= 1 || numel(scaleGg) ~= 1 || ...
            ~isfinite(scaleFx) || ~isfinite(scaleGg) || ...
            scaleFx <= 0 || scaleGg <= 0
        error('STEP27B_CONTROL_SCALES: unique positive FX/GG scales required.');
    end
end

function draws = parse_draw_count(textValue, defaultValue)
    draws = str2double(string(textValue));
    if ~isfinite(draws)
        draws = defaultValue;
    end
    draws = floor(draws);
    if draws < 19
        error('STEP27B_DRAWS: at least 19 bootstrap draws are required.');
    end
end

function E = load_event_features(componentFile, prFile, pcFile)
    C = readtable(componentFile, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    requiredC = ["event_date", "window", "policy_indicator_10bp", ...
        "STOXX50", "estimation_sample", "in_project_sample"];
    assert_columns(C, requiredC, componentFile);
    C.event_date = Parse_date_flexible(C.event_date);
    C.window = upper(string(C.window));
    numericC = ["policy_indicator_10bp", "STOXX50"];
    for v = numericC
        if ~isnumeric(C.(v)); C.(v) = str2double(string(C.(v))); end
    end
    C.estimation_sample = to_logical(C.estimation_sample);
    C.in_project_sample = to_logical(C.in_project_sample);
    C = C(C.estimation_sample & C.in_project_sample & ...
        ismember(C.window, ["PR", "PC"]), :);

    PR = unique_component_rows(C(C.window == "PR", :), "PR");
    PC = unique_component_rows(C(C.window == "PC", :), "PC");
    E = innerjoin(PR, PC, 'Keys', 'event_date');

    Rpr = load_phase_rows(prFile);
    Rpc = load_phase_rows(pcFile);
    stateCheck = Step27b_event_state(Rpr, Rpc);
    E = innerjoin(E, stateCheck, 'Keys', 'event_date');
    E.year = year(E.event_date);
    E.pr_shock = [double(E.policy_indicator_10bp_PR), double(E.STOXX50_PR)];
    E.pc_shock = [double(E.policy_indicator_10bp_PC), double(E.STOXX50_PC)];
    finite = all(isfinite(E.pr_shock), 2) & all(isfinite(E.pc_shock), 2) & ...
        isfinite(E.pre_state_z) & isfinite(E.regime_hike);
    E = sortrows(E(finite, :), 'event_date');
end

function T = unique_component_rows(T, suffix)
    T = T(:, {'event_date', 'policy_indicator_10bp', 'STOXX50'});
    [dates, ~, group] = unique(T.event_date, 'stable');
    if numel(dates) ~= height(T)
        counts = accumarray(group, 1);
        if any(counts ~= 1)
            error('STEP27B_COMPONENT_DUPLICATE: duplicate %s component dates.', suffix);
        end
    end
    namesT = T.Properties.VariableNames;
    T.Properties.VariableNames{strcmp(namesT, 'policy_indicator_10bp')} = ...
        char("policy_indicator_10bp_" + suffix);
    namesT = T.Properties.VariableNames;
    T.Properties.VariableNames{strcmp(namesT, 'STOXX50')} = ...
        char("STOXX50_" + suffix);
end

function T = load_phase_rows(filePath)
    T = readtable(filePath, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "root_code", "abnormal_log_BV", ...
        "pre_state_z", "regime_hike", "root_gg"];
    assert_columns(T, required, filePath);
    T.event_date = Parse_date_flexible(T.event_date);
    T.root_code = lower(string(T.root_code));
    numeric = ["abnormal_log_BV", "pre_state_z", "regime_hike", "root_gg"];
    for v = numeric
        if ~isnumeric(T.(v)) && ~islogical(T.(v))
            T.(v) = str2double(string(T.(v)));
        end
    end
end

function dynamic = build_dynamic_panel(returnFile, features, scaleFx, scaleGg, cfg)
    T = readtable(returnFile, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["event_date", "root_code", "phase", "segment", ...
        "relative_endpoint_minutes", "log_return", "exact_return_pair"];
    assert_columns(T, required, returnFile);
    T.event_date = Parse_date_flexible(T.event_date);
    T.root_code = lower(string(T.root_code));
    T.phase = upper(string(T.phase));
    T.segment = lower(string(T.segment));
    numeric = ["relative_endpoint_minutes", "log_return"];
    for v = numeric
        if ~isnumeric(T.(v)); T.(v) = str2double(string(T.(v))); end
    end
    T.exact_return_pair = to_logical(T.exact_return_pair);
    T = T(T.phase == "PC" & ismember(T.root_code, ["fx", "gg"]) & ...
        T.exact_return_pair & isfinite(T.log_return), :);
    T = T(ismember(T.event_date, features.event_date), :);

    rows = cell(height(features) * numel(cfg.allContributionTimes), 1);
    cursor = 0;
    keptEvents = false(height(features), 1);
    for e = 1:height(features)
        X = T(T.event_date == features.event_date(e), :);
        eventRows = cell(numel(cfg.allContributionTimes), 1);
        eventCursor = 0;
        for segment = ["pre", "post"]
            if segment == "pre"
                currentTimes = cfg.preContributionTimes;
            else
                currentTimes = cfg.postContributionTimes;
            end
            for time = currentTimes
                previousTime = time - 5;
                valuesPrevious = nan(1, 2);
                valuesCurrent = nan(1, 2);
                roots = ["fx", "gg"];
                for k = 1:2
                    previous = X.segment == segment & X.root_code == roots(k) & ...
                        X.relative_endpoint_minutes == previousTime;
                    current = X.segment == segment & X.root_code == roots(k) & ...
                        X.relative_endpoint_minutes == time;
                    if sum(previous) == 1 && sum(current) == 1
                        valuesPrevious(k) = X.log_return(previous);
                        valuesCurrent(k) = X.log_return(current);
                    end
                end
                if any(~isfinite(valuesPrevious)) || any(~isfinite(valuesCurrent))
                    continue;
                end
                valuesPrevious = valuesPrevious ./ [scaleFx, scaleGg];
                valuesCurrent = valuesCurrent ./ [scaleFx, scaleGg];
                Y = Step27b_bipower_matrix(valuesPrevious, valuesCurrent);
                R = table();
                R.event_date = features.event_date(e);
                R.event_index = e;
                R.year = features.year(e);
                R.pre_state_z = features.pre_state_z(e);
                R.pre_state_fx_z = features.pre_state_fx_z(e);
                R.pre_state_gg_z = features.pre_state_gg_z(e);
                R.regime_hike = features.regime_hike(e);
                R.segment = segment;
                R.minutes_from_pc = time;
                R.bipower_fx = Y(1);
                R.bipower_cross_sqrt2 = Y(2);
                R.bipower_gg = Y(3);
                eventCursor = eventCursor + 1;
                eventRows{eventCursor} = R;
            end
        end
        eventRows = eventRows(1:eventCursor);
        if isempty(eventRows); continue; end
        Erows = vertcat(eventRows{:});
        nPre = sum(Erows.segment == "pre");
        nPost = sum(Erows.segment == "post");
        if nPre < cfg.minimumPreContributions || nPost < cfg.minimumPostContributions
            continue;
        end
        keptEvents(e) = true;
        for j = 1:height(Erows)
            cursor = cursor + 1;
            rows{cursor} = Erows(j, :);
        end
    end
    if cursor == 0
        error('STEP27B_DYNAMIC_EMPTY: no complete paired bipower paths.');
    end
    R = vertcat(rows{1:cursor});
    events = features(keptEvents, :);
    if height(events) < cfg.minimumEvents
        error('STEP27B_DYNAMIC_EVENTS: only %d events; at least %d required.', ...
            height(events), cfg.minimumEvents);
    end
    oldIndices = find(keptEvents);
    newIndex = nan(height(features), 1);
    newIndex(oldIndices) = 1:numel(oldIndices);
    R.event_index = newIndex(R.event_index);
    R = sortrows(R, {'event_index', 'minutes_from_pc'});
    events.event_index = (1:height(events))';
    Y = R{:, {'bipower_fx', 'bipower_cross_sqrt2', 'bipower_gg'}};
    dynamic = struct();
    dynamic.rows = R;
    dynamic.events = events;
    dynamic.y = reshape(Y', [], 1);
end

function assert_columns(T, required, label)
    missing = required(~ismember(required, string(T.Properties.VariableNames)));
    if ~isempty(missing)
        error('STEP27B_COLUMNS: %s missing %s.', label, strjoin(missing, ', '));
    end
end

function value = to_logical(value)
    if islogical(value); return; end
    if isnumeric(value)
        value = value ~= 0;
        return;
    end
    textValue = lower(strtrim(string(value)));
    value = ismember(textValue, ["1", "true", "yes", "y"]);
end

function A = build_aggregate_package(prFile, pcFile, componentFile, events, cfg)
    C = readtable(componentFile, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    assert_columns(C, ["event_date", "window", "policy_indicator_10bp", ...
        "STOXX50", "estimation_sample", "in_project_sample"], componentFile);
    C.event_date = Parse_date_flexible(C.event_date);
    C.window = upper(string(C.window));
    if ~isnumeric(C.policy_indicator_10bp)
        C.policy_indicator_10bp = str2double(string(C.policy_indicator_10bp));
    end
    if ~isnumeric(C.STOXX50); C.STOXX50 = str2double(string(C.STOXX50)); end
    C.estimation_sample = to_logical(C.estimation_sample);
    C.in_project_sample = to_logical(C.in_project_sample);

    PR = prepare_aggregate_phase(load_phase_rows(prFile), C, "PR");
    PC = prepare_aggregate_phase(load_phase_rows(pcFile), C, "PC");
    PR = PR(ismember(PR.event_date, events.event_date), :);
    PC = PC(ismember(PC.event_date, events.event_date), :);
    predictors = ["q_policy", "q_equity", "q_policy_equity", ...
        "pre_state_z", "q_policy_x_pre", "q_equity_x_pre", ...
        "q_policy_equity_x_pre", "regime_hike", "root_gg"];
    prKey = string(PR.event_date, 'yyyy-MM-dd') + "|" + PR.root_code;
    pcKey = string(PC.event_date, 'yyyy-MM-dd') + "|" + PC.root_code;
    [keys, ia, ib] = intersect(prKey, pcKey, 'stable'); %#ok<ASGLU>
    PR = PR(ia, :);
    PC = PC(ib, :);
    if isempty(PR) || numel(unique(PR.event_date)) ~= height(events)
        error('STEP27B_AGGREGATE_MATCH: aggregate and dynamic events disagree.');
    end
    Xpr = aggregate_design(PR, predictors);
    Xpc = aggregate_design(PC, predictors);
    zero = zeros(size(Xpr));
    A = struct();
    A.X = [Xpr, zero; zero, Xpc];
    A.y = [double(PR.abnormal_log_BV); double(PC.abnormal_log_BV)];
    terms = ["Intercept", predictors];
    A.term_names = ["PR_" + terms, "PC_" + terms]';
    A.events = events;
    A.row_event_index = nan(numel(A.y), 1);
    for e = 1:height(events)
        prRows = PR.event_date == events.event_date(e);
        pcRows = PC.event_date == events.event_date(e);
        A.row_event_index(find(prRows)) = e;
        A.row_event_index(height(PR) + find(pcRows)) = e;
    end
    if any(~isfinite(A.y)) || any(~isfinite(A.X), 'all') || ...
            any(~isfinite(A.row_event_index))
        error('STEP27B_AGGREGATE_NONFINITE: aggregate package is incomplete.');
    end
    A.shock_covariance = cov([events.pr_shock; events.pc_shock], 0);
    A.null = Step27_rank_one_null_fit(A.y, A.X, A.term_names, ...
        A.shock_covariance, cfg.coarseShockDegrees);
end

function T = prepare_aggregate_phase(T, C, phase)
    keep = C.window == phase & C.estimation_sample & C.in_project_sample;
    S = C(keep, {'event_date', 'policy_indicator_10bp', 'STOXX50'});
    [~, first] = unique(S.event_date, 'stable');
    S = S(first, :);
    T = innerjoin(T, S, 'Keys', 'event_date');
    policy = double(T.policy_indicator_10bp);
    equity = double(T.STOXX50);
    state = double(T.pre_state_z);
    T.q_policy = policy .^ 2;
    T.q_equity = equity .^ 2;
    T.q_policy_equity = 2 .* policy .* equity;
    T.q_policy_x_pre = T.q_policy .* state;
    T.q_equity_x_pre = T.q_equity .* state;
    T.q_policy_equity_x_pre = T.q_policy_equity .* state;
    finite = all(isfinite(T{:, {'abnormal_log_BV', 'q_policy', 'q_equity', ...
        'q_policy_equity', 'pre_state_z', 'q_policy_x_pre', ...
        'q_equity_x_pre', 'q_policy_equity_x_pre', 'regime_hike', ...
        'root_gg'}}), 2);
    T = T(finite, :);
end

function X = aggregate_design(T, predictors)
    X = ones(height(T), 1);
    for v = predictors
        X = [X, double(T.(v))]; %#ok<AGROW>
    end
end

function fit = fit_aggregate_null(A, coarseDegrees)
    covariance = cov([A.events.pr_shock; A.events.pc_shock], 0);
    fit = Step27_rank_one_null_fit(A.y, A.X, A.term_names, ...
        covariance, coarseDegrees);
end

function fit = resampled_shock_mode(A, events, sample, wild, cfg)
    rowBlocks = cell(numel(sample), 1);
    yBlocks = cell(numel(sample), 1);
    for g = 1:numel(sample)
        rows = find(A.row_event_index == sample(g));
        rowBlocks{g} = rows;
        yBlocks{g} = A.null.fitted(rows) + A.null.residual(rows) .* wild(g);
    end
    rowIndex = vertcat(rowBlocks{:});
    yStar = vertcat(yBlocks{:});
    XStar = A.X(rowIndex, :);
    covariance = cov([events.pr_shock(sample, :); ...
        events.pc_shock(sample, :)], 0);
    fit = Step27_rank_one_null_fit(yStar, XStar, A.term_names, ...
        covariance, cfg.coarseShockDegrees);
end

function [zPr, zPc] = projected_energies(h, prShock, pcShock)
    h = double(h(:));
    if numel(h) ~= 3
        error('STEP27B_SHOCK_DIRECTION: quadratic direction must have three entries.');
    end
    rawPr = h(1) .* prShock(:, 1).^2 + h(2) .* prShock(:, 2).^2 + ...
        2 .* h(3) .* prShock(:, 1) .* prShock(:, 2);
    rawPc = h(1) .* pcShock(:, 1).^2 + h(2) .* pcShock(:, 2).^2 + ...
        2 .* h(3) .* pcShock(:, 1) .* pcShock(:, 2);
    zPr = standardize_energy(rawPr, "PR");
    zPc = standardize_energy(rawPc, "PC");
end

function z = standardize_energy(z, label)
    z = double(z(:));
    scale = std(z, 0);
    if any(~isfinite(z)) || ~isfinite(scale) || scale <= 1e-12
        error('STEP27B_ENERGY_SCALE: %s projected energy has no support.', label);
    end
    z = (z - mean(z)) ./ scale;
end

function innovation = cross_year_innovation(zPr, zPc, events, cfg) %#ok<INUSD>
    years = double(events.year(:));
    state = double(events.pre_state_z(:));
    hike = double(events.regime_hike(:));
    X = [ones(numel(zPr), 1), zPr(:), state, hike];
    innovation = nan(numel(zPr), 1);
    uniqueYears = unique(years);
    if numel(uniqueYears) < 5
        error('STEP27B_CROSSFIT_YEARS: at least five years are required.');
    end
    for y = transpose(uniqueYears)
        test = years == y;
        train = ~test;
        if sum(train) < 20 || rank(X(train, :)) < size(X, 2)
            error('STEP27B_CROSSFIT_SUPPORT: inadequate training support for year %d.', y);
        end
        beta = X(train, :) \ zPc(train);
        innovation(test) = zPc(test) - X(test, :) * beta;
    end
    scale = std(innovation, 0);
    if any(~isfinite(innovation)) || ~isfinite(scale) || scale <= 1e-12
        error('STEP27B_CROSSFIT_SCALE: PC innovation is degenerate.');
    end
    innovation = (innovation - mean(innovation)) ./ scale;
end

function [psi, fit] = estimate_pre_risk_direction(rows, y, zPr, cfg)
    contributionMask = rows.segment == "pre";
    vectorMask = repelem(contributionMask, 3);
    yPre = y(vectorMask);
    preRows = rows(contributionMask, :);
    objective = @(angle) pre_risk_sse(angle, preRows, yPre, zPr);
    step = deg2rad(cfg.coarseRiskDegrees);
    grid = 0:step:(pi - step / 2);
    loss = nan(numel(grid), 1);
    for j = 1:numel(grid)
        loss(j) = objective(grid(j));
    end
    [~, best] = min(loss);
    center = grid(best);
    wrapped = @(angle) objective(mod(angle, pi));
    psi = fminbnd(wrapped, center - step, center + step, ...
        optimset('TolX', 1e-9, 'Display', 'off'));
    psi = mod(psi, pi);
    [~, fit] = pre_risk_sse(psi, preRows, yPre, zPr);
end

function [sse, fit] = pre_risk_sse(psi, rows, y, zPr)
    [u, ~] = Step27b_risk_vectors(psi);
    times = unique(rows.minutes_from_pc, 'sorted')';
    [timeRisk, component, eventIndex] = background_design(rows, times);
    state = repelem(double(rows.pre_state_z), 3);
    hike = repelem(double(rows.regime_hike), 3);
    componentState = component_controls(component, state);
    componentHike = component_controls(component, hike);
    t = double(rows.minutes_from_pc(:)) ./ 45;
    B = [ones(height(rows), 1), t, t.^2];
    eventZ = zPr(rows.event_index);
    signal = repelem(eventZ .* B, 3, 1) .* u(component);
    signalState = signal .* state;
    X = [timeRisk, componentState, componentHike, signal, signalState];
    if rank(X) < size(X, 2)
        sse = Inf;
        fit = struct('operator_rms_norm', NaN);
        return;
    end
    beta = X \ y;
    residual = y - X * beta;
    sse = residual' * residual;
    firstSignal = size(timeRisk, 2) + size(componentState, 2) + ...
        size(componentHike, 2) + 1;
    signalBeta = beta(firstSignal:firstSignal + 2);
    amplitudes = B * signalBeta;
    fit = struct();
    fit.operator_rms_norm = sqrt(mean(amplitudes .^ 2));
    fit.signal_coefficients = signalBeta;
end

function [X, alternatives, info] = full_design(rows, zPr, innovation, psi, cfg)
    [u, tangent] = Step27b_risk_vectors(psi);
    [timeRisk, component, eventIndex] = background_design(rows, ...
        cfg.allContributionTimes);
    state = repelem(double(rows.pre_state_z), 3);
    hike = repelem(double(rows.regime_hike), 3);
    stateControls = component_controls(component, state);
    hikeControls = component_controls(component, hike);
    [B, intensity, reactivation] = ...
        Step27b_temporal_basis(rows.minutes_from_pc);
    zRows = zPr(rows.event_index);
    prBase = repelem(zRows .* B, 3, 1) .* u(component);
    prState = prBase .* state;

    innovationRows = innovation(rows.event_index);
    pcPermanent = component_profile(component, ...
        repelem(innovationRows .* intensity, 3));
    pcTransient = component_profile(component, ...
        repelem(innovationRows .* reactivation, 3));
    X = [timeRisk, stateControls, hikeControls, prBase, prState, ...
        pcPermanent, pcTransient];

    intensityVector = repelem(zRows .* intensity, 3) .* u(component);
    reactivationVector = repelem(zRows .* reactivation, 3) .* u(component);
    rotationVector = repelem(zRows .* intensity, 3) .* tangent(component);
    alternatives = [intensityVector, reactivationVector, rotationVector];
    info = struct();
    firstPr = size(timeRisk, 2) + size(stateControls, 2) + ...
        size(hikeControls, 2) + 1;
    info.pr_level_columns = firstPr:(firstPr + size(B, 2) - 1);
    info.event_index_vector = eventIndex;
end

function [timeRisk, component, eventIndex] = background_design(rows, times)
    n = height(rows);
    component = repmat((1:3)', n, 1);
    eventIndex = repelem(rows.event_index, 3);
    timeVector = repelem(double(rows.minutes_from_pc), 3);
    timeRisk = zeros(3 * n, 3 * numel(times));
    cursor = 0;
    for t = times
        for k = 1:3
            cursor = cursor + 1;
            timeRisk(:, cursor) = double(timeVector == t & component == k);
        end
    end
    if any(sum(timeRisk, 1) == 0) || any(sum(timeRisk, 2) ~= 1)
        error('STEP27B_TIME_SUPPORT: the frozen event-time grid is incomplete.');
    end
end

function X = component_controls(component, value)
    X = zeros(numel(component), 3);
    for k = 1:3
        X(:, k) = double(component == k) .* value;
    end
end

function X = component_profile(component, value)
    X = zeros(numel(component), 3);
    for k = 1:3
        X(:, k) = double(component == k) .* value;
    end
end

function [Q, designRank] = full_qr(X)
    if any(~isfinite(X), 'all')
        error('STEP27B_DESIGN_NONFINITE: design matrix must be finite.');
    end
    designRank = rank(X);
    if designRank < size(X, 2)
        error('STEP27B_DESIGN_RANK: rank %d below %d columns.', ...
            designRank, size(X, 2));
    end
    [Q, ~] = qr(X, 0);
end

function residualized = residualize_alternatives(alternatives, Q)
    residualized = alternatives - Q * (Q' * alternatives);
    norms = sqrt(sum(residualized .^ 2, 1));
    if any(~isfinite(norms)) || any(norms <= 1e-8)
        error('STEP27B_ALTERNATIVE_SUPPORT: a jump profile is unidentified.');
    end
end

function dynamic = attach_null_fit(dynamic, fitted, residual)
    fittedMatrix = reshape(fitted, 3, [])';
    residualMatrix = reshape(residual, 3, [])';
    for k = 1:3
        dynamic.rows.("null_fitted_" + k) = fittedMatrix(:, k);
        dynamic.rows.("null_residual_" + k) = residualMatrix(:, k);
    end
end

function draw = resample_dynamic(dynamic, sample, wild)
    rowCells = cell(numel(sample), 1);
    eventCells = cell(numel(sample), 1);
    for g = 1:numel(sample)
        R = dynamic.rows(dynamic.rows.event_index == sample(g), :);
        R.event_index(:) = g;
        E = dynamic.events(sample(g), :);
        E.event_index = g;
        rowCells{g} = R;
        eventCells{g} = E;
    end
    draw.rows = vertcat(rowCells{:});
    draw.events = vertcat(eventCells{:});
    fitted = draw.rows{:, {'null_fitted_1', 'null_fitted_2', ...
        'null_fitted_3'}};
    residual = draw.rows{:, {'null_residual_1', 'null_residual_2', ...
        'null_residual_3'}};
    weights = wild(draw.rows.event_index);
    yMatrix = fitted + residual .* weights;
    draw.y0 = reshape(yMatrix', [], 1);
end

function signal = injected_signal(rows, zPr, psi, baselineNorm, ...
        alternative, rho, directionSign, cfg) %#ok<INUSD>
    [u, ~] = Step27b_risk_vectors(psi);
    n = height(rows);
    component = repmat((1:3)', n, 1);
    [~, intensity, reactivation] = ...
        Step27b_temporal_basis(rows.minutes_from_pc);
    zRows = zPr(rows.event_index);
    if alternative == "INTENSITY"
        profile = repelem(zRows .* intensity, 3);
        signal = directionSign .* rho .* baselineNorm .* profile .* u(component);
    elseif alternative == "REACTIVATION"
        profile = repelem(zRows .* reactivation, 3);
        signal = directionSign .* rho .* baselineNorm .* profile .* u(component);
    elseif alternative == "RISK_ROTATION"
        angle = asin(min(rho ./ sqrt(2), 1));
        [rotated, ~] = Step27b_risk_vectors(psi + directionSign .* angle);
        delta = rotated - u;
        profile = repelem(zRows .* intensity, 3);
        signal = baselineNorm .* profile .* delta(component);
    else
        error('STEP27B_ALTERNATIVE: unknown alternative %s.', alternative);
    end
end

function angle = observed_projective_angle(psi)
    angle = mod(psi, pi);
    if angle > pi / 2
        angle = angle - pi;
    end
end

function [nullDraws, powerDraws, powerGrid, frontier] = summarize_frontier( ...
        nullStatistics, powerStatistics, validDraw, cfg)
    nAlt = numel(cfg.alternatives);
    nRho = numel(cfg.rhoGrid);
    nSigns = numel(cfg.signs);
    validDraw = logical(validDraw(:));
    critical = nan(nAlt, 1);
    nullCells = cell(nAlt, 1);
    for a = 1:nAlt
        values = nullStatistics(validDraw, a);
        values = values(isfinite(values));
        critical(a) = quantile(values, 1 - cfg.alpha);
        N = table();
        N.draw = find(validDraw);
        N.alternative = repmat(cfg.alternatives(a), sum(validDraw), 1);
        N.statistic = nullStatistics(validDraw, a);
        N.critical_q95 = repmat(critical(a), sum(validDraw), 1);
        nullCells{a} = N;
    end
    nullDraws = vertcat(nullCells{:});

    drawCells = cell(nAlt * nRho * nSigns, 1);
    gridCells = cell(nAlt * nRho * nSigns, 1);
    cursor = 0;
    for a = 1:nAlt
        for r = 1:nRho
            for s = 1:nSigns
                cursor = cursor + 1;
                values = squeeze(powerStatistics(:, a, r, s));
                usable = validDraw & isfinite(values);
                rejected = values(usable) > critical(a);
                P = table();
                P.draw = find(usable);
                P.alternative = repmat(cfg.alternatives(a), sum(usable), 1);
                P.rho = repmat(cfg.rhoGrid(r), sum(usable), 1);
                P.direction_sign = repmat(cfg.signs(s), sum(usable), 1);
                P.statistic = values(usable);
                P.critical_q95 = repmat(critical(a), sum(usable), 1);
                P.reject = rejected;
                drawCells{cursor} = P;

                G = table();
                G.alternative = cfg.alternatives(a);
                G.rho = cfg.rhoGrid(r);
                G.direction_sign = cfg.signs(s);
                G.valid_draws = sum(usable);
                G.rejections = sum(rejected);
                G.power_raw = mean(rejected);
                G.critical_q95 = critical(a);
                gridCells{cursor} = G;
            end
        end
    end
    powerDraws = vertcat(drawCells{:});
    signedGrid = vertcat(gridCells{:});

    combinedCells = cell(nAlt * nRho, 1);
    cursor = 0;
    for a = 1:nAlt
        rawWorst = nan(nRho, 1);
        for r = 1:nRho
            X = signedGrid(signedGrid.alternative == cfg.alternatives(a) & ...
                signedGrid.rho == cfg.rhoGrid(r), :);
            if height(X) ~= 2
                error('STEP27B_POWER_SIGNS: two directions required per grid point.');
            end
            rawWorst(r) = min(X.power_raw);
        end
        monotone = isotonic_non_decreasing(rawWorst);
        for r = 1:nRho
            cursor = cursor + 1;
            X = signedGrid(signedGrid.alternative == cfg.alternatives(a) & ...
                signedGrid.rho == cfg.rhoGrid(r), :);
            G = table();
            G.alternative = cfg.alternatives(a);
            G.rho = cfg.rhoGrid(r);
            G.power_negative = X.power_raw(X.direction_sign == -1);
            G.power_positive = X.power_raw(X.direction_sign == 1);
            G.power_worst_raw = rawWorst(r);
            G.power_worst_isotonic = monotone(r);
            G.valid_draws_min = min(X.valid_draws);
            G.critical_q95 = unique(X.critical_q95);
            combinedCells{cursor} = G;
        end
    end
    powerGrid = vertcat(combinedCells{:});

    frontierCells = cell(nAlt, 1);
    for a = 1:nAlt
        X = powerGrid(powerGrid.alternative == cfg.alternatives(a), :);
        X = sortrows(X, 'rho');
        rho = interpolate_frontier([0; X.rho], ...
            [cfg.alpha; X.power_worst_isotonic], cfg.targetPower);
        F = table();
        F.alternative = cfg.alternatives(a);
        F.frontier_rho = rho;
        if cfg.alternatives(a) == "RISK_ROTATION" && isfinite(rho)
            F.frontier_rotation_degrees = rad2deg(asin(min(rho / sqrt(2), 1)));
        else
            F.frontier_rotation_degrees = NaN;
        end
        F.alpha = cfg.alpha;
        F.target_power = cfg.targetPower;
        F.feasibility_threshold_rho = cfg.feasibleRho;
        if cfg.bootstrapRep ~= 999
            F.frontier_status = "not_evaluated_smoke_only";
        elseif ~isfinite(rho)
            F.frontier_status = "above_frozen_grid";
        elseif rho <= cfg.feasibleRho
            F.frontier_status = "feasible";
        else
            F.frontier_status = "underpowered_for_moderate_jump";
        end
        frontierCells{a} = F;
    end
    frontier = vertcat(frontierCells{:});
end

function fitted = isotonic_non_decreasing(values)
    values = double(values(:));
    n = numel(values);
    level = values;
    weight = ones(n, 1);
    start = (1:n)';
    stop = (1:n)';
    blocks = n;
    j = 1;
    while j < blocks
        if level(j) <= level(j + 1)
            j = j + 1;
        else
            newWeight = weight(j) + weight(j + 1);
            level(j) = (weight(j) * level(j) + ...
                weight(j + 1) * level(j + 1)) / newWeight;
            weight(j) = newWeight;
            stop(j) = stop(j + 1);
            level(j + 1:blocks - 1) = level(j + 2:blocks);
            weight(j + 1:blocks - 1) = weight(j + 2:blocks);
            start(j + 1:blocks - 1) = start(j + 2:blocks);
            stop(j + 1:blocks - 1) = stop(j + 2:blocks);
            blocks = blocks - 1;
            if j > 1; j = j - 1; end
        end
    end
    fitted = nan(n, 1);
    for j = 1:blocks
        fitted(start(j):stop(j)) = level(j);
    end
end

function rho = interpolate_frontier(grid, power, target)
    first = find(power >= target, 1, 'first');
    if isempty(first)
        rho = NaN;
    elseif first == 1
        rho = grid(1);
    else
        lo = first - 1;
        if power(first) <= power(lo) + eps
            rho = grid(first);
        else
            fraction = (target - power(lo)) / (power(first) - power(lo));
            rho = grid(lo) + fraction * (grid(first) - grid(lo));
        end
    end
end

function decision = build_decision(frontier, cfg)
    rows = cell(5, 1);
    rows{1} = decision_row("MODULE_A_CONDITION", "pass", ...
        "final_rank_one_admissibility_gate_inherited", true, cfg.alpha);
    for a = 1:numel(cfg.alternatives)
        F = frontier(frontier.alternative == cfg.alternatives(a), :);
        if cfg.bootstrapRep ~= 999
            status = "not_evaluated_smoke_only";
            recommendation = "run_final_999_draw_frontier";
            claim = false;
        elseif F.frontier_status == "feasible"
            status = "pass";
            recommendation = lower(cfg.alternatives(a)) + ...
                "_jump_is_detectable_at_moderate_relative_size";
            claim = true;
        else
            status = "fail";
            recommendation = lower(cfg.alternatives(a)) + ...
                "_jump_is_underpowered_at_moderate_relative_size";
            claim = true;
        end
        rows{1 + a} = decision_row("FRONTIER_" + cfg.alternatives(a), ...
            status, recommendation, claim, cfg.alpha);
    end
    feasible = any(frontier.frontier_status == "feasible");
    if cfg.bootstrapRep ~= 999
        rows{5} = decision_row("MODULE_C_OPERATOR_ESTIMATION", ...
            "not_evaluated_smoke_only", "final_module_b_required", false, cfg.alpha);
    elseif feasible
        rows{5} = decision_row("MODULE_C_OPERATOR_ESTIMATION", ...
            "eligible_not_run", "freeze_estimator_only_for_feasible_alternatives", ...
            false, cfg.alpha);
    else
        rows{5} = decision_row("MODULE_C_OPERATOR_ESTIMATION", "blocked", ...
            "dynamic_extension_stops_for_lack_of_power", true, cfg.alpha);
    end
    decision = vertcat(rows{:});
end

function row = decision_row(testId, status, recommendation, robustClaim, alpha)
    row = table();
    row.test_id = string(testId);
    row.status = string(status);
    row.recommendation = string(recommendation);
    row.robust_claim = logical(robustClaim);
    row.alpha = alpha;
end

function T = observed_null_row(dynamic, aggregate, shockFit, psi, ...
        baselineNorm, designRank, scaleFx, scaleGg, cfg)
    [u, ~] = Step27b_risk_vectors(psi);
    T = table();
    T.n_events = height(dynamic.events);
    T.n_dynamic_contributions = height(dynamic.rows);
    T.n_vector_observations = numel(dynamic.y);
    T.n_aggregate_observations = numel(aggregate.y);
    T.control_scale_fx = scaleFx;
    T.control_scale_gg = scaleGg;
    T.shock_policy_direction = shockFit.reference_direction(1);
    T.shock_equity_direction = shockFit.reference_direction(2);
    T.shock_angle_degrees = shockFit.reference_angle_degrees;
    T.shock_sector = shockFit.reference_sector;
    T.risk_fx_loading = cos(psi);
    T.risk_gg_loading = sin(psi);
    T.risk_projective_angle_degrees = rad2deg(observed_projective_angle(psi));
    T.risk_mode_bipower_fx = u(1);
    T.risk_mode_bipower_cross_sqrt2 = u(2);
    T.risk_mode_bipower_gg = u(3);
    T.pre_pc_operator_rms_norm = baselineNorm;
    T.null_design_rank = designRank;
    T.null_continuous_at_pc = true;
    T.observed_jump_estimated = false;
    T.bootstrap_draws_planned = cfg.bootstrapRep;
end

function T = design_table(cfg)
    ids = ["PRIMARY_DYNAMIC_OUTCOME"; "PRE_STATE"; "SHOCK_MODE"; "PC_INNOVATION"; ...
        "NULL_TIME_LAW"; "INTENSITY_ALTERNATIVE"; ...
        "REACTIVATION_ALTERNATIVE"; "ROTATION_ALTERNATIVE"; ...
        "INFERENCE"; "POWER_TARGET"; "FEASIBILITY_THRESHOLD"; ...
        "LOOKAHEAD_RULE"];
    values = [ ...
        "polarized_multivariate_bipower_contribution"; ...
        "equal_weight_mean_of_fx_and_gg_pr_pre_root_specific_z_scores"; ...
        "step27a_common_direction_reestimated_per_draw"; ...
        "leave_year_out_residual_of_pc_energy_on_pr_energy_state_and_regime"; ...
        "piecewise_quadratic_with_level_continuity_at_pc"; ...
        "permanent_post_pc_step_in_common_mode"; ...
        "post_pc_pulse_with_15_minute_decay"; ...
        "post_pc_tangent_rotation_of_cross_market_risk_mode"; ...
        "meeting_pairs_plus_common_event_wild_sign_and_empirical_critical_value"; ...
        string(cfg.targetPower); string(cfg.feasibleRho); ...
        "module_b_never_computes_observed_jump_statistic"];
    T = table(ids, values, 'VariableNames', {'design_id', 'frozen_value'});
end

function M = build_manifest(files, cfg, dynamic, aggregate, observed)
    names = string(fieldnames(files));
    paths = strings(numel(names), 1);
    hashes = strings(numel(names), 1);
    for j = 1:numel(names)
        paths(j) = string(files.(names(j)));
        hashes(j) = File_sha256(paths(j));
    end
    M = table();
    M.name = ["schema_version"; "created_utc"; "module"; ...
        "module_a_condition"; "observed_jump_estimated"; ...
        "primary_dynamic_outcome"; "pre_state_definition"; ...
        "pre_state_phase_validation"; "event_time_contributions_minutes"; ...
        "n_events"; "n_dynamic_contributions"; "n_aggregate_observations"; ...
        "bootstrap_draws"; "seed"; "alpha"; "target_power"; ...
        "feasibility_threshold_rho"; "rho_grid"; "alternative_signs"; ...
        "alternatives"; "null_time_basis"; "reactivation_decay_minutes"; ...
        "shock_direction_rule"; "risk_direction_rule"; ...
        "pc_innovation_rule"; "bootstrap_design"; "input_files"; ...
        "input_sha256"];
    M.value = ["step27b_v2"; ...
        string(datetime('now', 'TimeZone', 'UTC'), 'yyyy-MM-dd''T''HH:mm:ss''Z'''); ...
        "B_pre_estimation_power_frontier_only"; ...
        "final_step27a_gate_pass"; "false"; ...
        "polarized_multivariate_bipower_frobenius_coordinates"; ...
        "equal_weight_mean_of_fx_and_gg_pr_pre_root_specific_z_scores"; ...
        "pr_pc_identity_validated_separately_within_fx_and_gg"; ...
        strjoin(string(cfg.allContributionTimes), '|'); ...
        string(height(dynamic.events)); string(height(dynamic.rows)); ...
        string(numel(aggregate.y)); string(cfg.bootstrapRep); string(cfg.seed); ...
        string(cfg.alpha); string(cfg.targetPower); string(cfg.feasibleRho); ...
        strjoin(string(cfg.rhoGrid), '|'); strjoin(string(cfg.signs), '|'); ...
        strjoin(cfg.alternatives, '|'); ...
        "1|t|t2|t_positive|t_positive2_continuous_at_zero"; "15"; ...
        "rank_one_mode_reestimated_from_null_aggregate_fit_per_draw"; ...
        "pre_pc_only_rank_one_risk_mode_reestimated_per_draw"; ...
        "leave_year_out_cross_fitted_and_unrestricted_across_risk_coordinates"; ...
        "event_pairs_resampling_plus_common_event_rademacher_residual_sign"; ...
        strjoin(paths, '|'); strjoin(hashes, '|')];
    if observed.observed_jump_estimated
        error('STEP27B_LOOKAHEAD: manifest cannot certify an observed jump estimate.');
    end
end
