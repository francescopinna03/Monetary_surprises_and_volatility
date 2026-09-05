function cfg = Surprise_source_config(projectRoot)
%SURPRISE_SOURCE_CONFIG Resolve the policy-surprise input selected for a run.
%
% SURPRISE_SOURCE is deliberately a two-value contract:
%   EA_EMPD (default) - primary estimation source;
%   EA_MPD           - reproducible robustness source.

% The returned path is canonical and no output is used to select the source.

    if nargin < 1 || strlength(strtrim(string(projectRoot))) == 0
        projectRoot = Get_project_root();
    end

    requested = upper(strtrim(string(getenv('SURPRISE_SOURCE'))));
    requested = replace(requested, "-", "_");
    if strlength(requested) == 0
        requested = "EA_EMPD";
    end

    cfg = struct();
    cfg.schema_version = "surprise_source_v1";
    cfg.source_id = requested;

    switch requested
        case "EA_EMPD"
            cfg.dataset_name = "EA-EMPD";
            cfg.is_primary = true;
            cfg.relative_path = fullfile('Raw', 'EA-EMPD', 'EA-EMPD.xlsx');
            cfg.legacy_phase_sheets = strings(0, 1);
        case "EA_MPD"
            cfg.dataset_name = "EA-MPD";
            cfg.is_primary = false;
            cfg.relative_path = locate_ea_mpd_relative_path(projectRoot);
            cfg.legacy_phase_sheets = ["Press Release Window"; ...
                "Press Conference Window"; "Monetary Event Window"];
        otherwise
            error('SURPRISE_SOURCE_INVALID: expected EA_EMPD or EA_MPD, got %s.', ...
                requested);
    end

    cfg.file_path = string(fullfile(projectRoot, cfg.relative_path));
    if exist(cfg.file_path, 'file') ~= 2
        error('SURPRISE_SOURCE_MISSING: %s selected but %s was not found.', ...
            cfg.source_id, cfg.file_path);
    end
end

function relativePath = locate_ea_mpd_relative_path(projectRoot)
    candidates = [ ...
        string(fullfile('Raw', 'EA_MPD', 'Dataset_EA-MPD.xlsx')); ...
        string(fullfile('Raw', 'EA_MPD', 'Dataset_EA_MPD.xlsx')); ...
        string(fullfile('Raw', 'EA_MPD', 'EA-MPD.xlsx')); ...
        string(fullfile('Raw', 'EA_MPD', 'EA_MPD.xlsx'))];

    found = false(size(candidates));
    for j = 1:numel(candidates)
        found(j) = exist(fullfile(projectRoot, candidates(j)), 'file') == 2;
    end
    if sum(found) > 1
        error(['SURPRISE_SOURCE_AMBIGUOUS: multiple EA-MPD workbooks exist. ' ...
            'Keep exactly one supported workbook under Raw/EA_MPD.']);
    elseif ~any(found)
        % Return the documented canonical location so the error reports a
        % stable, actionable path.
        relativePath = candidates(1);
    else
        relativePath = candidates(find(found, 1));
    end
end
