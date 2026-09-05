function [filePath, source] = Locate_ea_policy_dataset(projectRoot)
%LOCATE_EA_POLICY_DATASET Resolve the run-level policy-surprise source.

    source = Surprise_source_config(projectRoot);
    filePath = source.file_path;
end
