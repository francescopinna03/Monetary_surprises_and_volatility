function [summary, eventLoss] = Step23_grouped_oos(y, Xbase, Xcandidate, clusters)
%STEP23_GROUPED_OOS Leave-one-event-out comparison of two fixed designs.

    y = double(y(:));
    Xbase = double(Xbase);
    Xcandidate = double(Xcandidate);
    clusters = string(clusters(:));

    if size(Xbase, 1) ~= numel(y) || size(Xcandidate, 1) ~= numel(y) || ...
            numel(clusters) ~= numel(y)
        error('STEP23_OOS_DIMENSIONS: inputs must have equal rows.');
    end
    if any(~isfinite(y)) || any(~isfinite(Xbase), 'all') || ...
            any(~isfinite(Xcandidate), 'all')
        error('STEP23_OOS_NONFINITE: model inputs must be finite.');
    end

    [clusterNames, ~, clusterId] = unique(clusters, 'stable');
    G = numel(clusterNames);
    predBase = nan(numel(y), 1);
    predCandidate = nan(numel(y), 1);

    for g = 1:G
        test = clusterId == g;
        train = ~test;
        betaBase = Xbase(train, :) \ y(train);
        betaCandidate = Xcandidate(train, :) \ y(train);
        predBase(test) = Xbase(test, :) * betaBase;
        predCandidate(test) = Xcandidate(test, :) * betaCandidate;
    end

    lossBase = (y - predBase) .^ 2;
    lossCandidate = (y - predCandidate) .^ 2;
    eventLoss = table('Size', [G, 4], ...
        'VariableTypes', {'string', 'double', 'double', 'double'}, ...
        'VariableNames', {'event_cluster', 'loss_base', ...
        'loss_candidate', 'loss_improvement'});
    eventLoss.event_cluster = clusterNames;

    for g = 1:G
        idx = clusterId == g;
        eventLoss.loss_base(g) = mean(lossBase(idx));
        eventLoss.loss_candidate(g) = mean(lossCandidate(idx));
    end
    eventLoss.loss_improvement = eventLoss.loss_base - eventLoss.loss_candidate;

    summary = table();
    summary.n_obs = numel(y);
    summary.n_clusters = G;
    summary.mse_base = mean(lossBase);
    summary.mse_candidate = mean(lossCandidate);
    summary.loss_improvement = summary.mse_base - summary.mse_candidate;
    summary.oos_improvement_pct = 100 * summary.loss_improvement / summary.mse_base;
end
