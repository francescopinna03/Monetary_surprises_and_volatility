function U = Step27b_event_state(PR, PC)
%STEP27B_EVENT_STATE Build the frozen scalar state for the cross-market operator.
%
% The phase-counterfactual files contain one PR-pre state per market root.
% Those root-specific z-scores are expected to differ.  Module B validates
% PR/PC identity within root and then uses their symmetric equal-weight mean
% as the scalar state of the cross-market dynamic operator.

    required = ["event_date", "root_code", "pre_state_z", "regime_hike"];
    assert_state_columns(PR, required, "PR");
    assert_state_columns(PC, required, "PC");

    PR.root_code = lower(string(PR.root_code));
    PC.root_code = lower(string(PC.root_code));
    PR = PR(ismember(PR.root_code, ["fx", "gg"]), :);
    PC = PC(ismember(PC.root_code, ["fx", "gg"]), :);

    dates = intersect(unique(PR.event_date, 'stable'), ...
        unique(PC.event_date, 'stable'), 'stable');
    rows = cell(numel(dates), 1);
    for j = 1:numel(dates)
        date = dates(j);
        prFx = root_value(PR, date, "fx", "pre_state_z", "PR");
        prGg = root_value(PR, date, "gg", "pre_state_z", "PR");
        pcFx = root_value(PC, date, "fx", "pre_state_z", "PC");
        pcGg = root_value(PC, date, "gg", "pre_state_z", "PC");
        prHikeFx = root_value(PR, date, "fx", "regime_hike", "PR");
        prHikeGg = root_value(PR, date, "gg", "regime_hike", "PR");
        pcHikeFx = root_value(PC, date, "fx", "regime_hike", "PC");
        pcHikeGg = root_value(PC, date, "gg", "regime_hike", "PC");

        stateScale = max([1, abs(prFx), abs(prGg), abs(pcFx), abs(pcGg)]);
        if abs(prFx - pcFx) > 1e-10 * stateScale || ...
                abs(prGg - pcGg) > 1e-10 * stateScale
            error(['STEP27B_STATE_PHASE_MISMATCH: PR and PC root-specific ' ...
                'states disagree for %s.'], string(date, 'yyyy-MM-dd'));
        end
        hikes = [prHikeFx, prHikeGg, pcHikeFx, pcHikeGg];
        if any(abs(hikes - hikes(1)) > 1e-12) || ...
                ~ismember(hikes(1), [0, 1])
            error(['STEP27B_REGIME_MISMATCH: regime is not unique and binary ' ...
                'for %s.'], string(date, 'yyyy-MM-dd'));
        end

        R = table();
        R.event_date = date;
        R.pre_state_fx_z = 0.5 * (prFx + pcFx);
        R.pre_state_gg_z = 0.5 * (prGg + pcGg);
        R.pre_state_z = 0.5 * (R.pre_state_fx_z + R.pre_state_gg_z);
        R.regime_hike = hikes(1);
        rows{j} = R;
    end

    if isempty(rows)
        U = table();
        U.event_date = PR.event_date([]);
        U.pre_state_fx_z = zeros(0, 1);
        U.pre_state_gg_z = zeros(0, 1);
        U.pre_state_z = zeros(0, 1);
        U.regime_hike = zeros(0, 1);
    else
        U = vertcat(rows{:});
    end
end

function value = root_value(T, date, root, variable, phase)
    rows = T.event_date == date & T.root_code == root;
    values = double(T.(variable)(rows));
    if isempty(values) || any(~isfinite(values))
        error(['STEP27B_STATE_ROOT_MISSING: finite %s %s value required ' ...
            'for root %s on %s.'], phase, variable, root, ...
            string(date, 'yyyy-MM-dd'));
    end
    reference = values(1);
    tolerance = 1e-10 * max(1, abs(reference));
    if any(abs(values - reference) > tolerance)
        error(['STEP27B_STATE_ROOT_CONFLICT: conflicting %s %s values ' ...
            'for root %s on %s.'], phase, variable, root, ...
            string(date, 'yyyy-MM-dd'));
    end
    value = mean(values);
end

function assert_state_columns(T, required, phase)
    missing = required(~ismember(required, string(T.Properties.VariableNames)));
    if ~isempty(missing)
        error('STEP27B_STATE_SCHEMA: %s rows missing %s.', ...
            phase, strjoin(missing, ', '));
    end
end
