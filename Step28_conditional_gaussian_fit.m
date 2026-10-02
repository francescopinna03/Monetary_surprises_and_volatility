function model = Step28_conditional_gaussian_fit(target, conditioning, group, isControl, foldKey, options)

    if nargin < 6 || isempty(options)
        options = struct();
    end
    options = apply_defaults(options);

    target = double(target);
    conditioning = double(conditioning);
    group = string(group(:));
    isControl = logical(isControl(:));
    foldKey = string(foldKey(:));

    [nRows, dimension] = size(target);
    if nRows == 0 || dimension == 0
        error('STEP28_LAW_EMPTY: target must be a non-empty N-by-d array.');
    end
    if size(conditioning, 1) ~= nRows
        error('STEP28_LAW_ROWS: conditioning must have one row per target row.');
    end
    if numel(group) ~= nRows || numel(isControl) ~= nRows || numel(foldKey) ~= nRows
        error('STEP28_LAW_LABELS: every label must have one entry per row.');
    end
    if any(~isfinite(target), 'all') || any(~isfinite(conditioning), 'all')
        error('STEP28_LAW_NONFINITE: target and conditioning must be finite.');
    end
    if ~any(isControl)
        error('STEP28_LAW_NO_CONTROLS: the penalty is tuned on control rows.');
    end

    [groupIndex, groupNames] = findgroups(group);
    nGroups = numel(groupNames);
    counts = accumarray(groupIndex, 1, [nGroups, 1]);
    if any(counts < options.minimumGroupRows)
        short = groupNames(counts < options.minimumGroupRows);
        error('STEP28_LAW_GROUP_SUPPORT: groups %s fall below %d rows.', strjoin(short, ', '), options.minimumGroupRows);
    end

    check_conditioning_rank(conditioning, groupIndex, nGroups, options.pooling);

    meanBlock = fit_affine_block(target, conditioning, groupIndex, nGroups, options.pooling);
    meanFitted = predict_affine_block(meanBlock, conditioning, groupIndex);
    residual = target - meanFitted;

    eulerMascheroni = 0.577215664901532860606512090082;
    logOffset = -(eulerMascheroni + log(2)) / 2;
    logAbsResidual = log(max(abs(residual), options.residualFloor));
    scaleBlock = fit_affine_block(logAbsResidual - logOffset, conditioning, groupIndex, nGroups, options.pooling);
    logScale = predict_affine_block(scaleBlock, conditioning, groupIndex);
    scale = exp(logScale);
    if any(~isfinite(scale), 'all') || any(scale <= 0, 'all')
        error('STEP28_LAW_SCALE: the fitted log-scale is not a positive scale.');
    end

    standardised = residual ./ scale;

    correlationIndex = correlation_index(groupIndex, options.correlationScope);
    rawCorrelation = raw_correlations(standardised, correlationIndex, dimension);

    [penalty, penaltyProfile, tuningDropped] = select_penalty(target,         conditioning, group, isControl, foldKey, options.penaltyGrid, dimension, options, logOffset);
    correlation = shrink_correlations(rawCorrelation, penalty, dimension);

    model = struct();
    model.schema_version = "step28_conditional_gaussian_v1";
    model.dimension = dimension;
    model.n_conditioning = size(conditioning, 2);
    model.pooling = string(options.pooling);
    model.correlation_scope = string(options.correlationScope);
    model.group_names = groupNames;
    model.mean_block = meanBlock;
    model.scale_block = scaleBlock;
    model.log_offset = logOffset;
    model.residual_floor = options.residualFloor;
    model.correlation_index_names = correlation_names(groupNames, options.correlationScope);
    model.correlation = correlation;
    model.penalty = penalty;
    model.penalty_grid = options.penaltyGrid(:)';
    model.penalty_profile = penaltyProfile;
    model.penalty_tuning_dropped_columns = tuningDropped;
    model.n_rows = nRows;
end

function check_conditioning_rank(conditioning, groupIndex, nGroups, pooling)

    nCovariates = size(conditioning, 2);
    if nCovariates == 0
        return;
    end
    tolerance = 1e-10 * max(1, norm(conditioning, 'fro'));

    if pooling == "per_group"
        for g = 1:nGroups
            rows = groupIndex == g;
            design = [ones(sum(rows), 1), conditioning(rows, :)];
            if rank(design, tolerance) < nCovariates + 1
                error(['STEP28_LAW_RANK_DEFICIENT: the conditioning block is '                     'rank deficient in group %d, so the affine coefficients ' 'are not identified.'], g);
            end
        end
        return;
    end

    groupMeanX = zeros(nGroups, nCovariates);
    for g = 1:nGroups
        groupMeanX(g, :) = mean(conditioning(groupIndex == g, :), 1);
    end
    demeaned = conditioning - groupMeanX(groupIndex, :);
    effectiveRank = rank(demeaned, tolerance);
    if effectiveRank < nCovariates
        constant = all(abs(demeaned) <= tolerance, 1);
        if any(constant)
            error(['STEP28_LAW_RANK_DEFICIENT: %d of %d conditioning columns '                 'carry no within-group variation in the fit sample, so the '                 'affine coefficients are not identified. Check whether '                 'law_fit_sample and control_conditioning_rule zero the same ' 'block.'], sum(constant), nCovariates);
        end
        error(['STEP28_LAW_RANK_DEFICIENT: the conditioning block has rank %d '             'out of %d columns with no column constant, so two or more frozen '             'columns are collinear. Check the frozen state and surprise '             'dictionaries for a duplicated or exactly rescaled column.'], effectiveRank, nCovariates);
    end
end

function dropped = unidentified_columns(conditioning, groupIndex, nGroups)

    nCovariates = size(conditioning, 2);
    dropped = false(1, nCovariates);
    if nCovariates == 0
        return;
    end
    tolerance = 1e-10 * max(1, norm(conditioning, 'fro'));
    groupMeanX = zeros(nGroups, nCovariates);
    for g = 1:nGroups
        groupMeanX(g, :) = mean(conditioning(groupIndex == g, :), 1);
    end
    demeaned = conditioning - groupMeanX(groupIndex, :);
    dropped = all(abs(demeaned) <= tolerance, 1);
end

function options = apply_defaults(options)
    if ~isfield(options, 'pooling') || isempty(options.pooling)
        options.pooling = "group_intercept_pooled_slopes";
    end
    options.pooling = string(options.pooling);
    if ~ismember(options.pooling, ["group_intercept_pooled_slopes", "per_group"])
        error(['STEP28_LAW_POOLING: pooling must be ' 'group_intercept_pooled_slopes or per_group.']);
    end
    if ~isfield(options, 'penaltyGrid') || isempty(options.penaltyGrid)
        options.penaltyGrid = [0, 0.05, 0.10, 0.20, 0.35, 0.50, 0.75, 1.00];
    end
    options.penaltyGrid = double(options.penaltyGrid(:))';
    if any(~isfinite(options.penaltyGrid)) || any(options.penaltyGrid < 0) || any(options.penaltyGrid > 1) || any(diff(options.penaltyGrid) <= 0)
        error(['STEP28_LAW_PENALTY_GRID: penaltyGrid must increase strictly ' 'within [0,1].']);
    end
    if ~isfield(options, 'minimumGroupRows') || isempty(options.minimumGroupRows)
        options.minimumGroupRows = 20;
    end
    if ~isfield(options, 'correlationScope') || isempty(options.correlationScope)
        options.correlationScope = "pooled";
    end
    options.correlationScope = string(options.correlationScope);
    if ~ismember(options.correlationScope, ["pooled", "per_group"])
        error('STEP28_LAW_CORRELATION_SCOPE: scope must be pooled or per_group.');
    end
    if ~isfield(options, 'residualFloor') || isempty(options.residualFloor)
        options.residualFloor = 1e-8;
    end
end

function block = fit_affine_block(response, conditioning, groupIndex, nGroups, pooling)
    dimension = size(response, 2);
    nCovariates = size(conditioning, 2);
    block = struct();
    block.pooling = pooling;
    block.n_groups = nGroups;

    if pooling == "per_group"
        block.intercept = zeros(nGroups, dimension);
        block.slope = zeros(nCovariates, dimension, nGroups);
        for g = 1:nGroups
            rows = groupIndex == g;
            X = [ones(sum(rows), 1), conditioning(rows, :)];
            beta = X \ response(rows, :);
            block.intercept(g, :) = beta(1, :);
            block.slope(:, :, g) = beta(2:end, :);
        end
        return;
    end

    groupMeanY = zeros(nGroups, dimension);
    groupMeanX = zeros(nGroups, nCovariates);
    for g = 1:nGroups
        rows = groupIndex == g;
        groupMeanY(g, :) = mean(response(rows, :), 1);
        groupMeanX(g, :) = mean(conditioning(rows, :), 1);
    end
    demeanedY = response - groupMeanY(groupIndex, :);
    demeanedX = conditioning - groupMeanX(groupIndex, :);
    slope = demeanedX \ demeanedY;
    if nCovariates == 0
        slope = zeros(0, dimension);
    end
    block.slope = slope;
    block.intercept = groupMeanY - groupMeanX * slope;
end

function fitted = predict_affine_block(block, conditioning, groupIndex)
    if block.pooling == "per_group"
        fitted = zeros(size(conditioning, 1), size(block.intercept, 2));
        for g = 1:block.n_groups
            rows = groupIndex == g;
            if ~any(rows); continue; end
            fitted(rows, :) = block.intercept(g, :) + conditioning(rows, :) * block.slope(:, :, g);
        end
        return;
    end
    fitted = block.intercept(groupIndex, :) + conditioning * block.slope;
end

function index = correlation_index(groupIndex, scope)
    if scope == "per_group"
        index = groupIndex;
    else
        index = ones(size(groupIndex));
    end
end

function names = correlation_names(groupNames, scope)
    if scope == "per_group"
        names = groupNames;
    else
        names = "pooled";
    end
end

function raw = raw_correlations(standardised, index, dimension)
    nBlocks = max(index);
    raw = zeros(dimension, dimension, nBlocks);
    for b = 1:nBlocks
        rows = index == b;
        if sum(rows) <= dimension
            error(['STEP28_LAW_CORRELATION_SUPPORT: correlation block %d has ' 'too few rows.'], b);
        end
        R = corrcoef_matrix(standardised(rows, :));
        raw(:, :, b) = R;
    end
end

function R = corrcoef_matrix(X)
    dimension = size(X, 2);
    if dimension == 1
        R = 1;
        return;
    end
    S = (X' * X) / size(X, 1);
    S = (S + S') / 2;
    scale = sqrt(diag(S));
    if any(scale <= 0)
        error('STEP28_LAW_CORRELATION_SCALE: standardised residuals are degenerate.');
    end
    R = S ./ (scale * scale');
    R = (R + R') / 2;
    R(1:dimension + 1:end) = 1;
end

function shrunk = shrink_correlations(raw, penalty, dimension)
    shrunk = raw;
    for b = 1:size(raw, 3)
        R = (1 - penalty) * raw(:, :, b) + penalty * eye(dimension);
        R = (R + R') / 2;
        R(1:dimension + 1:end) = 1;
        [~, notPositive] = chol(R);
        if notPositive ~= 0
            error(['STEP28_LAW_CORRELATION_PD: the shrunk correlation is not ' 'positive definite at penalty %g.'], penalty);
        end
        shrunk(:, :, b) = R;
    end
end

function [penalty, profile, dropped] = select_penalty(target, conditioning, group, isControl, foldKey, grid, dimension, options, logOffset)
    folds = unique(foldKey(isControl));
    if numel(folds) < 2
        error(['STEP28_LAW_TUNING_FOLDS: penalty selection needs at least two ' 'control folds.']);
    end

    dropped = false(1, size(conditioning, 2));
    prepared = cell(numel(folds), 1);
    reasons = strings(0, 1);
    for f = 1:numel(folds)
        trainRows = isControl & foldKey ~= folds(f);
        testRows = isControl & foldKey == folds(f);
        if ~any(trainRows) || ~any(testRows)
            reasons(end + 1, 1) = folds(f) + ": the fold leaves no control row on one side";
            continue;
        end
        [prepared{f}, reason, foldDropped] = prepare_penalty_fold(target, conditioning, group, trainRows, testRows, options, logOffset);
        if isempty(prepared{f})
            reasons(end + 1, 1) = folds(f) + ": " + reason;
        else
            dropped = dropped | foldDropped;
        end
    end

    nGrid = numel(grid);
    heldOutLogLikelihood = NaN(nGrid, 1);
    for q = 1:nGrid
        total = 0;
        usable = 0;
        for f = 1:numel(folds)
            if isempty(prepared{f})
                continue;
            end
            value = fold_log_likelihood(prepared{f}, grid(q), dimension);
            if isfinite(value)
                total = total + value;
                usable = usable + 1;
            end
        end
        if usable == numel(folds)
            heldOutLogLikelihood(q) = total;
        end
    end

    if all(~isfinite(heldOutLogLikelihood))
        if isempty(reasons)
            reasons = "the shrunk correlation was not usable in every fold";
        end
        error(['STEP28_LAW_TUNING_FAILED: no penalty on the frozen grid gave a '             'usable held-out likelihood. Folds reported: %s.'], strjoin(unique(reasons, 'stable'), '; '));
    end
    [~, best] = max(heldOutLogLikelihood);
    penalty = grid(best);
    profile = table(grid(:), heldOutLogLikelihood, 'VariableNames', {'penalty', 'held_out_log_likelihood'});
end

function [prepared, reason, dropped] = prepare_penalty_fold(target, conditioning, group, trainRows, testRows, options, logOffset)
    prepared = [];
    reason = "";
    dropped = false(1, size(conditioning, 2));
    trainGroupNames = unique(group(trainRows), 'stable');
    [foundTrain, trainIndex] = ismember(group(trainRows), trainGroupNames);
    [foundTest, testIndex] = ismember(group(testRows), trainGroupNames);
    if ~all(foundTrain) || ~all(foundTest)
        reason = "a group is missing from the tuning training rows";
        return;
    end
    nGroups = numel(trainGroupNames);
    counts = accumarray(trainIndex, 1, [nGroups, 1]);
    if any(counts < options.minimumGroupRows)
        reason = sprintf('a group holds fewer than %d control rows', options.minimumGroupRows);
        return;
    end

    trainConditioning = conditioning(trainRows, :);
    testConditioning = conditioning(testRows, :);
    trainTarget = target(trainRows, :);
    testTarget = target(testRows, :);

    dropped = unidentified_columns(trainConditioning, trainIndex, nGroups);
    trainConditioning = trainConditioning(:, ~dropped);
    testConditioning = testConditioning(:, ~dropped);

    try
        check_conditioning_rank(trainConditioning, trainIndex, nGroups, options.pooling);
        meanBlock = fit_affine_block(trainTarget, trainConditioning, trainIndex, nGroups, options.pooling);
        trainResidual = trainTarget - predict_affine_block(meanBlock, trainConditioning, trainIndex);
        testResidual = testTarget - predict_affine_block(meanBlock, testConditioning, testIndex);

        logAbs = log(max(abs(trainResidual), options.residualFloor));
        scaleBlock = fit_affine_block(logAbs - logOffset, trainConditioning, trainIndex, nGroups, options.pooling);
        trainScale = exp(predict_affine_block(scaleBlock, trainConditioning, trainIndex));
        testScale = exp(predict_affine_block(scaleBlock, testConditioning, testIndex));
    catch failure
        reason = string(failure.message);
        return;
    end
    if any(~isfinite(trainScale), 'all') || any(~isfinite(testScale), 'all') || any(trainScale <= 0, 'all') || any(testScale <= 0, 'all')
        reason = "the fitted log-scale is not a positive scale";
        return;
    end
    trainStandardised = trainResidual ./ trainScale;
    testStandardised = testResidual ./ testScale;
    if options.correlationScope == "pooled"
        trainIndex = ones(size(trainIndex));
        testIndex = ones(size(testIndex));
    end

    prepared = struct('train_standardised', trainStandardised,         'test_standardised', testStandardised, 'train_index', trainIndex, 'test_index', testIndex);
end

function value = fold_log_likelihood(prepared, penalty, dimension)
    trainStandardised = prepared.train_standardised;
    testStandardised = prepared.test_standardised;
    trainIndex = prepared.train_index;
    testIndex = prepared.test_index;
    value = 0;
    for b = 1:max(trainIndex)
        train = trainIndex == b;
        test = testIndex == b;
        if ~any(test)
            continue;
        end
        if sum(train) <= dimension
            value = NaN;
            return;
        end
        R = corrcoef_matrix(trainStandardised(train, :));
        R = (1 - penalty) * R + penalty * eye(dimension);
        R = (R + R') / 2;
        R(1:dimension + 1:end) = 1;
        [cholesky, notPositive] = chol(R, 'lower');
        if notPositive ~= 0
            value = NaN;
            return;
        end
        E = testStandardised(test, :);
        solved = cholesky \ E';
        quadratic = sum(solved .^ 2, 1)';
        logDeterminant = 2 * sum(log(diag(cholesky)));
        value = value - 0.5 * sum(quadratic) - 0.5 * numel(quadratic) * (logDeterminant + dimension * log(2 * pi));
    end
end
