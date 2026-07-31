function Phase_window_self_test()
%PHASE_WINDOW_SELF_TEST Freeze the non-overlap logic across timing regimes.

    prEarly = datetime(2021, 6, 10, 11, 45, 0);
    pcEarly = datetime(2021, 6, 10, 12, 30, 0);
    prLate = datetime(2023, 9, 14, 12, 15, 0);
    pcLate = datetime(2023, 9, 14, 12, 45, 0);

    assert(minutes(pcEarly - (prEarly + minutes(25))) == 20, ...
        'Early-regime PR-PC buffer must be 20 minutes.');
    assert(minutes(pcLate - (prLate + minutes(25))) == 5, ...
        'Late-regime PR-PC buffer must be 5 minutes.');

    provider = [prLate - minutes(5); prLate; prLate + minutes(5)];
    startEnds = Canonical_bar_end_time(provider, 5, "interval_start");
    endEnds = Canonical_bar_end_time(provider, 5, "interval_end");
    assert(all(startEnds == provider + minutes(5)));
    assert(all(endEnds == provider));
    fprintf('Phase_window_self_test: timing-regime and canonical-end checks passed.\n');
end
