function SBB_dirac_gaussian_self_test()
%SBB_DIRAC_GAUSSIAN_SELF_TEST Deterministic tests of the Step-28 SBB core.

    kappa = 3;
    identityResult = SBB_dirac_gaussian_cost(zeros(3, 1), ...
        zeros(3, 1), eye(3), kappa);
    assert(identityResult.total_cost == 0);
    assert(all(identityResult.modes.numerical_branch == "series"));

    % This coefficient is evaluated through the stable branch, independently
    % of the direct c-1 subtraction which the test is meant to guard.
    targetCoefficient = kappa / (4 * (kappa + 2));
    for epsilon = [1e-8, -1e-8]
        nearIdentity = SBB_dirac_gaussian_cost(0, 0, 1 + epsilon, kappa);
        measuredCoefficient = nearIdentity.total_cost / epsilon^2;
        relativeError = abs(measuredCoefficient - targetCoefficient) / ...
            targetCoefficient;
        assert(relativeError < 1e-6, ...
            'Near-identity covariance coefficient failed for epsilon=%g.', ...
            epsilon);
        assert(nearIdentity.modes.numerical_branch == "series");
    end

    % Verify all degree-six coefficients, not only the leading near-identity
    % coefficient.  This guards the removable-ratio Horner implementation.
    lambda = 1 + 1e-4;
    seriesResult = SBB_dirac_gaussian_cost(0, 0, lambda, kappa);
    delta = 1 - seriesResult.modes.P(1);
    expectedRatio = 1 / 2 + (2 / 3) * delta + (3 / 4) * delta^2 + ...
        (4 / 5) * delta^3 + (5 / 6) * delta^4 + ...
        (6 / 7) * delta^5 + (7 / 8) * delta^6;
    assert(abs(seriesResult.modes.ratio(1) - expectedRatio) < 1e-15);

    % Orthogonal rotations preserve the covariance-control cost.
    A = [1, 2, 0; -2, 1, 2; 2, 0, 1];
    [rotation, ~] = qr(A);
    spectrum = diag([2.0, 0.7, 0.2]);
    rotated = rotation * spectrum * rotation';
    diagonalResult = SBB_dirac_gaussian_cost([0; 0; 0], [1; -2; 0.5], ...
        spectrum, 2.5);
    rotatedResult = SBB_dirac_gaussian_cost(rotation * [0; 0; 0], ...
        rotation * [1; -2; 0.5], rotated, 2.5);
    assert(abs(diagonalResult.total_cost - rotatedResult.total_cost) < 1e-12);

    [profile, details] = SBB_cost_profile(zeros(2, 1), [0.2; -0.1], ...
        diag([1.1, 0.8]), [1.25; 2; 5]);
    assert(height(profile) == 3 && numel(details) == 3);
    assert(all(profile.total_cost >= 0));

    crossingLambda = 1 + 1e-4;
    seriesSide = SBB_dirac_gaussian_cost(0, 0, crossingLambda, kappa, 1e-4);
    closedSide = SBB_dirac_gaussian_cost(0, 0, crossingLambda, kappa, 1e-5);
    assert(seriesSide.modes.numerical_branch(1) == "series" && ...
        closedSide.modes.numerical_branch(1) == "closed_form", ...
        'The two tauNum values must select different branches.');
    branchGap = abs(seriesSide.total_cost - closedSide.total_cost) / ...
        seriesSide.total_cost;
    assert(branchGap < 1e-6, ...
        'The series and closed-form branches disagree by %g at the boundary.', ...
        branchGap);

    for degenerateKappa = [1.5, 3, 7]
        limitValue = degenerateKappa / (2 * (degenerateKappa + 1));
        degenerate = SBB_dirac_gaussian_cost(0, 0, 1e-12, degenerateKappa);
        assert(abs(degenerate.volatility_cost - limitValue) < 1e-5, ...
            'The degenerate volatility cost does not approach kappa/(2(kappa+1)).');
        degenerateReference = sqrt((degenerateKappa + 1) * 1e-12);
        assert(abs(degenerate.modes.c(1) - degenerateReference) < ...
            1e-5 * degenerateReference, ...
            'The degenerate mode does not follow c ~ sqrt((kappa+1) lambda).');
    end

    for quadratureKappa = [1.5, 3, 7]
        for quadratureLambda = [0.2, 0.7, 1.3, 3]
            reference = SBB_dirac_gaussian_cost(0, 0, quadratureLambda, ...
                quadratureKappa);
            [quadratureDrift, quadratureVolatility] = bridge_quadrature( ...
                reference.modes.c(1), reference.modes.P(1), ...
                reference.modes.Q(1), quadratureKappa);
            assert(abs(quadratureDrift - reference.drift_cost) < ...
                1e-8 * reference.drift_cost, ...
                'Equation (54) disagrees with the bridge quadrature.');
            assert(abs(quadratureVolatility - reference.volatility_cost) < ...
                1e-8 * reference.volatility_cost, ...
                'Equation (55) disagrees with the bridge quadrature.');
        end
    end

    spread = SBB_dirac_gaussian_cost([0; 0; 0], [0; 0; 0], ...
        diag([20, 1.3, 0.05]), kappa);
    assert(spread.max_root_equation_residual < 1e-13, ...
        'Equation (51) is not satisfied to numerical precision.');

    didFail = false;
    try
        SBB_dirac_gaussian_cost(0, 0, 1, 1);
    catch ME
        didFail = contains(string(ME.message), "SBB_KAPPA_DOMAIN");
    end
    assert(didFail, 'kappa <= 1 must fail closed.');

    fprintf('SBB_dirac_gaussian_self_test passed.\n');
end

function [drift, volatility] = bridge_quadrature(c, P, Q, kappa)

    n = 200000;
    t = ((1:n)' - 0.5) / n;
    Pt = P + t .* (1 - P);
    Qt = Q + t .* (c - Q);
    sigma = Qt ./ Pt;
    v = (Qt .^ 2) .* t ./ (P .* Pt);
    vPrime = (2 .* Qt .* (c - Q) .* t .* Pt + (Qt .^ 2) .* Pt - ...
        (Qt .^ 2) .* t .* (1 - P)) ./ (P .* (Pt .^ 2));
    a = (vPrime - sigma .^ 2) ./ (2 .* v);
    drift = mean(0.5 .* (a .^ 2) .* v);
    volatility = mean(0.5 .* kappa .* (sigma - 1) .^ 2);
end
