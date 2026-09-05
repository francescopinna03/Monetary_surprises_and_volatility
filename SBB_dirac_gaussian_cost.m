function result = SBB_dirac_gaussian_cost(z, m, Sigma, kappa, tauNum)
%SBB_DIRAC_GAUSSIAN_COST Exact Schrödinger--Bass Dirac--Gaussian cost.
%
% The transition is normalised to [0,1], X_0 = z and
% X_1 ~ N(m,Sigma).  kappa = beta * Delta_t must exceed one.  The returned
% drift and volatility terms follow equations (51)--(60) of the frozen
% Step-28 technical note.  Near Sigma = I, the implementation deliberately
% avoids both the removable 0/0 ratio and the subtraction c - 1.

    if nargin < 5 || isempty(tauNum)
        tauNum = 1e-4;
    end

    z = double(z(:));
    m = double(m(:));
    Sigma = double(Sigma);
    kappa = double(kappa);
    tauNum = double(tauNum);

    if numel(z) ~= numel(m) || isempty(z) || any(~isfinite(z)) || ...
            any(~isfinite(m))
        error('SBB_ENDPOINTS: z and m must be finite vectors of equal size.');
    end
    dimension = numel(z);
    if ~isequal(size(Sigma), [dimension, dimension]) || ...
            any(~isfinite(Sigma), 'all')
        error('SBB_COVARIANCE_SIZE: Sigma must be a finite square endpoint covariance.');
    end
    if ~isscalar(kappa) || ~isfinite(kappa) || kappa <= 1
        error('SBB_KAPPA_DOMAIN: kappa must be a finite scalar strictly greater than one.');
    end
    if ~isscalar(tauNum) || ~isfinite(tauNum) || tauNum <= 0 || tauNum >= 1
        error('SBB_NUMERICAL_THRESHOLD: tauNum must lie strictly between zero and one.');
    end

    covarianceScale = max(1, norm(Sigma, 'fro'));
    symmetryError = norm(Sigma - Sigma', 'fro') / covarianceScale;
    if symmetryError > 1e-10
        error('SBB_COVARIANCE_SYMMETRY: Sigma must be symmetric.');
    end
    Sigma = (Sigma + Sigma') / 2;
    [eigenvectors, eigenvalues] = eig(Sigma, 'vector');
    eigenvalues = real(eigenvalues);
    [eigenvalues, order] = sort(eigenvalues, 'descend');
    eigenvectors = real(eigenvectors(:, order));
    positiveTolerance = 100 * eps(covarianceScale);
    if any(eigenvalues <= positiveTolerance)
        error('SBB_COVARIANCE_PD: Sigma must be positive definite after regularisation.');
    end

    nModes = numel(eigenvalues);
    c = NaN(nModes, 1);
    deltaC = NaN(nModes, 1);
    P = NaN(nModes, 1);
    Q = NaN(nModes, 1);
    ratio = NaN(nModes, 1);
    branch = strings(nModes, 1);

    for j = 1:nModes
        lambda = eigenvalues(j);
        denominator = sqrt(kappa^2 * lambda^2 + ...
            4 * (kappa + 1) * lambda) + kappa * lambda;
        cDirect = 2 * (kappa + 1) * lambda / denominator;
        % P=(kappa+1)-kappa*c is mathematically identical to c^2/lambda.
        % The latter avoids catastrophic cancellation when lambda is large.
        pDirect = cDirect^2 / lambda;

        if abs(1 - pDirect) <= tauNum
            epsilon = lambda - 1;
            deltaC(j) = epsilon / (kappa + 2) - ...
                ((kappa + 1)^2 / (kappa + 2)^3) * epsilon^2;
            c(j) = 1 + deltaC(j);
            P(j) = 1 - kappa * deltaC(j);
            Q(j) = 1 - (kappa - 1) * deltaC(j);
            delta = 1 - P(j);
            ratio(j) = ratio_series_degree_six(delta);
            branch(j) = "series";
        else
            c(j) = cDirect;
            deltaC(j) = cDirect - 1;
            P(j) = pDirect;
            % Q-P=c-1 is the stable equivalent of
            % Q=kappa-(kappa-1)c.
            Q(j) = P(j) + deltaC(j);
            delta = 1 - P(j);
            ratio(j) = (delta + P(j) * log1p(-delta)) / ...
                (P(j) * delta^2);
            branch(j) = "closed_form";
        end
    end

    if any(~isfinite(P)) || any(P <= 0) || any(~isfinite(ratio)) || ...
            any(ratio <= 0)
        error('SBB_NUMERICAL_ADMISSIBILITY: the computed bridge is not admissible.');
    end

    driftTranslation = 0.5 * sum((m - z).^2);
    driftCovarianceByMode = 0.5 * kappa^2 * deltaC.^2 .* ratio;
    volatilityByMode = 0.5 * kappa * deltaC.^2 ./ P;
    driftCost = driftTranslation + sum(driftCovarianceByMode);
    volatilityCost = sum(volatilityByMode);

    rootResidual = abs(eigenvalues - c.^2 ./ P);
    modes = table((1:nModes)', eigenvalues, c, deltaC, P, Q, ratio, ...
        driftCovarianceByMode, volatilityByMode, rootResidual, branch, ...
        'VariableNames', {'mode', 'lambda', 'c', 'delta_c', 'P', 'Q', ...
        'ratio', 'drift_covariance_cost', 'volatility_cost', ...
        'root_equation_residual', 'numerical_branch'});

    result = struct();
    result.schema_version = "sbb_dirac_gaussian_v1";
    result.dimension = dimension;
    result.kappa = kappa;
    result.tau_num = tauNum;
    result.drift_translation_cost = driftTranslation;
    result.drift_covariance_cost = sum(driftCovarianceByMode);
    result.drift_cost = driftCost;
    result.volatility_cost = volatilityCost;
    result.total_cost = driftCost + volatilityCost;
    result.max_root_equation_residual = max(rootResidual);
    result.eigenvectors = eigenvectors;
    result.modes = modes;
end

function value = ratio_series_degree_six(delta)
% The Taylor coefficient of delta^ell is (ell+1)/(ell+2), ell=0,...,6.
% Evaluate the degree-six polynomial by Horner.
    value = 7 / 8;
    for numerator = 6:-1:1
        value = numerator / (numerator + 1) + delta * value;
    end
end
