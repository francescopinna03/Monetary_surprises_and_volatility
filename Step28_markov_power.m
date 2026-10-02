function result = Step28_markov_power(scoreResult, residual, meetingKey, r2Grid, draws, seed, powerTarget)

    if nargin < 7 || isempty(powerTarget)
        powerTarget = 0.80;
    end
    residual = double(residual);
    meetingKey = string(meetingKey(:));
    r2Grid = double(r2Grid(:))';
    if isempty(r2Grid) || any(r2Grid <= 0) || any(r2Grid >= 1) || any(diff(r2Grid) <= 0)
        error(['STEP28_POWER_GRID: r2Grid must increase strictly inside ' '(0, 1).']);
    end

    basis = scoreResult.basis;
    critical = scoreResult.critical_value;
    energy = sum(residual .^ 2, 'all');
    [meetingIndex, meetings] = findgroups(meetingKey);
    nOutcome = size(residual, 2);
    nDirections = size(basis, 2);

    stream = RandStream('mt19937ar', 'Seed', seed);
    nullResidual = cell(draws, 1);
    for b = 1:draws
        signs = 2 * (rand(stream, numel(meetings), 1) >= 0.5) - 1;
        nullResidual{b} = residual .* signs(meetingIndex);
    end

    worstPower = NaN(numel(r2Grid), 1);
    powerByDirection = NaN(numel(r2Grid), nDirections * nOutcome);
    for q = 1:numel(r2Grid)
        r2 = r2Grid(q);
        amplitude = sqrt(r2 / (1 - r2) * energy);
        column = 0;
        for h = 1:nDirections
            direction = basis(:, h);
            for j = 1:nOutcome
                column = column + 1;
                exceed = 0;
                for b = 1:draws
                    injected = nullResidual{b};
                    injected(:, j) = injected(:, j) + amplitude * direction;
                    statistic = sum((basis' * injected) .^ 2, 'all');
                    exceed = exceed + double(statistic > critical);
                end
                powerByDirection(q, column) = exceed / draws;
            end
        end
        worstPower(q) = min(powerByDirection(q, :));
    end

    reached = find(worstPower >= powerTarget, 1);
    if isempty(reached)
        r280 = NaN;
        status = "above_frozen_grid";
    else
        r280 = r2Grid(reached);
        status = "attained";
    end

    result = struct();
    result.schema_version = "step28_markov_power_v1";
    result.status = status;
    result.r2_80 = r280;
    result.power_target = powerTarget;
    result.r2_grid = r2Grid;
    result.worst_power = worstPower';
    result.n_directions = nDirections;
    result.n_outcome = nOutcome;
    result.profile = table(r2Grid(:), worstPower, 'VariableNames', {'r2', 'worst_sign_power'});
end
