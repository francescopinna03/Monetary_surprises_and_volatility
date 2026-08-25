function filePath = Locate_ea_policy_dataset(projectRoot)

    filePath = fullfile(projectRoot, 'Raw', 'EA-EMPD', 'EA-EMPD.xlsx');
    if exist(filePath, 'file') ~= 2
        error('EA_EMPD_DATASET_MISSING: %s was not found.', filePath);
    end
end
