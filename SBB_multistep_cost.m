function [costs, transitions] = SBB_multistep_cost(z, m, Sigma, kappaGrid, sequenceKey, phase, tauNum)

    if nargin < 7 || isempty(tauNum)
        tauNum = 1e-4;
    end

    z = double(z);
    m = double(m);
    kappaGrid = double(kappaGrid(:));
    sequenceKey = string(sequenceKey(:));
    phase = string(phase(:));

    [nTransitions, dimension] = size(z);
    if nTransitions == 0 || dimension == 0
        error('SBB_MULTISTEP_EMPTY: at least one transition is required.');
    end
    if ~isequal(size(m), [nTransitions, dimension])
        error('SBB_MULTISTEP_MEAN_SIZE: m must match the size of z.');
    end
    sigmaSize = size(Sigma);
    if numel(sigmaSize) == 2
        sigmaSize(3) = 1;
    end
    if ~isequal(sigmaSize, [dimension, dimension, nTransitions])
        error('SBB_MULTISTEP_COVARIANCE_SIZE: Sigma must be d-by-d-by-N.');
    end
    if numel(sequenceKey) ~= nTransitions || numel(phase) ~= nTransitions
        error('SBB_MULTISTEP_LABELS: labels must have one entry per transition.');
    end
    if isempty(kappaGrid) || any(~isfinite(kappaGrid)) || any(kappaGrid <= 1) || any(diff(kappaGrid) <= 0)
        error(['SBB_MULTISTEP_KAPPA_GRID: kappaGrid must be strictly ' 'increasing and greater than one.']);
    end

    nKappa = numel(kappaGrid);
    driftByTransition = NaN(nTransitions, nKappa);
    volatilityByTransition = NaN(nTransitions, nKappa);
    translationByTransition = NaN(nTransitions, nKappa);

    for i = 1:nTransitions
        for q = 1:nKappa
            result = SBB_dirac_gaussian_cost(z(i, :)', m(i, :)', Sigma(:, :, i), kappaGrid(q), tauNum);
            driftByTransition(i, q) = result.drift_cost;
            volatilityByTransition(i, q) = result.volatility_cost;
            translationByTransition(i, q) = result.drift_translation_cost;
        end
    end

    totalByTransition = driftByTransition + volatilityByTransition;

    transitionKappa = repmat(kappaGrid', nTransitions, 1);
    transitions = table(         repmat(sequenceKey, nKappa, 1),         repmat(phase, nKappa, 1),         repmat((1:nTransitions)', nKappa, 1),         transitionKappa(:),         translationByTransition(:),         driftByTransition(:),         volatilityByTransition(:),         totalByTransition(:),         'VariableNames', {'sequence_key', 'phase', 'transition_index',         'kappa', 'drift_translation_cost', 'drift_cost', 'volatility_cost', 'total_cost'});

    key = sequenceKey + "|" + phase;
    [groupIndex, groupNames] = findgroups(key);
    nGroups = numel(groupNames);
    parts = split(groupNames, "|");
    if nGroups == 1
        parts = reshape(parts, 1, []);
    end
    groupSequence = parts(:, 1);
    groupPhase = parts(:, 2);
    groupCount = accumarray(groupIndex, 1, [nGroups, 1]);

    driftSum = zeros(nGroups, nKappa);
    volatilitySum = zeros(nGroups, nKappa);
    for q = 1:nKappa
        driftSum(:, q) = accumarray(groupIndex, driftByTransition(:, q), [nGroups, 1]);
        volatilitySum(:, q) = accumarray(groupIndex, volatilityByTransition(:, q), [nGroups, 1]);
    end
    totalSum = driftSum + volatilitySum;
    driftMean = driftSum ./ groupCount;
    volatilityMean = volatilitySum ./ groupCount;
    totalMean = totalSum ./ groupCount;

    costKappa = repmat(kappaGrid', nGroups, 1);
    costs = table(         repmat(groupSequence, nKappa, 1),         repmat(groupPhase, nKappa, 1),         repmat(groupCount, nKappa, 1),         costKappa(:),         driftSum(:), volatilitySum(:), totalSum(:),         driftMean(:), volatilityMean(:), totalMean(:),         'VariableNames', {'sequence_key', 'phase', 'n_transitions',         'kappa', 'drift_sum', 'volatility_sum', 'total_sum', 'drift_mean', 'volatility_mean', 'total_mean'});
    costs = sortrows(costs, {'phase', 'sequence_key', 'kappa'});
end
