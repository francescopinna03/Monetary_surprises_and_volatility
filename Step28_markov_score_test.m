function result = Step28_markov_score_test(conditioning, group, history, residual, meetingKey, draws, seed)

    conditioning = double(conditioning);
    history = double(history);
    residual = double(residual);
    group = string(group(:));
    meetingKey = string(meetingKey(:));

    nRows = size(residual, 1);
    if size(conditioning, 1) ~= nRows || size(history, 1) ~= nRows || numel(meetingKey) ~= nRows || numel(group) ~= nRows
        error('STEP28_SCORE_ROWS: every block must have one row per transition.');
    end
    if isempty(history) || size(history, 2) == 0
        error('STEP28_SCORE_NO_HISTORY: the history block is empty.');
    end

    [groupIndex, groupNames] = findgroups(group);
    dummies = zeros(nRows, numel(groupNames));
    for g = 1:numel(groupNames)
        dummies(:, g) = double(groupIndex == g);
    end
    X = [dummies, conditioning];

    residualised = history - X * (pinv(X' * X) * (X' * history));
    tolerance = 1e-10 * max(1, norm(residualised, 'fro'));
    [U, S, ~] = svd(residualised, 'econ');
    keep = diag(S) > tolerance;
    if ~any(keep)
        error(['STEP28_SCORE_HISTORY_SPANNED: the history block lies in the ' 'conditioning set, so the null is untestable.']);
    end
    basis = U(:, keep);

    statistic = sum((basis' * residual) .^ 2, 'all');

    [meetingIndex, meetings] = findgroups(meetingKey);
    stream = RandStream('mt19937ar', 'Seed', seed);
    nullStatistic = NaN(draws, 1);
    for b = 1:draws
        signs = 2 * (rand(stream, numel(meetings), 1) >= 0.5) - 1;
        starred = residual .* signs(meetingIndex);
        nullStatistic(b) = sum((basis' * starred) .^ 2, 'all');
    end

    result = struct();
    result.schema_version = "step28_markov_score_v1";
    result.statistic = statistic;
    result.critical_value = quantile(nullStatistic, 0.95);
    result.p_value = (1 + sum(nullStatistic >= statistic)) / (draws + 1);
    result.rejects = statistic > result.critical_value;
    result.history_dimension = sum(keep);
    result.basis = basis;
    result.n_rows = nRows;
    result.n_meetings = numel(meetings);
    result.null_statistic = nullStatistic;
end
