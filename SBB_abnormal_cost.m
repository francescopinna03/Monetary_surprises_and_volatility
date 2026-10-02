function [abnormal, contrast] = SBB_abnormal_cost(costs, links)

    requiredCosts = ["sequence_key", "phase", "kappa", "drift_mean", "volatility_mean", "total_mean"];
    requiredLinks = ["event_key", "phase", "control_key", "weight"];
    require_columns(costs, requiredCosts, 'costs');
    require_columns(links, requiredLinks, 'links');

    costs.sequence_key = string(costs.sequence_key);
    costs.phase = string(costs.phase);
    costs.kappa = double(costs.kappa);
    links.event_key = string(links.event_key);
    links.phase = string(links.phase);
    links.control_key = string(links.control_key);
    links.weight = double(links.weight);

    if isempty(links) || any(~isfinite(links.weight)) || any(links.weight < 0)
        error('SBB_ABNORMAL_WEIGHTS: weights must be finite and non-negative.');
    end

    weightKey = links.event_key + "|" + links.phase;
    [weightGroup, weightNames] = findgroups(weightKey);
    weightTotal = accumarray(weightGroup, links.weight, [numel(weightNames), 1]);
    if any(abs(weightTotal - 1) > 1e-10)
        offending = weightNames(abs(weightTotal - 1) > 1e-10);
        error('SBB_ABNORMAL_WEIGHT_SUM: weights do not sum to one for %s.', strjoin(offending(1:min(5, numel(offending))), ', '));
    end

    kappaGrid = unique(costs.kappa);
    components = ["drift", "volatility", "total"];
    columnOf = containers.Map(cellstr(components), {'drift_mean', 'volatility_mean', 'total_mean'});

    costIndex = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for i = 1:height(costs)
        costIndex(char(costs.sequence_key(i) + "|" + costs.phase(i) + "|" + sprintf('%.17g', costs.kappa(i)))) = i;
    end

    events = unique(links.event_key + "|" + links.phase);
    nRows = numel(events) * numel(kappaGrid);
    outEvent = strings(nRows, 1);
    outPhase = strings(nRows, 1);
    outKappa = NaN(nRows, 1);
    outEventCost = NaN(nRows, 3);
    outControlCost = NaN(nRows, 3);
    outAbnormal = NaN(nRows, 3);
    outControls = zeros(nRows, 1);
    row = 0;

    for e = 1:numel(events)
        parts = split(events(e), "|");
        eventKey = parts(1);
        phase = parts(2);
        selected = links.event_key == eventKey & links.phase == phase;
        controlKeys = links.control_key(selected);
        weights = links.weight(selected);

        for q = 1:numel(kappaGrid)
            kappa = kappaGrid(q);
            eventValues = lookup_costs(costIndex, costs, columnOf, components, eventKey, phase, kappa, "event");
            controlValues = zeros(1, 3);
            for c = 1:numel(controlKeys)
                controlValues = controlValues + weights(c) *                     lookup_costs(costIndex, costs, columnOf, components, controlKeys(c), phase, kappa, "control");
            end

            row = row + 1;
            outEvent(row) = eventKey;
            outPhase(row) = phase;
            outKappa(row) = kappa;
            outEventCost(row, :) = eventValues;
            outControlCost(row, :) = controlValues;
            outAbnormal(row, :) = eventValues - controlValues;
            outControls(row) = numel(controlKeys);
        end
    end

    abnormal = table(outEvent, outPhase, outKappa, outControls,         outEventCost(:, 1), outEventCost(:, 2), outEventCost(:, 3),         outControlCost(:, 1), outControlCost(:, 2), outControlCost(:, 3),         outAbnormal(:, 1), outAbnormal(:, 2), outAbnormal(:, 3),         'VariableNames', {'event_key', 'phase', 'kappa', 'n_controls',         'event_drift', 'event_volatility', 'event_total',         'control_drift', 'control_volatility', 'control_total', 'abnormal_drift', 'abnormal_volatility', 'abnormal_total'});
    abnormal = sortrows(abnormal, {'phase', 'event_key', 'kappa'});

    contrast = paired_contrast(abnormal);
end

function values = lookup_costs(costIndex, costs, columnOf, components, key, phase, kappa, role)
    lookupKey = char(key + "|" + phase + "|" + sprintf('%.17g', kappa));
    if ~isKey(costIndex, lookupKey)
        error(['SBB_ABNORMAL_MISSING_COST: no %s cost for %s in phase %s at ' 'kappa %.10g.'], role, key, phase, kappa);
    end
    index = costIndex(lookupKey);
    values = zeros(1, numel(components));
    for j = 1:numel(components)
        values(j) = costs.(columnOf(char(components(j))))(index);
    end
end

function contrast = paired_contrast(abnormal)
    kappaGrid = unique(abnormal.kappa);
    prRows = abnormal.phase == "PR";
    pcRows = abnormal.phase == "PC";
    paired = intersect(unique(abnormal.event_key(prRows)), unique(abnormal.event_key(pcRows)));

    if isempty(paired)
        error('SBB_ABNORMAL_UNPAIRED: no event survives in both phases.');
    end

    nKappa = numel(kappaGrid);
    kappaOut = NaN(nKappa, 1);
    nEvents = zeros(nKappa, 1);
    meanDrift = NaN(nKappa, 1);
    meanVolatility = NaN(nKappa, 1);
    meanTotal = NaN(nKappa, 1);

    for q = 1:nKappa
        kappa = kappaGrid(q);
        pr = abnormal(abnormal.phase == "PR" & abnormal.kappa == kappa, :);
        pc = abnormal(abnormal.phase == "PC" & abnormal.kappa == kappa, :);
        [~, prPos] = ismember(paired, pr.event_key);
        [~, pcPos] = ismember(paired, pc.event_key);
        if any(prPos == 0) || any(pcPos == 0)
            error('SBB_ABNORMAL_PAIRING: a paired event is missing at kappa %.10g.', kappa);
        end
        kappaOut(q) = kappa;
        nEvents(q) = numel(paired);
        meanDrift(q) = mean(pc.abnormal_drift(pcPos) - pr.abnormal_drift(prPos));
        meanVolatility(q) = mean(pc.abnormal_volatility(pcPos) - pr.abnormal_volatility(prPos));
        meanTotal(q) = mean(pc.abnormal_total(pcPos) - pr.abnormal_total(prPos));
    end

    contrast = table(kappaOut, nEvents, meanDrift, meanVolatility, meanTotal,         'VariableNames', {'kappa', 'n_paired_events', 'contrast_drift', 'contrast_volatility', 'contrast_total'});
end

function require_columns(T, required, label)
    missing = required(~ismember(required, string(T.Properties.VariableNames)));
    if ~isempty(missing)
        error('SBB_ABNORMAL_%s_SCHEMA: missing %s.', upper(label), strjoin(missing, ', '));
    end
end
