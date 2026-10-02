function Archive_analysis_outputs(directory, names)
    names = string(names);
    paths = fullfile(directory, names);
    paths = paths(isfile(paths));
    if isempty(paths); return; end
    archiveRoot = fullfile(directory, 'archive');
    if ~isfolder(archiveRoot); mkdir(archiveRoot); end
    archiveDir = tempname(archiveRoot);
    mkdir(archiveDir);
    for path = paths(:)'
        [~, name, extension] = fileparts(path);
        movefile(path, fullfile(archiveDir, name + extension));
    end
end
