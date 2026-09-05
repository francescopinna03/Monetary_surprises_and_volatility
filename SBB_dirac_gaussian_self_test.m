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
    delta = 1e-4;
    lambda = 1 + delta;
    seriesResult = SBB_dirac_gaussian_cost(0, 0, lambda, kappa);
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

    didFail = false;
    try
        SBB_dirac_gaussian_cost(0, 0, 1, 1);
    catch ME
        didFail = contains(string(ME.message), "SBB_KAPPA_DOMAIN");
    end
    assert(didFail, 'kappa <= 1 must fail closed.');

    fprintf('SBB_dirac_gaussian_self_test passed.\n');
end
