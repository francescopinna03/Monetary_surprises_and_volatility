function Quasi_markov_input_self_test()
    root = tempname;
    directory = fullfile(root, 'Output', 'analysis');
    mkdir(directory);
    cleanup = onCleanup(@() rmdir(root, 's'));
    stateFile = fullfile(directory, 'pr_state_dependent_panel.csv');
    barFile = fullfile(directory, 'pr_bar_panel.csv');
    componentFile = fullfile(directory, 'pr_bns_component_panel.csv');
    reportFile = fullfile(directory, 'pr_bns_feasibility_report.csv');
    outcomes = ["asinh_BV_PR", "asinh_PR_rv"];
    state = table([0.01; 0.02], 'VariableNames', {'asinh_PR_rv'});
    writetable(state, stateFile);
    writetable(table((1:5)', 'VariableNames', {'r_bar'}), barFile);
    component = state;
    component.asinh_BV_PR = [0.005; 0.01];
    writetable(component, componentFile);
    F = table("median_bar_count_too_small", File_sha256(barFile),         File_sha256(stateFile), "", 'VariableNames', {'status', 'bar_file_sha256', 'state_panel_sha256', 'component_panel_sha256'});
    writetable(F, reportFile);

    [T, source, gate] = Quasi_markov_input_gate(root, outcomes);
    assert(string(source) == string(stateFile));
    assert(isequal(T.asinh_PR_rv, state.asinh_PR_rv));
    assert(isequal(gate.status, ["blocked_bns_gate"; "eligible"]));
    assert(~ismember('asinh_BV_PR', T.Properties.VariableNames));
    Archive_analysis_outputs(directory, "pr_bns_component_panel.csv");
    assert(~isfile(componentFile));
    archived = dir(fullfile(directory, 'archive', '*', 'pr_bns_component_panel.csv'));
    assert(numel(archived) == 1);
    assert(File_sha256(fullfile(archived.folder, archived.name)) ~= "");
    Quasi_markov_input_gate(root, outcomes);

    F.status = "ok";
    writetable(F, reportFile);
    expect_failure(@() Quasi_markov_input_gate(root, outcomes), 'QUASIMARKOV_BNS_PANEL_MISSING');
    writetable(component, componentFile);
    F.component_panel_sha256 = File_sha256(componentFile);
    writetable(F, reportFile);
    [~, source, gate] = Quasi_markov_input_gate(root, outcomes);
    assert(string(source) == string(componentFile) && all(gate.status == "eligible"));
    component.asinh_BV_PR(1) = 0.006;
    writetable(component, componentFile);
    expect_failure(@() Quasi_markov_input_gate(root, outcomes), 'QUASIMARKOV_BNS_PANEL_CHANGED');

    F.status = "median_bar_count_too_small";
    writetable(F, reportFile);
    state.asinh_PR_rv(1) = 0.03;
    writetable(state, stateFile);
    expect_failure(@() Quasi_markov_input_gate(root, outcomes), 'QUASIMARKOV_BNS_INPUT_CHANGED');
    F.state_panel_sha256 = File_sha256(stateFile);
    F.status = "unexpected_status";
    writetable(F, reportFile);
    expect_failure(@() Quasi_markov_input_gate(root, outcomes), 'QUASIMARKOV_BNS_STATUS_UNKNOWN');
    delete(reportFile);
    expect_failure(@() Quasi_markov_input_gate(root, outcomes), 'QUASIMARKOV_BNS_REPORT_MISSING');
    fprintf('Quasi_markov_input_self_test passed.\n');
end

function expect_failure(operation, token)
    try
        operation();
    catch exception
        assert(contains(exception.message, token), 'Unexpected failure: %s', exception.message);
        return;
    end
    error('Expected failure was not raised: %s', token);
end
