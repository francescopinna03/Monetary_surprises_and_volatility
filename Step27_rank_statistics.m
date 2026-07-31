function [summary, geometry] = Step27_rank_statistics(deltaLevel, deltaSlope, ...
        shockCovariance, states, referenceDirection)
%STEP27_RANK_STATISTICS Frozen triad for the Step-27A rank-one gate.

    deltaLevel = double(deltaLevel(:));
    deltaSlope = double(deltaSlope(:));
    states = double(states(:));
    referenceDirection = double(referenceDirection(:));
    if numel(referenceDirection) ~= 2 || any(~isfinite(referenceDirection)) || ...
            norm(referenceDirection) <= eps
        error('STEP27_STATS_REFERENCE: reference direction must be nonzero 2-by-1.');
    end
    referenceDirection = referenceDirection / norm(referenceDirection);

    rows = cell(numel(states), 1);
    for j = 1:numel(states)
        G = Step25_phase_geometry(deltaLevel, deltaSlope, ...
            shockCovariance, states(j));
        direction = [G.policy_direction; G.equity_direction];
        cosine = min(1, max(0, abs(direction' * referenceDirection)));
        row = table();
        row.state = states(j);
        row.leading_eigenvalue = G.leading_eigenvalue;
        row.secondary_eigenvalue = G.secondary_eigenvalue;
        row.leading_absolute_share = G.leading_absolute_share;
        row.secondary_absolute_share = 1 - G.leading_absolute_share;
        row.policy_direction = G.policy_direction;
        row.equity_direction = G.equity_direction;
        row.angle_degrees = G.angle_degrees;
        row.projective_deviation_degrees = acosd(cosine);
        row.sector = G.sector;
        rows{j} = row;
    end
    geometry = vertcat(rows{:});

    summary = struct();
    summary.max_abs_secondary = max(abs(geometry.secondary_eigenvalue));
    summary.max_secondary_share = max(geometry.secondary_absolute_share);
    summary.max_direction_deviation_degrees = ...
        max(geometry.projective_deviation_degrees);
    summary.all_states_mp_like = all(geometry.sector == "MP_LIKE");
    summary.all_leading_negative = all(geometry.leading_eigenvalue < 0);
end
