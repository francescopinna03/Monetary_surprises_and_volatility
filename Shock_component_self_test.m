function Shock_component_self_test()
%SHOCK_COMPONENT_SELF_TEST Deterministic checks for the Step-22 first stage.

    rng(22026, 'twister');
    n = 240;

    structuralMP = randn(n, 1);
    structuralCBI = randn(n, 1);
    policy = structuralMP + structuralCBI;
    equity = -0.75 * structuralMP + 0.55 * structuralCBI;

    maturityLoadings = [0.65, 0.85, 1.00, 1.15];
    ois = policy * maturityLoadings + 0.08 * randn(n, 4);

    [out, fit] = Build_JK_shock_components(ois, equity, true(n, 1), 0.5);
    valid = out.shock_sample;

    assert(max(abs(out.MP_rotation(valid) + out.CBI_rotation(valid) - ...
        out.policy_indicator(valid))) < 1e-10, 'Median shocks do not sum to PC1.');
    assert(max(abs(out.MP_pm(valid) + out.CBI_pm(valid) - ...
        out.policy_indicator(valid))) < 1e-12, 'Poor-man shocks do not sum to PC1.');
    assert(fit.C(1, 2) < 0 && fit.C(2, 2) > 0, ...
        'Equity sign restrictions were not satisfied.');
    assert(fit.pc1_loading(4) > 0, 'PC1 is not oriented positively on OIS 1Y.');
    assert(abs(out.MP_rotation(valid)' * out.CBI_rotation(valid)) < 1e-8, ...
        'Rotated shocks are not orthogonal in raw second moments.');

    frozen = Apply_JK_shock_fit(ois(1:12, :), equity(1:12), fit);
    assert(max(abs(frozen.MP_rotation + frozen.CBI_rotation - ...
        frozen.policy_indicator)) < 1e-10, 'Frozen fit does not reconstruct PC1.');

    fprintf('Shock_component_self_test: all deterministic checks passed.\n');
end

