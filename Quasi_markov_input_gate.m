function [T, panelFile, decisions] = Quasi_markov_input_gate(projectRoot, outcomes)
    outcomes = string(outcomes(:));
    assert(all(ismember(outcomes, ["asinh_BV_PR", "asinh_PR_rv"])), 'QUASIMARKOV_UNKNOWN_OUTCOME');
    directory = fullfile(projectRoot, 'Output', 'analysis');
    reportFile = fullfile(directory, 'pr_bns_feasibility_report.csv');
    stateFile = fullfile(directory, 'pr_state_dependent_panel.csv');
    barFile = fullfile(directory, 'pr_bar_panel.csv');
    assert(isfile(reportFile), 'QUASIMARKOV_BNS_REPORT_MISSING: rerun BNS_volatility.');
    F = readtable(reportFile, 'Delimiter', ',', 'TextType', 'string', 'VariableNamingRule', 'preserve');
    required = ["status", "bar_file_sha256", "state_panel_sha256", "component_panel_sha256"];
    assert(height(F) == 1 && all(ismember(required,         string(F.Properties.VariableNames))), 'QUASIMARKOV_BNS_REPORT_STALE: rerun BNS_volatility.');
    assert(isfile(barFile) && isfile(stateFile), 'QUASIMARKOV_SOURCE_MISSING');
    assert(File_sha256(barFile) == F.bar_file_sha256(1) &&         File_sha256(stateFile) == F.state_panel_sha256(1), 'QUASIMARKOV_BNS_INPUT_CHANGED: rerun BNS_volatility.');

    blockedStates = ["too_few_groups_with_enough_bars", "median_bar_count_too_small", "bns_components_not_computable"];
    status = repmat("eligible", size(outcomes));
    reason = repmat("bns_gate_passed", size(outcomes));
    if F.status(1) == "ok"
        panelFile = fullfile(directory, 'pr_bns_component_panel.csv');
        assert(isfile(panelFile), 'QUASIMARKOV_BNS_PANEL_MISSING');
        assert(~ismissing(F.component_panel_sha256(1)) &&             File_sha256(panelFile) == F.component_panel_sha256(1), 'QUASIMARKOV_BNS_PANEL_CHANGED: rerun BNS_volatility.');
    elseif ismember(F.status(1), blockedStates)
        panelFile = stateFile;
        bv = outcomes == "asinh_BV_PR";
        status(bv) = "blocked_bns_gate";
        reason(bv) = F.status(1);
        reason(~bv) = "rv_available_independently_of_bns";
        fprintf('Step 17: BV blocked (%s); RV uses the state panel.\n', F.status(1));
    else
        error('QUASIMARKOV_BNS_STATUS_UNKNOWN: %s', F.status(1));
    end

    T = readtable(panelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    assert(all(ismember(outcomes(status == "eligible"), string(T.Properties.VariableNames))), 'QUASIMARKOV_OUTCOME_MISSING');
    source_file = repmat(string(panelFile), size(outcomes));
    source_sha256 = repmat(File_sha256(panelFile), size(outcomes));
    source_file(status ~= "eligible") = "";
    source_sha256(status ~= "eligible") = "";
    decisions = table(outcomes, status, reason, source_file, source_sha256,         repmat(File_sha256(reportFile), size(outcomes)), 'VariableNames', {'outcome', 'status', 'reason', 'source_file', 'source_sha256', 'bns_report_sha256'});
end
