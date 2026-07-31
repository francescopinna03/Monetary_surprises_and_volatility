function Invariant_phase_attribution_self_test()
%INVARIANT_PHASE_ATTRIBUTION_SELF_TEST Deterministic Step-25 geometry checks.

    level = [-0.45; -0.45; 0.55];
    slope = [0; 0; 0];
    covariance = eye(2);
    G = Step25_phase_geometry(level, slope, covariance, 0);
    assert(G.sector == "MP_LIKE", ...
        'Known opposite-sign direction was not classified as MP-like.');
    assert(G.leading_eigenvalue < 0 && G.leading_absolute_share > 0.85, ...
        'Known dominant negative direction was not recovered.');

    % x = T*u: A_u = T'*A_x*T and Sigma_u = inv(T)*Sigma_x*inv(T)'.
    T = [7, 0.3; -0.2, 0.4];
    A = [level(1), level(3); level(3), level(2)];
    transformedA = T' * A * T;
    transformedLevel = [transformedA(1, 1); transformedA(2, 2); ...
        transformedA(1, 2)];
    transformedCovariance = (T \ covariance) / T';
    H = Step25_phase_geometry(transformedLevel, slope, ...
        transformedCovariance, 0);
    mappedDirection = T * [H.policy_direction; H.equity_direction];
    mappedDirection = mappedDirection / norm(mappedDirection);
    originalDirection = [G.policy_direction; G.equity_direction];
    assert(abs(abs(mappedDirection' * originalDirection) - 1) < 1e-10, ...
        'Geometry changed under a nonsingular unit transformation.');
    assert(max(abs(sort([G.leading_eigenvalue; G.secondary_eigenvalue]) - ...
        sort([H.leading_eigenvalue; H.secondary_eigenvalue]))) < 1e-10, ...
        'Generalised eigenvalues changed under reparameterisation.');

    fprintf(['Invariant_phase_attribution_self_test: MP-sector geometry and ' ...
        'unit-invariance checks passed.\n']);
end
