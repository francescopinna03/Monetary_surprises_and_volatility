function Rank_one_feasibility_self_test()
%RANK_ONE_FEASIBILITY_SELF_TEST Deterministic Step-27A checks.

    rng(27020, 'twister');
    covariance = [1.30, 0.18; 0.18, 0.75];
    [vectors, values] = eig((covariance + covariance') / 2);
    inverseRoot = vectors * diag(1 ./ sqrt(diag(values))) * vectors';

    theta = deg2rad(120);
    w = [cos(theta); sin(theta)];
    A = inverseRoot * (w * w') * inverseRoot;
    h = [A(1, 1); A(2, 2); A(1, 2)];

    base = ["Intercept", "q_policy", "q_equity", ...
        "q_policy_equity", "pre_state_z", "q_policy_x_pre", ...
        "q_equity_x_pre", "q_policy_equity_x_pre", ...
        "regime_hike", "root_gg"];
    termNames = ["PR_" + base, "PC_" + base]';
    n = 500;
    X = randn(n, numel(termNames));
    X(:, termNames == "PR_Intercept" | termNames == "PC_Intercept") = ...
        randn(n, 2);
    beta = 0.15 * randn(numel(termNames), 1);
    level = ["q_policy", "q_equity", "q_policy_equity"];
    slope = ["q_policy_x_pre", "q_equity_x_pre", ...
        "q_policy_equity_x_pre"];
    for j = 1:3
        beta(termNames == "PC_" + level(j)) = ...
            beta(termNames == "PR_" + level(j)) - 0.80 * h(j);
        beta(termNames == "PC_" + slope(j)) = ...
            beta(termNames == "PR_" + slope(j)) - 0.18 * h(j);
    end
    y = X * beta;

    nullFit = Step27_rank_one_null_fit(y, X, termNames, covariance, 5);
    assert(nullFit.sse < 1e-16 * max(1, y' * y), ...
        'STEP27_SELFTEST_NULL_FIT: exact rank-one null was not recovered.');

    [squareVectors, squareValues] = eig((covariance + covariance') / 2);
    squareRoot = squareVectors * diag(sqrt(diag(squareValues))) * squareVectors';
    expectedDirection = squareRoot * w;
    expectedDirection = expectedDirection / norm(expectedDirection);
    assert(abs(abs(expectedDirection' * nullFit.reference_direction) - 1) < 1e-8, ...
        'STEP27_SELFTEST_DIRECTION: common direction was not recovered.');
    assert(nullFit.reference_sector == "MP_LIKE", ...
        'STEP27_SELFTEST_SECTOR: known MP-like direction was misclassified.');

    deltaLevel = -0.80 * h;
    deltaSlope = -0.18 * h;
    [rankOneStats, geometry] = Step27_rank_statistics(deltaLevel, ...
        deltaSlope, covariance, [-1, 0, 1], nullFit.reference_direction);
    assert(rankOneStats.max_abs_secondary < 1e-10 && ...
        rankOneStats.max_secondary_share < 1e-10 && ...
        rankOneStats.max_direction_deviation_degrees < 1e-5 && ...
        rankOneStats.all_states_mp_like && height(geometry) == 3, ...
        'STEP27_SELFTEST_STATS: exact rank-one statistics are not zero/stable.');

    orthogonal = [-w(2); w(1)];
    A2 = inverseRoot * (orthogonal * orthogonal') * inverseRoot;
    h2 = [A2(1, 1); A2(2, 2); A2(1, 2)];
    alternativeLevel = deltaLevel + 0.30 * h2;
    [alternativeStats, ~] = Step27_rank_statistics(alternativeLevel, ...
        deltaSlope, covariance, [-1, 0, 1], nullFit.reference_direction);
    assert(alternativeStats.max_abs_secondary > 0.20 && ...
        alternativeStats.max_secondary_share > 0.15, ...
        'STEP27_SELFTEST_ALTERNATIVE: a genuine second mode was not detected.');

    fprintf(['Rank_one_feasibility_self_test: constrained null, estimated ' ...
        'direction, rank triad and second-mode checks passed.\n']);
end
