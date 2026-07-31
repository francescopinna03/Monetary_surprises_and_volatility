function [scores, fit] = Step26_abgmr_factors(X, eventDates, windowCode, preCrisisEnd)
%STEP26_ABGMR_FACTORS Reproduce the ABGMR Target/Timing/FG/QE rotation.
%
% X contains changes in the 1M, 3M, 6M, 1Y, 2Y, 5Y and 10Y risk-free
% rates, in basis points.  Principal components are extracted from centered,
% unstandardised changes, exactly as in the public ABGMR replication code.
% The press-release rotation returns Target.  The press-conference rotation
% returns Timing, Forward Guidance and QE; FG and QE have zero 1M loading and
% QE minimises its pre-crisis second moment in that two-dimensional subspace.

    if nargin < 4 || isempty(preCrisisEnd)
        preCrisisEnd = datetime(2008, 8, 7);
    end
    X = double(X);
    eventDates = eventDates(:);
    windowCode = upper(string(windowCode));
    if ~ismember(windowCode, ["PR", "PC"])
        error('STEP26_FACTOR_WINDOW: windowCode must be PR or PC.');
    end
    if size(X, 2) ~= 7 || size(X, 1) ~= numel(eventDates)
        error('STEP26_FACTOR_DIMENSIONS: X must be N-by-7 with one date per row.');
    end
    if any(~isfinite(X), 'all') || any(isnat(eventDates))
        error('STEP26_FACTOR_NONFINITE: factor-estimation inputs must be complete.');
    end
    if size(X, 1) < 30
        error('STEP26_FACTOR_TOO_FEW: at least 30 complete events are required.');
    end

    n = size(X, 1);
    p = size(X, 2);
    centre = mean(X, 1);
    Xc = X - centre;
    [~, singularValues, eigenvectors] = svd(Xc, 'econ');
    baseLoadings = sqrt(p) * eigenvectors;
    rawFactors = Xc * baseLoadings / p;
    rawScale = std(rawFactors, 0, 1);
    if any(~isfinite(rawScale(1:3)) | rawScale(1:3) <= 0)
        error('STEP26_FACTOR_DEGENERATE: the first three PCs must vary.');
    end
    F = rawFactors(:, 1:3) ./ rawScale(1:3);
    L = baseLoadings(:, 1:3) .* rawScale(1:3);

    oneMonthDirection = L(1, :)';
    if norm(oneMonthDirection) <= 1e-12
        error('STEP26_FACTOR_1M_LOADING: the retained space has no 1M loading.');
    end
    u1 = oneMonthDirection / norm(oneMonthDirection);

    if windowCode == "PR"
        U = u1;
        factorNames = "TARGET";
        anchorRows = 1;
    else
        pre = eventDates <= preCrisisEnd;
        if sum(pre) < 12 || sum(~pre) < 8
            error(['STEP26_FACTOR_PRECRISIS: conference rotation requires at ' ...
                'least 12 pre-crisis and 8 later observations.']);
        end
        basis = null(u1');
        preMoment = (F(pre, :)' * F(pre, :)) / sum(pre);
        [withinVectors, withinValues] = eig(basis' * preMoment * basis, 'vector');
        [~, order] = sort(withinValues, 'ascend');
        u3 = basis * withinVectors(:, order(1));
        u2 = basis * withinVectors(:, order(end));
        U = [u1, u2, u3];
        factorNames = ["TIMING", "FG", "QE"];
        anchorRows = [3, 5, 7];
    end

    rotated = F * U;
    rotatedLoadings = L * U;
    anchorSlopes = nan(1, numel(anchorRows));
    for j = 1:numel(anchorRows)
        anchor = X(:, anchorRows(j));
        r = rotated(:, j);
        anchorSlopes(j) = ((r - mean(r))' * (anchor - mean(anchor))) / ...
            sum((r - mean(r)) .^ 2);
        if ~isfinite(anchorSlopes(j)) || abs(anchorSlopes(j)) <= 1e-12
            error('STEP26_FACTOR_ANCHOR: factor %s cannot be normalised.', factorNames(j));
        end
    end
    scores = rotated .* anchorSlopes;
    normalisedLoadings = rotatedLoadings ./ anchorSlopes;

    eigenvalues = diag(singularValues) .^ 2;
    explained = eigenvalues / sum(eigenvalues);
    reconstructed = scores * normalisedLoadings';

    fit = struct();
    fit.window = windowCode;
    fit.factor_names = factorNames;
    fit.maturity_names = ["OIS_1M", "OIS_3M", "OIS_6M", "OIS_1Y", ...
        "OIS_2Y", "OIS_5Y", "OIS_10Y"];
    fit.anchor_rows = anchorRows;
    fit.center = centre;
    fit.base_loadings = baseLoadings(:, 1:3);
    fit.raw_factor_scale = rawScale(1:3);
    fit.rotation = U;
    fit.anchor_slopes = anchorSlopes;
    fit.loadings = normalisedLoadings;
    fit.explained = explained;
    fit.n = n;
    fit.pre_crisis_n = sum(eventDates <= preCrisisEnd);
    fit.pre_crisis_end = preCrisisEnd;
    fit.max_anchor_error = max(abs(normalisedLoadings(anchorRows + ...
        (0:numel(anchorRows)-1) * size(normalisedLoadings, 1)) - 1));
    fit.reconstruction_r2 = 1 - sum((Xc - reconstructed) .^ 2, 'all') / ...
        sum(Xc .^ 2, 'all');
    if windowCode == "PC"
        fit.max_zero_1m_loading = max(abs(normalisedLoadings(1, 2:3)));
        fit.qe_pre_second_moment = mean(rotated(eventDates <= preCrisisEnd, 3) .^ 2);
        fit.fg_pre_second_moment = mean(rotated(eventDates <= preCrisisEnd, 2) .^ 2);
    else
        fit.max_zero_1m_loading = NaN;
        fit.qe_pre_second_moment = NaN;
        fit.fg_pre_second_moment = NaN;
    end
end
