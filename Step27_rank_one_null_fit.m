function fit = Step27_rank_one_null_fit(y, X, termNames, shockCovariance, coarseDegrees)
%STEP27_RANK_ONE_NULL_FIT Constrained least-squares fit of the Step-27A null.
%
% The six PC-minus-PR quadratic coefficients are restricted to
%
%   Delta A(s) = (a0 + a1*s) * Sigma^(-1/2) w*w' Sigma^(-1/2),
%
% where w is a single direction on the standardised shock ellipse.  The
% direction is estimated jointly with the two amplitudes; it is not an
% externally fixed or separately estimated MP vector.  All remaining
% coefficients are unrestricted.

    if nargin < 5 || isempty(coarseDegrees)
        coarseDegrees = 5;
    end
    y = double(y(:));
    X = double(X);
    termNames = string(termNames(:));
    shockCovariance = double(shockCovariance);

    if size(X, 1) ~= numel(y) || size(X, 2) ~= numel(termNames)
        error('STEP27_NULL_DIMENSIONS: y, X and term names are inconsistent.');
    end
    if any(~isfinite(y)) || any(~isfinite(X), 'all')
        error('STEP27_NULL_NONFINITE: y and X must be finite.');
    end
    if ~isfinite(coarseDegrees) || coarseDegrees <= 0 || coarseDegrees > 30
        error('STEP27_NULL_GRID: coarseDegrees must lie in (0, 30].');
    end

    [squareRoot, inverseSquareRoot] = covariance_roots(shockCovariance);
    coarseRadians = deg2rad(coarseDegrees);
    grid = 0:coarseRadians:(pi - coarseRadians / 2);
    losses = nan(numel(grid), 1);
    for j = 1:numel(grid)
        losses(j) = profiled_loss(grid(j), y, X, termNames, inverseSquareRoot);
    end
    [~, best] = min(losses);
    theta0 = grid(best);
    objective = @(theta) profiled_loss(theta, y, X, termNames, inverseSquareRoot);
    theta = fminbnd(objective, theta0 - coarseRadians, ...
        theta0 + coarseRadians, optimset('TolX', 1e-10, 'Display', 'off'));
    theta = mod(theta, pi);

    [sse, beta, fitted, residual, amplitudes, designRank, h] = ...
        profiled_loss(theta, y, X, termNames, inverseSquareRoot);
    w = [cos(theta); sin(theta)];
    direction = squareRoot * w;
    direction = direction / norm(direction);
    if direction(1) < 0
        direction = -direction;
    end

    fit = struct();
    fit.beta = beta;
    fit.fitted = fitted;
    fit.residual = residual;
    fit.sse = sse;
    fit.theta_standardised_degrees = rad2deg(theta);
    fit.reference_direction = direction;
    fit.reference_angle_degrees = atan2d(direction(2), direction(1));
    fit.reference_sector = classify_sector(direction);
    fit.level_amplitude = amplitudes(1);
    fit.slope_amplitude = amplitudes(2);
    fit.coefficient_direction = h;
    fit.restricted_design_rank = designRank;
end

function [sse, beta, fitted, residual, amplitudes, designRank, h] = ...
        profiled_loss(theta, y, X, termNames, inverseSquareRoot)
    w = [cos(theta); sin(theta)];
    A = inverseSquareRoot * (w * w') * inverseSquareRoot;
    A = (A + A') / 2;
    h = [A(1, 1); A(2, 2); A(1, 2)];
    [mapping, amplitudeColumns] = coefficient_mapping(termNames, h);
    Z = X * mapping;
    gamma = Z \ y;
    beta = mapping * gamma;
    fitted = X * beta;
    residual = y - fitted;
    sse = residual' * residual;
    amplitudes = gamma(amplitudeColumns);
    if nargout >= 6
        designRank = rank(Z);
    else
        designRank = NaN;
    end
end

function [mapping, amplitudeColumns] = coefficient_mapping(termNames, h)
    level = ["q_policy", "q_equity", "q_policy_equity"];
    slope = ["q_policy_x_pre", "q_equity_x_pre", ...
        "q_policy_equity_x_pre"];
    prLevel = locate_terms(termNames, "PR_" + level);
    pcLevel = locate_terms(termNames, "PC_" + level);
    prSlope = locate_terms(termNames, "PR_" + slope);
    pcSlope = locate_terms(termNames, "PC_" + slope);

    removed = [pcLevel; pcSlope];
    kept = setdiff((1:numel(termNames))', removed, 'stable');
    mapping = zeros(numel(termNames), numel(kept) + 2);
    for j = 1:numel(kept)
        mapping(kept(j), j) = 1;
    end
    for j = 1:3
        commonLevel = find(kept == prLevel(j), 1);
        commonSlope = find(kept == prSlope(j), 1);
        mapping(pcLevel(j), commonLevel) = 1;
        mapping(pcSlope(j), commonSlope) = 1;
        mapping(pcLevel(j), end - 1) = h(j);
        mapping(pcSlope(j), end) = h(j);
    end
    amplitudeColumns = [size(mapping, 2) - 1; size(mapping, 2)];
end

function indices = locate_terms(termNames, requested)
    indices = nan(numel(requested), 1);
    for j = 1:numel(requested)
        hit = find(termNames == requested(j));
        if numel(hit) ~= 1
            error('STEP27_NULL_TERMS: expected exactly one term named %s.', ...
                requested(j));
        end
        indices(j) = hit;
    end
end

function [squareRoot, inverseSquareRoot] = covariance_roots(Sigma)
    Sigma = (Sigma + Sigma') / 2;
    if ~isequal(size(Sigma), [2, 2]) || any(~isfinite(Sigma), 'all')
        error('STEP27_NULL_COVARIANCE: shock covariance must be finite 2-by-2.');
    end
    [vectors, values] = eig(Sigma);
    eigenvalues = real(diag(values));
    tolerance = 1e-12 * max(1, max(abs(eigenvalues)));
    if any(eigenvalues <= tolerance)
        error('STEP27_NULL_COVARIANCE: shock covariance must be positive definite.');
    end
    squareRoot = vectors * diag(sqrt(eigenvalues)) * vectors';
    inverseSquareRoot = vectors * diag(1 ./ sqrt(eigenvalues)) * vectors';
end

function sector = classify_sector(direction)
    product = direction(1) * direction(2);
    if product < 0
        sector = "MP_LIKE";
    elseif product > 0
        sector = "CBI_LIKE";
    else
        sector = "BOUNDARY";
    end
end
