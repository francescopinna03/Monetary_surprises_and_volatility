function fit = Step23_cluster_ols(y, X, clusters)
%STEP23_CLUSTER_OLS OLS with event-clustered CR1 covariance.

    y = double(y(:));
    X = double(X);
    clusters = string(clusters(:));

    if size(X, 1) ~= numel(y) || numel(clusters) ~= numel(y)
        error('STEP23_CLUSTER_DIMENSIONS: y, X and clusters must have equal rows.');
    end
    if any(~isfinite(y)) || any(~isfinite(X), 'all')
        error('STEP23_CLUSTER_NONFINITE: y and X must be finite.');
    end

    n = numel(y);
    k = size(X, 2);
    beta = X \ y;
    residual = y - X * beta;
    clusterId = findgroups(clusters);
    G = max(clusterId);
    XtXi = pinv(X' * X);
    meat = zeros(k, k);

    for g = 1:G
        idx = clusterId == g;
        score = X(idx, :)' * residual(idx);
        meat = meat + score * score';
    end

    correction = (G / max(G - 1, 1)) * ((n - 1) / max(n - k, 1));
    V = correction * XtXi * meat * XtXi;
    se = sqrt(max(diag(V), 0));
    tstat = beta ./ se;
    pval = 2 * tcdf(-abs(tstat), max(G - 1, 1));
    sse = residual' * residual;
    tss = sum((y - mean(y)) .^ 2);
    r2 = 1 - sse / tss;

    fit = struct();
    fit.beta = beta;
    fit.V = V;
    fit.se = se;
    fit.tstat = tstat;
    fit.pval = pval;
    fit.n = n;
    fit.k = k;
    fit.G = G;
    fit.rank = rank(X);
    fit.r2 = r2;
    fit.residual = residual;
end
