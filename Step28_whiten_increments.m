function [panel, moments] = Step28_whiten_increments(returns, dateKey, position, foldKey, isControl, minimumDates)

    if nargin < 6 || isempty(minimumDates)
        minimumDates = 30;
    end

    returns = double(returns);
    dateKey = string(dateKey(:));
    position = double(position(:));
    foldKey = string(foldKey(:));
    isControl = logical(isControl(:));
    minimumDates = double(minimumDates);

    nRows = size(returns, 1);
    dimension = size(returns, 2);
    if nRows == 0 || dimension == 0
        error('STEP28_WHITEN_EMPTY: returns must be a non-empty N-by-d array.');
    end
    if any(~isfinite(returns), 'all')
        error('STEP28_WHITEN_NONFINITE: returns must be finite.');
    end
    if numel(dateKey) ~= nRows || numel(position) ~= nRows || numel(foldKey) ~= nRows || numel(isControl) ~= nRows
        error('STEP28_WHITEN_DIMENSIONS: every label must have one entry per row.');
    end
    if any(~isfinite(position)) || any(position < 1) || any(position ~= floor(position))
        error('STEP28_WHITEN_POSITION: position must be a positive integer.');
    end
    if ~isscalar(minimumDates) || ~isfinite(minimumDates) || minimumDates < dimension + 1
        error(['STEP28_WHITEN_MINIMUM: minimumDates must be a scalar of at ' 'least d+1 control dates.']);
    end
    if ~any(isControl)
        error('STEP28_WHITEN_NO_CONTROLS: normal moments require control rows.');
    end

    [~, ~, pairIndex] = unique(dateKey + "|" + string(position));
    if numel(pairIndex) ~= numel(unique(pairIndex))
        error(['STEP28_WHITEN_DUPLICATE: a date supplies at most one row per ' 'intraday position.']);
    end

    folds = unique(foldKey);
    positions = unique(position);
    whitened = NaN(nRows, dimension);

    momentFold = strings(0, 1);
    momentPosition = zeros(0, 1);
    momentCount = zeros(0, 1);
    momentMean = zeros(0, dimension);
    momentCholesky = zeros(0, dimension * dimension);
    momentCondition = zeros(0, 1);

    for f = 1:numel(folds)
        for q = 1:numel(positions)
            k = positions(q);
            target = position == k & foldKey == folds(f);
            if ~any(target)
                continue;
            end

            estimation = isControl & position == k & foldKey ~= folds(f);
            nDates = sum(estimation);
            if nDates < minimumDates
                error(['STEP28_WHITEN_SUPPORT: fold %s position %d has %d '                     'control dates, below the frozen minimum of %d.'], folds(f), k, nDates, minimumDates);
            end

            sample = returns(estimation, :);
            centre = mean(sample, 1);
            covariance = cov(sample);
            covariance = (covariance + covariance') / 2;
            [cholesky, notPositive] = chol(covariance, 'lower');
            if notPositive ~= 0
                error(['STEP28_WHITEN_COVARIANCE: the normal covariance at '                     'fold %s position %d is not positive definite.'], folds(f), k);
            end

            centred = returns(target, :) - centre;
            whitened(target, :) = (cholesky \ centred')';

            momentFold(end + 1, 1) = folds(f);
            momentPosition(end + 1, 1) = k;
            momentCount(end + 1, 1) = nDates;
            momentMean(end + 1, :) = centre;
            momentCholesky(end + 1, :) = reshape(cholesky, 1, []);
            momentCondition(end + 1, 1) = cond(covariance);
        end
    end

    if any(~isfinite(whitened), 'all')
        error('STEP28_WHITEN_INCOMPLETE: some rows were never whitened.');
    end

    level = NaN(nRows, dimension);
    [dateGroup, dateNames] = findgroups(dateKey);
    for g = 1:numel(dateNames)
        rows = find(dateGroup == g);
        [~, order] = sort(position(rows));
        rows = rows(order);
        level(rows, :) = cumsum(whitened(rows, :), 1);
    end

    panel = table(dateKey, position, foldKey, isControl, 'VariableNames', {'date_key', 'position', 'fold_key', 'is_control'});
    panel.increment = whitened;
    panel.level = level;
    panel = sortrows(panel, {'date_key', 'position'});

    moments = table(momentFold, momentPosition, momentCount, 'VariableNames', {'fold_key', 'position', 'n_control_dates'});
    moments.normal_mean = momentMean;
    moments.normal_cholesky = momentCholesky;
    moments.covariance_condition = momentCondition;
end
