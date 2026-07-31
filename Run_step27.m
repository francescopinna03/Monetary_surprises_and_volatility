function Run_step27()
%RUN_STEP27 Execute the sequential Step-27 feasibility protocol.
%
% Module A is always run first. Module B is run only after a final 999-draw
% Module-A pass. A failed or smoke-only gate is recorded as a disciplined
% stop, not converted into a MATLAB execution error.

    projectRoot = Get_project_root();
    requestedDraws = str2double(string(getenv('RANK_ONE_FEASIBILITY_DRAWS')));
    if ~isfinite(requestedDraws)
        requestedDraws = 999;
    end

    fprintf('\n[27A/27] Rank_one_feasibility\n');
    Rank_one_feasibility_self_test();
    Rank_one_feasibility();

    if requestedDraws ~= 999
        fprintf(['Step 27B not run: Module A was executed as a smoke test ' ...
            'rather than a final gate.\n']);
        return;
    end

    decisionFile = fullfile(projectRoot, 'Output', ...
        'rank_one_feasibility', 'step27a_decision.csv');
    manifestFile = fullfile(projectRoot, 'Output', ...
        'rank_one_feasibility', 'step27a_manifest.csv');

    if exist(decisionFile, 'file') ~= 2 || exist(manifestFile, 'file') ~= 2
        fprintf(['Step 27B not run: Module A did not produce a final ' ...
            '999-draw gate.\n']);
        return;
    end

    D = readtable(decisionFile, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve', 'ReadRowNames', false);
    required = ["test_id", "status"];
    missing = required(~ismember(required, string(D.Properties.VariableNames)));
    if ~isempty(missing)
        error('STEP27_GATE_SCHEMA: decision file missing %s.', ...
            strjoin(missing, ', '));
    end

    gate = string(D.test_id) == "MODULE_A_RANK_GATE";
    if sum(gate) ~= 1
        error('STEP27_GATE_ROW: expected one MODULE_A_RANK_GATE row.');
    end

    M = readtable(manifestFile, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve', 'ReadRowNames', false);
    schema = Step27b_manifest_value(M, "schema_version");
    draws = str2double(Step27b_manifest_value(M, "bootstrap_draws"));
    finalGate = string(D.status(gate)) == "pass" && ...
        schema == "step27a_v1" && draws == 999;

    if ~finalGate
        fprintf(['Step 27B not run: rank one is not admissible under the ' ...
            'final Module-A gate.\n']);
        return;
    end

    fprintf('\n[27B/27] Dynamic_jump_frontier\n');
    Dynamic_jump_frontier_self_test();
    Dynamic_jump_frontier();
end
