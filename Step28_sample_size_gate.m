function [decision, counts] = Step28_sample_size_gate(panel, calibration, historyLag)

    if ~isstruct(calibration) || ~isfield(calibration, 'minimum_meetings')
        error(['STEP28_SAMPLE_SIZE_CALIBRATION_REQUIRED: the outcome-free ' 'calibration must be supplied.']);
    end
    historyLag = double(historyLag);
    if ~isscalar(historyLag) || ~isfinite(historyLag) || historyLag < 0 || historyLag ~= floor(historyLag)
        error('STEP28_SAMPLE_SIZE_LAG: historyLag must be a non-negative integer.');
    end

    dateKey = string(panel.date_key(:));
    role = string(panel.role(:));
    phase = string(panel.phase(:));

    phases = ["PR", "PC"];
    phaseOut = strings(0, 1);
    meetingsWithData = zeros(0, 1);
    transitionsBeforeLag = zeros(0, 1);
    nUse = zeros(0, 1);
    gUse = zeros(0, 1);
    minTransitions = zeros(0, 1);
    medianTransitions = zeros(0, 1);
    maxTransitions = zeros(0, 1);
    perMeeting = table('Size', [0, 3], 'VariableTypes',         {'string', 'string', 'double'}, 'VariableNames', {'phase', 'event_key', 'transitions'});

    for p = 1:numel(phases)
        selected = role == "event" & phase == phases(p);
        events = unique(dateKey(selected));
        K = zeros(numel(events), 1);
        for e = 1:numel(events)
            K(e) = max(sum(selected & dateKey == events(e)) - 1, 0);
        end

        phaseOut(end + 1, 1) = phases(p);
        meetingsWithData(end + 1, 1) = numel(events);
        transitionsBeforeLag(end + 1, 1) = sum(K);
        nUse(end + 1, 1) = sum(max(K - historyLag, 0));
        gUse(end + 1, 1) = sum(K > historyLag);
        minTransitions(end + 1, 1) = min([K; NaN]);
        medianTransitions(end + 1, 1) = median(K);
        maxTransitions(end + 1, 1) = max([K; NaN]);

        perMeeting = [perMeeting; table(repmat(phases(p), numel(events), 1),             events, K, 'VariableNames', {'phase', 'event_key', 'transitions'})];
    end

    counts = table(phaseOut, meetingsWithData, transitionsBeforeLag, nUse,         gUse, minTransitions, medianTransitions, maxTransitions,         'VariableNames', {'phase', 'n_meetings_with_data',         'n_transitions_before_lag', 'n_use', 'g_use',         'min_transitions_per_meeting', 'median_transitions_per_meeting', 'max_transitions_per_meeting'});
    counts.history_lag = repmat(historyLag, height(counts), 1);
    counts.g_min_spec = repmat(calibration.minimum_meetings, height(counts), 1);
    counts.meets_minimum = counts.g_use >= calibration.minimum_meetings;

    calibrated = calibration.status == "calibrated" && isfinite(calibration.minimum_meetings);
    if ~calibrated
        status = "blocked_calibration_not_available";
        nextAction = "the frozen G grid admits no G_min^spec; widen the grid " + "or revise the frontier eigengap before looking at the intersection";
    elseif all(counts.meets_minimum)
        status = "pass_sample_size_gate";
        nextAction = "run the spectral gate";
    else
        status = "blocked_sample_size_gate";
        short = strjoin(counts.phase(~counts.meets_minimum), '|');
        nextAction = "spectral gate is non-informative in " + short + "; Step 28 stops before rank or angles are interpreted";
    end

    decision = table("step28_sample_size_gate_v1", string(status),         double(calibration.minimum_meetings),         double(counts.g_use(counts.phase == "PR")),         double(counts.g_use(counts.phase == "PC")),         double(counts.n_use(counts.phase == "PR")),         double(counts.n_use(counts.phase == "PC")),         historyLag, string(calibration.status),         double(calibration.frontier_eigengap),         double(calibration.projector_tolerance),         double(calibration.seed), string(nextAction),         string(datetime('now', 'TimeZone', 'UTC'),         'yyyy-MM-dd''T''HH:mm:ssXXX'),         'VariableNames', {'schema_version', 'status', 'g_min_spec',         'g_use_pr', 'g_use_pc', 'n_use_pr', 'n_use_pc', 'history_lag',         'calibration_status', 'frontier_eigengap', 'projector_tolerance', 'calibration_seed', 'next_action', 'generated_at_utc'});

    decision.per_meeting_rows = height(perMeeting);
    counts.Properties.UserData = perMeeting;
end
