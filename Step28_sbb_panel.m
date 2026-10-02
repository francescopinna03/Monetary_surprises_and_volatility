function panel = Step28_sbb_panel(projectRoot, specification)

    if nargin < 1 || strlength(strtrim(string(projectRoot))) == 0
        projectRoot = Get_project_root();
    end
    outputDir = fullfile(projectRoot, 'Output', 'step28_sbbts');

    intersectionFile = fullfile(outputDir, 'step28_date_phase_intersection.csv');
    barsFile = fullfile(outputDir, 'step28_canonical_bars.csv');
    selectedFile = fullfile(outputDir, 'step28_selected_contracts.csv');
    coverageFile = fullfile(outputDir, 'step28_phase_coverage.csv');
    supportFile = fullfile(outputDir, 'step28_event_control_support.csv');
    stateFile = fullfile(projectRoot, 'Output', 'analysis', 'event_state_panel.csv');

    required = string({barsFile, selectedFile, coverageFile, supportFile, stateFile, intersectionFile});
    missing = required(~isfile(required));
    if ~isempty(missing)
        error('STEP28_SBB_PANEL_INPUTS: missing %s.', strjoin(missing, ' | '));
    end

    bars = read_csv(barsFile);
    selected = read_csv(selectedFile);
    coverage = read_csv(coverageFile);
    support = read_csv(supportFile);
    state = read_csv(stateFile);

    basePostRange = struct('PR', [5, 25], 'PC', [5, 45]);
    barMinutes = 5;
    assets = ["schatz", "bobl", "bund"];

    perturbationFamily = struct(         'drop_first_post', struct('shift', 0, 'dropFirst', true, 'dropLast', false),         'drop_last_post', struct('shift', 0, 'dropFirst', false, 'dropLast', true),         'shift_forward_one_bar', struct('shift', barMinutes, 'dropFirst', false, 'dropLast', false), 'shift_backward_one_bar', struct('shift', -barMinutes, 'dropFirst', false, 'dropLast', false));

    bars.bar_end_utc = Parse_utc_datetime(bars.bar_end_utc);
    bars.trade_date = string(bars.trade_date);
    bars.sample_role = string(bars.sample_role);
    bars.asset_id = string(bars.asset_id);
    bars.candidate_rank = double(bars.candidate_rank);
    bars.Close = double(bars.Close);

    selectedKey = string(selected.trade_date) + "|" +         string(selected.sample_role) + "|" + string(selected.asset_id) + "|" + string(double(selected.candidate_rank));
    barKey = bars.trade_date + "|" + bars.sample_role + "|" + bars.asset_id + "|" + string(bars.candidate_rank);
    bars = bars(ismember(barKey, selectedKey), :);
    if isempty(bars)
        error('STEP28_SBB_PANEL_SELECTION: no bar survives the certified selection.');
    end

    closeIndex = containers.Map(cellstr(bars.trade_date + "|" +         bars.sample_role + "|" + bars.asset_id + "|" +         string(bars.bar_end_utc, 'yyyy-MM-dd HH:mm:ss')), num2cell(bars.Close));

    coverage.trade_date = string(coverage.trade_date);
    coverage.sample_role = string(coverage.sample_role);
    coverage.phase = string(coverage.phase);
    coverage.anchor_utc = Parse_utc_datetime(coverage.anchor_utc);
    coverage = unique(coverage(:, {'trade_date', 'sample_role', 'phase', 'anchor_utc'}), 'rows');

    intersection = read_csv(intersectionFile);
    eligibleKey = string(intersection.trade_date) + "|" + string(intersection.sample_role) + "|" + string(intersection.phase);
    eligibleKey = eligibleKey(String_to_boolean(intersection.three_asset_eligible));
    coverageKey = coverage.trade_date + "|" + coverage.sample_role + "|" + coverage.phase;
    dropped = ~ismember(coverageKey, eligibleKey);
    nDropped = sum(dropped);
    coverage = coverage(~dropped, :);
    if isempty(coverage)
        error(['STEP28_SBB_PANEL_INTERSECTION: no date-phase cell survives the ' 'certified three-asset intersection.']);
    end

    [dateKey, role, phase, position, foldKey, returns] = build_rows(         coverage, closeIndex, assets, basePostRange, barMinutes, struct('shift', 0, 'dropFirst', false, 'dropLast', false));

    if isempty(returns)
        error('STEP28_SBB_PANEL_EMPTY: no synchronised transition survives.');
    end

    links = build_links(support);

    state.date_key = string(state.event_date);
    stateColumns = ["date_key", specification.state_columns];
    surpriseColumns = ["date_key", specification.surprise_columns];
    require_columns(state, stateColumns, 'state');
    require_columns(state, surpriseColumns, 'surprise');

    conditioningColumns = [specification.state_columns, specification.surprise_columns];
    finiteEvent = true(height(state), 1);
    for c = 1:numel(conditioningColumns)
        finiteEvent = finiteEvent & isfinite(double(state.(char(conditioningColumns(c)))));
    end
    usableEventKeys = state.date_key(finiteEvent);
    excludedEvents = setdiff(unique(dateKey(role == "event")), usableEventKeys);

    if ~isempty(excludedEvents)
        drop = role == "event" & ismember(dateKey, excludedEvents);
        dateKey(drop) = [];
        role(drop) = [];
        phase(drop) = [];
        position(drop) = [];
        foldKey(drop) = [];
        returns(drop, :) = [];
        links = links(~ismember(links.event_key, excludedEvents), :);
        if isempty(links)
            error(['STEP28_SBB_PANEL_CONDITIONING: no event retains a finite ' 'state and surprise block.']);
        end
    end

    panel = struct();
    panel.schema_version = "step28_sbb_panel_v1";
    panel.assets = assets;
    panel.returns = returns;
    panel.date_key = dateKey;
    panel.role = role;
    panel.phase = phase;
    panel.position = position;
    panel.fold_key = foldKey;
    panel.state = state(:, cellstr(stateColumns));
    panel.surprise = state(:, cellstr(surpriseColumns));
    panel.links = links;
    perturbationNames = string(fieldnames(perturbationFamily))';
    perturbations = struct();
    for q = 1:numel(perturbationNames)
        name = perturbationNames(q);
        [pDate, pRole, pPhase, pPosition, pFold, pReturns] = build_rows(             coverage, closeIndex, assets, basePostRange, barMinutes, perturbationFamily.(char(name)));
        if isempty(pReturns)
            error(['STEP28_SBB_PANEL_PERTURBATION: %s leaves no synchronised ' 'transition.'], name);
        end
        perturbations.(char(name)) = struct('date_key', pDate, 'role', pRole,             'phase', pPhase, 'position', pPosition, 'fold_key', pFold, 'returns', pReturns);
    end
    panel.perturbations = perturbations;
    panel.perturbation_names = perturbationNames;
    panel.n_intersection_cells_dropped = nDropped;
    panel.n_event_dates = numel(unique(dateKey(role == "event")));
    panel.n_control_dates = numel(unique(dateKey(role == "matched_control")));
    panel.excluded_event_dates = excludedEvents(:)';
    panel.n_excluded_event_dates = numel(excludedEvents);
    panel.exclusion_rule = "exclude_event_without_finite_frozen_conditioning_block";
end

function [dateKey, role, phase, position, foldKey, returns] = build_rows( coverage, closeIndex, assets, basePostRange, barMinutes, variant)

    dateKey = strings(0, 1);
    role = strings(0, 1);
    phase = strings(0, 1);
    position = zeros(0, 1);
    foldKey = strings(0, 1);
    returns = zeros(0, numel(assets));

    for i = 1:height(coverage)
        thisDate = coverage.trade_date(i);
        thisRole = coverage.sample_role(i);
        thisPhase = coverage.phase(i);
        anchor = coverage.anchor_utc(i);
        if ~isfield(basePostRange, thisPhase)
            error('STEP28_SBB_PANEL_PHASE: unknown phase %s.', thisPhase);
        end
        offsets = basePostRange.(thisPhase) + variant.shift;
        endpoints = anchor + minutes(offsets(1):barMinutes:offsets(2));
        if variant.dropFirst
            endpoints = endpoints(2:end);
        end
        if variant.dropLast
            endpoints = endpoints(1:end - 1);
        end
        if numel(endpoints) < 2
            continue;
        end

        for k = 1:numel(endpoints)
            value = NaN(1, numel(assets));
            for a = 1:numel(assets)
                current = lookup_close(closeIndex, thisDate, thisRole, assets(a), endpoints(k));
                previous = lookup_close(closeIndex, thisDate, thisRole, assets(a), endpoints(k) - minutes(barMinutes));
                if isnan(current) || isnan(previous) || current <= 0 || previous <= 0
                    value(a) = NaN;
                else
                    value(a) = log(current) - log(previous);
                end
            end
            if any(isnan(value))
                continue;
            end
            dateKey(end + 1, 1) = thisDate;
            role(end + 1, 1) = thisRole;
            phase(end + 1, 1) = thisPhase;
            position(end + 1, 1) = k;
            foldKey(end + 1, 1) = extractBefore(thisDate, 5);
            returns(end + 1, :) = value;
        end
    end
end

function value = lookup_close(closeIndex, tradeDate, sampleRole, asset, stamp)
    key = char(tradeDate + "|" + sampleRole + "|" + asset + "|" + string(stamp, 'yyyy-MM-dd HH:mm:ss'));
    if isKey(closeIndex, key)
        value = closeIndex(key);
    else
        value = NaN;
    end
end

function links = build_links(support)
    eventKey = strings(0, 1);
    phase = strings(0, 1);
    controlKey = strings(0, 1);
    weight = zeros(0, 1);

    for i = 1:height(support)
        if ~String_to_boolean(support.event_usable(i))
            continue;
        end
        raw = strtrim(string(support.usable_control_dates(i)));
        if strlength(raw) == 0
            continue;
        end
        controls = strtrim(split(raw, "|"));
        controls = controls(strlength(controls) > 0);
        if isempty(controls)
            continue;
        end
        share = 1 / numel(controls);
        for c = 1:numel(controls)
            eventKey(end + 1, 1) = string(support.event_date(i));
            phase(end + 1, 1) = string(support.phase(i));
            controlKey(end + 1, 1) = controls(c);
            weight(end + 1, 1) = share;
        end
    end

    if isempty(eventKey)
        error('STEP28_SBB_PANEL_LINKS: no usable event-control link survives.');
    end
    links = table(eventKey, phase, controlKey, weight, 'VariableNames', {'event_key', 'phase', 'control_key', 'weight'});
end

function T = read_csv(path)
    T = readtable(path, 'Delimiter', ',', 'TextType', 'string', 'VariableNamingRule', 'preserve');
end

function require_columns(T, required, label)
    missing = required(~ismember(required, string(T.Properties.VariableNames)));
    if ~isempty(missing)
        error('STEP28_SBB_PANEL_%s_SCHEMA: missing %s.', upper(label), strjoin(missing, ', '));
    end
end
