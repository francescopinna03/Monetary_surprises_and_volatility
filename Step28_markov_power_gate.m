function [decision, detail] = Step28_markov_power_gate(design, specification)

    lawOptions = struct('pooling', specification.law_pooling,         'correlationScope', specification.law_correlation_scope,         'penaltyGrid', specification.law_penalty_grid,         'minimumGroupRows', specification.law_minimum_group_rows, 'residualFloor', specification.law_residual_floor);

    scopes = ["PR", "PC", "pooled"];
    branches = ["mean", "covariance"];
    rows = {};

    for s = 1:numel(scopes)
        if scopes(s) == "pooled"
            inScope = true(design.n_rows, 1);
        else
            inScope = design.phase == scopes(s);
        end
        eventInScope = inScope & design.is_event;
        if sum(eventInScope) <= size(design.conditioning, 2) + 2
            continue;
        end

        conditioning = design.conditioning(inScope, :);
        group = design.group(inScope);
        target = design.target(inScope, :);
        meetingKey = design.meeting_key(inScope);
        foldKey = design.fold_key(inScope);
        isEvent = design.is_event(inScope);
        isControl = ~isEvent;

        if specification.law_fit_sample == "controls_only"
            fitMask = isControl;
        else
            fitMask = true(sum(inScope), 1);
        end
        if ~any(fitMask) || ~any(isControl)
            continue;
        end

        [~, standardised] = Step28_conditional_residuals(conditioning, group, target, foldKey, isControl, lawOptions, fitMask);

        withoutState = [design.origin(inScope, :), design.surprise(inScope, :)];
        stateBlock = design.state(inScope, :);
        baselineResidual = out_of_fold_linear_residual(withoutState, group, target, foldKey);

        for b = 1:numel(branches)
            if branches(b) == "mean"
                outcome = standardised(isEvent, :);
                historyBlock = design.history(inScope, :);
                historyBlock = historyBlock(isEvent, :);
                benchmarkOutcome = target(isEvent, :);
            else
                outcome = covariance_outcome(standardised(isEvent, :));
                historyBlock = design.history_covariance(inScope, :);
                historyBlock = historyBlock(isEvent, :);
                benchmarkOutcome = centred_outer(baselineResidual(isEvent, :));
            end

            score = Step28_markov_score_test(conditioning(isEvent, :),                 group(isEvent), historyBlock, outcome, meetingKey(isEvent), specification.markov_draws, specification.bootstrap_seed);
            power = Step28_markov_power(score, outcome, meetingKey(isEvent),                 specification.markov_r2_grid, specification.markov_power_draws, specification.bootstrap_seed + 1, 0.80);
            benchmark = Step28_state_partial_r2(withoutState(isEvent, :),                 stateBlock(isEvent, :), group(isEvent), benchmarkOutcome,                 meetingKey(isEvent), foldKey(isEvent),                 specification.markov_benchmark_draws, specification.bootstrap_seed + 2);

            [branchStatus, reason] = branch_verdict(score, power, benchmark);
            rows{end + 1} = table(scopes(s), branches(b), string(branchStatus),                 score.statistic, score.critical_value, score.p_value,                 score.rejects, power.r2_80, string(power.status),                 benchmark.point_estimate, benchmark.lower_bound,                 string(benchmark.status), string(reason),                 score.n_rows, score.n_meetings,                 'VariableNames', {'scope', 'branch', 'status', 'statistic',                 'critical_value', 'p_value', 'rejects', 'r2_80',                 'power_status', 'r2_state_point', 'r2_state_lower', 'benchmark_status', 'reason', 'n_use', 'g_use'});
        end
    end

    if isempty(rows)
        error('STEP28_MARKOV_GATE_EMPTY: no scope has enough rows to calibrate.');
    end
    detail = vertcat(rows{:});

    meanStatus = binding_status(detail, "mean");
    covarianceStatus = binding_status(detail, "covariance");

    if meanStatus == "pass_mean_branch" && covarianceStatus == "pass_covariance_branch"
        status = "pass_markov_power_gate";
        nextAction = "run the Gaussian calibration gate";
    else
        status = "blocked_markov_power_gate";
        nextAction = "the history-free compression fails in at least one " +             "branch; Step 28 stops before the transport and the favourable " + "branch does not reopen the gate";
    end

    decision = table("step28_markov_power_gate_v1", string(status),         string(meanStatus), string(covarianceStatus),         binding_value(detail, "mean", 'r2_80'),         binding_value(detail, "mean", 'r2_state_lower'),         binding_value(detail, "covariance", 'r2_80'),         binding_value(detail, "covariance", 'r2_state_lower'),         string(nextAction), string(datetime('now', 'TimeZone', 'UTC'),         'yyyy-MM-dd''T''HH:mm:ssXXX'),         'VariableNames', {'schema_version', 'status', 'mean_branch_status',         'covariance_branch_status', 'mean_r2_80', 'mean_r2_state_lower',         'covariance_r2_80', 'covariance_r2_state_lower', 'next_action', 'generated_at_utc'});
end

function residual = out_of_fold_linear_residual(covariates, group, target, foldKey)
    [groupIndex, groupNames] = findgroups(group);
    dummies = zeros(numel(groupIndex), numel(groupNames));
    for g = 1:numel(groupNames)
        dummies(:, g) = double(groupIndex == g);
    end
    design = [dummies, covariates];
    folds = unique(foldKey);
    residual = NaN(size(target));
    for f = 1:numel(folds)
        test = foldKey == folds(f);
        train = ~test;
        if sum(train) <= size(design, 2) || ~any(test)
            residual(test, :) = target(test, :);
            continue;
        end
        beta = design(train, :) \ target(train, :);
        residual(test, :) = target(test, :) - design(test, :) * beta;
    end
end

function outcome = centred_outer(residual)
    outcome = covariance_outcome_raw(residual);
    outcome = outcome - mean(outcome, 1);
end

function outcome = covariance_outcome_raw(values)
    [nRows, rank] = size(values);
    pairs = rank * (rank + 1) / 2;
    outcome = zeros(nRows, pairs);
    for i = 1:nRows
        v = values(i, :);
        column = 0;
        for c = 1:rank
            for r = c:rank
                column = column + 1;
                outcome(i, column) = v(r) * v(c);
            end
        end
    end
end

function outcome = covariance_outcome(standardised)
    [nRows, rank] = size(standardised);
    pairs = rank * (rank + 1) / 2;
    outcome = zeros(nRows, pairs);
    identity = eye(rank);
    for i = 1:nRows
        eps = standardised(i, :)';
        M = eps * eps' - identity;
        column = 0;
        for c = 1:rank
            for r = c:rank
                column = column + 1;
                outcome(i, column) = M(r, c);
            end
        end
    end
end

function [status, reason] = branch_verdict(score, power, benchmark)
    if score.rejects
        status = "reject";
        reason = "the history block is not redundant at the calibrated level";
        return;
    end
    if benchmark.status ~= "estimated" || ~isfinite(benchmark.lower_bound) || benchmark.lower_bound <= 0
        status = "insufficient_relative_power";
        reason = "the state benchmark is unavailable or non-positive, so the " + "history-free law is only descriptive";
        return;
    end
    if ~isfinite(power.r2_80) || power.r2_80 > benchmark.lower_bound
        status = "insufficient_relative_power";
        reason = "R2_80 exceeds the conservative state benchmark";
        return;
    end
    status = "pass";
    reason = "the history contributes less than the conservative state " + "benchmark in the calibrated class";
end

function status = binding_status(detail, branch)
    rows = detail.scope == "PR" & detail.branch == branch;
    if ~any(rows)
        status = "unavailable_" + branch + "_branch";
        return;
    end
    if detail.status(rows) == "pass"
        status = "pass_" + branch + "_branch";
    elseif detail.status(rows) == "reject"
        status = "reject_" + branch + "_branch";
    else
        status = "insufficient_power_" + branch + "_branch";
    end
end

function value = binding_value(detail, branch, column)
    rows = detail.scope == "PR" & detail.branch == branch;
    if ~any(rows)
        value = NaN;
        return;
    end
    value = double(detail.(column)(rows));
end
