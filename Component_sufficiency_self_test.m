function Component_sufficiency_self_test()
%COMPONENT_SUFFICIENCY_SELF_TEST Deterministic Step-23 utility checks.

    rng(23026, 'twister');
    G = 48;
    rowsPerEvent = 2;
    clusters = repelem("event_" + string((1:G)'), rowsPerEvent);
    x = randn(G * rowsPerEvent, 1);
    z = randn(G * rowsPerEvent, 1);
    y = 0.5 + 0.7 * x + 1.2 * z + 0.08 * randn(G * rowsPerEvent, 1);
    Xbase = [ones(size(y)), x];
    Xcandidate = [Xbase, z];

    fit = Step23_cluster_ols(y, Xcandidate, clusters);
    assert(fit.G == G && fit.rank == 3, 'Clustered OLS dimensions failed.');
    assert(abs(fit.beta(3) - 1.2) < 0.05, 'Clustered OLS coefficient check failed.');

    [summary, eventLoss] = Step23_grouped_oos( ...
        y, Xbase, Xcandidate, clusters);
    assert(summary.oos_improvement_pct > 50, ...
        'Grouped OOS comparison failed to detect a strong signal.');
    [boot, draws] = Step23_paired_bootstrap(eventLoss, 199);
    assert(numel(draws) == 199 && boot.p_one_sided_improvement < 0.05, ...
        'Paired event bootstrap failed.');

    adjusted = Step23_holm_adjust([0.01; 0.04; 0.20]);
    assert(max(abs(adjusted - [0.03; 0.08; 0.20])) < 1e-12, ...
        'Holm adjustment failed.');

    fprintf(['Component_sufficiency_self_test: clustered OLS, grouped OOS, ' ...
        'bootstrap and Holm checks passed.\n']);
end
