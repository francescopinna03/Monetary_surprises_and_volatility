function [decision, detail] = Step28_gaussian_calibration_gate(design, specification)

    lawOptions = struct('pooling', specification.law_pooling,         'correlationScope', specification.law_correlation_scope,         'penaltyGrid', specification.law_penalty_grid,         'minimumGroupRows', specification.law_minimum_group_rows, 'residualFloor', specification.law_residual_floor);

    scopes = ["PR", "PC"];
    rows = {};
    for s = 1:numel(scopes)
        selected = design.phase == scopes(s);
        eventSelected = selected & design.is_event;
        if sum(eventSelected) <= size(design.conditioning, 2) + 2
            continue;
        end

        isControl = ~design.is_event(selected);
        if specification.law_fit_sample == "controls_only"
            fitMask = isControl;
        else
            fitMask = true(sum(selected), 1);
        end
        if ~any(fitMask) || ~any(isControl)
            continue;
        end

        [~, allStandardised] = Step28_conditional_residuals(             design.conditioning(selected, :), design.group(selected),             design.target(selected, :), design.fold_key(selected), isControl, lawOptions, fitMask);
        isEventWithinScope = design.is_event(selected);
        standardised = allStandardised(isEventWithinScope, :);
        meetingKey = design.meeting_key(eventSelected);

        rank = size(standardised, 2);
        centre = mean(standardised, 1);
        centreError = clustered_mean_error(standardised, meetingKey);
        worstCentre = max(abs(centre) ./ max(centreError, eps));

        second = (standardised' * standardised) / size(standardised, 1);
        covarianceGap = norm(second - eye(rank), 'fro') / sqrt(rank);

        levels = specification.gaussian_coverage_levels;
        mahalanobis = sum(standardised .^ 2, 2);
        empirical = NaN(1, numel(levels));
        for l = 1:numel(levels)
            empirical(l) = mean(mahalanobis <= chi2inv(levels(l), rank));
        end
        worstCoverage = max(abs(empirical - levels));

        passes = worstCentre <= specification.gaussian_mean_tolerance &&             covarianceGap <= specification.gaussian_covariance_tolerance && worstCoverage <= specification.gaussian_coverage_tolerance;

        rows{end + 1} = table(scopes(s), worstCentre, covarianceGap,             worstCoverage, passes, size(standardised, 1),             numel(unique(meetingKey)), strjoin(string(empirical), '|'),             'VariableNames', {'phase', 'worst_standardised_mean_t',             'covariance_gap', 'worst_coverage_error', 'passes', 'n_use', 'g_use', 'empirical_coverage'});
    end

    if isempty(rows)
        error('STEP28_CALIBRATION_EMPTY: no phase has enough rows to diagnose.');
    end
    detail = vertcat(rows{:});

    prRow = detail(detail.phase == "PR", :);
    if isempty(prRow)
        status = "blocked_calibration_gate";
        nextAction = "PR has no usable calibration sample; PR is binding";
    elseif all(detail.passes)
        status = "pass_calibration_gate";
        nextAction = "the empirical SBB profile is authorised";
    else
        status = "blocked_calibration_gate";
        nextAction = "the Gaussian law fails an out-of-sample diagnostic; " + "the cost would be measured against a misstated reference";
    end

    decision = table("step28_gaussian_calibration_gate_v1", string(status),         double(max(detail.worst_standardised_mean_t)),         double(specification.gaussian_mean_tolerance),         double(max(detail.covariance_gap)),         double(specification.gaussian_covariance_tolerance),         double(max(detail.worst_coverage_error)),         double(specification.gaussian_coverage_tolerance),         string(nextAction), string(datetime('now', 'TimeZone', 'UTC'),         'yyyy-MM-dd''T''HH:mm:ssXXX'),         'VariableNames', {'schema_version', 'status',         'worst_standardised_mean_t', 'mean_tolerance', 'worst_covariance_gap',         'covariance_tolerance', 'worst_coverage_error', 'coverage_tolerance', 'next_action', 'generated_at_utc'});
end

function error_ = clustered_mean_error(values, meetingKey)
    [meetingIndex, meetings] = findgroups(meetingKey);
    nMeetings = numel(meetings);
    nRows = size(values, 1);
    centre = mean(values, 1);
    clusterSum = zeros(nMeetings, size(values, 2));
    for m = 1:nMeetings
        clusterSum(m, :) = sum(values(meetingIndex == m, :) - centre, 1);
    end
    meat = sum(clusterSum .^ 2, 1) * (nMeetings / max(nMeetings - 1, 1));
    error_ = sqrt(meat) / nRows;
end
