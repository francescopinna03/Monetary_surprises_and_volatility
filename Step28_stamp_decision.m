function decision = Step28_stamp_decision(decision, provenance)

    decision.data_manifest_sha256 = repmat( string(provenance.data_manifest_sha256), height(decision), 1);
    decision.specification_sha256 = repmat( string(provenance.specification_sha256), height(decision), 1);
    decision.state_panel_sha256 = repmat( string(provenance.state_panel_sha256), height(decision), 1);
    decision.surprise_source_sha256 = repmat( string(provenance.surprise_source_sha256), height(decision), 1);
    decision.surprise_manifest_sha256 = repmat( string(provenance.surprise_manifest_sha256), height(decision), 1);
    decision.code_sha256 = repmat(string(provenance.code_sha256), height(decision), 1);
end
