function [pValue, draws, observed] = Step24_wild_wald(y, X, clusters, R, B)
%STEP24_WILD_WALD Null-imposed Rademacher wild-cluster Wald test.

    y = double(y(:));
    X = double(X);
    clusters = string(clusters(:));
    R = double(R);
    fit = Step23_cluster_ols(y, X, clusters);
    observedTest = Step24_wald_test(fit, R);
    observed = observedTest.f_statistic;

    XtXi = pinv(X' * X);
    middle = pinv(R * XtXi * R');
    betaRestricted = fit.beta - XtXi * R' * middle * (R * fit.beta);
    fittedRestricted = X * betaRestricted;
    residualRestricted = y - fittedRestricted;
    clusterId = findgroups(clusters);
    G = max(clusterId);
    draws = nan(B, 1);

    for b = 1:B
        weights = 2 * (rand(G, 1) >= 0.5) - 1;
        yStar = fittedRestricted + residualRestricted .* weights(clusterId);
        fitStar = Step23_cluster_ols(yStar, X, clusters);
        testStar = Step24_wald_test(fitStar, R);
        draws(b) = testStar.f_statistic;
    end

    usable = isfinite(draws);
    pValue = (1 + sum(draws(usable) >= observed)) / (1 + sum(usable));
end
