function calibration = Step28_sample_size_calibration(options)

    options = validate_options(options);

    ranks = options.trueRank;
    if numel(ranks) > 1
        perRank = cell(numel(ranks), 1);
        minima = NaN(numel(ranks), 1);
        for j = 1:numel(ranks)
            single = options;
            single.trueRank = ranks(j);
            perRank{j} = Step28_sample_size_calibration(single);
            minima(j) = perRank{j}.minimum_meetings;
            perRank{j}.profile.true_rank = repmat(ranks(j), height(perRank{j}.profile), 1);
        end
        calibration = perRank{end};
        calibration.true_rank = ranks;
        profiles = cell(numel(ranks), 1);
        for j = 1:numel(ranks)
            profiles{j} = perRank{j}.profile;
        end
        calibration.profile = vertcat(profiles{:});
        if any(~isfinite(minima))
            calibration.minimum_meetings = NaN;
            calibration.status = "no_admissible_G_on_the_frozen_grid";
        else
            calibration.minimum_meetings = max(minima);
            calibration.status = "calibrated";
        end
        calibration.minimum_by_rank = minima';
        return;
    end

    dimension = options.dimension;
    positions = options.positions;
    rho = solve_rho_for_eigengap(options.frontierEigengap, positions, options.rhoBracket);

    basis = eye(dimension);
    factorBasis = basis(:, 1:options.trueRank);
    trueProjector = factorBasis * factorBasis';

    grid = options.meetingGrid;
    nGrid = numel(grid);
    recovery = NaN(nGrid, 1);
    projectorQuantile = NaN(nGrid, 1);
    medianProjector = NaN(nGrid, 1);
    statusCounts = zeros(nGrid, 4);

    stream = RandStream('mt19937ar', 'Seed', options.seed);
    for g = 1:nGrid
        nMeetings = grid(g);
        fprintf('Synthetic calibration: rank %d, G=%d, %d replications\n', options.trueRank, nMeetings, options.replications);
        recovered = false(options.replications, 1);
        distances = NaN(options.replications, 1);
        for s = 1:options.replications
            [levels, position, dateKey] = simulate_panel(stream, nMeetings, positions, dimension, options.trueRank, rho);
            rankOptions = struct('seed', randi(stream, 2^31 - 1),                 'parallelDraws', options.parallelDraws,                 'parallelQuantile', options.parallelQuantile, 'reconstructionFolds', options.reconstructionFolds);
            verdict = Step28_spectral_rank(levels, position, dateKey, rankOptions);

            switch verdict.status
                case "low_rank_accepted"
                    statusCounts(g, 1) = statusCounts(g, 1) + 1;
                case "full_rank_terminal"
                    statusCounts(g, 2) = statusCounts(g, 2) + 1;
                case "no_signal_terminal"
                    statusCounts(g, 3) = statusCounts(g, 3) + 1;
                otherwise
                    statusCounts(g, 4) = statusCounts(g, 4) + 1;
            end
            recovered(s) = verdict.accepted_rank == options.trueRank;

            subspace = Step28_factor_subspace(levels, options.trueRank);
            distances(s) = Step28_projector_distance(subspace.projector, trueProjector);
        end
        recovery(g) = mean(recovered);
        projectorQuantile(g) = quantile(distances, options.projectorQuantile);
        medianProjector(g) = median(distances);
    end

    recoveryFloor = flipud(cummin(flipud(recovery)));
    projectorCeiling = flipud(cummax(flipud(projectorQuantile)));
    passes = recoveryFloor >= options.recoveryTarget & projectorCeiling <= options.projectorTolerance;
    firstPass = find(passes, 1);
    if isempty(firstPass)
        minimumMeetings = NaN;
        status = "no_admissible_G_on_the_frozen_grid";
    else
        minimumMeetings = grid(firstPass);
        status = "calibrated";
    end

    profile = table(grid(:), recovery, recoveryFloor, medianProjector,         projectorQuantile, projectorCeiling, passes, statusCounts(:, 1),         statusCounts(:, 2), statusCounts(:, 3), statusCounts(:, 4),         'VariableNames', {'n_meetings', 'rank_recovery',         'rank_recovery_monotone_floor', 'median_projector_distance',         'projector_distance_quantile',         'projector_distance_monotone_ceiling', 'passes',         'n_low_rank_accepted', 'n_full_rank_terminal', 'n_no_signal_terminal', 'n_unstable_subspace'});

    calibration = struct();
    calibration.schema_version = "step28_sample_size_calibration_v2";
    calibration.status = status;
    calibration.minimum_meetings = minimumMeetings;
    calibration.true_rank = options.trueRank;
    calibration.dimension = dimension;
    calibration.positions = positions;
    calibration.frontier_eigengap = options.frontierEigengap;
    calibration.induced_rho = rho;
    calibration.projector_tolerance = options.projectorTolerance;
    calibration.recovery_target = options.recoveryTarget;
    calibration.replications = options.replications;
    calibration.seed = options.seed;
    calibration.profile = profile;
end

function options = validate_options(options)
    required = ["meetingGrid", "frontierEigengap", "projectorTolerance", "trueRank", "seed"];
    missing = required(~isfield(options, required));
    if ~isempty(missing)
        error(['STEP28_CALIBRATION_UNFROZEN: %s must be frozen before the ' 'run and has no default.'], strjoin(missing, ', '));
    end
    options.trueRank = double(options.trueRank(:))';
    options.meetingGrid = double(options.meetingGrid(:))';
    if any(options.meetingGrid < 4) || any(diff(options.meetingGrid) <= 0)
        error(['STEP28_CALIBRATION_GRID: meetingGrid must increase strictly ' 'from at least four meetings.']);
    end
    if ~isscalar(options.frontierEigengap) || options.frontierEigengap <= 0
        error('STEP28_CALIBRATION_EIGENGAP: frontierEigengap must be positive.');
    end
    if ~isscalar(options.projectorTolerance) || options.projectorTolerance <= 0 || options.projectorTolerance >= 1
        error('STEP28_CALIBRATION_TAU_P: projectorTolerance must lie in (0,1).');
    end
    options = default_field(options, 'dimension', 3);
    options = default_field(options, 'positions', 5);
    options = default_field(options, 'replications', 200);
    options = default_field(options, 'recoveryTarget', 0.80);
    options = default_field(options, 'projectorQuantile', 0.95);
    options = default_field(options, 'parallelDraws', 99);
    options = default_field(options, 'parallelQuantile', 0.95);
    options = default_field(options, 'reconstructionFolds', 5);
    options = default_field(options, 'rhoBracket', [1e-6, 0.999]);
    if isempty(options.trueRank) || any(options.trueRank < 1) ||             any(options.trueRank >= options.dimension) ||             any(options.trueRank ~= floor(options.trueRank)) || numel(unique(options.trueRank)) ~= numel(options.trueRank)
        error(['STEP28_CALIBRATION_RANK: trueRank must be distinct integer ' 'low ranks, each strictly below the dimension.']);
    end
end

function options = default_field(options, name, value)
    if ~isfield(options, name) || isempty(options.(name))
        options.(name) = value;
    end
end

function gap = eigengap_of_rho(rho, positions)
    factorVariance = 0;
    for k = 1:positions
        value = k;
        for m = 1:k - 1
            value = value + 2 * (k - m) * rho ^ m;
        end
        factorVariance = factorVariance + value;
    end
    factorVariance = factorVariance / positions;
    complementVariance = (positions + 1) / 2;
    gap = factorVariance - complementVariance;
end

function rho = solve_rho_for_eigengap(targetGap, positions, bracket)
    lower = bracket(1);
    upper = bracket(2);
    if eigengap_of_rho(upper, positions) < targetGap
        error(['STEP28_CALIBRATION_UNREACHABLE: the frontier eigengap %g '             'exceeds what %d positions can induce (max %g).'], targetGap, positions, eigengap_of_rho(upper, positions));
    end
    for iteration = 1:200
        middle = (lower + upper) / 2;
        if eigengap_of_rho(middle, positions) < targetGap
            lower = middle;
        else
            upper = middle;
        end
    end
    rho = (lower + upper) / 2;
end

function [levels, position, dateKey] = simulate_panel(stream, nMeetings, positions, dimension, trueRank, rho)
    rows = nMeetings * positions;
    levels = zeros(rows, dimension);
    position = zeros(rows, 1);
    dateKey = strings(rows, 1);
    row = 0;
    for e = 1:nMeetings
        factor = zeros(positions, trueRank);
        previous = randn(stream, 1, trueRank);
        for k = 1:positions
            innovation = randn(stream, 1, trueRank);
            previous = rho * previous + sqrt(1 - rho ^ 2) * innovation;
            factor(k, :) = previous;
        end
        complement = randn(stream, positions, dimension - trueRank);
        increment = [factor, complement];
        level = cumsum(increment, 1);
        for k = 1:positions
            row = row + 1;
            levels(row, :) = level(k, :);
            position(row) = k;
            dateKey(row) = "s" + string(e);
        end
    end
end
