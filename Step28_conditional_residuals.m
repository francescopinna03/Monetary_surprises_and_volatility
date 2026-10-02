function [residual, standardised, diagnostics] = Step28_conditional_residuals( conditioning, group, target, foldKey, isControl, lawOptions, fitMask)

    if nargin < 7 || isempty(fitMask)
        fitMask = true(size(target, 1), 1);
    end
    fitMask = logical(fitMask(:));
    if ~any(fitMask)
        error('STEP28_RESIDUAL_FIT_SAMPLE: the fit sample is empty.');
    end

    folds = unique(foldKey);
    if numel(folds) < 2
        error('STEP28_RESIDUAL_FOLDS: at least two folds are required.');
    end

    residual = NaN(size(target));
    standardised = NaN(size(target));
    penalties = NaN(numel(folds), 1);

    for f = 1:numel(folds)
        test = foldKey == folds(f);
        train = ~test & fitMask;
        if ~any(test)
            continue;
        end
        if ~any(train)
            error(['STEP28_RESIDUAL_FOLD_EMPTY: fold %s leaves no row in the ' 'fit sample.'], folds(f));
        end
        model = Step28_conditional_gaussian_fit(target(train, :),             conditioning(train, :), group(train), isControl(train), foldKey(train), lawOptions);
        penalties(f) = model.penalty;
        [predictedMean, predictedCovariance] =             Step28_conditional_gaussian_predict(model, conditioning(test, :), group(test));
        rows = find(test);
        residual(rows, :) = target(rows, :) - predictedMean;
        for i = 1:numel(rows)
            Sigma = predictedCovariance(:, :, i);
            [cholesky, notPositive] = chol(Sigma, 'lower');
            if notPositive ~= 0
                error(['STEP28_RESIDUAL_COVARIANCE: a predicted covariance is ' 'not positive definite.']);
            end
            standardised(rows(i), :) = (cholesky \ residual(rows(i), :)')';
        end
    end

    if any(~isfinite(residual), 'all') || any(~isfinite(standardised), 'all')
        error('STEP28_RESIDUAL_INCOMPLETE: some rows were never predicted.');
    end

    diagnostics = struct();
    diagnostics.fold_penalties = penalties;
    diagnostics.n_folds = numel(folds);
end
