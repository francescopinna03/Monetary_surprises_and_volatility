function [rows, replicaKey, replicaRole, replicaPhase, replicaEvent, links, isMomentControl] = Step28_expand_meetings(panel, meetings)

    dateKey = string(panel.date_key(:));
    role = string(panel.role(:));
    phase = string(panel.phase(:));

    linkTable = panel.links;
    rows = zeros(0, 1);
    replicaKey = strings(0, 1);
    replicaRole = strings(0, 1);
    replicaPhase = strings(0, 1);
    replicaEvent = strings(0, 1);
    isMomentControl = false(0, 1);
    linkEvent = strings(0, 1);
    linkPhase = strings(0, 1);
    linkControl = strings(0, 1);
    linkWeight = zeros(0, 1);
    seenControlPhase = strings(0, 1);

    phases = unique(linkTable.phase);

    for b = 1:numel(meetings)
        eventKey = meetings(b);
        suffix = "#" + string(b);
        used = false;

        for p = 1:numel(phases)
            thisPhase = phases(p);
            selected = linkTable.event_key == eventKey & linkTable.phase == thisPhase;
            if ~any(selected)
                continue;
            end
            eventRows = find(dateKey == eventKey & role == "event" & phase == thisPhase);
            if isempty(eventRows)
                continue;
            end

            controls = unique(linkTable.control_key(selected));
            controlRowsAll = cell(numel(controls), 1);
            keep = false(numel(controls), 1);
            for c = 1:numel(controls)
                controlRowsAll{c} = find(dateKey == controls(c) & role == "matched_control" & phase == thisPhase);
                keep(c) = ~isempty(controlRowsAll{c});
            end
            if ~any(keep)
                continue;
            end

            used = true;
            rows = [rows; eventRows];
            replicaKey = [replicaKey; repmat(eventKey + suffix, numel(eventRows), 1)];
            replicaRole = [replicaRole; repmat("event", numel(eventRows), 1)];
            replicaPhase = [replicaPhase; repmat(thisPhase, numel(eventRows), 1)];
            replicaEvent = [replicaEvent; repmat(eventKey + suffix, numel(eventRows), 1)];
            isMomentControl = [isMomentControl; false(numel(eventRows), 1)];

            survivors = controls(keep);
            share = 1 / numel(survivors);
            for c = find(keep)'
                controlRows = controlRowsAll{c};
                controlKey = controls(c) + suffix;
                rows = [rows; controlRows];
                replicaKey = [replicaKey; repmat(controlKey, numel(controlRows), 1)];
                replicaRole = [replicaRole; repmat("matched_control", numel(controlRows), 1)];
                replicaPhase = [replicaPhase; repmat(thisPhase, numel(controlRows), 1)];
                replicaEvent = [replicaEvent; repmat(eventKey + suffix, numel(controlRows), 1)];

                identity = controls(c) + "|" + thisPhase;
                firstUse = ~ismember(identity, seenControlPhase);
                isMomentControl = [isMomentControl; repmat(firstUse, numel(controlRows), 1)];
                if firstUse
                    seenControlPhase(end + 1, 1) = identity;
                end

                linkEvent(end + 1, 1) = eventKey + suffix;
                linkPhase(end + 1, 1) = thisPhase;
                linkControl(end + 1, 1) = controlKey;
                linkWeight(end + 1, 1) = share;
            end
        end

        if ~used
            error(['STEP28_SBB_MEETING_MISSING: %s has no usable event and ' 'control rows in any phase.'], eventKey);
        end
    end

    links = table(linkEvent, linkPhase, linkControl, linkWeight, 'VariableNames', {'event_key', 'phase', 'control_key', 'weight'});
end

