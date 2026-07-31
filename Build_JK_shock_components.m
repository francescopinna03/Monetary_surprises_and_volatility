function [out, fit] = Build_JK_shock_components(oisChanges, equitySurprise, baseSample, rotationQuantile)
%BUILD_JK_SHOCK_COMPONENTS Estimate and apply the broad MP-CBI decomposition.
%
% oisChanges must contain OIS changes at 1M, 3M, 6M and 1Y, in that order.
% The policy indicator reproduces the public Jarocinski-Karadi convention:
% scale each OIS change by its sample standard deviation without centering,
% take PC1, orient it positively on OIS 1Y, and rescale it by
% std(OIS_1Y)/100. Shocks are returned in percentage-point units.

    if nargin < 3 || isempty(baseSample)
        baseSample = true(size(oisChanges, 1), 1);
    end
    if nargin < 4 || isempty(rotationQuantile)
        rotationQuantile = 0.5;
    end

    validateattributes(oisChanges, {'numeric'}, {'2d', 'ncols', 4});
    validateattributes(equitySurprise, {'numeric'}, {'column', 'numel', size(oisChanges, 1)});

    baseSample = logical(baseSample(:));
    if numel(baseSample) ~= size(oisChanges, 1)
        error('JK_SAMPLE_SIZE: baseSample must have one entry per observation.');
    end

    pcaSample = baseSample & all(isfinite(oisChanges), 2);
    if sum(pcaSample) < 8
        error('JK_PCA_TOO_FEW_ROWS: at least eight complete OIS observations are required.');
    end

    oisScale = std(oisChanges(pcaSample, :), 0, 1);
    if any(~isfinite(oisScale) | oisScale <= 0)
        error('JK_PCA_SCALE: every OIS maturity must have positive finite variation.');
    end

    standardizedOis = oisChanges(pcaSample, :) ./ oisScale;
    [~, singularValues, loadings] = svd(standardizedOis, 'econ');

    % Freeze otherwise arbitrary signs for diagnostic curve PCs. PC1 is
    % oriented economically below; PC2-PC4 have their largest loading positive.
    for component = 2:size(loadings, 2)
        [~, anchor] = max(abs(loadings(:, component)));
        if loadings(anchor, component) < 0
            loadings(:, component) = -loadings(:, component);
        end
    end
    pc1Loading = loadings(:, 1);

    % The SVD sign is arbitrary. Positive values must be tightening shocks.
    if pc1Loading(4) < 0
        pc1Loading = -pc1Loading;
        loadings(:, 1) = pc1Loading;
    end

    scoreInSample = standardizedOis * loadings;
    scoreScaleAll = std(scoreInSample, 0, 1);
    if any(~isfinite(scoreScaleAll) | scoreScaleAll <= 0)
        error('JK_CURVE_PC_SCALE: every retained curve PC must have variation.');
    end
    scoreScale = scoreScaleAll(1);
    ois1yScale = std(oisChanges(pcaSample, 4), 0, 1);

    if ~isfinite(scoreScale) || scoreScale <= 0
        error('JK_PC1_SCALE: the first principal component has zero variation.');
    end

    pc1 = nan(size(equitySurprise));
    curvePcZ = nan(size(oisChanges));
    pc1Available = baseSample & all(isfinite(oisChanges), 2);
    standardizedAll = oisChanges(pc1Available, :) ./ oisScale;
    curvePcZ(pc1Available, :) = (standardizedAll * loadings) ./ scoreScaleAll;
    pc1(pc1Available) = curvePcZ(pc1Available, 1) * ois1yScale / 100;

    shockSample = pc1Available & isfinite(equitySurprise);
    if sum(shockSample) < 8
        error('JK_SHOCK_TOO_FEW_ROWS: at least eight complete policy-equity observations are required.');
    end

    observed = [pc1(shockSample), equitySurprise(shockSample)];
    [rotationShocks, C, angle] = JK_median_rotation(observed, rotationQuantile);

    mpRotation = nan(size(pc1));
    cbiRotation = nan(size(pc1));
    mpRotation(shockSample) = rotationShocks(:, 1);
    cbiRotation(shockSample) = rotationShocks(:, 2);

    mpPoor = nan(size(pc1));
    cbiPoor = nan(size(pc1));
    oppositeSigns = prod(observed, 2) < 0;
    pm = [observed(:, 1) .* oppositeSigns, ...
        observed(:, 1) .* ~oppositeSigns];
    mpPoor(shockSample) = pm(:, 1);
    cbiPoor(shockSample) = pm(:, 2);

    eigenvalues = diag(singularValues).^2;
    explained = eigenvalues / sum(eigenvalues);

    out = struct();
    out.policy_indicator = pc1;
    out.MP_pm = mpPoor;
    out.CBI_pm = cbiPoor;
    out.MP_rotation = mpRotation;
    out.CBI_rotation = cbiRotation;
    out.curve_pc_z = curvePcZ;
    out.pca_sample = pcaSample;
    out.shock_sample = shockSample;

    fit = struct();
    fit.ois_scale = oisScale;
    fit.pc1_loading = pc1Loading;
    fit.curve_loadings = loadings;
    fit.score_scale = scoreScale;
    fit.curve_score_scale = scoreScaleAll;
    fit.ois1y_scale = ois1yScale;
    fit.pca_explained = explained;
    fit.C = C;
    fit.rotation_angle = angle;
    fit.rotation_quantile = rotationQuantile;
    fit.n_pca = sum(pcaSample);
    fit.n_shocks = sum(shockSample);
end
