function manifest = Require_time_alignment_manifest(projectRoot)
%REQUIRE_TIME_ALIGNMENT_MANIFEST Reject legacy cleaned files with unknown clocks.

    if nargin < 1 || strlength(string(projectRoot)) == 0
        projectRoot = Get_project_root();
    end

    cfg = Time_alignment_config();
    manifestFile = fullfile(projectRoot, 'Output', 'manifests', 'time_alignment_manifest.csv');

    if exist(manifestFile, 'file') ~= 2
        error(['TIME_ALIGNMENT_MANIFEST_MISSING: rerun Clean_raw_files. ' ...
            'Legacy cleaned files cannot be used because their Time column may be America/Chicago wall clock rather than canonical UTC.']);
    end

    manifest = readtable(manifestFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    required = ["schema_version", "raw_time_zone", "event_time_zone", ...
        "analysis_time_zone", "cleaned_time_column", "status"];
    missing = required(~ismember(required, string(manifest.Properties.VariableNames)));

    if ~isempty(missing) || height(manifest) ~= 1
        error('TIME_ALIGNMENT_MANIFEST_INVALID: malformed %s.', manifestFile);
    end

    ok = manifest.schema_version(1) == cfg.schema_version & ...
        manifest.raw_time_zone(1) == cfg.raw_time_zone & ...
        manifest.event_time_zone(1) == cfg.event_time_zone & ...
        manifest.analysis_time_zone(1) == cfg.analysis_time_zone & ...
        manifest.cleaned_time_column(1) == cfg.cleaned_time_column & ...
        manifest.status(1) == "complete";

    if ~ok
        error('TIME_ALIGNMENT_MANIFEST_MISMATCH: rerun Steps 1--2 with the current code before continuing.');
    end
end
