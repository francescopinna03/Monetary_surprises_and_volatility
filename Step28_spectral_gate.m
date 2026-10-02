function [decision, detail] = Step28_spectral_gate(panel, specification, calibration, shockEnergy)

    meetings = unique(panel.date_key(panel.role == "event"));
    expanded = Step28_expanded_levels(panel, specification, meetings);
    levels = expanded.levels;
    meta = expanded.meta;

    phases = ["PR", "PC"];
    rankVerdict = struct();
    acceptedRank = NaN(1, numel(phases));
    for p = 1:numel(phases)
        rows = meta.phase == phases(p) & meta.role == "event";
        controlRows = meta.phase == phases(p) & meta.role == "matched_control" & meta.is_moment_control;
        if ~any(rows) || ~any(controlRows)
            error('STEP28_SPECTRAL_PHASE_SUPPORT: %s lacks events or controls.', phases(p));
        end
        rankOptions = rank_options(specification, levels(controlRows, :), meta.position(controlRows), meta.date_key(controlRows));
        verdict = Step28_spectral_rank(levels(rows, :), meta.position(rows), meta.date_key(rows), rankOptions);
        rankVerdict.(char(phases(p))) = verdict;
        if verdict.status == "low_rank_accepted"
            acceptedRank(p) = verdict.accepted_rank;
        end
    end

    statuses = string({rankVerdict.PR.status, rankVerdict.PC.status});
    if any(statuses == "no_signal_terminal")
        decision = write_row("blocked_no_signal_terminal", 0, NaN, NaN, NaN,             NaN, statuses, calibration, "no event mode exceeds the exact-clock control null; Step 28 stops");
        detail = struct('rank', rankVerdict);
        return;
    end
    if any(statuses == "full_rank_terminal")
        decision = write_row("blocked_full_rank_terminal", NaN, NaN, NaN, NaN,             NaN, statuses, calibration, "no low-rank structure in the primary panel; Step 28 stops");
        detail = struct('rank', rankVerdict);
        return;
    end
    if any(statuses ~= "low_rank_accepted")
        decision = write_row("blocked_unstable_subspace", NaN, NaN, NaN, NaN,             NaN, statuses, calibration, "the rank procedures disagree; no common multivariate operator");
        detail = struct('rank', rankVerdict);
        return;
    end
    if acceptedRank(1) ~= acceptedRank(2)
        decision = write_row("blocked_unstable_subspace", NaN, NaN, NaN, NaN,             NaN, statuses, calibration, "PR and PC accept different ranks; there is no common space");
        detail = struct('rank', rankVerdict);
        return;
    end

    rank = acceptedRank(1);
    stream = RandStream('mt19937ar', 'Seed', specification.bootstrap_seed);

    stability = table();
    worstQuantile = 0;
    for p = 1:numel(phases)
        [phaseStability, phaseQuantile] = projector_stability(panel, specification, rank, stream, phases(p), shockEnergy);
        stability = [stability; phaseStability];
        worstQuantile = max(worstQuantile, phaseQuantile);
    end

    projectorPasses = worstQuantile <= calibration.projector_tolerance;

    [angles, cosines, angleQuantile, anglePasses, matchedPasses] = principal_angle_test(levels, meta, rank, specification, stream);

    prLoadings = Step28_factor_subspace(levels(meta.phase == "PR" &         meta.role == "event", :), rank).loadings;
    pcLoadings = Step28_factor_subspace(levels(meta.phase == "PC" &         meta.role == "event", :), rank).loadings;
    commonBasis = [];
    basisDiagnostics = struct();
    commonBasisPasses = true;
    try
        [commonBasis, basisDiagnostics] = Step28_common_basis(prLoadings, pcLoadings);
    catch ME
        if contains(string(ME.message), "STEP28_COMMON_BASIS")
            commonBasisPasses = false;
            basisDiagnostics.status = "degenerate_common_basis";
            basisDiagnostics.message = string(ME.message);
        else
            rethrow(ME);
        end
    end

    if ~projectorPasses
        status = "blocked_unstable_subspace";
        nextAction = "the projector is not stable at the calibrated tolerance";
    elseif ~anglePasses || ~matchedPasses || ~commonBasisPasses
        status = "blocked_no_common_space";
        nextAction = "PR and PC do not share enough of a subspace to compare " + "costs in a common space";
    else
        status = "pass_spectral_gate";
        nextAction = "run the Markov power gate on both branches";
    end

    decision = write_row(status, rank, worstQuantile, min(cosines), angleQuantile, double(matchedPasses), statuses, calibration, nextAction);

    detail = struct();
    detail.rank = rankVerdict;
    detail.stability = stability;
    detail.principal_angles = angles;
    detail.principal_cosines = cosines;
    detail.common_basis = commonBasis;
    detail.common_basis_diagnostics = basisDiagnostics;
end

function options = rank_options(specification, controlLevels, controlPosition, controlDateKey)
    options = struct('seed', specification.bootstrap_seed,         'parallelDraws', specification.spectral_parallel_draws,         'parallelQuantile', specification.spectral_parallel_quantile,         'reconstructionFolds', specification.spectral_reconstruction_folds,         'controlLevels', controlLevels, 'controlPosition', controlPosition, 'controlDateKey', controlDateKey);
end

function [stability, worstQuantile] = projector_stability(panel, specification, rank, stream, phase, shockEnergy)

    meetings = unique(panel.date_key(panel.role == "event"));
    reference = phase_projector(panel, specification, rank, meetings, "none", phase);

    exercise = strings(0, 1);
    level = strings(0, 1);
    distance = zeros(0, 1);

    foldOf = strings(numel(meetings), 1);
    for m = 1:numel(meetings)
        foldOf(m) = panel.fold_key(find(panel.date_key == meetings(m), 1));
    end
    folds = unique(foldOf);
    for f = 1:numel(folds)
        kept = meetings(foldOf ~= folds(f));
        exercise(end + 1, 1) = "leave_year_out";
        level(end + 1, 1) = folds(f);
        distance(end + 1, 1) = Step28_projector_distance(phase_projector( panel, specification, rank, kept, "none", phase), reference);
    end

    [~, order] = sort(shock_energy_for(meetings, shockEnergy), 'descend');
    for k = specification.leave_top_k
        keepCount = numel(meetings) - min(k, numel(meetings) - 2);
        kept = meetings(order(end - keepCount + 1:end));
        exercise(end + 1, 1) = "leave_top_k_by_shock_energy";
        level(end + 1, 1) = string(k);
        distance(end + 1, 1) = Step28_projector_distance(phase_projector( panel, specification, rank, kept, "none", phase), reference);
    end

    for q = 1:numel(specification.boundary_bar_perturbations)
        name = specification.boundary_bar_perturbations(q);
        exercise(end + 1, 1) = "boundary_bar_perturbation";
        level(end + 1, 1) = name;
        distance(end + 1, 1) = Step28_projector_distance(phase_projector( panel, specification, rank, meetings, name, phase), reference);
    end

    bootstrapDistance = NaN(specification.spectral_stability_draws, 1);
    for b = 1:specification.spectral_stability_draws
        drawn = meetings(randi(stream, numel(meetings), numel(meetings), 1));
        bootstrapDistance(b) = Step28_projector_distance(phase_projector( panel, specification, rank, drawn, "none", phase), reference);
    end
    quantileValue = quantile(bootstrapDistance, 0.95);
    exercise(end + 1, 1) = "meeting_bootstrap_q95";
    level(end + 1, 1) = string(specification.spectral_stability_draws);
    distance(end + 1, 1) = quantileValue;

    worstQuantile = max(distance);
    stability = table(repmat(phase, numel(exercise), 1), exercise, level,         distance, 'VariableNames', {'phase', 'exercise', 'level', 'projector_distance'});
end

function projector = phase_projector(panel, specification, rank, meetings, perturbation, phase)
    working = panel;
    if perturbation ~= "none"
        variant = panel.perturbations.(char(perturbation));
        working.returns = variant.returns;
        working.date_key = variant.date_key;
        working.role = variant.role;
        working.phase = variant.phase;
        working.position = variant.position;
        working.fold_key = variant.fold_key;
    end

    expanded = Step28_expanded_levels(working, specification, meetings);
    level = expanded.levels;
    replicaRole = expanded.meta.role;
    replicaPhase = expanded.meta.phase;
    selected = replicaPhase == phase & replicaRole == "event";
    if sum(selected) <= size(level, 2)
        error('STEP28_SPECTRAL_STABILITY_SUPPORT: %s has too few rows.', phase);
    end
    projector = Step28_factor_subspace(level(selected, :), rank).projector;
end

function energy = shock_energy_for(meetings, shockEnergy)
    energy = zeros(numel(meetings), 1);
    for i = 1:numel(meetings)
        if isKey(shockEnergy, char(meetings(i)))
            energy(i) = shockEnergy(char(meetings(i)));
        else
            error(['STEP28_SPECTRAL_SHOCK_ENERGY: no shock energy for %s; '                 'leave-top-K is ordered by shock energy, not by level ' 'energy.'], meetings(i));
        end
    end
end

function [angles, cosines, nullQuantile, passes, matchedPasses] = principal_angle_test(levels, meta, rank, specification, stream)

    prRows = meta.phase == "PR" & meta.role == "event";
    pcRows = meta.phase == "PC" & meta.role == "event";
    prLoadings = Step28_factor_subspace(levels(prRows, :), rank).loadings;
    pcLoadings = Step28_factor_subspace(levels(pcRows, :), rank).loadings;
    [angles, cosines] = Step28_principal_angles(prLoadings, pcLoadings);

    draws = specification.spectral_angle_draws;
    nullSmallestCosine = NaN(draws, 1);
    for b = 1:draws
        prNull = permute_within_position(levels(prRows, :), meta.position(prRows), stream);
        pcNull = permute_within_position(levels(pcRows, :), meta.position(pcRows), stream);
        a = Step28_factor_subspace(prNull, rank).loadings;
        c = Step28_factor_subspace(pcNull, rank).loadings;
        [~, nullCosines] = Step28_principal_angles(a, c);
        nullSmallestCosine(b) = min(nullCosines);
    end
    nullQuantile = quantile(nullSmallestCosine, specification.spectral_parallel_quantile);
    passes = min(cosines) > nullQuantile;

    prPositions = numel(unique(meta.position(prRows)));
    matchedRows = pcRows & meta.position <= prPositions;
    if sum(matchedRows) <= size(levels, 2)
        matchedPasses = false;
        return;
    end
    matchedLoadings = Step28_factor_subspace(levels(matchedRows, :), rank).loadings;
    [~, matchedCosines] = Step28_principal_angles(prLoadings, matchedLoadings);
    matchedPasses = min(matchedCosines) > nullQuantile;
end

function permuted = permute_within_position(levels, position, stream)
    permuted = levels;
    positions = unique(position);
    for q = 1:numel(positions)
        rows = find(position == positions(q));
        for j = 1:size(levels, 2)
            permuted(rows, j) = levels(rows(randperm(stream, numel(rows))), j);
        end
    end
end

function decision = write_row(status, rank, projectorQuantile,         smallestCosine, nullQuantile, matchedPasses, statuses, calibration, nextAction)
    decision = table("step28_spectral_gate_v1", string(status),         double(rank), double(projectorQuantile),         double(calibration.projector_tolerance), double(smallestCosine),         double(nullQuantile), double(matchedPasses),         string(statuses(1)), string(statuses(2)), string(nextAction),         string(datetime('now', 'TimeZone', 'UTC'),         'yyyy-MM-dd''T''HH:mm:ssXXX'),         'VariableNames', {'schema_version', 'status', 'accepted_rank',         'worst_projector_distance', 'projector_tolerance',         'smallest_principal_cosine', 'null_cosine_quantile',         'length_matched_passes', 'pr_rank_status', 'pc_rank_status', 'next_action', 'generated_at_utc'});
end
