function Surprise_source_self_test()
%SURPRISE_SOURCE_SELF_TEST Synthetic contract test for EA-EMPD/EA-MPD routing.

    oldSource = getenv('SURPRISE_SOURCE');
    testRoot = string(tempname);
    cleanup = onCleanup(@() restore_state(oldSource, testRoot)); %#ok<NASGU>
    mkdir(testRoot);
    mkdir(fullfile(testRoot, 'Raw'));
    mkdir(fullfile(testRoot, 'Output'));
    mkdir(fullfile(testRoot, 'Raw', 'EA-EMPD'));
    mkdir(fullfile(testRoot, 'Raw', 'EA_MPD'));

    empdFile = fullfile(testRoot, 'Raw', 'EA-EMPD', 'EA-EMPD.xlsx');
    mpdFile = fullfile(testRoot, 'Raw', 'EA_MPD', 'Dataset_EA-MPD.xlsx');
    dates = datetime([2001, 2008, 2008], [9, 10, 10], [17, 8, 8])';
    U = table(["GC_PR"; "GC_PR"; "GC_PC"], dates, ...
        [1; 2; 3], [2; 3; 4], [3; 4; 5], [4; 5; 6], [5; 6; 7], ...
        'VariableNames', {'event_type', 'date_time', 'OIS_1M', 'OIS_3M', ...
        'OIS_6M', 'OIS_1Y', 'STOXX50E'});
    writetable(U, empdFile, 'Sheet', 'EA-EMPD');

    L = table(datetime([2001, 2008], [9, 10], [17, 8])', [1; 2], ...
        [2; 3], [3; 4], [4; 5], [5; 6], 'VariableNames', ...
        {'Date', 'OIS_1M', 'OIS_3M', 'OIS_6M', 'OIS_1Y', 'STOXX50'});
    writetable(L, mpdFile, 'Sheet', 'Press Release Window');
    writetable(L, mpdFile, 'Sheet', 'Press Conference Window', ...
        'WriteMode', 'overwritesheet');
    writetable(L, mpdFile, 'Sheet', 'Monetary Event Window', ...
        'WriteMode', 'overwritesheet');

    setenv('SURPRISE_SOURCE', '');
    [resolved, source] = Locate_ea_policy_dataset(testRoot);
    assert(source.source_id == "EA_EMPD" && source.is_primary);
    assert(string(resolved) == string(empdFile));
    [T, metadata] = Read_ea_policy_window(resolved, "PR", source.source_id);
    assert(metadata.dataset_name == "EA-EMPD" && height(T) == 2);
    assert(T.window_timing_valid(T.event_date == datetime(2001, 9, 17)));
    assert(~T.window_timing_valid(T.event_date == datetime(2008, 10, 8)));

    setenv('SURPRISE_SOURCE', 'EA-MPD');
    [resolved, source] = Locate_ea_policy_dataset(testRoot);
    assert(source.source_id == "EA_MPD" && ~source.is_primary);
    assert(string(resolved) == string(mpdFile));
    [T, metadata] = Read_ea_policy_window(resolved, "PC", source.source_id);
    assert(metadata.dataset_name == "EA-MPD" && height(T) == 2);

    panelFile = fullfile(testRoot, 'Output', 'panel.csv');
    matchFile = fullfile(testRoot, 'Output', 'match.csv');
    writetable(table((1:2)', 'VariableNames', {'value'}), panelFile);
    writetable(table(1, 'VariableNames', {'value'}), matchFile);
    Write_surprise_source_manifest(testRoot, source, panelFile, matchFile);
    M = Require_surprise_source_manifest(testRoot, source);
    assert(M.surprise_source == "EA_MPD");

    setenv('SURPRISE_SOURCE', 'not_a_dataset');
    didFail = false;
    try
        Surprise_source_config(testRoot);
    catch ME
        didFail = contains(string(ME.message), "SURPRISE_SOURCE_INVALID");
    end
    assert(didFail, 'Invalid SURPRISE_SOURCE must fail closed.');

    fprintf('Surprise_source_self_test passed.\n');
end

function restore_state(oldSource, testRoot)
    setenv('SURPRISE_SOURCE', oldSource);
    if exist(testRoot, 'dir') == 7
        rmdir(testRoot, 's');
    end
end
