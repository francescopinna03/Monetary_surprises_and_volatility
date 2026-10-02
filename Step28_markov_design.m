function design = Step28_markov_design(levels, meta, rank, historyLag, stateBlock, surpriseBlock)

    phases = ["PR", "PC"];
    phaseLoadings = struct();
    for p = 1:numel(phases)
        rows = meta.phase == phases(p) & meta.role == "event";
        if ~any(rows)
            error('STEP28_MARKOV_DESIGN_PHASE: %s has no event row.', phases(p));
        end
        phaseLoadings.(char(phases(p))) = Step28_factor_subspace(levels(rows, :), rank).loadings;
    end
    commonBasis = Step28_common_basis(phaseLoadings.PR, phaseLoadings.PC);

    pairs = rank * (rank + 1) / 2;
    originZ = zeros(0, rank);
    targetZ = zeros(0, rank);
    history = zeros(0, rank * max(historyLag, 1));
    historyCovariance = zeros(0, pairs * max(historyLag, 1));
    isEventRow = false(0, 1);
    group = strings(0, 1);
    meetingKey = strings(0, 1);
    foldKey = strings(0, 1);
    phaseOut = strings(0, 1);
    positionOut = zeros(0, 1);
    stateRows = zeros(0, size(stateBlock, 2));
    surpriseRows = zeros(0, size(surpriseBlock, 2));

    isEvent = meta.role == "event";
    key = meta.date_key + "|" + meta.phase;
    [groupIndex, groupNames] = findgroups(key);
    for g = 1:numel(groupNames)
        rows = find(groupIndex == g);
        sequenceIsEvent = all(isEvent(rows));
        [~, order] = sort(meta.position(rows));
        rows = rows(order);
        phase = meta.phase(rows(1));
        Z = levels(rows, :) * commonBasis;
        increments = [Z(1, :); diff(Z, 1, 1)];
        nPositions = size(Z, 1);

        positionsOfRows = meta.position(rows);
        for k = 1:nPositions - 1
            if k <= historyLag
                continue;
            end
            if positionsOfRows(k + 1) - positionsOfRows(k) ~= 1
                continue;
            end
            if historyLag > 0 &&                     positionsOfRows(k) - positionsOfRows(k - historyLag + 1) ~= historyLag - 1
                continue;
            end
            block = zeros(1, rank * max(historyLag, 1));
            quadratic = zeros(1, pairs * max(historyLag, 1));
            for l = 1:historyLag
                lagged = increments(k - l + 1, :);
                block((l - 1) * rank + (1:rank)) = lagged;
                quadratic((l - 1) * pairs + (1:pairs)) = vech_outer(lagged);
            end
            originZ(end + 1, :) = Z(k, :);
            targetZ(end + 1, :) = Z(k + 1, :);
            history(end + 1, :) = block;
            historyCovariance(end + 1, :) = quadratic;
            isEventRow(end + 1, 1) = sequenceIsEvent;
            group(end + 1, 1) = phase + "|" + string(meta.position(rows(k)));
            meetingKey(end + 1, 1) = meta.date_key(rows(k));
            foldKey(end + 1, 1) = meta.fold_key(rows(k));
            phaseOut(end + 1, 1) = phase;
            positionOut(end + 1, 1) = meta.position(rows(k));
            stateRows(end + 1, :) = stateBlock(rows(k), :);
            surpriseRows(end + 1, :) = surpriseBlock(rows(k), :);
        end
    end

    if isempty(originZ)
        error(['STEP28_MARKOV_DESIGN_EMPTY: no transition survives the frozen ' 'history lag.']);
    end
    if historyLag == 0
        history = zeros(size(originZ, 1), 0);
        historyCovariance = zeros(size(originZ, 1), 0);
    end
    if ~any(isEventRow)
        error(['STEP28_MARKOV_DESIGN_NO_EVENTS: no event transition survives ' 'the frozen history lag.']);
    end

    design = struct();
    design.schema_version = "step28_markov_design_v1";
    design.rank = rank;
    design.history_lag = historyLag;
    design.origin = originZ;
    design.target = targetZ;
    design.history = history;
    design.history_covariance = historyCovariance;
    design.is_event = isEventRow;
    design.state = stateRows;
    design.surprise = surpriseRows;
    design.conditioning = [originZ, stateRows, surpriseRows];
    design.group = group;
    design.meeting_key = meetingKey;
    design.fold_key = foldKey;
    design.phase = phaseOut;
    design.position = positionOut;
    design.common_basis = commonBasis;
    design.n_use = sum(isEventRow);
    design.g_use = numel(unique(meetingKey(isEventRow)));
    design.n_rows = size(originZ, 1);
end

function v = vech_outer(x)
    r = numel(x);
    v = zeros(1, r * (r + 1) / 2);
    column = 0;
    for c = 1:r
        for i = c:r
            column = column + 1;
            v(column) = x(i) * x(c);
        end
    end
end
