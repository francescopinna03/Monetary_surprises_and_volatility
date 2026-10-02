function decision = Run_step28_sbb()

    projectRoot = Get_project_root();
    outputDir = fullfile(projectRoot, 'Output', 'step28_sbbts');
    if exist(outputDir, 'dir') ~= 7
        mkdir(outputDir);
    end

    supersede_outputs(outputDir, ["step28_sbb_decision.csv",         "step28_sbb_gate_check.csv", "step28_sbb_costs.csv",         "step28_sbb_abnormal_costs.csv",         "step28_sbb_contrast_profile.csv", "step28_sbb_bands.csv",         "step28_sbb_verdict.csv", "step28_sbb_stability.csv", "step28_sbb_admissible_conclusion.csv"]);

    fprintf('\n[28 SBB preflight] Estimation layer self-test\n');
    Step28_sbb_self_test();

    specificationPath = string(getenv('STEP28_SBB_SPECIFICATION'));
    if strlength(strtrim(specificationPath)) == 0
        specificationPath = fullfile(projectRoot, 'Raw', 'Certification', 'step28_sbb_specification.csv');
    end
    specification = Step28_sbb_specification(specificationPath);

    verify_upstream(projectRoot);

    fprintf('\n[28 SBB] Sequential gate check\n');
    [authorised, gates, acceptedRank] = Step28_sbb_authorisation(projectRoot, specification);
    writetable(gates, fullfile(outputDir, 'step28_sbb_gate_check.csv'));
    fprintf('Gates passed: %d/%d\n', sum(gates.pass), height(gates));
    for g = 1:height(gates)
        fprintf('  %-26s %s\n', gates.gate_id(g), gates.observed(g));
    end

    if ~authorised
        blocked = gates.gate_id(~gates.pass);
        decision = write_decision(outputDir, "blocked_before_sbb", false,             strjoin(blocked, '|'),             "run the blocked gates; an SBB profile may not be produced first", "", "", NaN, Step28_provenance(projectRoot, specification));
        fprintf(['\nEmpirical SBB estimation is blocked. Outstanding gates: ' '%s\n'], strjoin(blocked, ', '));
        return;
    end

    specification.factor_rank = acceptedRank;

    fprintf('\nFrozen specification: %s\n', specification.specification_path);
    fprintf('Rank %d, %d kappa values, K_rob of %d, %d draws, seed %d\n',         specification.factor_rank, numel(specification.kappa_grid),         numel(specification.kappa_robust_grid), specification.bootstrap_draws, specification.bootstrap_seed);

    fprintf('\n[28 SBB] Assembling the synchronised transition panel\n');
    panel = Step28_sbb_panel(projectRoot, specification);
    fprintf('Event dates %d, control dates %d, synchronised rows %d\n', panel.n_event_dates, panel.n_control_dates, size(panel.returns, 1));
    if panel.n_excluded_event_dates > 0
        fprintf('Events excluded for a non-finite frozen conditioning block: %d (%s)\n',             panel.n_excluded_event_dates, strjoin(panel.excluded_event_dates, ', '));
    end

    meetings = unique(panel.date_key(panel.role == "event"));
    [pointContrast, artefacts] = Step28_sbb_estimate(panel, specification, meetings, "none");
    writetable(artefacts.costs, fullfile(outputDir, 'step28_sbb_costs.csv'));
    writetable(artefacts.abnormal, fullfile(outputDir, 'step28_sbb_abnormal_costs.csv'));
    writetable(pointContrast, fullfile(outputDir, 'step28_sbb_contrast_profile.csv'));

    fprintf('\n[28 SBB] Meeting bootstrap with full upstream re-estimation\n');
    options = struct(         'draws', specification.bootstrap_draws,         'alpha', specification.alpha,         'seed', specification.bootstrap_seed,         'robustnessGrid', specification.kappa_robust_grid,         'leaveTopK', specification.leave_top_k,         'perturbations', specification.boundary_bar_perturbations,         'foldOfMeeting', fold_of(panel, meetings), 'rankOfMeeting', shock_energy_of(panel, meetings, specification));

    estimator = @(context) Step28_sbb_estimate(panel, specification, context.meetings, context.perturbation);
    inference = SBB_profile_inference(estimator, meetings, specification.kappa_grid, options);

    writetable(inference.bands, fullfile(outputDir, 'step28_sbb_bands.csv'));
    writetable(inference.verdict, fullfile(outputDir, 'step28_sbb_verdict.csv'));
    writetable(inference.stability, fullfile(outputDir, 'step28_sbb_stability.csv'));
    writetable(inference.admissible_conclusion, fullfile(outputDir, 'step28_sbb_admissible_conclusion.csv'));

    fprintf('\n================ STEP 28 SBB PROFILE ================\n');
    disp(inference.verdict);
    fprintf('A conclusion is admissible only where the simultaneous band\n');
    fprintf('excludes zero uniformly on K_rob and every frozen stability\n');
    fprintf('exercise preserves the sign.\n');
    disp(inference.admissible_conclusion);
    fprintf('Output directory: %s\n', outputDir);
    fprintf('=====================================================\n');

    decision = write_decision(outputDir, "sbb_profile_estimated", true, "",         "read the profile on K_rob; a single kappa is illustrative only",         specification.specification_sha256,         strjoin(string(inference.admissible_conclusion.component(         inference.admissible_conclusion.admissible)), '|'),         specification.factor_rank, Step28_provenance(projectRoot, specification));
end

function verify_upstream(projectRoot)
    [dataDecision, audit] = Step28_data_gate(projectRoot);
    if dataDecision.status(1) ~= "pass_data_gate" ||             ~String_to_boolean(dataDecision.ready_for_sample_size_gate(1)) || any(audit.binding & ~audit.pass)
        error(['STEP28_SBB_DATA_GATE_BLOCKED: current Barchart files fail the ' 'data-gate revalidation.']);
    end
    source = Surprise_source_config(projectRoot);
    Require_time_alignment_manifest(projectRoot);
    Require_surprise_source_manifest(projectRoot, source);
end

function supersede_outputs(outputDir, names)
    stamp = string(datetime('now', 'TimeZone', 'UTC'), 'yyyyMMdd''T''HHmmssSSS');
    for i = 1:numel(names)
        path = fullfile(outputDir, names(i));
        if isfile(path)
            movefile(path, char(path + ".superseded-" + stamp));
        end
    end
end

function folds = fold_of(panel, meetings)
    folds = strings(numel(meetings), 1);
    for i = 1:numel(meetings)
        match = find(panel.date_key == meetings(i), 1);
        folds(i) = panel.fold_key(match);
    end
end

function energy = shock_energy_of(panel, meetings, specification)
    columns = specification.surprise_columns;
    energy = zeros(numel(meetings), 1);
    keys = string(panel.surprise.date_key);
    for i = 1:numel(meetings)
        match = find(keys == meetings(i), 1);
        if isempty(match)
            error('STEP28_SBB_ENERGY: no surprise row for %s.', meetings(i));
        end
        values = zeros(1, numel(columns));
        for c = 1:numel(columns)
            values(c) = double(panel.surprise.(char(columns(c)))(match));
        end
        energy(i) = norm(values);
    end
end

function decision = write_decision(outputDir, status, authorised,         failedGates, nextAction, specificationHash, admissibleComponents, selectedFactorRank, provenance)
    decision = table("step28_sbb_stage_v2", string(status),         logical(authorised), string(failedGates), string(nextAction),         string(specificationHash), string(admissibleComponents),         double(selectedFactorRank),         string(datetime('now', 'TimeZone', 'UTC'),         'yyyy-MM-dd''T''HH:mm:ssXXX'),         'VariableNames', {'schema_version', 'status',         'empirical_sbb_produced', 'failed_gates', 'next_action',         'specification_sha256', 'admissible_components', 'selected_factor_rank', 'generated_at_utc'});
    if nargin >= 9 && ~isempty(provenance)
        decision = Step28_stamp_decision(decision, provenance);
    end
    writetable(decision, fullfile(outputDir, 'step28_sbb_decision.csv'));
end
