function manifest = Final_analysis_build_gate(projectRoot, buildDir)
    manifest = jsondecode(fileread(fullfile(buildDir, 'status.json')));
    assert(string(manifest.status) == "frozen", 'FINAL_BUILD_INCOMPLETE');
    assert(File_sha256(fullfile(buildDir, 'preferred_contracts.csv')) == string(manifest.table_hashes.preferred_contracts_csv), 'FINAL_PREFERRED_HASH_MISMATCH');
    H = readtable(fullfile(buildDir, 'input_hashes.csv'),         'Delimiter', ',', 'ReadVariableNames', true, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    assert(isequal(string(H.Properties.VariableNames), ["relative_path", "sha256"]), 'FINAL_INPUT_HASH_SCHEMA_MISMATCH');
    for i = 1:height(H)
        if H.relative_path(i) == "specification"
            source = fullfile(fileparts(mfilename('fullpath')), 'Raw', 'Certification', 'final_analysis_spec_v1.json');
        else
            source = fullfile(projectRoot, H.relative_path(i));
        end
        assert(File_sha256(source) == H.sha256(i), 'FINAL_SOURCE_HASH_MISMATCH: %s', source);
    end
end
