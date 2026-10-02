function expanded = Step28_expanded_levels(panel, specification, meetings)

    meetings = string(meetings(:));
    if isempty(meetings)
        error('STEP28_EXPANDED_LEVELS_EMPTY: at least one meeting is required.');
    end

    [rows, replicaKey, replicaRole, replicaPhase, replicaEvent, links, isMomentControl] = Step28_expand_meetings(panel, meetings);
    position = double(panel.position(rows));
    foldKey = string(panel.fold_key(rows));
    sequenceKey = replicaKey + "|" + replicaPhase;

    [whitened, moments] = Step28_whiten_increments(panel.returns(rows, :),         sequenceKey, position, foldKey, isMomentControl, specification.whitening_minimum_dates);
    [found, back] = ismember(sequenceKey + "|" + string(position), whitened.date_key + "|" + string(whitened.position));
    if ~all(found)
        error(['STEP28_EXPANDED_LEVELS_ALIGNMENT: whitening did not return ' 'every matched panel row.']);
    end

    meta = struct();
    meta.date_key = replicaKey;
    meta.base_date_key = strip_replica(replicaKey);
    meta.event_key = replicaEvent;
    meta.role = replicaRole;
    meta.phase = replicaPhase;
    meta.position = position;
    meta.fold_key = foldKey;
    meta.is_control = replicaRole == "matched_control";
    meta.is_moment_control = isMomentControl;

    expanded = struct();
    expanded.schema_version = "step28_expanded_levels_v1";
    expanded.levels = whitened.level(back, :);
    expanded.meta = meta;
    expanded.rows = rows;
    expanded.links = links;
    expanded.whitening_moments = moments;
    expanded.is_moment_control = isMomentControl;
end

function base = strip_replica(keys)
    base = extractBefore(keys, "#");
    missing = ismissing(base);
    base(missing) = keys(missing);
end
