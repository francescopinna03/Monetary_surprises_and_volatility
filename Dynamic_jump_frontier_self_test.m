function Dynamic_jump_frontier_self_test()
%DYNAMIC_JUMP_FRONTIER_SELF_TEST Deterministic Step-27B contract checks.

    [u, tangent] = Step27b_risk_vectors(deg2rad(31));
    assert(abs(norm(u) - 1) < 1e-12);
    assert(abs(norm(tangent) - 1) < 1e-12);
    assert(abs(u' * tangent) < 1e-12);

    [B, intensity, reactivation] = Step27b_temporal_basis( ...
        [-20; -5; 10; 25; 45]);
    assert(isequal(size(B), [5, 5]));
    assert(all(intensity(1:2) == 0) && all(intensity(3:5) == 1));
    assert(abs(reactivation(3) - 1) < 1e-12);
    assert(reactivation(3) > reactivation(4) && ...
        reactivation(4) > reactivation(5));
    left = Step27b_temporal_basis(-1e-9);
    right = Step27b_temporal_basis(1e-9);
    assert(norm(left - right) < 1e-8, ...
        'Null temporal basis must be continuous at conference time.');

    previous = [0.10, -0.20; -0.15, 0.25; 0.20, 0.10];
    current = [-0.05, 0.30; 0.10, -0.20; -0.25, 0.15];
    Y = Step27b_bipower_matrix(previous, current);
    direct1 = (pi / 2) .* abs(previous(:, 1)) .* abs(current(:, 1));
    direct2 = (pi / 2) .* abs(previous(:, 2)) .* abs(current(:, 2));
    assert(max(abs(Y(:, 1) - direct1)) < 1e-12);
    assert(max(abs(Y(:, 3) - direct2)) < 1e-12);
    plus = (pi / 2) .* abs(previous(:, 1) + previous(:, 2)) .* ...
        abs(current(:, 1) + current(:, 2));
    minus = (pi / 2) .* abs(previous(:, 1) - previous(:, 2)) .* ...
        abs(current(:, 1) - current(:, 2));
    polarized = (plus - minus) ./ 4;
    assert(max(abs(Y(:, 2) ./ sqrt(2) - polarized)) < 1e-12);

    rng(27031, 'twister');
    X = [ones(60, 1), linspace(-1, 1, 60)'];
    [Q, ~] = qr(X, 0);
    g = sin((1:60)' ./ 7);
    gResidual = g - Q * (Q' * g);
    yNull = X * [1; -0.3];
    yAlternative = yNull + 2 .* gResidual;
    statNull = Step27b_partial_statistic(yNull, Q, gResidual);
    statAlternative = Step27b_partial_statistic(yAlternative, Q, gResidual);
    assert(statNull < 1e-10);
    assert(statAlternative > 0.99);

    for rho = [0.1, 0.5, 1.0]
        angle = asin(rho / sqrt(2));
        [rotated, ~] = Step27b_risk_vectors(deg2rad(31) + angle);
        assert(abs(norm(rotated - u) - rho) < 1e-12);
    end

    manifestColumns = table( ...
        ["schema_version"; "bootstrap_draws"], ...
        ["step27a_v1"; "999"], ...
        'VariableNames', {'name', 'value'});
    assert(Step27b_manifest_value(manifestColumns, "schema_version") == ...
        "step27a_v1");
    assert(Step27b_manifest_value(manifestColumns, "bootstrap_draws") == "999");

    manifestRows = table( ...
        ["step27a_v1"; "999"], ...
        'VariableNames', {'value'}, ...
        'RowNames', {'schema_version', 'bootstrap_draws'});
    assert(Step27b_manifest_value(manifestRows, "schema_version") == ...
        "step27a_v1");
    assert(Step27b_manifest_value(manifestRows, "bootstrap_draws") == "999");

    dates = repelem([datetime(2013, 1, 10); datetime(2013, 2, 7)], 2);
    roots = repmat(["fx"; "gg"], 2, 1);
    state = [1.2; -0.4; -0.6; 0.8];
    hike = zeros(4, 1);
    PR = table(dates, roots, state, hike, ...
        'VariableNames', {'event_date', 'root_code', ...
        'pre_state_z', 'regime_hike'});
    PC = PR;
    PC.pre_state_z = PC.pre_state_z + [1e-12; -1e-12; 0; 0];
    eventState = Step27b_event_state(PR, PC);
    assert(height(eventState) == 2);
    assert(max(abs(eventState.pre_state_z - [0.4; 0.1])) < 1e-10);
    assert(max(abs(eventState.pre_state_fx_z - [1.2; -0.6])) < 1e-10);
    assert(max(abs(eventState.pre_state_gg_z - [-0.4; 0.8])) < 1e-10);

    duplicate = PR(1, :);
    duplicate.pre_state_z = duplicate.pre_state_z + 0.25;
    rejectedConflict = false;
    try
        Step27b_event_state([PR; duplicate], PC);
    catch ME
        rejectedConflict = contains(string(ME.message), ...
            "STEP27B_STATE_ROOT_CONFLICT");
    end
    assert(rejectedConflict);

    fprintf(['Dynamic_jump_frontier_self_test: polarized bipower, continuous ' ...
        'null, rank-one risk geometry, partial jump statistics, root-specific ' ...
        'state aggregation and manifest gate compatibility passed.\n']);
end
