function Step28_gates_self_test()

    test_spectral_rank();
    test_calibration_generator();
    test_sample_size_calibration();
    test_sample_size_gate();
    test_markov_design();
    test_score_test();
    test_power_and_benchmark();
    test_markov_power_gate();
    test_gaussian_gate();

    fprintf('Step28_gates_self_test passed.\n');
end

function test_markov_power_gate()
    specification = gate_specification();
    specification.markov_draws = 99;
    specification.markov_power_draws = 99;
    specification.markov_benchmark_draws = 99;
    specification.markov_r2_grid = [0.02, 0.05, 0.10, 0.25, 0.50];
    specification.bootstrap_seed = 7301;

    design = synthetic_design(53, 1.0);
    [decision, detail] = Step28_markov_power_gate(design, specification);
    assert(height(decision) == 1 && height(detail) == 6, 'The complete Markov gate must return one decision and six diagnostics.');
    assert(all(ismember(["PR", "PC", "pooled"], unique(detail.scope))));
    assert(all(ismember(["mean", "covariance"], unique(detail.branch))));
    assert(ismember(decision.status(1), ["pass_markov_power_gate", "blocked_markov_power_gate"]));
    assert(strlength(decision.mean_branch_status(1)) > 0 && strlength(decision.covariance_branch_status(1)) > 0);
end

function test_spectral_rank()
    [levels, position, dateKey] = ar_panel(11, 120, 4, 3, 1, 0.9);
    options = struct('seed', 11, 'parallelDraws', 79);
    verdict = Step28_spectral_rank(levels, position, dateKey, options);
    assert(verdict.status == "low_rank_accepted" && verdict.accepted_rank == 1,         'A single persistent factor must be accepted as rank one, got %s (%g).', verdict.status, verdict.accepted_rank);

    [flatLevels, flatPosition, flatDates] = ar_panel(12, 120, 4, 3, 1, 0.0);
    flat = Step28_spectral_rank(flatLevels, flatPosition, flatDates, options);
    assert(flat.status ~= "low_rank_accepted" &&         flat.status ~= "full_rank_terminal", 'White increments must not be labeled low rank or full rank.');
    if flat.parallel_rank == 0
        assert(flat.status == "no_signal_terminal", 'parallel_rank zero must map to no_signal_terminal.');
    end

    [controlLevels, controlPosition, controlDates] = ar_panel(13, 180, 4, 3, 1, 0.0);
    controlOptions = options;
    controlOptions.controlLevels = controlLevels;
    controlOptions.controlPosition = controlPosition;
    controlOptions.controlDateKey = controlDates;
    controlled = Step28_spectral_rank(levels, position, dateKey, controlOptions);
    assert(controlled.null_source == "exact_clock_controls");
    assert(controlled.status == "low_rank_accepted" &&         controlled.accepted_rank == 1, 'A persistent event factor must clear the exact-clock control null.');

    [twoLevels, twoPosition, twoDates] = ar_panel(14, 200, 5, 3, 2, 0.9);
    [twoNullLevels, twoNullPosition, twoNullDates] = ar_panel(15, 300, 5, 3, 2, 0.0);
    twoOptions = options;
    twoOptions.controlLevels = twoNullLevels;
    twoOptions.controlPosition = twoNullPosition;
    twoOptions.controlDateKey = twoNullDates;
    two = Step28_spectral_rank(twoLevels, twoPosition, twoDates, twoOptions);
    assert(two.status == "low_rank_accepted" && two.accepted_rank == 2,         'Two persistent factors must be accepted as rank two, got %s (%g).', two.status, two.accepted_rank);

    assert_error(@() Step28_spectral_rank(levels, position, dateKey, struct()), "STEP28_RANK_SEED");
end

function test_calibration_generator()
    calibration = Step28_sample_size_calibration(struct(         'meetingGrid', [20, 40], 'frontierEigengap', 1.0,         'projectorTolerance', 0.9, 'trueRank', 1, 'positions', 5, 'replications', 5, 'parallelDraws', 19, 'seed', 5));
    assert(calibration.induced_rho > 0 && calibration.induced_rho < 1);

    levels = ar_panel(7, 4000, 5, 3, 1, calibration.induced_rho);
    Omega = (levels' * levels) / size(levels, 1);
    eigenvalues = sort(real(eig(Omega)), 'descend');
    realised = eigenvalues(1) - eigenvalues(2);
    assert(abs(realised - 1.0) < 0.15, 'The solved rho does not reproduce the frozen eigengap: %g.', realised);

    assert_error(@() Step28_sample_size_calibration(struct('meetingGrid', 20)), "STEP28_CALIBRATION_UNFROZEN");
    assert_error(@() Step28_sample_size_calibration(struct('meetingGrid', 20,         'frontierEigengap', 1e6, 'projectorTolerance', 0.5, 'trueRank', 1, 'seed', 1)), "STEP28_CALIBRATION_UNREACHABLE");
end

function test_sample_size_calibration()
    calibration = Step28_sample_size_calibration(struct(         'meetingGrid', [15, 60], 'frontierEigengap', 1.2,         'projectorTolerance', 0.7, 'trueRank', 1, 'positions', 5, 'replications', 24, 'parallelDraws', 19, 'seed', 21));
    assert(height(calibration.profile) == 2);
    assert(all(calibration.profile.rank_recovery_monotone_floor <= calibration.profile.rank_recovery + 1e-12));
    assert(all(calibration.profile.projector_distance_monotone_ceiling >= calibration.profile.projector_distance_quantile - 1e-12));
    assert(all(diff(calibration.profile.rank_recovery_monotone_floor) >= -1e-12));
    assert(all(diff(calibration.profile.projector_distance_monotone_ceiling) <= 1e-12));
    assert(all(diff(double(calibration.profile.passes)) >= 0), 'Once the conservative calibration passes, every larger G must pass.');

    impossible = Step28_sample_size_calibration(struct(         'meetingGrid', [15, 60], 'frontierEigengap', 1.2,         'projectorTolerance', 1e-5, 'trueRank', 1, 'positions', 5, 'replications', 8, 'parallelDraws', 19, 'seed', 22));
    assert(impossible.status == "no_admissible_G_on_the_frozen_grid" &&         isnan(impossible.minimum_meetings), 'An unattainable tau_P must leave G_min^spec undefined.');
end

function test_sample_size_gate()
    panel = synthetic_gate_panel(31, 30, 20);
    calibration = struct('minimum_meetings', 25, 'status', "calibrated", 'frontier_eigengap', 1.2, 'projector_tolerance', 0.7, 'seed', 1);

    [decision, counts] = Step28_sample_size_gate(panel, calibration, 1);
    prRow = counts(counts.phase == "PR", :);
    assert(prRow.n_transitions_before_lag == 30 * 4);
    assert(prRow.n_use == 30 * 3 && prRow.g_use == 30,         'Equation (26) is not reproduced: N_use %g, G_use %g.', prRow.n_use, prRow.g_use);
    assert(decision.status(1) == "pass_sample_size_gate");

    demanding = calibration;
    demanding.minimum_meetings = 45;
    blocked = Step28_sample_size_gate(panel, demanding, 1);
    assert(blocked.status(1) == "blocked_sample_size_gate", 'A G_use below G_min^spec must block the gate.');

    unavailable = calibration;
    unavailable.status = "no_admissible_G_on_the_frozen_grid";
    unavailable.minimum_meetings = NaN;
    noCalibration = Step28_sample_size_gate(panel, unavailable, 1);
    assert(noCalibration.status(1) == "blocked_calibration_not_available");
end

function test_markov_design()
    panel = synthetic_gate_panel(32, 12, 8);
    [levels, meta] = Step28_whitened_levels(panel, 6);
    state = randn_block(meta, 2, 41);
    surprise = randn_block(meta, 2, 42);

    design = Step28_markov_design(levels, meta, 2, 1, state, surprise);
    events = numel(unique(meta.date_key(meta.role == "event")));
    allDates = numel(unique(meta.date_key));
    perDate = (5 - 1 - 1) + (9 - 1 - 1);
    assert(design.n_use == events * perDate, 'N_use is %d, expected %d.', design.n_use, events * perDate);
    assert(design.n_rows == allDates * perDate, 'The design must also carry the control transitions.');
    assert(design.g_use == events && events == 12, 'The design must cluster on the twelve event dates, got %d.', events);
    assert(size(design.history, 2) == 2, 'One lag of a rank-two factor is two columns.');
    assert(size(design.history_covariance, 2) == 3, 'The covariance dictionary of a rank-two factor has three columns.');
    assert(sum(design.is_event) == design.n_use);

    noLag = Step28_markov_design(levels, meta, 2, 0, state, surprise);
    assert(noLag.n_use > design.n_use, 'A larger lag must remove rows.');

    assert(norm(design.history_covariance(:, 1) - design.history(:, 1)) > 1e-6, 'The covariance branch must not receive the linear history block.');
end

function test_score_test()
    stream = RandStream('mt19937ar', 'Seed', 4242);
    n = 600;
    meetings = "m" + string(mod(0:n - 1, 60) + 1)';
    group = repmat("PR|1", n, 1);
    X = randn(stream, n, 2);
    H = randn(stream, n, 2);

    nullOutcome = randn(stream, n, 2);
    nullResult = Step28_markov_score_test(X, group, H, nullOutcome, meetings, 299, 7);
    assert(nullResult.p_value > 0.05,         'The score test rejects an independent history block, p = %g.', nullResult.p_value);

    alternative = 1.5 * H + 0.3 * randn(stream, n, 2);
    alternativeResult = Step28_markov_score_test(X, group, H, alternative, meetings, 299, 7);
    assert(alternativeResult.rejects && alternativeResult.p_value < 0.05, 'The score test misses a strong history dependence.');

    assert_error(@() Step28_markov_score_test(X, group, X, nullOutcome, meetings, 99, 7), "STEP28_SCORE_HISTORY_SPANNED");
end

function test_power_and_benchmark()
    stream = RandStream('mt19937ar', 'Seed', 909);
    n = 400;
    meetings = "m" + string(mod(0:n - 1, 40) + 1)';
    group = repmat("PR|1", n, 1);
    folds = "y" + string(mod(0:n - 1, 4) + 1)';
    X = randn(stream, n, 2);
    H = randn(stream, n, 2);
    outcome = randn(stream, n, 2);

    score = Step28_markov_score_test(X, group, H, outcome, meetings, 199, 3);
    power = Step28_markov_power(score, outcome, meetings, [0.02, 0.05, 0.10, 0.25, 0.50], 199, 4, 0.80);
    assert(all(diff(power.worst_power) >= -0.05), 'The worst-sign power curve must be essentially monotone in R2.');
    assert(power.worst_power(end) >= power.worst_power(1));
    if isfinite(power.r2_80)
        assert(ismember(power.r2_80, power.r2_grid));
    else
        assert(power.status == "above_frozen_grid");
    end

    state = randn(stream, n, 2);
    target = 0.8 * state + 0.2 * randn(stream, n, 2);
    benchmark = Step28_state_partial_r2(X, state, group, target, meetings, folds, 199, 5);
    assert(benchmark.point_estimate > 0.5,         'A dominant state block must show a large partial R2, got %g.', benchmark.point_estimate);
    assert(benchmark.status == "estimated");
    assert(benchmark.lower_bound < benchmark.point_estimate, 'The bootstrap lower bound must lie below the point estimate.');

    irrelevant = Step28_state_partial_r2(X, randn(stream, n, 2), group, randn(stream, n, 2), meetings, folds, 199, 6);
    assert(irrelevant.lower_bound < 0.05, 'An irrelevant state block must not clear a positive benchmark.');
end

function test_gaussian_gate()
    specification = gate_specification();

    correct = synthetic_design(51, 1.0);
    [decision, detail] = Step28_gaussian_calibration_gate(correct, specification);
    assert(decision.status(1) == "pass_calibration_gate", 'A correctly specified law must pass, got %s.', decision.status(1));
    assert(height(detail) == 2);

    misstated = synthetic_design(52, 2.2);
    wrong = Step28_gaussian_calibration_gate(misstated, specification);
    assert(wrong.status(1) == "blocked_calibration_gate", 'A misstated spread must block the calibration gate.');

    controlsOnly = specification;
    controlsOnly.law_fit_sample = "controls_only";
    assert_error(@() Step28_gaussian_calibration_gate(correct, controlsOnly), "STEP28_LAW_RANK_DEFICIENT");
end

function specification = gate_specification()
    specification = struct();
    specification.law_pooling = "group_intercept_pooled_slopes";
    specification.law_correlation_scope = "pooled";
    specification.law_penalty_grid = [0, 0.1];
    specification.law_minimum_group_rows = 20;
    specification.law_residual_floor = 1e-8;
    specification.gaussian_mean_tolerance = 3.0;
    specification.gaussian_covariance_tolerance = 0.25;
    specification.gaussian_coverage_levels = [0.5, 0.8, 0.9, 0.95];
    specification.gaussian_coverage_tolerance = 0.08;
    specification.law_fit_sample = "pooled";
end

function design = synthetic_design(seed, tailScale)
    stream = RandStream('mt19937ar', 'Seed', seed);
    nMeetings = 90;
    nControls = 60;
    phases = ["PR", "PC"];
    positions = struct('PR', 1:3, 'PC', 1:3);
    slope = [0.35, -0.15; -0.20, 0.30];

    origin = zeros(0, 2);
    target = zeros(0, 2);
    group = strings(0, 1);
    meetingKey = strings(0, 1);
    foldKey = strings(0, 1);
    phaseOut = strings(0, 1);
    stateBlock = zeros(0, 1);
    surpriseBlock = zeros(0, 1);
    isEvent = false(0, 1);

    total = nMeetings + nControls;
    for e = 1:total
        thisIsEvent = e <= nMeetings;
        if thisIsEvent
            stateValue = randn(stream);
            surpriseValue = randn(stream);
        else
            stateValue = 0;
            surpriseValue = 0;
        end
        for p = 1:numel(phases)
            for k = positions.(phases(p))
                z = randn(stream, 1, 2);
                noise = randn(stream, 1, 2);
                if thisIsEvent && rand(stream) < 0.10
                    noise = noise * tailScale;
                end
                origin(end + 1, :) = z;
                target(end + 1, :) = z * slope + 0.4 * stateValue + noise;
                group(end + 1, 1) = phases(p) + "|" + string(k);
                meetingKey(end + 1, 1) = "m" + string(e);
                foldKey(end + 1, 1) = "y" + string(mod(e, 5) + 1);
                phaseOut(end + 1, 1) = phases(p);
                stateBlock(end + 1, 1) = stateValue;
                surpriseBlock(end + 1, 1) = surpriseValue;
                isEvent(end + 1, 1) = thisIsEvent;
            end
        end
    end

    nRows = size(origin, 1);
    design = struct();
    design.rank = 2;
    design.origin = origin;
    design.target = target;
    design.state = stateBlock;
    design.surprise = surpriseBlock;
    design.conditioning = [origin, stateBlock, surpriseBlock];
    design.group = group;
    design.meeting_key = meetingKey;
    design.fold_key = foldKey;
    design.phase = phaseOut;
    design.is_event = isEvent;
    design.history = randn(stream, nRows, 2);
    design.history_covariance = randn(stream, nRows, 3);
    design.n_rows = nRows;
    design.n_use = sum(isEvent);
    design.g_use = nMeetings;
end

function [levels, position, dateKey] = ar_panel(seed, nMeetings, positions, dimension, trueRank, rho)
    stream = RandStream('mt19937ar', 'Seed', seed);
    rows = nMeetings * positions;
    levels = zeros(rows, dimension);
    position = zeros(rows, 1);
    dateKey = strings(rows, 1);
    row = 0;
    for e = 1:nMeetings
        previous = randn(stream, 1, trueRank);
        factor = zeros(positions, trueRank);
        for k = 1:positions
            previous = rho * previous + sqrt(1 - rho ^ 2) * randn(stream, 1, trueRank);
            factor(k, :) = previous;
        end
        increment = [factor, randn(stream, positions, dimension - trueRank)];
        level = cumsum(increment, 1);
        for k = 1:positions
            row = row + 1;
            levels(row, :) = level(k, :);
            position(row) = k;
            dateKey(row) = "s" + string(e);
        end
    end
end

function panel = synthetic_gate_panel(seed, nEvents, nControls)
    stream = RandStream('mt19937ar', 'Seed', seed);
    phases = ["PR", "PC"];
    positions = struct('PR', 1:5, 'PC', 1:9);
    keys = ["E" + string(1:nEvents), "C" + string(1:nControls)]';
    roles = [repmat("event", nEvents, 1); repmat("matched_control", nControls, 1)];
    folds = "y" + string(mod(0:numel(keys) - 1, 4) + 1)';

    dateKey = strings(0, 1);
    role = strings(0, 1);
    phase = strings(0, 1);
    position = zeros(0, 1);
    foldKey = strings(0, 1);
    returns = zeros(0, 3);
    for i = 1:numel(keys)
        for p = 1:numel(phases)
            for k = positions.(phases(p))
                dateKey(end + 1, 1) = keys(i);
                role(end + 1, 1) = roles(i);
                phase(end + 1, 1) = phases(p);
                position(end + 1, 1) = k;
                foldKey(end + 1, 1) = folds(i);
                returns(end + 1, :) = randn(stream, 1, 3);
            end
        end
    end

    linkEvent = strings(0, 1);
    linkPhase = strings(0, 1);
    linkControl = strings(0, 1);
    linkWeight = zeros(0, 1);
    for e = 1:nEvents
        chosen = "C" + string(mod((e - 1) * 3 + (0:2), nControls) + 1);
        for p = 1:numel(phases)
            for c = 1:numel(chosen)
                linkEvent(end + 1, 1) = "E" + string(e);
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
    panel.links = table(linkEvent, linkPhase, linkControl, linkWeight, 'VariableNames', {'event_key', 'phase', 'control_key', 'weight'});
end

function block = randn_block(meta, width, seed)
    stream = RandStream('mt19937ar', 'Seed', seed);
    dates = unique(meta.date_key);
    values = randn(stream, numel(dates), width);
    block = zeros(numel(meta.date_key), width);
    for i = 1:numel(meta.date_key)
        block(i, :) = values(meta.date_key(i) == dates, :);
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
