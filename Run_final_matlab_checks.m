function Run_final_matlab_checks()
    root = Get_project_root();
    Generation_archive_self_test();
    build = string(getenv('FINAL_ANALYSIS_BUILD'));
    assert(strlength(build)>0, 'FINAL_ANALYSIS_BUILD must point to a frozen build.');
    Final_analysis_build_gate(root, build);
    if string(getenv('FINAL_GENERATION_ONLY')) == "1"
        p = readtable(fullfile(build, 'preferred_contracts.csv'), 'TextType', 'string');
        dates = Parse_date_flexible(p.event_date);
        assert(all(~isnat(dates) & dates >= datetime(2013,1,1)), 'FINAL_GENERATION_LEAKAGE: frozen selection contains pre-2013 dates');
        fprintf('Generation subset 2013-2025; later rows excluded: %d\n', sum(dates >= datetime(2026,1,1)));
    end
    Require_time_alignment_manifest(root);
    Require_window_semantics_manifest(root);
    Final_window_self_test();
    archive = fullfile(root, 'Output', 'archive', "before_final_matlab_" + string(datetime('now'), 'yyyyMMdd_HHmmss'));
    assert(exist(archive, 'dir')~=7, 'Archive already exists.');
    mkdir(archive);
    for name = ["analysis", "event_windows"]
        source = fullfile(root, 'Output', name);
        if exist(source, 'dir')==7; copyfile(source, fullfile(archive, name)); end
    end
    for stage = ["Event_windows", "Press_release_panel", "PR_signal_model",             "State_vector_panel", "State_dependent_models", "Volatility_components", "Hierarchical_shrinkage", "PR_bar_panel", "BNS_volatility"]
        fprintf('\nFinal auxiliary rebuild: %s\n', stage);
        run_stage(stage);
    end
    fprintf('Auxiliary rebuild completed. Post-selection p-values remain descriptive.\n');
end
function run_stage(stage)
    eval(stage);
end
