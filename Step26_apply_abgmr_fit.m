function scores = Step26_apply_abgmr_fit(X, fit)
%STEP26_APPLY_ABGMR_FIT Apply a frozen Step-26 PCA and rotation.

    X = double(X);
    if size(X, 2) ~= 7
        error('STEP26_APPLY_DIMENSIONS: X must have seven maturity columns.');
    end
    scores = nan(size(X, 1), numel(fit.factor_names));
    complete = all(isfinite(X), 2);
    if ~any(complete); return; end
    Xc = X(complete, :) - fit.center;
    raw = Xc * fit.base_loadings / 7;
    standardised = raw ./ fit.raw_factor_scale;
    scores(complete, :) = (standardised * fit.rotation) .* fit.anchor_slopes;
end
