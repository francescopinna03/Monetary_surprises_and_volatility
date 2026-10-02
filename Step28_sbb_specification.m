function specification = Step28_sbb_specification(path)

    if nargin < 1 || strlength(strtrim(string(path))) == 0
        error('STEP28_SBB_SPEC_PATH: the frozen specification path is required.');
    end
    path = string(path);
    if ~isfile(path)
        error(['STEP28_SBB_SPEC_MISSING: %s does not exist. Copy '             'config/step28_sbb_specification_template.csv, freeze every ' 'value and point the runner at it.'], path);
    end

    importOptions = detectImportOptions(path, 'Delimiter', ',');
    importOptions = setvartype(importOptions, 'string');
    importOptions.VariableNamingRule = 'preserve';
    importOptions.VariableNamesLine = 1;
    importOptions.DataLines = [2, Inf];
    T = readtable(path, importOptions);

    expectedRows = count_data_lines(path);
    if height(T) ~= expectedRows
        error(['STEP28_SBB_SPEC_TRUNCATED: the file has %d data lines but %d ' 'were read.'], expectedRows, height(T));
    end
    if ~all(ismember(["key", "value"], string(T.Properties.VariableNames)))
        error('STEP28_SBB_SPEC_SCHEMA: the specification needs key and value columns.');
    end
    keys = strtrim(T.key);
    values = strtrim(T.value);
    if numel(unique(keys)) ~= numel(keys)
        error('STEP28_SBB_SPEC_DUPLICATE: every key must appear once.');
    end

    map = containers.Map(cellstr(keys), cellstr(values));

    specification = struct();
    specification.schema_version = required_text(map, 'schema_version');
    if specification.schema_version ~= "step28_sbb_specification_v3"
        error('STEP28_SBB_SPEC_VERSION: unsupported schema %s.', specification.schema_version);
    end

    specification.factor_rank_rule = required_choice(map, 'factor_rank_rule', "selected_by_spectral_gate");
    specification.kappa_grid = required_numeric_list(map, 'kappa_grid');
    if any(specification.kappa_grid <= 1) || any(diff(specification.kappa_grid) <= 0)
        error(['STEP28_SBB_SPEC_KAPPA: kappa_grid must be strictly increasing ' 'with every value greater than one.']);
    end
    specification.kappa_robust_grid = required_numeric_list(map, 'kappa_robust_grid');
    [isMember, position] = ismember(specification.kappa_robust_grid, specification.kappa_grid);
    if ~all(isMember)
        error('STEP28_SBB_SPEC_KROB_SUBSET: kappa_robust_grid must lie in kappa_grid.');
    end
    if any(diff(sort(position)) ~= 1)
        error('STEP28_SBB_SPEC_KROB_CONTIGUOUS: kappa_robust_grid must be contiguous.');
    end

    specification.bootstrap_draws = required_integer(map, 'bootstrap_draws', 99, 1e6);
    specification.bootstrap_seed = required_integer(map, 'bootstrap_seed', 0, 2^31 - 1);
    specification.alpha = required_scalar(map, 'alpha', 1e-4, 0.5 - 1e-9);
    specification.leave_top_k = required_numeric_list(map, 'leave_top_k');
    specification.boundary_bar_perturbations = required_text_list(map, 'boundary_bar_perturbations');
    supportedPerturbations = ["drop_first_post", "drop_last_post", "shift_forward_one_bar", "shift_backward_one_bar"];
    if numel(unique(specification.boundary_bar_perturbations)) ~=             numel(specification.boundary_bar_perturbations) ||             any(~ismember(specification.boundary_bar_perturbations, supportedPerturbations))
        error(['STEP28_SBB_SPEC_PERTURBATIONS: boundary_bar_perturbations '             'must be a non-empty, duplicate-free subset of %s.'], strjoin(supportedPerturbations, ', '));
    end
    specification.whitening_minimum_dates = required_integer(map, 'whitening_minimum_dates', 4, 1e6);
    specification.history_lag = required_integer(map, 'history_lag', 0, 100);

    specification.state_columns = required_text_list(map, 'state_columns');
    specification.surprise_columns = required_text_list(map, 'surprise_columns');
    specification.control_conditioning_rule = required_choice(map,         'control_conditioning_rule', ["state_and_surprise_zeroed", "inherit_matched_event", "state_only"]);
    specification.law_fit_sample = required_choice(map, 'law_fit_sample', ["controls_only", "pooled"]);
    specification.law_pooling = required_choice(map, 'law_pooling', ["group_intercept_pooled_slopes", "per_group"]);
    specification.law_correlation_scope = required_choice(map, 'law_correlation_scope', ["pooled", "per_group"]);
    specification.law_penalty_grid = required_numeric_list(map, 'law_penalty_grid');
    if any(specification.law_penalty_grid < 0) ||             any(specification.law_penalty_grid > 1) || any(diff(specification.law_penalty_grid) <= 0)
        error(['STEP28_SBB_SPEC_PENALTY: law_penalty_grid must increase strictly ' 'within [0,1].']);
    end
    specification.law_minimum_group_rows = required_integer(map, 'law_minimum_group_rows', 4, 1e6);
    specification.law_residual_floor = required_scalar(map, 'law_residual_floor', realmin, 1);

    specification.calibration_meeting_grid = required_numeric_list(map, 'calibration_meeting_grid');
    specification.calibration_frontier_eigengap = required_scalar(map, 'calibration_frontier_eigengap', 1e-9, 1e6);
    specification.calibration_projector_tolerance = required_scalar(map, 'calibration_projector_tolerance', 1e-6, 1 - 1e-9);
    specification.calibration_true_rank = required_numeric_list(map, 'calibration_true_rank');
    if ~isequal(sort(specification.calibration_true_rank), [1, 2])
        error(['STEP28_SBB_SPEC_CALIBRATION_RANK: calibration_true_rank must '             'contain exactly 1|2, because equation (33) is binding for every ' 'admissible low rank.']);
    end
    specification.calibration_positions = optional_integer(map, 'calibration_positions', 5, 1, 100);
    if specification.calibration_positions ~= 5
        error(['STEP28_SBB_SPEC_CALIBRATION_POSITIONS: the primary PR window '             'has five whitened levels and four transitions; spectral ' 'calibration must use five positions.']);
    end
    specification.calibration_replications = optional_integer(map, 'calibration_replications', 200, 20, 1e5);

    specification.spectral_parallel_draws = optional_integer(map, 'spectral_parallel_draws', 199, 19, 1e5);
    specification.spectral_parallel_quantile = optional_scalar(map, 'spectral_parallel_quantile', 0.95, 0.5 + 1e-9, 1 - 1e-9);
    specification.spectral_reconstruction_folds = optional_integer(map, 'spectral_reconstruction_folds', 5, 2, 100);
    specification.spectral_stability_draws = optional_integer(map, 'spectral_stability_draws', 199, 19, 1e5);
    specification.spectral_angle_draws = optional_integer(map, 'spectral_angle_draws', 199, 19, 1e5);

    specification.markov_r2_grid = required_numeric_list(map, 'markov_r2_grid');
    if any(specification.markov_r2_grid <= 0) ||             any(specification.markov_r2_grid >= 1) || any(diff(specification.markov_r2_grid) <= 0)
        error(['STEP28_SBB_SPEC_R2_GRID: markov_r2_grid must increase strictly ' 'inside (0, 1).']);
    end
    specification.markov_draws = optional_integer(map, 'markov_draws', 999, 99, 1e5);
    specification.markov_power_draws = optional_integer(map, 'markov_power_draws', 499, 99, 1e5);
    specification.markov_benchmark_draws = optional_integer(map, 'markov_benchmark_draws', 999, 99, 1e5);

    specification.gaussian_mean_tolerance = required_scalar(map, 'gaussian_mean_tolerance', 1e-6, 1e3);
    specification.gaussian_covariance_tolerance = required_scalar(map, 'gaussian_covariance_tolerance', 1e-6, 1e3);
    specification.gaussian_coverage_levels = required_numeric_list(map, 'gaussian_coverage_levels');
    if any(specification.gaussian_coverage_levels <= 0) || any(specification.gaussian_coverage_levels >= 1)
        error(['STEP28_SBB_SPEC_COVERAGE_LEVELS: gaussian_coverage_levels must ' 'lie strictly inside (0, 1).']);
    end
    specification.gaussian_coverage_tolerance = required_scalar(map, 'gaussian_coverage_tolerance', 1e-6, 1);

    specification.specification_path = path;
    specification.specification_sha256 = File_sha256(path);
end

function n = count_data_lines(path)
    text = string(fileread(path));
    lines = splitlines(text);
    lines = strtrim(lines);
    lines = lines(strlength(lines) > 0);
    n = numel(lines) - 1;
end

function value = optional_scalar(map, key, fallback, lower, upper)
    if ~isKey(map, key) || strlength(strtrim(string(map(key)))) == 0
        value = fallback;
        return;
    end
    value = required_scalar(map, key, lower, upper);
end

function value = optional_integer(map, key, fallback, lower, upper)
    if ~isKey(map, key) || strlength(strtrim(string(map(key)))) == 0
        value = fallback;
        return;
    end
    value = required_integer(map, key, lower, upper);
end

function value = required_text(map, key)
    if ~isKey(map, key)
        error('STEP28_SBB_SPEC_REQUIRED: %s is missing.', key);
    end
    value = strtrim(string(map(key)));
    if strlength(value) == 0
        error('STEP28_SBB_SPEC_UNFROZEN: %s is empty and has no default.', key);
    end
end

function value = required_choice(map, key, admissible)
    value = required_text(map, key);
    if ~ismember(value, admissible)
        error('STEP28_SBB_SPEC_CHOICE: %s must be one of %s.', key, strjoin(admissible, ', '));
    end
end

function value = required_scalar(map, key, lower, upper)
    value = str2double(required_text(map, key));
    if ~isfinite(value) || value < lower || value > upper
        error('STEP28_SBB_SPEC_RANGE: %s must lie in [%g, %g].', key, lower, upper);
    end
end

function value = required_integer(map, key, lower, upper)
    value = required_scalar(map, key, lower, upper);
    if value ~= floor(value)
        error('STEP28_SBB_SPEC_INTEGER: %s must be an integer.', key);
    end
end

function values = required_numeric_list(map, key)
    parts = split(required_text(map, key), "|");
    values = str2double(parts(:))';
    if isempty(values) || any(~isfinite(values))
        error('STEP28_SBB_SPEC_LIST: %s must be a pipe-separated numeric list.', key);
    end
end

function values = required_text_list(map, key)
    values = strtrim(split(required_text(map, key), "|"));
    values = values(:)';
    if any(strlength(values) == 0)
        error('STEP28_SBB_SPEC_TEXT_LIST: %s has an empty entry.', key);
    end
end
