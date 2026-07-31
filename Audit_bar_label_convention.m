function [rows, summary] = Audit_bar_label_convention(oneMinute, fiveMinute, tolerance)
%AUDIT_BAR_LABEL_CONVENTION Identify interval-start versus interval-end labels.
%
% Both inputs must use the standardized columns time_utc, Open, High, Low,
% Latest and Volume. Each five-minute bar is reconstructed from one-minute
% bars under the two competing timestamp conventions.

    if nargin < 3 || isempty(tolerance)
        tolerance = 1e-10;
    end

    rows = table();
    rowCells = cell(height(fiveMinute) * 2, 1);
    cursor = 0;

    for i = 1:height(fiveMinute)
        for convention = ["interval_start", "interval_end"]
            cursor = cursor + 1;
            rowCells{cursor} = compare_one_bar(oneMinute, fiveMinute(i, :), ...
                convention, tolerance);
        end
    end

    if cursor > 0
        rows = vertcat(rowCells{1:cursor});
    end

    conventions = ["interval_start"; "interval_end"];
    summary = table();
    summary.convention = conventions;
    summary.n_five_minute_bars = repmat(height(fiveMinute), 2, 1);
    summary.n_aggregatable = zeros(2, 1);
    summary.aggregation_share = nan(2, 1);
    summary.ohlcv_exact_share = nan(2, 1);
    summary.volume_exact_share = nan(2, 1);
    summary.mean_field_match_share = nan(2, 1);

    for j = 1:2
        X = rows(rows.convention == conventions(j), :);
        summary.n_aggregatable(j) = sum(X.has_five_one_minute_bars);
        summary.aggregation_share(j) = mean(X.has_five_one_minute_bars);
        valid = X.has_five_one_minute_bars;
        summary.ohlcv_exact_share(j) = safe_mean(double(X.all_fields_match(valid)));
        summary.volume_exact_share(j) = safe_mean(double(X.volume_match(valid)));
        summary.mean_field_match_share(j) = safe_mean(X.field_match_share(valid));
    end

    score = summary.ohlcv_exact_share;
    [bestScore, best] = max(score);
    other = 3 - best;
    margin = bestScore - score(other);
    enoughRows = summary.n_aggregatable(best) >= 100;
    pass = enoughRows && isfinite(bestScore) && bestScore >= 0.95 && ...
        isfinite(margin) && margin >= 0.20;

    summary.selected = false(2, 1);
    summary.selected(best) = pass;
    summary.score_margin = repmat(margin, 2, 1);
    summary.overall_pass = repmat(pass, 2, 1);
    if pass
        summary.decision = repmat(conventions(best), 2, 1);
    else
        summary.decision = repmat("UNRESOLVED", 2, 1);
    end
end

function row = compare_one_bar(oneMinute, fiveBar, convention, tolerance)
    t = fiveBar.time_utc;
    if convention == "interval_start"
        expected = transpose(t : minutes(1) : t + minutes(4));
    else
        expected = transpose(t - minutes(4) : minutes(1) : t);
    end

    [present, loc] = ismember(expected, oneMinute.time_utc);
    hasFive = all(present);
    aggregate = nan(1, 5);

    if hasFive
        X = oneMinute(loc, :);
        aggregate = [X.Open(1), max(X.High), min(X.Low), ...
            X.Latest(end), sum(X.Volume)];
    end

    observed = [fiveBar.Open, fiveBar.High, fiveBar.Low, ...
        fiveBar.Latest, fiveBar.Volume];
    scale = max(1, max(abs(aggregate), abs(observed)));
    matches = hasFive & abs(aggregate - observed) <= tolerance .* scale;

    row = table();
    row.five_minute_time_utc = t;
    row.convention = convention;
    row.has_five_one_minute_bars = hasFive;
    row.open_match = matches(1);
    row.high_match = matches(2);
    row.low_match = matches(3);
    row.close_match = matches(4);
    row.volume_match = matches(5);
    row.field_match_share = mean(matches);
    row.all_fields_match = all(matches);
    row.observed_volume = observed(5);
    row.aggregated_volume = aggregate(5);
end

function value = safe_mean(x)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = mean(x);
    end
end
