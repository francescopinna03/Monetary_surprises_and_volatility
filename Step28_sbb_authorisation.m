function [authorised, gates, acceptedRank] = Step28_sbb_authorisation(projectRoot, specification)

    if nargin < 1 || strlength(strtrim(string(projectRoot))) == 0
        projectRoot = Get_project_root();
    end

    outputDir = fullfile(projectRoot, 'Output', 'step28_sbbts');
    acceptedRank = NaN;

    contract = [         "data",                  "step28_data_gate_decision.csv",             "status",            "pass_data_gate";         "sample_size",           "step28_sample_size_gate_decision.csv",             "status",            "pass_sample_size_gate";         "spectral",              "step28_spectral_gate_decision.csv",             "status",            "pass_spectral_gate";         "markov_power_mean",     "step28_markov_power_gate_decision.csv",             "mean_branch_status",       "pass_mean_branch";         "markov_power_covariance", "step28_markov_power_gate_decision.csv",             "covariance_branch_status", "pass_covariance_branch";         "gaussian_calibration",  "step28_gaussian_calibration_gate_decision.csv", "status",            "pass_calibration_gate"];

    nGates = size(contract, 1);
    gateId = strings(nGates, 1);
    passed = false(nGates, 1);
    observed = strings(nGates, 1);
    required = strings(nGates, 1);
    sourceFile = strings(nGates, 1);
    sourceHash = strings(nGates, 1);

    for g = 1:nGates
        gateId(g) = contract(g, 1);
        required(g) = contract(g, 4);
        path = fullfile(outputDir, contract(g, 2));
        sourceFile(g) = string(path);

        if ~isfile(path)
            observed(g) = "decision_file_missing";
            sourceHash(g) = "missing";
            continue;
        end

        sourceHash(g) = File_sha256(path);
        T = readtable(path, 'Delimiter', ',', 'TextType', 'string', 'VariableNamingRule', 'preserve');
        if height(T) ~= 1
            observed(g) = "decision_not_single_row";
            continue;
        end
        if ~ismember(contract(g, 3), string(T.Properties.VariableNames))
            observed(g) = "status_column_missing:" + contract(g, 3);
            continue;
        end

        observed(g) = strtrim(string(T.(char(contract(g, 3)))(1)));
        passed(g) = observed(g) == required(g);
    end

    hasSpecification = nargin >= 2 && ~isempty(specification);
    if hasSpecification
        provenance = Step28_provenance(projectRoot, specification);
        stampFiles = unique(contract(:, 2), 'stable');
        for f = 1:numel(stampFiles)
            if stampFiles(f) == "step28_data_gate_decision.csv"
                requiredFields = "data_manifest_sha256";
            else
                requiredFields = ["data_manifest_sha256",                     "specification_sha256", "state_panel_sha256",                     "surprise_source_sha256", "surprise_manifest_sha256", "code_sha256"];
            end
            [stampPass, stampObserved] = check_stamp( fullfile(outputDir, stampFiles(f)), provenance, requiredFields);
            gateId(end + 1, 1) = "provenance:" + erase(stampFiles(f), "step28_");
            passed(end + 1, 1) = stampPass;
            observed(end + 1, 1) = stampObserved;
            required(end + 1, 1) = "matches the current data, specification, surprise source and code";
            sourceFile(end + 1, 1) = string(fullfile(outputDir, stampFiles(f)));
            sourceHash(end + 1, 1) = "n/a";
        end

        [rankPass, rankObserved, rankRequired, acceptedRank] =             check_rank_selection( outputDir, specification);
        gateId(end + 1, 1) = "rank_selection";
        passed(end + 1, 1) = rankPass;
        observed(end + 1, 1) = rankObserved;
        required(end + 1, 1) = rankRequired;
        sourceFile(end + 1, 1) = string(fullfile(outputDir, 'step28_spectral_gate_decision.csv'));
        sourceHash(end + 1, 1) = "n/a";
    else
        gateId(end + 1, 1) = "frozen_specification";
        passed(end + 1, 1) = false;
        observed(end + 1, 1) = "not supplied";
        required(end + 1, 1) = "frozen specification with current provenance";
        sourceFile(end + 1, 1) = "";
        sourceHash(end + 1, 1) = "missing";
    end

    gates = table(gateId, passed, observed, required, sourceFile,         sourceHash, 'VariableNames', {'gate_id', 'pass', 'observed', 'required', 'source_file', 'source_sha256'});

    authorised = all(gates.pass);
end

function [passes, observed] = check_stamp(path, provenance, fields)
    if ~isfile(path)
        passes = false;
        observed = "decision_file_missing";
        return;
    end
    T = readtable(path, 'Delimiter', ',', 'TextType', 'string', 'VariableNamingRule', 'preserve');
    if height(T) ~= 1
        passes = false;
        observed = "decision_not_single_row";
        return;
    end
    names = string(T.Properties.VariableNames);
    missing = fields(~ismember(fields, names));
    if ~isempty(missing)
        passes = false;
        observed = "missing stamp: " + strjoin(missing, ", ");
        return;
    end
    mismatched = strings(0, 1);
    unavailable = ["missing", "unreadable", "stale"];
    for f = 1:numel(fields)
        expected = string(provenance.(char(fields(f))));
        actual = strtrim(string(T.(char(fields(f)))(1)));
        if ismember(expected, unavailable) || actual ~= expected
            mismatched(end + 1, 1) = fields(f);
        end
    end
    passes = isempty(mismatched);
    if passes
        observed = "stamped and current";
    else
        observed = "stale: " + strjoin(mismatched, ", ");
    end
end

function [passes, observed, required, acceptedRank] = check_rank_selection(outputDir, specification)
    required = "factor_rank_rule = selected_by_spectral_gate and accepted_rank in {1,2}";
    acceptedRank = NaN;
    if ~isfield(specification, 'factor_rank_rule') || string(specification.factor_rank_rule) ~= "selected_by_spectral_gate"
        passes = false;
        observed = "invalid or missing factor_rank_rule";
        return;
    end
    path = fullfile(outputDir, 'step28_spectral_gate_decision.csv');
    if ~isfile(path)
        passes = false;
        observed = "spectral_decision_missing";
        return;
    end
    T = readtable(path, 'Delimiter', ',', 'TextType', 'string', 'VariableNamingRule', 'preserve');
    if height(T) ~= 1 || ~ismember("accepted_rank", string(T.Properties.VariableNames))
        passes = false;
        observed = "accepted_rank_unreadable";
        return;
    end
    candidate = double(T.accepted_rank(1));
    observed = "accepted_rank = " + string(candidate) + ", factor_rank_rule = " + string(specification.factor_rank_rule);
    passes = isfinite(candidate) && candidate == floor(candidate) && ismember(candidate, [1, 2]);
    if passes
        acceptedRank = candidate;
    end
end
