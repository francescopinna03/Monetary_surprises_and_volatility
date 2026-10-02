function [contrast, artefacts] = Step28_sbb_estimate(panel, specification, meetings, perturbation)

    if nargin < 4 || strlength(string(perturbation)) == 0
        perturbation = "none";
    end
    perturbation = string(perturbation);
    meetings = string(meetings(:));
    if isempty(meetings)
        error('STEP28_SBB_ESTIMATE_EMPTY: at least one meeting is required.');
    end

    validate_panel(panel);
    panel = apply_perturbation(panel, perturbation);

    expanded = Step28_expanded_levels(panel, specification, meetings);
    replicaKey = expanded.meta.date_key;
    replicaRole = expanded.meta.role;
    replicaPhase = expanded.meta.phase;
    replicaEvent = expanded.meta.event_key;
    links = expanded.links;
    position = expanded.meta.position;

    if ~any(expanded.is_moment_control)
        error(['STEP28_SBB_ESTIMATE_NO_CONTROLS: the matched control leg of ' 'equation (27) is empty.']);
    end
    level = expanded.levels;
    whiteningMoments = expanded.whitening_moments;

    phases = ["PR", "PC"];
    subspaces = struct();
    for p = 1:numel(phases)
        selected = replicaPhase == phases(p) & replicaRole == "event";
        if ~any(selected)
            error(['STEP28_SBB_ESTIMATE_PHASE: %s has no row, so no common ' 'PR-PC space can be built.'], phases(p));
        end
        subspaces.(char(phases(p))) = Step28_factor_subspace( level(selected, :), specification.factor_rank);
    end
    [commonBasis, basisDiagnostics] = Step28_common_basis( subspaces.PR.loadings, subspaces.PC.loadings);
    factorLevel = level * commonBasis;

    transition = build_transitions(replicaKey, replicaPhase, replicaRole, replicaEvent, position, factorLevel, panel, specification);

    lawRows = true(height(transition), 1);
    if specification.law_fit_sample == "controls_only"
        lawRows = transition.role == "matched_control";
        if ~any(lawRows)
            error(['STEP28_SBB_ESTIMATE_LAW_SAMPLE: controls_only was frozen ' 'but no control transition survives.']);
        end
    end

    lawOptions = struct('pooling', specification.law_pooling,         'correlationScope', specification.law_correlation_scope,         'penaltyGrid', specification.law_penalty_grid,         'minimumGroupRows', specification.law_minimum_group_rows, 'residualFloor', specification.law_residual_floor);
    model = Step28_conditional_gaussian_fit(transition.target(lawRows, :),         transition.conditioning(lawRows, :), transition.group(lawRows),         transition.is_control(lawRows), transition.fold_key(lawRows), lawOptions);

    [conditionalMean, conditionalCovariance] =         Step28_conditional_gaussian_predict(model, transition.conditioning, transition.group);

    costs = SBB_multistep_cost(transition.origin, conditionalMean,         conditionalCovariance, specification.kappa_grid, transition.sequence_key, transition.phase);

    [abnormal, contrast] = SBB_abnormal_cost(costs, links);

    artefacts = struct();
    artefacts.schema_version = "step28_sbb_estimate_v1";
    artefacts.perturbation = perturbation;
    artefacts.n_meetings = numel(meetings);
    artefacts.n_transitions = height(transition);
    artefacts.whitening_moments = whiteningMoments;
    artefacts.subspaces = subspaces;
    artefacts.common_basis = commonBasis;
    artefacts.common_basis_diagnostics = basisDiagnostics;
    artefacts.law = model;
    artefacts.costs = costs;
    artefacts.abnormal = abnormal;
end

function panel = apply_perturbation(panel, perturbation)
    if perturbation == "none"
        return;
    end
    if ~isfield(panel, 'perturbations') || ~ismember(perturbation, string(fieldnames(panel.perturbations)))
        error(['STEP28_SBB_PERTURBATION_UNKNOWN: %s is not in the frozen ' 'boundary-bar perturbation family.'], perturbation);
    end
    variant = panel.perturbations.(char(perturbation));
    panel.returns = variant.returns;
    panel.date_key = variant.date_key;
    panel.role = variant.role;
    panel.phase = variant.phase;
    panel.position = variant.position;
    panel.fold_key = variant.fold_key;
end

function validate_panel(panel)
    required = ["returns", "date_key", "role", "phase", "position", "fold_key", "state", "surprise", "links"];
    missing = required(~isfield(panel, required));
    if ~isempty(missing)
        error('STEP28_SBB_PANEL_SCHEMA: panel is missing %s.', strjoin(missing, ', '));
    end
end

function transition = build_transitions(replicaKey, replicaPhase, replicaRole, replicaEvent, position, factorLevel, panel, specification)

    key = replicaKey + "|" + replicaPhase;
    [groupIndex, groupNames] = findgroups(key);

    originRows = zeros(0, 1);
    targetRows = zeros(0, 1);
    for g = 1:numel(groupNames)
        rows = find(groupIndex == g);
        [~, order] = sort(position(rows));
        rows = rows(order);
        if numel(rows) < 2
            continue;
        end
        consecutive = diff(position(rows)) == 1;
        originRows = [originRows; rows([consecutive; false])];
        targetRows = [targetRows; rows([false; consecutive])];
    end

    if isempty(originRows)
        error(['STEP28_SBB_NO_TRANSITIONS: every sequence has fewer than two ' 'synchronised positions.']);
    end

    origin = factorLevel(originRows, :);
    target = factorLevel(targetRows, :);
    sequenceKey = replicaKey(originRows);
    phase = replicaPhase(originRows);
    role = replicaRole(originRows);
    eventOf = replicaEvent(originRows);
    fromPosition = position(originRows);

    stateBlock = covariate_block(panel.state, specification.state_columns,         sequenceKey, eventOf, role, specification.control_conditioning_rule, "state");
    surpriseBlock = covariate_block(panel.surprise,         specification.surprise_columns, sequenceKey, eventOf, role, specification.control_conditioning_rule, "surprise");

    transition = table(sequenceKey, phase, role, fromPosition,         role == "matched_control",         'VariableNames', {'sequence_key', 'phase', 'role', 'from_position', 'is_control'});
    transition.group = phase + "|" + string(fromPosition);
    transition.fold_key = panel_fold(panel, sequenceKey);
    transition.origin = origin;
    transition.target = target;
    transition.conditioning = [origin, stateBlock, surpriseBlock];
end

function block = covariate_block(source, columns, sequenceKey, eventOf, role, rule, kind)

    nRows = numel(sequenceKey);
    block = zeros(nRows, numel(columns));
    if numel(columns) == 0
        return;
    end

    lookupKey = strip_replica(sequenceKey);
    eventKey = strip_replica(eventOf);
    isControl = role == "matched_control";

    sourceKeys = string(source.date_key);
    for c = 1:numel(columns)
        name = char(columns(c));
        if ~ismember(columns(c), string(source.Properties.VariableNames))
            error('STEP28_SBB_COVARIATE_MISSING: %s block lacks column %s.', kind, columns(c));
        end
        values = double(source.(name));
        for i = 1:nRows
            if isControl(i)
                switch rule
                    case "state_and_surprise_zeroed"
                        block(i, c) = 0;
                        continue;
                    case "inherit_matched_event"
                        wanted = eventKey(i);
                    case "state_only"
                        if kind == "surprise"
                            block(i, c) = 0;
                            continue;
                        end
                        wanted = eventKey(i);
                    otherwise
                        error('STEP28_SBB_CONTROL_RULE: unknown rule %s.', rule);
                end
            else
                wanted = lookupKey(i);
            end
            match = find(sourceKeys == wanted, 1);
            if isempty(match)
                error('STEP28_SBB_COVARIATE_LOOKUP: %s has no %s row.', wanted, kind);
            end
            block(i, c) = values(match);
        end
    end

    if any(~isfinite(block), 'all')
        error('STEP28_SBB_COVARIATE_NONFINITE: the %s block is not finite.', kind);
    end
end

function base = strip_replica(keys)
    base = extractBefore(keys, "#");
    missing = ismissing(base);
    base(missing) = keys(missing);
end

function folds = panel_fold(panel, sequenceKey)
    base = strip_replica(sequenceKey);
    dateKey = string(panel.date_key(:));
    foldKey = string(panel.fold_key(:));
    folds = strings(numel(base), 1);
    for i = 1:numel(base)
        match = find(dateKey == base(i), 1);
        if isempty(match)
            error('STEP28_SBB_FOLD_LOOKUP: no fold for %s.', base(i));
        end
        folds(i) = foldKey(match);
    end
end
