function Window_semantics_self_test()
%WINDOW_SEMANTICS_SELF_TEST Deterministic provenance and bar-label tests.

    rng(22027, 'twister');
    t0 = datetime(2023, 9, 14, 6, 0, 0);
    times = transpose(t0 : minutes(1) : t0 + minutes(599));
    n = numel(times);
    open = 100 + cumsum([0; 0.01 * randn(n - 1, 1)]);
    close = open + 0.01 * randn(n, 1);
    high = max(open, close) + 0.005 * rand(n, 1);
    low = min(open, close) - 0.005 * rand(n, 1);
    volume = randi([1, 1000], n, 1);

    one = table(times, open, high, low, close, volume, ...
        'VariableNames', {'time_utc', 'Open', 'High', 'Low', 'Latest', 'Volume'});
    fiveStart = aggregate_five(one, "interval_start");
    fiveEnd = aggregate_five(one, "interval_end");

    [~, startSummary] = Audit_bar_label_convention(one, fiveStart, 1e-12);
    [~, endSummary] = Audit_bar_label_convention(one, fiveEnd, 1e-12);

    archive = fiveStart;
    premier = fiveStart;
    archive.wall_time = archive.time_utc;
    premier.wall_time = premier.time_utc;
    timeSummary = Audit_timezone_provenance(archive, premier, 1e-12);

    assert(all(startSummary.decision == "interval_start"), ...
        'Start-label synthetic data were not identified.');
    assert(all(endSummary.decision == "interval_end"), ...
        'End-label synthetic data were not identified.');
    assert(all(timeSummary.overall_pass), ...
        'Identical archived and Premier exports did not pass provenance audit.');
    fprintf(['Window_semantics_self_test: provenance, interval-start and ' ...
        'interval-end checks passed.\n']);
end

function five = aggregate_five(one, convention)
    startRows = 1:5:(height(one) - 4);
    m = numel(startRows);
    time = NaT(m, 1);
    Open = nan(m, 1);
    High = nan(m, 1);
    Low = nan(m, 1);
    Latest = nan(m, 1);
    Volume = nan(m, 1);

    for i = 1:m
        idx = startRows(i):(startRows(i) + 4);
        X = one(idx, :);
        if convention == "interval_start"
            time(i) = X.time_utc(1);
        else
            time(i) = X.time_utc(end);
        end
        Open(i) = X.Open(1);
        High(i) = max(X.High);
        Low(i) = min(X.Low);
        Latest(i) = X.Latest(end);
        Volume(i) = sum(X.Volume);
    end

    five = table(time, Open, High, Low, Latest, Volume, ...
        'VariableNames', {'time_utc', 'Open', 'High', 'Low', 'Latest', 'Volume'});
end
