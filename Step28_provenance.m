function provenance = Step28_provenance(projectRoot, specification)

    outputDir = fullfile(projectRoot, 'Output', 'step28_sbbts');
    manifestFile = fullfile(outputDir, 'step28_barchart_data_manifest.csv');
    sourceManifest = fullfile(projectRoot, 'Output', 'manifests', 'surprise_source_manifest.csv');
    statePanel = fullfile(projectRoot, 'Output', 'analysis', 'event_state_panel.csv');

    provenance = struct();
    provenance.schema_version = "step28_provenance_v1";

    if isfile(manifestFile)
        provenance.data_manifest_sha256 = File_sha256(manifestFile);
    else
        provenance.data_manifest_sha256 = "missing";
    end

    if nargin >= 2 && ~isempty(specification) && isfield(specification, 'specification_sha256')
        provenance.specification_sha256 = string(specification.specification_sha256);
    else
        provenance.specification_sha256 = "missing";
    end

    if isfile(statePanel)
        provenance.state_panel_sha256 = File_sha256(statePanel);
    else
        provenance.state_panel_sha256 = "missing";
    end

    if isfile(sourceManifest)
        provenance.surprise_manifest_sha256 = File_sha256(sourceManifest);
        T = readtable(sourceManifest, 'Delimiter', ',', 'TextType', 'string', 'VariableNamingRule', 'preserve');
        required = ["surprise_source", "source_file", "source_file_sha256"];
        if height(T) == 1 && all(ismember(required, string(T.Properties.VariableNames)))
            provenance.surprise_source = string(T.surprise_source(1));
            sourceFile = fullfile(projectRoot, string(T.source_file(1)));
            if isfile(sourceFile) && File_sha256(sourceFile) == string(T.source_file_sha256(1))
                provenance.surprise_source_sha256 = File_sha256(sourceFile);
            else
                provenance.surprise_source_sha256 = "stale";
            end
        else
            provenance.surprise_source_sha256 = "unreadable";
            provenance.surprise_source = "unreadable";
        end
    else
        provenance.surprise_manifest_sha256 = "missing";
        provenance.surprise_source_sha256 = "missing";
        provenance.surprise_source = "missing";
    end

    provenance.code_sha256 = step28_code_hash();
end

function digest = step28_code_hash()
    here = fileparts(which('Step28_provenance'));
    patterns = ["Step28_*.m", "SBB_*.m", "Run_step28*.m", "Run_step28*.sh", "step28_*.py"];
    names = strings(0, 1);
    for p = 1:numel(patterns)
        found = dir(fullfile(here, patterns(p)));
        for f = 1:numel(found)
            names(end + 1, 1) = string(found(f).name);
        end
    end
    names = unique(names);
    parts = strings(numel(names), 1);
    for i = 1:numel(names)
        parts(i) = names(i) + ":" + File_sha256(fullfile(here, names(i)));
    end
    dependencies = ["File_sha256.m", "Get_project_root.m",         "Parse_utc_datetime.m", "String_to_boolean.m",         "Surprise_source_config.m", "Require_surprise_source_manifest.m", "Require_time_alignment_manifest.m"];
    for i = 1:numel(dependencies)
        path = fullfile(here, dependencies(i));
        if ~isfile(path)
            error('STEP28_PROVENANCE_DEPENDENCY: missing %s.', path);
        end
        parts(end + 1, 1) = dependencies(i) + ":" + File_sha256(path);
    end
    combined = strjoin(sort(parts), '|');

    temporary = [tempname, '.txt'];
    cleanup = onCleanup(@() delete_if_present(temporary));
    fid = fopen(temporary, 'w');
    if fid < 0
        error('STEP28_PROVENANCE_TEMP: cannot write the code hash buffer.');
    end
    fwrite(fid, char(combined));
    fclose(fid);
    digest = File_sha256(temporary);
end

function delete_if_present(path)
    if isfile(path)
        delete(path);
    end
end
