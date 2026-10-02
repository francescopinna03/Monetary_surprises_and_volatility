function summary = Run_step28_gates()

    projectRoot = Get_project_root();
    outputDir = fullfile(projectRoot, 'Output', 'step28_sbbts');
    if exist(outputDir, 'dir') ~= 7
        mkdir(outputDir);
    end

    downstream = ["step28_sample_size_gate_decision.csv",         "step28_sample_size_calibration.csv", "step28_sample_size_counts.csv",         "step28_spectral_gate_decision.csv",         "step28_spectral_stability.csv", "step28_spectral_common_basis.csv",         "step28_markov_power_gate_decision.csv",         "step28_markov_branches.csv",         "step28_gaussian_calibration_gate_decision.csv",         "step28_gaussian_calibration_detail.csv", "step28_sbb_decision.csv"];
    supersede(outputDir, downstream);

    fprintf('\n[28 gates preflight] Gate module self-test\n');
    Step28_gates_self_test();

    specificationPath = string(getenv('STEP28_SBB_SPECIFICATION'));
    if strlength(strtrim(specificationPath)) == 0
        specificationPath = fullfile(projectRoot, 'Raw', 'Certification', 'step28_sbb_specification.csv');
    end
    specification = Step28_sbb_specification(specificationPath);
    fprintf('Frozen specification: %s\n', specification.specification_path);

    verify_upstream(projectRoot);
    provenance = Step28_provenance(projectRoot, specification);
    fprintf('Data manifest %s | surprise %s (%s) | code %s\n',         short_hash(provenance.data_manifest_sha256),         provenance.surprise_source,         short_hash(provenance.surprise_source_sha256), short_hash(provenance.code_sha256));

    summary = struct();

    fprintf('\n[28 gate 2] Outcome-free sample-size calibration\n');
    calibration = Step28_sample_size_calibration(struct(         'meetingGrid', specification.calibration_meeting_grid,         'frontierEigengap', specification.calibration_frontier_eigengap,         'projectorTolerance', specification.calibration_projector_tolerance,         'trueRank', specification.calibration_true_rank,         'positions', specification.calibration_positions,         'replications', specification.calibration_replications,         'parallelDraws', specification.spectral_parallel_draws,         'parallelQuantile', specification.spectral_parallel_quantile,         'reconstructionFolds', specification.spectral_reconstruction_folds, 'seed', specification.bootstrap_seed));
    writetable(calibration.profile, fullfile(outputDir, 'step28_sample_size_calibration.csv'));
    fprintf('G_min^spec = %g (%s), rho %.4f at eigengap %g\n',         calibration.minimum_meetings, calibration.status, calibration.induced_rho, calibration.frontier_eigengap);
    summary.calibration = calibration;

    fprintf('\n[28 gate 2] Numerosity gate on the certified intersection\n');
    panel = Step28_sbb_panel(projectRoot, specification);
    [sampleDecision, counts] = Step28_sample_size_gate(panel, calibration, specification.history_lag);
    sampleDecision = Step28_stamp_decision(sampleDecision, provenance);
    writetable(sampleDecision, fullfile(outputDir, 'step28_sample_size_gate_decision.csv'));
    writetable(counts, fullfile(outputDir, 'step28_sample_size_counts.csv'));
    disp(counts(:, {'phase', 'n_use', 'g_use', 'g_min_spec', 'meets_minimum'}));
    summary.sample_size = sampleDecision;
    if sampleDecision.status(1) ~= "pass_sample_size_gate"
        fprintf('Stopped: %s\n', sampleDecision.next_action(1));
        return;
    end

    fprintf('\n[28 gate 3] Spectral gate\n');
    shockEnergy = shock_energy_map(panel, specification);
    [spectralDecision, spectralDetail] = Step28_spectral_gate(panel, specification, calibration, shockEnergy);
    spectralDecision = Step28_stamp_decision(spectralDecision, provenance);
    writetable(spectralDecision, fullfile(outputDir, 'step28_spectral_gate_decision.csv'));
    if isfield(spectralDetail, 'stability') && ~isempty(spectralDetail.stability)
        writetable(spectralDetail.stability, fullfile(outputDir, 'step28_spectral_stability.csv'));
    end
    if isfield(spectralDetail, 'common_basis')
        writematrix(spectralDetail.common_basis, fullfile(outputDir, 'step28_spectral_common_basis.csv'));
    end
    fprintf('Status %s, rank %g\n', spectralDecision.status(1), spectralDecision.accepted_rank(1));
    summary.spectral = spectralDecision;
    if spectralDecision.status(1) ~= "pass_spectral_gate"
        fprintf('Stopped: %s\n', spectralDecision.next_action(1));
        return;
    end

    fprintf('\n[28 gate 4] Markov power gate, mean and covariance branches\n');
    meetings = unique(panel.date_key(panel.role == "event"));
    expanded = Step28_expanded_levels(panel, specification, meetings);
    levels = expanded.levels;
    meta = expanded.meta;
    [stateBlock, surpriseBlock] = conditioning_blocks(panel, specification, meta);
    design = Step28_markov_design(levels, meta,         spectralDecision.accepted_rank(1), specification.history_lag, stateBlock, surpriseBlock);
    fprintf('N_use %d over G_use %d meetings\n', design.n_use, design.g_use);
    [markovDecision, markovDetail] = Step28_markov_power_gate(design, specification);
    markovDecision = Step28_stamp_decision(markovDecision, provenance);
    writetable(markovDecision, fullfile(outputDir, 'step28_markov_power_gate_decision.csv'));
    writetable(markovDetail, fullfile(outputDir, 'step28_markov_branches.csv'));
    disp(markovDetail(:, {'scope', 'branch', 'status', 'p_value', 'r2_80', 'r2_state_lower'}));
    summary.markov = markovDecision;
    if markovDecision.status(1) ~= "pass_markov_power_gate"
        fprintf('Stopped: %s\n', markovDecision.next_action(1));
        return;
    end

    fprintf('\n[28 gate 5] Gaussian calibration gate\n');
    [gaussianDecision, gaussianDetail] = Step28_gaussian_calibration_gate(design, specification);
    gaussianDecision = Step28_stamp_decision(gaussianDecision, provenance);
    writetable(gaussianDecision, fullfile(outputDir, 'step28_gaussian_calibration_gate_decision.csv'));
    writetable(gaussianDetail, fullfile(outputDir, 'step28_gaussian_calibration_detail.csv'));
    disp(gaussianDetail);
    summary.gaussian = gaussianDecision;

    if gaussianDecision.status(1) == "pass_calibration_gate"
        fprintf(['\nAll gates passed. Run ./Run_step28_sbb.sh to produce the ' 'empirical profile.\n']);
    else
        fprintf('Stopped: %s\n', gaussianDecision.next_action(1));
    end
end

function verify_upstream(projectRoot)
    [decision, audit] = Step28_data_gate(projectRoot);
    if decision.status(1) ~= "pass_data_gate" ||             ~String_to_boolean(decision.ready_for_sample_size_gate(1)) || any(audit.binding & ~audit.pass)
        error(['STEP28_GATES_DATA_GATE_BLOCKED: the current Barchart files ' 'do not pass the MATLAB data-gate revalidation.']);
    end
    source = Surprise_source_config(projectRoot);
    Require_time_alignment_manifest(projectRoot);
    Require_surprise_source_manifest(projectRoot, source);
end

function supersede(outputDir, names)
    stamp = string(datetime('now', 'TimeZone', 'UTC'), 'yyyyMMdd''T''HHmmssSSS');
    for i = 1:numel(names)
        path = fullfile(outputDir, names(i));
        if isfile(path)
            movefile(path, char(path + ".superseded-" + stamp));
        end
    end
end

function short = short_hash(value)
    value = string(value);
    if strlength(value) >= 12
        short = extractBefore(value, 13);
    else
        short = value;
    end
end

function map = shock_energy_map(panel, specification)
    map = containers.Map('KeyType', 'char', 'ValueType', 'double');
    keys = string(panel.surprise.date_key);
    columns = specification.surprise_columns;
    for i = 1:numel(keys)
        values = zeros(1, numel(columns));
        for c = 1:numel(columns)
            values(c) = double(panel.surprise.(char(columns(c)))(i));
        end
        if all(isfinite(values))
            map(char(keys(i))) = norm(values);
        end
    end
end

function [stateBlock, surpriseBlock] = conditioning_blocks(panel, specification, meta)
    stateBlock = lookup_block(panel.state, specification.state_columns, meta, specification.control_conditioning_rule, "state");
    surpriseBlock = lookup_block(panel.surprise,         specification.surprise_columns, meta, specification.control_conditioning_rule, "surprise");
end

function block = lookup_block(source, columns, meta, rule, kind)
    nRows = numel(meta.date_key);
    block = zeros(nRows, numel(columns));
    if numel(columns) == 0
        return;
    end
    keys = string(source.date_key);
    eventKey = strip_replica(meta.event_key);
    for c = 1:numel(columns)
        values = double(source.(char(columns(c))));
        for i = 1:nRows
            if meta.is_control(i)
                switch rule
                    case "state_and_surprise_zeroed"
                        continue;
                    case "state_only"
                        if kind == "surprise"
                            continue;
                        end
                        wanted = eventKey(i);
                    case "inherit_matched_event"
                        wanted = eventKey(i);
                    otherwise
                        error('STEP28_GATES_CONTROL_RULE: unknown rule %s.', rule);
                end
            else
                wanted = meta.base_date_key(i);
            end
            match = find(keys == wanted, 1);
            if isempty(match)
                error('STEP28_GATES_LOOKUP: %s has no %s row.', wanted, kind);
            end
            block(i, c) = values(match);
        end
    end
end

function base = strip_replica(keys)
    base = extractBefore(string(keys), "#");
    missing = ismissing(base);
    base(missing) = string(keys(missing));
end
