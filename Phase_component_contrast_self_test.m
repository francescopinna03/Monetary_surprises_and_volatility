function Phase_component_contrast_self_test()
%PHASE_COMPONENT_CONTRAST_SELF_TEST Deterministic Step-24 inference checks.

    rng(24026, 'twister');
    G = 60;
    rows = 2 * G;
    clusters = repelem("event_" + string((1:G)'), 2);
    xPr = randn(rows, 1);
    xPc = randn(rows, 1);
    yPr = 0.4 + 0.5 * xPr + 0.10 * randn(rows, 1);
    yPc = 0.7 + 1.4 * xPc + 0.10 * randn(rows, 1);
    Xpr = [ones(rows, 1), xPr];
    Xpc = [ones(rows, 1), xPc];
    X = [Xpr, zeros(rows, 2); zeros(rows, 2), Xpc];
    y = [yPr; yPc];
    stackedClusters = [clusters; clusters];
    R = [0, -1, 0, 1];

    fit = Step23_cluster_ols(y, X, stackedClusters);
    test = Step24_wald_test(fit, R);
    assert(test.p_value < 0.01, 'Stacked phase contrast did not detect a signal.');
    [pWild, draws] = Step24_wild_wald(y, X, stackedClusters, R, 199);
    assert(pWild < 0.05 && numel(draws) == 199, ...
        'Wild-cluster phase contrast failed.');

    fprintf(['Phase_component_contrast_self_test: stacked covariance, Wald ' ...
        'and null-imposed wild-cluster checks passed.\n']);
end
