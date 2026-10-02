function Step28_sbb_self_test()

    test_whitening();
    test_subspace_geometry();
    test_conditional_law();
    test_multistep_cost();
    test_abnormal_cost();
    test_profile_inference();
    test_frozen_specification();
    test_authorisation();
    test_end_to_end_estimate();

    fprintf('Step28_sbb_self_test passed.\n');
end

function test_frozen_specification()
    here = fileparts(which('Step28_sbb_self_test'));
    path = fullfile(here, 'config', 'step28_sbb_specification_frozen.csv');
    specification = Step28_sbb_specification(path);
    assert(specification.schema_version == "step28_sbb_specification_v3");
    assert(specification.factor_rank_rule == "selected_by_spectral_gate");
    assert(~isfield(specification, 'factor_rank'), 'The ex-ante specification must not preselect the empirical rank.');
    assert(isequal(specification.calibration_true_rank, [1, 2]));
    assert(all(ismember(specification.kappa_robust_grid, specification.kappa_grid)));
end

function test_whitening()
    stream = RandStream('mt19937ar', 'Seed', 20260731);
    years = ["2019", "2020", "2021", "2022", "2023"];
    perYear = 80;
    positions = 1:4;

    trueMean = [0.10, -0.20, 0.05; 0.00, 0.30, -0.10; -0.05, 0.10, 0.20; 0.15, 0.00, -0.25];
    base = [1.00, 0.60, 0.30; 0.60, 1.00, 0.45; 0.30, 0.45, 1.00];

    rows = numel(years) * perYear * numel(positions);
    returns = zeros(rows, 3);
    dateKey = strings(rows, 1);
    position = zeros(rows, 1);
    foldKey = strings(rows, 1);
    isControl = true(rows, 1);
    r = 0;
    for y = 1:numel(years)
        for d = 1:perYear
            key = years(y) + "_" + string(d);
            for k = positions
                r = r + 1;
                scale = 1 + 0.25 * k;
                L = chol(scale * base, 'lower');
                returns(r, :) = trueMean(k, :) + (L * randn(stream, 3, 1))';
                dateKey(r) = key;
                position(r) = k;
                foldKey(r) = years(y);
            end
        end
    end

    [panel, moments] = Step28_whiten_increments(returns, dateKey, position, foldKey, isControl, 30);

    assert(height(panel) == rows);
    assert(height(moments) == numel(years) * numel(positions));
    assert(all(moments.n_control_dates == (numel(years) - 1) * perYear), 'Leave-year-out must drop exactly the held-out year.');

    increments = panel.increment;
    assert(max(abs(mean(increments, 1))) < 0.05, 'Whitened mean is not zero.');
    empirical = cov(increments);
    assert(max(abs(empirical(:) - reshape(eye(3), [], 1))) < 0.10, 'Whitened covariance is not the identity.');

    firstKey = panel.date_key(1);
    rowsOfDate = panel.date_key == firstKey;
    assert(max(abs(panel.level(rowsOfDate, :) - cumsum(panel.increment(rowsOfDate, :), 1)), [], 'all') < 1e-12);

    assert_error(@() Step28_whiten_increments(returns, dateKey, position, foldKey, isControl, 10000), "STEP28_WHITEN_SUPPORT");
    assert_error(@() Step28_whiten_increments(returns, dateKey, position, foldKey, false(rows, 1), 30), "STEP28_WHITEN_NO_CONTROLS");
end

function test_subspace_geometry()
    stream = RandStream('mt19937ar', 'Seed', 4242);
    direction = [0.6; 0.8; 0.0];
    scores = randn(stream, 400, 1);
    levels = scores * direction' + 1e-6 * randn(stream, 400, 3);

    subspace = Step28_factor_subspace(levels, 1);
    assert(subspace.rank == 1 && subspace.dimension == 3);
    assert(abs(abs(subspace.loadings' * direction) - 1) < 1e-4, 'The leading mode must recover the generating direction.');
    assert(subspace.explained_share > 0.999);
    assert(all(diff(subspace.eigenvalues) <= 0), 'Eigenvalues must descend.');

    assert_error(@() Step28_factor_subspace(levels, 4), "STEP28_SUBSPACE_RANK_DOMAIN");
    assert_error(@() Step28_factor_subspace(levels), "STEP28_SUBSPACE_RANK_REQUIRED");

    P = subspace.projector;
    assert(Step28_projector_distance(P, P) == 0);
    e1 = [1; 0]; e2 = [0; 1];
    assert(abs(Step28_projector_distance(e1 * e1', e2 * e2') - 1) < 1e-12, 'Orthogonal rank-one projectors are at distance one.');

    [angles, cosines] = Step28_principal_angles(e1, e1);
    assert(abs(angles) < 1e-12 && abs(cosines - 1) < 1e-12);
    [angles, cosines] = Step28_principal_angles(e1, e2);
    assert(abs(angles - pi / 2) < 1e-12 && abs(cosines) < 1e-12);
    assert_error(@() Step28_principal_angles([1, 1; 0, 0], eye(2)), "STEP28_ANGLES_ORTHONORMAL");
end

function test_conditional_law()
    stream = RandStream('mt19937ar', 'Seed', 90210);
    nPerGroup = 2500;
    groupNames = ["PR|1", "PR|2", "PC|1", "PC|2"];
    trueSlope = [0.40, -0.10; 0.05, 0.30; -0.20, 0.15];
    trueIntercept = [0.10, -0.20; 0.30, 0.00; -0.10, 0.25; 0.05, 0.15];
    trueScaleIntercept = [-0.20, 0.10; 0.00, -0.30; 0.15, 0.05; -0.05, 0.20];
    trueScaleSlope = [0.10, -0.05; -0.08, 0.06; 0.04, 0.09];
    trueCorrelation = [1, 0.5; 0.5, 1];
    cholCorrelation = chol(trueCorrelation, 'lower');

    total = nPerGroup * numel(groupNames);
    conditioning = randn(stream, total, 3);
    group = strings(total, 1);
    foldKey = strings(total, 1);
    target = zeros(total, 2);
    for g = 1:numel(groupNames)
        rows = (g - 1) * nPerGroup + (1:nPerGroup);
        group(rows) = groupNames(g);
        foldKey(rows) = "fold_" + string(mod(rows, 5) + 1);
        X = conditioning(rows, :);
        meanPart = trueIntercept(g, :) + X * trueSlope;
        logScale = trueScaleIntercept(g, :) + X * trueScaleSlope;
        noise = (cholCorrelation * randn(stream, 2, nPerGroup))';
        target(rows, :) = meanPart + exp(logScale) .* noise;
    end
    isControl = true(total, 1);

    options = struct('penaltyGrid', 0, 'seed', 1);
    model = Step28_conditional_gaussian_fit(target, conditioning, group, isControl, foldKey, options);

    assert(model.dimension == 2 && model.n_conditioning == 3);
    assert(max(abs(model.mean_block.slope - trueSlope), [], 'all') < 0.03, 'The affine mean slopes are not recovered.');
    assert(max(abs(model.scale_block.slope - trueScaleSlope), [], 'all') < 0.05, 'The log-scale slopes are not recovered.');
    assert(abs(model.correlation(1, 2) - trueCorrelation(1, 2)) < 0.03, 'The correlation is not recovered at zero penalty.');
    assert(model.penalty == 0);

    fullGrid = struct('penaltyGrid', [0, 0.05, 0.10, 0.20, 0.35, 0.50, 0.75, 1.00]);
    tuned = Step28_conditional_gaussian_fit(target, conditioning, group, isControl, foldKey, fullGrid);
    assert(ismember(tuned.penalty, fullGrid.penaltyGrid));
    assert(height(tuned.penalty_profile) == numel(fullGrid.penaltyGrid));

    [predictedMean, predictedCovariance] = Step28_conditional_gaussian_predict(model, conditioning, group);
    assert(isequal(size(predictedMean), [total, 2]));
    assert(isequal(size(predictedCovariance), [2, 2, total]));
    for i = [1, 137, total]
        Sigma = predictedCovariance(:, :, i);
        assert(norm(Sigma - Sigma', 'fro') < 1e-12);
        [~, notPositive] = chol(Sigma);
        assert(notPositive == 0, 'Every predicted covariance must be positive definite.');
    end
    assert(max(abs(mean(target - predictedMean, 1))) < 0.02);

    assert_error(@() Step28_conditional_gaussian_predict(model, conditioning, repmat("PR|9", total, 1)), "STEP28_LAW_PREDICT_GROUP");
    assert_error(@() Step28_conditional_gaussian_fit(target, conditioning, group, false(total, 1), foldKey, options), "STEP28_LAW_NO_CONTROLS");
end

function test_multistep_cost()
    kappaGrid = [1.5; 2; 4];
    z = [0, 0; 0, 0; 1, -1];
    m = [0, 0; 0, 0; 1, -1];
    Sigma = repmat(eye(2), 1, 1, 3);
    sequenceKey = ["a"; "a"; "b"];
    phase = ["PR"; "PR"; "PR"];

    [costs, transitions] = SBB_multistep_cost(z, m, Sigma, kappaGrid, sequenceKey, phase);
    assert(all(transitions.total_cost == 0), 'A transition with m = z and Sigma = I costs nothing.');
    assert(height(costs) == 2 * numel(kappaGrid));
    assert(all(costs.total_sum == 0) && all(costs.total_mean == 0));
    assert(all(costs.n_transitions(costs.sequence_key == "a") == 2));

    shifted = SBB_multistep_cost([0, 0], [3, 4], eye(2), kappaGrid, "c", "PC");
    assert(max(abs(shifted.total_mean - 12.5)) < 1e-12);
    assert(numel(unique(shifted.kappa)) == numel(kappaGrid), 'The kappa grid must never be aggregated.');

    Sigma2 = cat(3, diag([1.4, 0.8]), diag([0.9, 1.1]));
    varied = SBB_multistep_cost([0.1, 0.2; -0.3, 0.4], [0.2, 0.1; -0.1, 0.5], Sigma2, kappaGrid, ["d"; "d"], ["PR"; "PR"]);
    assert(max(abs(varied.total_sum - 2 * varied.total_mean)) < 1e-12);
    assert(max(abs(varied.total_sum - (varied.drift_sum + varied.volatility_sum))) < 1e-12, 'Equation (63) must hold.');

    assert_error(@() SBB_multistep_cost(z, m, Sigma, [2; 1.5], sequenceKey, phase), "SBB_MULTISTEP_KAPPA_GRID");
end

function test_abnormal_cost()
    kappaGrid = [1.5; 3];
    keys = ["e1"; "c1"; "c2"];
    costs = build_cost_table(keys, kappaGrid);

    links = table(["e1"; "e1"; "e1"; "e1"], ["PR"; "PR"; "PC"; "PC"],         ["c1"; "c2"; "c1"; "c2"], [0.5; 0.5; 0.5; 0.5], 'VariableNames', {'event_key', 'phase', 'control_key', 'weight'});

    [abnormal, contrast] = SBB_abnormal_cost(costs, links);
    assert(height(abnormal) == 2 * numel(kappaGrid));
    assert(all(abnormal.n_controls == 2));

    for i = 1:height(abnormal)
        expected = abnormal.event_total(i) - abnormal.control_total(i);
        assert(abs(abnormal.abnormal_total(i) - expected) < 1e-12);
    end
    assert(height(contrast) == numel(kappaGrid));
    for q = 1:numel(kappaGrid)
        kappa = kappaGrid(q);
        pr = abnormal(abnormal.phase == "PR" & abnormal.kappa == kappa, :);
        pc = abnormal(abnormal.phase == "PC" & abnormal.kappa == kappa, :);
        expected = pc.abnormal_total - pr.abnormal_total;
        assert(abs(contrast.contrast_total(contrast.kappa == kappa) - expected) < 1e-12);
    end

    identical = build_identical_cost_table(kappaGrid);
    [flat, flatContrast] = SBB_abnormal_cost(identical, links);
    assert(max(abs(flat.abnormal_total)) < 1e-12);
    assert(max(abs(flatContrast.contrast_total)) < 1e-12);

    bad = links;
    bad.weight = [0.5; 0.6; 0.5; 0.5];
    assert_error(@() SBB_abnormal_cost(costs, bad), "SBB_ABNORMAL_WEIGHT_SUM");
end

function costs = build_cost_table(keys, kappaGrid)
    phases = ["PR"; "PC"];
    rows = numel(keys) * numel(phases) * numel(kappaGrid);
    sequenceKey = strings(rows, 1);
    phase = strings(rows, 1);
    kappa = zeros(rows, 1);
    driftMean = zeros(rows, 1);
    volatilityMean = zeros(rows, 1);
    r = 0;
    for i = 1:numel(keys)
        for p = 1:numel(phases)
            for q = 1:numel(kappaGrid)
                r = r + 1;
                sequenceKey(r) = keys(i);
                phase(r) = phases(p);
                kappa(r) = kappaGrid(q);
                driftMean(r) = 0.1 * i + 0.01 * p + 0.001 * q;
                volatilityMean(r) = 0.2 * i - 0.02 * p + 0.002 * q;
            end
        end
    end
    costs = table(sequenceKey, phase, kappa, driftMean, volatilityMean,         driftMean + volatilityMean, 'VariableNames', {'sequence_key', 'phase', 'kappa', 'drift_mean', 'volatility_mean', 'total_mean'});
end

function costs = build_identical_cost_table(kappaGrid)
    costs = build_cost_table(["e1"; "c1"; "c2"], kappaGrid);
    for q = 1:numel(kappaGrid)
        for phase = ["PR", "PC"]
            rows = costs.kappa == kappaGrid(q) & costs.phase == phase;
            costs.drift_mean(rows) = 0.7;
            costs.volatility_mean(rows) = 0.3;
            costs.total_mean(rows) = 1.0;
        end
    end
end

function test_profile_inference()
    kappaGrid = [1.25; 1.5; 2; 3; 5];
    meetings = "m" + string(1:60)';
    stream = RandStream('mt19937ar', 'Seed', 777);
    effect = 1 + 0.2 * randn(stream, numel(meetings), 1);
    values = containers.Map(cellstr(meetings), num2cell(effect));

    estimator = @(context) synthetic_profile(context, kappaGrid, values);

    options = struct('draws', 199, 'alpha', 0.05, 'seed', 20260905,         'robustnessGrid', [1.5; 2; 3], 'leaveTopK', [1, 3],         'foldOfMeeting', "y" + string(mod(1:numel(meetings), 4) + 1)', 'rankOfMeeting', abs(effect));

    inference = SBB_profile_inference(estimator, meetings, kappaGrid, options);

    assert(inference.n_meetings == 60 && inference.draws == 199);
    assert(height(inference.bands) == 3 * numel(kappaGrid));
    assert(sum(inference.bands.in_robustness_interval) == 3 * 3);

    drift = inference.bands(inference.bands.component == "drift", :);
    assert(max(abs(drift.estimate - mean(effect))) < 1e-12, 'The point estimate must be the full-sample statistic.');
    assert(all(drift.band_lower < drift.estimate) && all(drift.estimate < drift.band_upper));

    verdict = inference.verdict(inference.verdict.component == "drift", :);
    assert(verdict.uniform_exclusion_of_zero && verdict.uniform_sign, 'A clearly non-zero profile must be uniformly signed on K_rob.');

    assert(any(inference.stability.exercise == "leave_year_out"));
    assert(any(inference.stability.exercise == "leave_top_k"));
    assert(height(inference.admissible_conclusion) == 3);

    nullValues = containers.Map(cellstr(meetings), num2cell(effect - mean(effect)));
    nullInference = SBB_profile_inference(         @(context) synthetic_profile(context, kappaGrid, nullValues), meetings, kappaGrid, options);
    nullVerdict = nullInference.verdict(nullInference.verdict.component == "total", :);
    assert(~nullVerdict.uniform_exclusion_of_zero, 'A zero-centred profile must not exclude zero uniformly.');

    assert_error(@() SBB_profile_inference(estimator, meetings, kappaGrid,         struct('seed', 1, 'robustnessGrid', [1.25; 2])), "SBB_PROFILE_ROBUSTNESS_CONTIGUOUS");
    assert_error(@() SBB_profile_inference(estimator, meetings, kappaGrid, struct('draws', 199)), "SBB_PROFILE_SEED");
end

function result = synthetic_profile(context, kappaGrid, values)
    drawn = context.meetings;
    total = 0;
    for i = 1:numel(drawn)
        total = total + values(char(drawn(i)));
    end
    average = total / numel(drawn);
    shape = 1 + 0.05 * log(kappaGrid);
    result = table(kappaGrid, average * shape, average * shape / 2,         average * shape * 1.5, 'VariableNames', {'kappa', 'contrast_drift', 'contrast_volatility', 'contrast_total'});
    result.contrast_drift = average * ones(numel(kappaGrid), 1);
    result.contrast_volatility = average * ones(numel(kappaGrid), 1) / 2;
    result.contrast_total = average * ones(numel(kappaGrid), 1) * 1.5;
end

function test_authorisation()
    root = string(tempname);
    cleanup = onCleanup(@() remove_directory(root));
    outputDir = fullfile(root, 'Output', 'step28_sbbts');
    mkdir(outputDir);

    [authorised, gates] = Step28_sbb_authorisation(root);
    assert(~authorised, 'An empty output directory must never authorise.');
    assert(height(gates) == 7);
    assert(sum(gates.observed == "decision_file_missing") == 6);
    assert(~gates.pass(gates.gate_id == "frozen_specification"));

    write_single(outputDir, 'step28_data_gate_decision.csv', {'status'}, {"pass_data_gate"});
    write_single(outputDir, 'step28_sample_size_gate_decision.csv', {'status'}, {"pass_sample_size_gate"});
    write_single(outputDir, 'step28_spectral_gate_decision.csv', {'status'}, {"pass_spectral_gate"});
    write_single(outputDir, 'step28_gaussian_calibration_gate_decision.csv', {'status'}, {"pass_calibration_gate"});
    write_single(outputDir, 'step28_markov_power_gate_decision.csv',         {'mean_branch_status', 'covariance_branch_status'}, {"pass_mean_branch", "reject_covariance_branch"});

    [authorised, gates] = Step28_sbb_authorisation(root);
    assert(~authorised, 'A covariance-branch rejection must block even when the mean passes.');
    assert(gates.pass(gates.gate_id == "markov_power_mean"));
    assert(~gates.pass(gates.gate_id == "markov_power_covariance"));

    write_single(outputDir, 'step28_markov_power_gate_decision.csv',         {'mean_branch_status', 'covariance_branch_status'}, {"pass_mean_branch", "pass_covariance_branch"});
    [authorised, gates] = Step28_sbb_authorisation(root);
    assert(~authorised && all(gates.pass(gates.gate_id ~=         "frozen_specification")), 'Passing status strings cannot authorise without a frozen specification.');

    specification = struct('factor_rank_rule', "selected_by_spectral_gate", 'specification_sha256', "abc");
    write_single(outputDir, 'step28_spectral_gate_decision.csv', {'status', 'accepted_rank'}, {"pass_spectral_gate", "2"});
    [authorised, gates] = Step28_sbb_authorisation(root, specification);
    assert(~authorised, 'Unstamped decisions must not authorise.');
    assert(any(startsWith(gates.gate_id, "provenance:")), 'The provenance rows must be reported.');
    assert(all(gates.observed(startsWith(gates.gate_id, "provenance:")) ~= "stamped and current"));

    rankRow = gates(gates.gate_id == "rank_selection", :);
    assert(height(rankRow) == 1 && rankRow.pass, 'An accepted low rank must pass its own check.');
    write_single(outputDir, 'step28_spectral_gate_decision.csv', {'status', 'accepted_rank'}, {"pass_spectral_gate", "3"});
    [~, gatesInvalid, invalidRank] = Step28_sbb_authorisation(root, specification);
    assert(~gatesInvalid.pass(gatesInvalid.gate_id == "rank_selection") &&         isnan(invalidRank), 'A terminal or invalid rank must never reach the estimator.');
    write_single(outputDir, 'step28_spectral_gate_decision.csv', {'status', 'accepted_rank'}, {"pass_spectral_gate", "2"});

    manifestDir = fullfile(root, 'Output', 'manifests');
    analysisDir = fullfile(root, 'Output', 'analysis');
    rawDir = fullfile(root, 'Raw');
    mkdir(manifestDir); mkdir(analysisDir); mkdir(rawDir);
    sourceFile = fullfile(rawDir, 'source.csv');
    writetable(table((1:3)', 'VariableNames', {'value'}), sourceFile);
    sourceManifest = table("EA_EMPD", "Raw/source.csv",         File_sha256(sourceFile), 'VariableNames', {'surprise_source', 'source_file', 'source_file_sha256'});
    writetable(sourceManifest, fullfile(manifestDir, 'surprise_source_manifest.csv'));
    stateFile = fullfile(analysisDir, 'event_state_panel.csv');
    writetable(table((1:3)', 'VariableNames', {'state'}), stateFile);
    dataManifest = fullfile(outputDir, 'step28_barchart_data_manifest.csv');
    writetable(table("certified", 'VariableNames', {'status'}), dataManifest);

    provenance = Step28_provenance(root, specification);
    write_single(outputDir, 'step28_data_gate_decision.csv',         {'status', 'data_manifest_sha256'}, {"pass_data_gate", provenance.data_manifest_sha256});
    write_stamped(outputDir, 'step28_sample_size_gate_decision.csv', {'status'}, {"pass_sample_size_gate"}, provenance);
    write_stamped(outputDir, 'step28_spectral_gate_decision.csv', {'status', 'accepted_rank'}, {"pass_spectral_gate", "2"}, provenance);
    write_stamped(outputDir, 'step28_gaussian_calibration_gate_decision.csv', {'status'}, {"pass_calibration_gate"}, provenance);
    write_stamped(outputDir, 'step28_markov_power_gate_decision.csv',         {'mean_branch_status', 'covariance_branch_status'}, {"pass_mean_branch", "pass_covariance_branch"}, provenance);
    [fullyAuthorised, fullyStamped, selectedRank] = Step28_sbb_authorisation(root, specification);
    assert(fullyAuthorised && all(fullyStamped.pass) && selectedRank == 2,         ['Current complete stamps must authorise the SBB estimator and ' 'return the spectral rank.']);

    writetable(table((1:4)', 'VariableNames', {'state'}), stateFile);
    [tamperedAuthorised, tampered] = Step28_sbb_authorisation(root, specification);
    assert(~tamperedAuthorised &&         ~tampered.pass(tampered.gate_id ==         "provenance:sample_size_gate_decision.csv"), 'Changing the state panel must invalidate prior gate decisions.');
end

function test_end_to_end_estimate()
    stream = RandStream('mt19937ar', 'Seed', 31415);
    [panel, specification] = synthetic_panel(stream, 0);

    meetings = unique(panel.date_key(panel.role == "event"));
    [contrast, artefacts] = Step28_sbb_estimate(panel, specification, meetings);

    assert(height(contrast) == numel(specification.kappa_grid));
    assert(max(abs(contrast.kappa(:) - specification.kappa_grid(:))) < 1e-12, 'The frozen kappa grid must survive the whole chain.');
    assert(all(isfinite(contrast.contrast_total)));
    assert(artefacts.law.dimension == specification.factor_rank);
    assert(isfield(artefacts.subspaces, 'PR') && isfield(artefacts.subspaces, 'PC'));
    assert(all(artefacts.abnormal.n_controls == 5));

    scale = mean(abs(artefacts.abnormal.event_total));
    assert(max(abs(contrast.contrast_total)) < 0.35 * scale, 'With identical event and control dynamics the contrast must be small.');

    [shiftedPanel, shiftedSpecification] = synthetic_panel(stream, 0.9);
    shiftedContrast = Step28_sbb_estimate(shiftedPanel, shiftedSpecification, unique(shiftedPanel.date_key(shiftedPanel.role == "event")));
    assert(all(shiftedContrast.contrast_total > contrast.contrast_total), 'An event-only drift must raise the abnormal cost at every kappa.');

    repeated = [meetings; meetings(1)];
    repeatedContrast = Step28_sbb_estimate(panel, specification, repeated);
    assert(height(repeatedContrast) == numel(specification.kappa_grid));

    asymmetric = panel;
    firstEvent = meetings(1);
    pcLinks = find(asymmetric.links.event_key == firstEvent & asymmetric.links.phase == "PC");
    asymmetric.links(pcLinks(3:end), :) = [];
    [~, ~, ~, ~, ~, asymmetricLinks] = Step28_expand_meetings(asymmetric, firstEvent);
    assert(sum(asymmetricLinks.phase == "PR") == 5 &&         sum(asymmetricLinks.phase == "PC") == 2, 'The meeting expansion must preserve phase-specific control sets.');

    gapped = panel;
    drop = gapped.date_key == firstEvent & gapped.role == "event" & gapped.phase == "PR" & gapped.position == 3;
    gapped.returns(drop, :) = [];
    gapped.date_key(drop) = [];
    gapped.role(drop) = [];
    gapped.phase(drop) = [];
    gapped.position(drop) = [];
    gapped.fold_key(drop) = [];
    [~, gappedArtefacts] = Step28_sbb_estimate(gapped, specification, meetings);
    assert(gappedArtefacts.n_transitions == artefacts.n_transitions - 2, 'An interior missing bar must remove two transitions, not create a bridge.');

    stateOnly = specification;
    stateOnly.control_conditioning_rule = "state_only";
    stateOnlyContrast = Step28_sbb_estimate(panel, stateOnly, meetings);
    assert(height(stateOnlyContrast) == numel(specification.kappa_grid));

    unidentified = specification;
    unidentified.law_fit_sample = "controls_only";
    assert_error(@() Step28_sbb_estimate(panel, unidentified, meetings), "STEP28_LAW_RANK_DEFICIENT");

    inherited = specification;
    inherited.law_fit_sample = "controls_only";
    inherited.control_conditioning_rule = "inherit_matched_event";
    inheritedContrast = Step28_sbb_estimate(panel, inherited, meetings);
    assert(height(inheritedContrast) == numel(specification.kappa_grid));

    assert_error(@() Step28_sbb_estimate(panel, specification, "not_a_meeting"), "STEP28_SBB_MEETING_MISSING");
    assert_error(@() Step28_sbb_estimate(panel, specification, meetings, "unfrozen_perturbation"), "STEP28_SBB_PERTURBATION_UNKNOWN");
end

function [panel, specification] = synthetic_panel(stream, eventDrift)
    nEvents = 40;
    nControls = 60;
    nFolds = 4;
    phases = ["PR", "PC"];
    positionsOf = struct('PR', 1:5, 'PC', 1:9);

    eventKeys = "E" + string(1:nEvents)';
    controlKeys = "C" + string(1:nControls)';
    allKeys = [eventKeys; controlKeys];
    roles = [repmat("event", nEvents, 1); repmat("matched_control", nControls, 1)];
    folds = "y" + string(mod(0:numel(allKeys) - 1, nFolds) + 1)';

    base = [1.00, 0.55, 0.25; 0.55, 1.00, 0.40; 0.25, 0.40, 1.00];

    dateKey = strings(0, 1);
    role = strings(0, 1);
    phase = strings(0, 1);
    position = zeros(0, 1);
    foldKey = strings(0, 1);
    returns = zeros(0, 3);

    for i = 1:numel(allKeys)
        for p = 1:numel(phases)
            for k = positionsOf.(phases(p))
                scale = 1 + 0.15 * k;
                L = chol(scale * base, 'lower');
                value = (L * randn(stream, 3, 1))';
                if roles(i) == "event"
                    value = value + eventDrift * [1, -1, 0.5];
                end
                dateKey(end + 1, 1) = allKeys(i);
                role(end + 1, 1) = roles(i);
                phase(end + 1, 1) = phases(p);
                position(end + 1, 1) = k;
                foldKey(end + 1, 1) = folds(i);
                returns(end + 1, :) = value;
            end
        end
    end

    stateValues = randn(stream, nEvents, 2);
    surpriseValues = randn(stream, nEvents, 2);
    state = table(eventKeys, stateValues(:, 1), stateValues(:, 2), 'VariableNames', {'date_key', 'state_a', 'state_b'});
    surprise = table(eventKeys, surpriseValues(:, 1), surpriseValues(:, 2), 'VariableNames', {'date_key', 'xi_a', 'xi_b'});

    linkEvent = strings(0, 1);
    linkPhase = strings(0, 1);
    linkControl = strings(0, 1);
    linkWeight = zeros(0, 1);
    for e = 1:nEvents
        chosen = controlKeys(mod((e - 1) * 5 + (0:4), nControls) + 1);
        for p = 1:numel(phases)
            for c = 1:numel(chosen)
                linkEvent(end + 1, 1) = eventKeys(e);
                linkPhase(end + 1, 1) = phases(p);
                linkControl(end + 1, 1) = chosen(c);
                linkWeight(end + 1, 1) = 1 / numel(chosen);
            end
        end
    end

    panel = struct();
    panel.returns = returns;
    panel.date_key = dateKey;
    panel.role = role;
    panel.phase = phase;
    panel.position = position;
    panel.fold_key = foldKey;
    panel.state = state;
    panel.surprise = surprise;
    panel.links = table(linkEvent, linkPhase, linkControl, linkWeight, 'VariableNames', {'event_key', 'phase', 'control_key', 'weight'});

    specification = struct();
    specification.factor_rank = 2;
    specification.kappa_grid = [1.5, 2, 4];
    specification.whitening_minimum_dates = 20;
    specification.state_columns = ["state_a", "state_b"];
    specification.surprise_columns = ["xi_a", "xi_b"];
    specification.control_conditioning_rule = "state_and_surprise_zeroed";
    specification.law_fit_sample = "pooled";
    specification.law_pooling = "group_intercept_pooled_slopes";
    specification.law_correlation_scope = "pooled";
    specification.law_penalty_grid = [0, 0.1];
    specification.law_minimum_group_rows = 20;
    specification.law_residual_floor = 1e-8;
end

function write_single(outputDir, name, columns, values)
    T = table();
    for c = 1:numel(columns)
        T.(columns{c}) = string(values{c});
    end
    writetable(T, fullfile(outputDir, name));
end

function write_stamped(outputDir, name, columns, values, provenance)
    T = table();
    for c = 1:numel(columns)
        T.(columns{c}) = string(values{c});
    end
    T = Step28_stamp_decision(T, provenance);
    writetable(T, fullfile(outputDir, name));
end

function remove_directory(root)
    if exist(root, 'dir') == 7
        rmdir(root, 's');
    end
end

function assert_error(fn, expectedIdentifier)
    didFail = false;
    try
        fn();
    catch ME
        didFail = contains(string(ME.message), expectedIdentifier);
        if ~didFail
            error('Expected %s, got: %s', expectedIdentifier, ME.message);
        end
    end
    assert(didFail, 'Expected %s, but no error was raised.', expectedIdentifier);
end
