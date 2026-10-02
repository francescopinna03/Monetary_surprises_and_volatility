function files = Require_generation_archive(rawDir)
    assert(exist(rawDir, 'dir') == 7, 'GENERATION_RAW_MISSING: %s', rawDir);
    files = dir(fullfile(rawDir, '*.csv'));
    files = files(~[files.isdir]);
    assert(~isempty(files), 'GENERATION_RAW_EMPTY');
    years = nan(numel(files), 1);
    for k = 1:numel(files)
        token = regexpi(files(k).name, '^(fx|gg|hf|hr)[hmuz](\d{2})_intraday-5min_historical-data-\d{2}-\d{2}-\d{4}\.csv$', 'tokens', 'once');
        assert(~isempty(token), 'GENERATION_UNKNOWN_FILENAME: %s', files(k).name);
        years(k) = 2000 + str2double(token{2});
        assert(years(k) >= 2013 && years(k) <= year(datetime('today')), 'GENERATION_MIXED_ARCHIVE: separate confirmation files before MATLAB: %s', files(k).name);
    end
    for k = 1:numel(files)
        fprintf('Generation raw input: %d %s\n', years(k), files(k).name);
    end
end
