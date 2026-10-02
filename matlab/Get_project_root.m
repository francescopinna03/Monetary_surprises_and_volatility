function projectRoot = Get_project_root()

    projectRoot = getenv('ECONOMETRICS_DATA_ROOT');

    if isempty(projectRoot)
        candidates = {fullfile(fileparts(mfilename('fullpath')), 'Econometrics_data'), fullfile(pwd, 'Econometrics_data')};

        for k = 1:numel(candidates)
            if exist(candidates{k}, 'dir')
                projectRoot = candidates{k};
                break
            end
        end
    end

    if isempty(projectRoot) || ~exist(fullfile(projectRoot, 'Raw'), 'dir')
        error('Could not locate the data package. Set the environment variable ECONOMETRICS_DATA_ROOT to the path of the unzipped Econometrics_data folder containing Raw and Output, or place the Econometrics_data folder next to the MATLAB scripts or in the current working directory.');
    end
end
