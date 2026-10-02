function result = Step28_state_partial_r2(conditioningWithoutState, stateBlock, group, target, meetingKey, foldKey, draws, seed)

    conditioningWithoutState = double(conditioningWithoutState);
    stateBlock = double(stateBlock);
    target = double(target);
    group = string(group(:));
    meetingKey = string(meetingKey(:));
    foldKey = string(foldKey(:));

    pointEstimate = out_of_fold_partial_r2(conditioningWithoutState, stateBlock, group, target, foldKey);

    [meetingIndex, meetings] = findgroups(meetingKey);
    rowsOf = cell(numel(meetings), 1);
    for m = 1:numel(meetings)
        rowsOf{m} = find(meetingIndex == m);
    end

    stream = RandStream('mt19937ar', 'Seed', seed);
    bootstrap = NaN(draws, 1);
    for b = 1:draws
        drawn = randi(stream, numel(meetings), numel(meetings), 1);
        rows = vertcat(rowsOf{drawn});
        try
            bootstrap(b) = out_of_fold_partial_r2(                 conditioningWithoutState(rows, :), stateBlock(rows, :), group(rows), target(rows, :), foldKey(rows));
        catch
            bootstrap(b) = NaN;
        end
    end

    usable = bootstrap(isfinite(bootstrap));
    if numel(usable) < 0.5 * draws
        lowerBound = NaN;
        status = "unavailable";
    else
        lowerBound = quantile(usable, 0.025);
        status = "estimated";
    end

    result = struct();
    result.schema_version = "step28_state_partial_r2_v1";
    result.status = status;
    result.point_estimate = pointEstimate;
    result.lower_bound = lowerBound;
    result.usable_draws = numel(usable);
    result.draws = draws;
end

function value = out_of_fold_partial_r2(withoutState, stateBlock, group, target, foldKey)
    folds = unique(foldKey);
    if numel(folds) < 2
        error('STEP28_PARTIAL_R2_FOLDS: at least two folds are required.');
    end
    [groupIndex, groupNames] = findgroups(group);
    dummies = zeros(numel(groupIndex), numel(groupNames));
    for g = 1:numel(groupNames)
        dummies(:, g) = double(groupIndex == g);
    end
    without = [dummies, withoutState];
    with = [without, stateBlock];

    residualWithout = out_of_fold_residual(without, target, foldKey, folds);
    residualWith = out_of_fold_residual(with, target, foldKey, folds);
    denominator = sum(residualWithout .^ 2, 'all');
    if ~(denominator > 0)
        error('STEP28_PARTIAL_R2_DEGENERATE: the baseline residual vanishes.');
    end
    value = 1 - sum(residualWith .^ 2, 'all') / denominator;
end

function residual = out_of_fold_residual(design, target, foldKey, folds)
    residual = NaN(size(target));
    for f = 1:numel(folds)
        train = foldKey ~= folds(f);
        test = ~train;
        if sum(train) <= size(design, 2) || ~any(test)
            residual(test, :) = target(test, :);
            continue;
        end
        beta = design(train, :) \ target(train, :);
        residual(test, :) = target(test, :) - design(test, :) * beta;
    end
    if any(~isfinite(residual), 'all')
        error('STEP28_PARTIAL_R2_RESIDUAL: some rows were never predicted.');
    end
end
