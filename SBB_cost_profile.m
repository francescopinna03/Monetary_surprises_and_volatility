function [profile, modeDetails] = SBB_cost_profile(z, m, Sigma, kappaGrid, tauNum)
%SBB_COST_PROFILE Evaluate the complete preregistered kappa path.
%
% No aggregation along kappa is performed here: the full path is the
% primary Step-28 object.  A scalar kappa can therefore only be a one-row
% illustrative special case of this function.

    if nargin < 5 || isempty(tauNum)
        tauNum = 1e-4;
    end
    kappaGrid = double(kappaGrid(:));
    if isempty(kappaGrid) || any(~isfinite(kappaGrid)) || ...
            any(kappaGrid <= 1) || numel(unique(kappaGrid)) ~= numel(kappaGrid)
        error(['SBB_KAPPA_GRID: kappaGrid must contain unique finite values ' ...
            'strictly greater than one.']);
    end
    if any(diff(kappaGrid) <= 0)
        error('SBB_KAPPA_GRID_ORDER: kappaGrid must be strictly increasing.');
    end

    nKappa = numel(kappaGrid);
    driftTranslation = NaN(nKappa, 1);
    driftCovariance = NaN(nKappa, 1);
    drift = NaN(nKappa, 1);
    volatility = NaN(nKappa, 1);
    total = NaN(nKappa, 1);
    maxResidual = NaN(nKappa, 1);
    nSeriesModes = NaN(nKappa, 1);
    modeDetails = cell(nKappa, 1);

    for q = 1:nKappa
        result = SBB_dirac_gaussian_cost(z, m, Sigma, ...
            kappaGrid(q), tauNum);
        driftTranslation(q) = result.drift_translation_cost;
        driftCovariance(q) = result.drift_covariance_cost;
        drift(q) = result.drift_cost;
        volatility(q) = result.volatility_cost;
        total(q) = result.total_cost;
        maxResidual(q) = result.max_root_equation_residual;
        nSeriesModes(q) = sum(result.modes.numerical_branch == "series");
        modeDetails{q} = result.modes;
    end

    profile = table(kappaGrid, driftTranslation, driftCovariance, drift, ...
        volatility, total, nSeriesModes, maxResidual, ...
        'VariableNames', {'kappa', 'drift_translation_cost', ...
        'drift_covariance_cost', 'drift_cost', 'volatility_cost', ...
        'total_cost', 'n_series_modes', 'max_root_equation_residual'});
end
