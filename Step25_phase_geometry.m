function G = Step25_phase_geometry(deltaLevel, deltaSlope, shockCovariance, state)
%STEP25_PHASE_GEOMETRY Rotation-invariant geometry of a quadratic phase gap.
%
% The quadratic response difference is
%   x' * (A_level + state * A_slope) * x,
% where x contains the policy indicator and the equity surprise.  Directions
% are evaluated on the one-standard-deviation ellipsoid induced by the pooled
% shock covariance.  This makes the eigenvalues invariant to nonsingular
% linear reparameterisations of the two observed surprises.

    deltaLevel = double(deltaLevel(:));
    deltaSlope = double(deltaSlope(:));
    shockCovariance = double(shockCovariance);
    validateattributes(deltaLevel, {'numeric'}, {'numel', 3, 'finite'});
    validateattributes(deltaSlope, {'numeric'}, {'numel', 3, 'finite'});
    validateattributes(shockCovariance, {'numeric'}, ...
        {'size', [2, 2], 'finite', 'real'});
    validateattributes(state, {'numeric'}, {'scalar', 'finite', 'real'});

    shockCovariance = (shockCovariance + shockCovariance') / 2;
    [vectors, values] = eig(shockCovariance);
    covarianceEigenvalues = real(diag(values));
    tolerance = 1e-12 * max(1, max(abs(covarianceEigenvalues)));
    if any(covarianceEigenvalues < -tolerance) || ...
            sum(covarianceEigenvalues > tolerance) < 2
        error('STEP25_SHOCK_COVARIANCE: covariance must be positive definite.');
    end
    covarianceEigenvalues = max(covarianceEigenvalues, 0);
    squareRoot = vectors * diag(sqrt(covarianceEigenvalues)) * vectors';

    delta = deltaLevel + state * deltaSlope;
    responseMatrix = [delta(1), delta(3); delta(3), delta(2)];
    whitenedMatrix = squareRoot * responseMatrix * squareRoot;
    whitenedMatrix = (whitenedMatrix + whitenedMatrix') / 2;
    [eigenvectors, eigenvaluesMatrix] = eig(whitenedMatrix);
    eigenvalues = real(diag(eigenvaluesMatrix));
    [~, order] = sort(abs(eigenvalues), 'descend');
    eigenvalues = eigenvalues(order);
    eigenvectors = real(eigenvectors(:, order));

    direction = squareRoot * eigenvectors(:, 1);
    if direction(1) < 0
        direction = -direction;
    end
    direction = direction / norm(direction);
    angle = atan2d(direction(2), direction(1));
    if direction(1) * direction(2) < 0
        sector = "MP_LIKE";
    elseif direction(1) * direction(2) > 0
        sector = "CBI_LIKE";
    else
        sector = "BOUNDARY";
    end

    denominator = sum(abs(eigenvalues));
    if denominator <= eps
        share = NaN;
    else
        share = abs(eigenvalues(1)) / denominator;
    end

    G = struct();
    G.state = state;
    G.leading_eigenvalue = eigenvalues(1);
    G.secondary_eigenvalue = eigenvalues(2);
    G.leading_absolute_share = share;
    G.policy_direction = direction(1);
    G.equity_direction = direction(2);
    G.angle_degrees = angle;
    G.sector = sector;
    G.response_matrix = responseMatrix;
    G.shock_covariance = shockCovariance;
end
