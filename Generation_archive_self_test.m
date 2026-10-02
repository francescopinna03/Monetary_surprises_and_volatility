function Generation_archive_self_test()
    directory = tempname;
    mkdir(directory);
    cleanup = onCleanup(@() rmdir(directory, 's'));
    good = fullfile(directory, 'ggh13_intraday-5min_historical-data-09-12-2026.csv');
    fid = fopen(good, 'w'); fclose(fid);
    assert(numel(Require_generation_archive(directory)) == 1);
    bad = fullfile(directory, 'ggh00_intraday-5min_historical-data-09-12-2026.csv');
    fid = fopen(bad, 'w'); fclose(fid);
    rejected = false;
    try
        Require_generation_archive(directory);
    catch err
        rejected = contains(err.message, 'GENERATION_MIXED_ARCHIVE');
    end
    assert(rejected, 'Generation archive guard did not reject a mixed folder');
    fprintf('Generation archive self-test passed.\n');
end
