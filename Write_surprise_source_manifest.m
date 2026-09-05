function manifest = Write_surprise_source_manifest(projectRoot, source, panelFile, matchFile)
%WRITE_SURPRISE_SOURCE_MANIFEST Record the exact policy input used by Step 6.

    manifestDir = fullfile(projectRoot, 'Output', 'manifests');
    if exist(manifestDir, 'dir') ~= 7; mkdir(manifestDir); end

    sourceInfo = dir(source.file_path);
    if isempty(sourceInfo)
        error('SURPRISE_SOURCE_MANIFEST_INPUT: source file disappeared: %s.', ...
            source.file_path);
    end

    manifest = table();
    manifest.schema_version = string(source.schema_version);
    manifest.status = "complete";
    manifest.surprise_source = string(source.source_id);
    manifest.dataset_name = string(source.dataset_name);
    manifest.primary_estimation_source = logical(source.is_primary);
    manifest.source_file = string(source.relative_path);
    manifest.source_file_bytes = sourceInfo.bytes;
    manifest.source_file_sha256 = File_sha256(source.file_path);
    manifest.step6_panel_file = relative_to_root(projectRoot, panelFile);
    manifest.step6_panel_sha256 = File_sha256(panelFile);
    manifest.step6_match_summary_file = relative_to_root(projectRoot, matchFile);
    manifest.step6_match_summary_sha256 = File_sha256(matchFile);
    [codeCommit, codeDirty] = current_code_state();
    manifest.code_commit = codeCommit;
    manifest.code_worktree_dirty = codeDirty;
    codeRoot = fileparts(which('Write_surprise_source_manifest'));
    manifest.step6_script_sha256 = File_sha256(fullfile(codeRoot, ...
        'Press_release_panel.m'));
    manifest.source_config_sha256 = File_sha256(fullfile(codeRoot, ...
        'Surprise_source_config.m'));
    manifest.source_reader_sha256 = File_sha256(fullfile(codeRoot, ...
        'Read_ea_policy_window.m'));
    manifest.manifest_writer_sha256 = File_sha256(fullfile(codeRoot, ...
        'Write_surprise_source_manifest.m'));
    manifest.generated_at_utc = string(datetime('now', 'TimeZone', 'UTC'), ...
        'yyyy-MM-dd''T''HH:mm:ssXXX');

    writetable(manifest, fullfile(manifestDir, ...
        'surprise_source_manifest.csv'));
end

function [commit, dirty] = current_code_state()
    codeRoot = fileparts(which('Write_surprise_source_manifest'));
    [status, output] = system(sprintf( ...
        'git -C "%s" rev-parse HEAD 2>/dev/null', codeRoot));
    if status == 0
        commit = strtrim(string(output));
        [dirtyStatus, dirtyOutput] = system(sprintf( ...
            'git -C "%s" status --porcelain --untracked-files=all 2>/dev/null', ...
            codeRoot));
        dirty = dirtyStatus ~= 0 || strlength(strtrim(string(dirtyOutput))) > 0;
    else
        commit = string(getenv('STEP21_GIT_SHA'));
        if strlength(commit) == 0; commit = "unavailable"; end
        dirty = true;
    end
end

function relative = relative_to_root(projectRoot, filePath)
    rootPrefix = regexprep(string(projectRoot), '[\\/]+$', '') + ...
        string(filesep);
    filePath = string(filePath);
    if ~startsWith(filePath, rootPrefix)
        error('SURPRISE_SOURCE_MANIFEST_PATH: output is outside the data root: %s.', ...
            filePath);
    end
    relative = extractAfter(filePath, strlength(rootPrefix));
end
