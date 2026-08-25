function filePath = Locate_ea_policy_dataset(projectRoot)

    explicitFile = strtrim(string(getenv('EA_POLICY_DATASET_FILE')));
    if strlength(explicitFile) > 0
        if exist(explicitFile, 'file') ~= 2
            error('EA_POLICY_DATASET_FILE_NOT_FOUND: %s', explicitFile);
        end
        filePath = explicitFile;
        return;
    end

    mode = lower(strtrim(string(getenv('EA_POLICY_DATASET'))));
    if strlength(mode) == 0
        mode = "auto";
    end

    roots = {
        fullfile(projectRoot, 'Raw', 'EA-EMPD');
        fullfile(projectRoot, 'Raw', 'EA_EMPD');
        fullfile(projectRoot, 'Raw', 'EA_MPD')};
    newNames = {
        'EA-EMPD.en.xlsx';
        'EA-EMPD.xlsx';
        'EA_EMPD.en.xlsx';
        'EA_EMPD.xlsx'};
    legacyNames = {
        'Dataset_EA-MPD.xlsx';
        'Dataset_EA_MPD.xlsx';
        'EA-MPD.xlsx';
        'EA_MPD.xlsx'};

    newCandidates = combine_paths(roots, newNames);
    legacyCandidates = combine_paths(roots, legacyNames);

    if ismember(mode, ["ea_empd", "ea-empd", "new"])
        candidates = newCandidates;
    elseif ismember(mode, ["ea_mpd", "ea-mpd", "legacy"])
        candidates = legacyCandidates;
    elseif mode == "auto"
        candidates = [newCandidates; legacyCandidates];
    else
        error('EA_POLICY_DATASET_MODE: unsupported value %s.', mode);
    end

    filePath = Locate_first_existing(candidates);
    if strlength(filePath) == 0 && mode ~= "auto"
        error('EA_POLICY_DATASET_MISSING: no workbook found for mode %s.', mode);
    end
end

function paths = combine_paths(roots, names)
    paths = cell(numel(roots) * numel(names), 1);
    cursor = 0;
    for r = 1:numel(roots)
        for n = 1:numel(names)
            cursor = cursor + 1;
            paths{cursor} = fullfile(roots{r}, names{n});
        end
    end
end
