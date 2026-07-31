function out = Apply_JK_shock_fit(oisChanges, equitySurprise, fit)
%APPLY_JK_SHOCK_FIT Apply a frozen PCA scale, loading and JK rotation.
%
% This function is used for leave-one-event-out diagnostics and will also be
% the entry point for bootstrap or cross-fitted applications in later steps.

    validateattributes(oisChanges, {'numeric'}, {'2d', 'ncols', 4});
    validateattributes(equitySurprise, {'numeric'}, {'column', 'numel', size(oisChanges, 1)});

    pc1 = nan(size(equitySurprise));
    curvePcZ = nan(size(oisChanges));
    completeOis = all(isfinite(oisChanges), 2);
    standardized = oisChanges(completeOis, :) ./ fit.ois_scale;
    curvePcZ(completeOis, :) = (standardized * fit.curve_loadings) ./ ...
        fit.curve_score_scale;
    pc1(completeOis) = curvePcZ(completeOis, 1) * fit.ois1y_scale / 100;

    completeShock = completeOis & isfinite(equitySurprise);
    shocks = nan(size(oisChanges, 1), 2);
    shocks(completeShock, :) = [pc1(completeShock), ...
        equitySurprise(completeShock)] / fit.C;

    observed = [pc1(completeShock), equitySurprise(completeShock)];
    oppositeSigns = prod(observed, 2) < 0;
    poor = [observed(:, 1) .* oppositeSigns, ...
        observed(:, 1) .* ~oppositeSigns];

    poorAll = nan(size(shocks));
    poorAll(completeShock, :) = poor;

    out = struct();
    out.policy_indicator = pc1;
    out.curve_pc_z = curvePcZ;
    out.MP_rotation = shocks(:, 1);
    out.CBI_rotation = shocks(:, 2);
    out.MP_pm = poorAll(:, 1);
    out.CBI_pm = poorAll(:, 2);
    out.complete_shock = completeShock;
end
