function inference = SBB_profile_inference(estimator, meetings, kappaGrid, options)

    if nargin < 4 || isempty(options)
        options = struct();
    end
    options = apply_defaults(options, kappaGrid);

    if ~isa(estimator, 'function_handle')
        error('SBB_PROFILE_ESTIMATOR: estimator must be a function handle.');
    end
    meetings = string(meetings(:));
    if numel(meetings) < 2 || numel(unique(meetings)) ~= numel(meetings)
        error('SBB_PROFILE_MEETINGS: meetings must be at least two unique keys.');
    end
    kappaGrid = double(kappaGrid(:));
    if isempty(kappaGrid) || any(kappaGrid <= 1) || any(diff(kappaGrid) <= 0)
        error(['SBB_PROFILE_KAPPA_GRID: kappaGrid must be strictly increasing ' 'and greater than one.']);
    end

    components = ["drift", "volatility", "total"];
    nKappa = numel(kappaGrid);
    nMeetings = numel(meetings);

    point = call_estimator(estimator, meetings, "point_estimate", "none", kappaGrid, components);

    stream = RandStream('mt19937ar', 'Seed', options.seed);
    draws = NaN(options.draws, nKappa, numel(components));
    for b = 1:options.draws
        index = randi(stream, nMeetings, nMeetings, 1);
        drawn = meetings(index);
        draws(b, :, :) = call_estimator(estimator, drawn, "bootstrap_" + string(b), "none", kappaGrid, components);
    end

    [~, robustnessPosition] = ismember(options.robustnessGrid, kappaGrid);
    if any(robustnessPosition == 0)
        error('SBB_PROFILE_ROBUSTNESS_GRID: K_rob must be a subset of K.');
    end
    if any(diff(sort(robustnessPosition)) ~= 1)
        error('SBB_PROFILE_ROBUSTNESS_CONTIGUOUS: K_rob must be contiguous in K.');
    end

    bandRows = cell(numel(components), 1);
    verdictRows = cell(numel(components), 1);
    for c = 1:numel(components)
        estimate = point(:, c);
        sample = draws(:, :, c);
        standardError = std(sample, 0, 1)';
        usable = standardError > 0 & isfinite(standardError);
        if ~all(usable)
            error(['SBB_PROFILE_DEGENERATE: the bootstrap standard error ' 'vanishes for component %s.'], components(c));
        end

        deviation = abs(sample - estimate') ./ standardError';
        supT = max(deviation(:, robustnessPosition), [], 2);
        critical = quantile(supT, 1 - options.alpha);

        lower = estimate - critical * standardError;
        upper = estimate + critical * standardError;

        bandRows{c} = table(repmat(components(c), nKappa, 1), kappaGrid,             estimate, standardError, repmat(critical, nKappa, 1),             lower, upper, ismember(kappaGrid, options.robustnessGrid),             'VariableNames', {'component', 'kappa', 'estimate',             'standard_error', 'critical_value', 'band_lower', 'band_upper', 'in_robustness_interval'});

        inRobust = ismember(kappaGrid, options.robustnessGrid);
        excludesZero = all(lower(inRobust) > 0) || all(upper(inRobust) < 0);
        signUniform = all(sign(estimate(inRobust)) == sign(estimate(find(inRobust, 1))));
        verdictRows{c} = table(components(c), excludesZero, signUniform,             critical, min(estimate(inRobust)), max(estimate(inRobust)),             'VariableNames', {'component', 'uniform_exclusion_of_zero',             'uniform_sign', 'critical_value', 'min_estimate_in_k_rob', 'max_estimate_in_k_rob'});
    end

    bands = vertcat(bandRows{:});
    verdict = vertcat(verdictRows{:});

    stability = stability_table(estimator, meetings, kappaGrid, components, point, options);

    inference = struct();
    inference.schema_version = "sbb_profile_inference_v1";
    inference.kappa_grid = kappaGrid';
    inference.robustness_grid = options.robustnessGrid(:)';
    inference.alpha = options.alpha;
    inference.draws = options.draws;
    inference.seed = options.seed;
    inference.n_meetings = nMeetings;
    inference.bands = bands;
    inference.verdict = verdict;
    inference.stability = stability;
    inference.admissible_conclusion = verdict(:, {'component'});
    inference.admissible_conclusion.admissible = verdict.uniform_exclusion_of_zero & verdict.uniform_sign & stability_all_pass(stability, components);
end

function options = apply_defaults(options, kappaGrid)
    kappaGrid = double(kappaGrid(:));
    if ~isfield(options, 'draws') || isempty(options.draws)
        options.draws = 999;
    end
    if ~isfield(options, 'alpha') || isempty(options.alpha)
        options.alpha = 0.05;
    end
    if ~isfield(options, 'seed') || isempty(options.seed)
        error(['SBB_PROFILE_SEED: the bootstrap seed must be frozen before ' 'the run, not defaulted.']);
    end
    if ~isfield(options, 'robustnessGrid') || isempty(options.robustnessGrid)
        options.robustnessGrid = kappaGrid;
    end
    options.robustnessGrid = double(options.robustnessGrid(:));
    if ~isfield(options, 'leaveTopK') || isempty(options.leaveTopK)
        options.leaveTopK = [1, 3, 5];
    end
    options.leaveTopK = double(options.leaveTopK(:))';
    if ~isfield(options, 'perturbations')
        options.perturbations = strings(0, 1);
    end
    options.perturbations = string(options.perturbations(:));
    if ~isfield(options, 'leaveOneFold')
        options.leaveOneFold = strings(0, 1);
    end
    options.leaveOneFold = string(options.leaveOneFold(:));
    if ~isfield(options, 'foldOfMeeting')
        options.foldOfMeeting = strings(0, 1);
    end
    options.foldOfMeeting = string(options.foldOfMeeting(:));
    if ~isfield(options, 'rankOfMeeting')
        options.rankOfMeeting = zeros(0, 1);
    end
    options.rankOfMeeting = double(options.rankOfMeeting(:));

    if options.draws < 99 || options.draws ~= floor(options.draws)
        error('SBB_PROFILE_DRAWS: draws must be an integer of at least 99.');
    end
    if options.alpha <= 0 || options.alpha >= 0.5
        error('SBB_PROFILE_ALPHA: alpha must lie strictly in (0, 0.5).');
    end
end

function values = call_estimator(estimator, meetings, label, perturbation, kappaGrid, components)
    context = struct('meetings', {meetings}, 'label', label, 'perturbation', perturbation);
    result = estimator(context);

    required = ["kappa", "contrast_drift", "contrast_volatility", "contrast_total"];
    missing = required(~ismember(required, string(result.Properties.VariableNames)));
    if ~isempty(missing)
        error('SBB_PROFILE_ESTIMATOR_SCHEMA: %s is missing %s.', label, strjoin(missing, ', '));
    end
    if height(result) ~= numel(kappaGrid) || any(abs(double(result.kappa) - kappaGrid) > 1e-12)
        error(['SBB_PROFILE_ESTIMATOR_GRID: %s did not return the frozen ' 'kappa grid.'], label);
    end

    values = NaN(numel(kappaGrid), numel(components));
    for c = 1:numel(components)
        column = "contrast_" + components(c);
        values(:, c) = double(result.(char(column)));
    end
    if any(~isfinite(values), 'all')
        error('SBB_PROFILE_ESTIMATOR_NONFINITE: %s returned a non-finite value.', label);
    end
end

function stability = stability_table(estimator, meetings, kappaGrid, components, point, options)
    rows = {};
    inRobust = ismember(kappaGrid, options.robustnessGrid);

    if ~isempty(options.foldOfMeeting)
        if numel(options.foldOfMeeting) ~= numel(meetings)
            error(['SBB_PROFILE_FOLD_LABELS: foldOfMeeting must have one entry ' 'per meeting.']);
        end
        folds = unique(options.foldOfMeeting);
        for f = 1:numel(folds)
            kept = meetings(options.foldOfMeeting ~= folds(f));
            rows{end + 1} = stability_row(estimator, kept, kappaGrid, components, point, inRobust, "leave_year_out", folds(f), "none");
        end
    end

    if ~isempty(options.rankOfMeeting)
        if numel(options.rankOfMeeting) ~= numel(meetings)
            error(['SBB_PROFILE_RANK_LABELS: rankOfMeeting must have one entry ' 'per meeting.']);
        end
        [~, order] = sort(options.rankOfMeeting, 'descend');
        for k = options.leaveTopK
            if k >= numel(meetings)
                error('SBB_PROFILE_LEAVE_TOP_K: k = %d removes every meeting.', k);
            end
            kept = meetings(setdiff(1:numel(meetings), order(1:k)));
            rows{end + 1} = stability_row(estimator, kept, kappaGrid, components, point, inRobust, "leave_top_k", string(k), "none");
        end
    end

    for p = 1:numel(options.perturbations)
        rows{end + 1} = stability_row(estimator, meetings, kappaGrid,             components, point, inRobust, "boundary_bar_perturbation", options.perturbations(p), options.perturbations(p));
    end

    if isempty(rows)
        stability = table('Size', [0, 6], 'VariableTypes',             {'string', 'string', 'string', 'logical', 'double', 'double'},             'VariableNames', {'exercise', 'level', 'component',             'sign_preserved_in_k_rob', 'min_estimate_in_k_rob', 'max_estimate_in_k_rob'});
        return;
    end
    stability = vertcat(rows{:});
end

function row = stability_row(estimator, kept, kappaGrid, components, point, inRobust, exercise, level, perturbation)
    label = exercise + ":" + level;
    values = call_estimator(estimator, kept, label, perturbation, kappaGrid, components);
    nComponents = numel(components);
    preserved = false(nComponents, 1);
    minimum = NaN(nComponents, 1);
    maximum = NaN(nComponents, 1);
    for c = 1:nComponents
        restricted = values(inRobust, c);
        reference = point(inRobust, c);
        preserved(c) = all(sign(restricted) == sign(reference));
        minimum(c) = min(restricted);
        maximum(c) = max(restricted);
    end
    row = table(repmat(exercise, nComponents, 1),         repmat(level, nComponents, 1), components(:), preserved, minimum,         maximum, 'VariableNames', {'exercise', 'level', 'component',         'sign_preserved_in_k_rob', 'min_estimate_in_k_rob', 'max_estimate_in_k_rob'});
end

function passes = stability_all_pass(stability, components)
    passes = true(numel(components), 1);
    if isempty(stability)
        return;
    end
    for c = 1:numel(components)
        rows = stability.component == components(c);
        if any(rows)
            passes(c) = all(stability.sign_preserved_in_k_rob(rows));
        end
    end
end
