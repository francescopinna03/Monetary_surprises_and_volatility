%% STEP 22: MONETARY-POLICY AND CENTRAL-BANK-INFORMATION SHOCKS.
%
% This script reproduces and extends the Jarocinski-Karadi construction on
% the EA-MPD workbook. Separate PR and PC median rotations are the primary
% definitions; the Monetary Event window is an aggregate benchmark. Poor-man
% shocks,
% rotation-quantile sensitivity and leave-one-event-out diagnostics are
% produced before any volatility outcome is loaded.
%
% Inputs:
%   Raw/EA_MPD/Dataset_EA-MPD.xlsx (accepted spelling variants below)
%   Output/manifests/time_alignment_manifest.csv
%
% Outputs under Output/analysis:
%   shock_components_by_event.csv
%   shock_components_audit.csv
%   shock_components_window_comparison.csv
%   shock_components_leave_one_out.csv
%   shock_components_rotation_sensitivity.csv
%   shock_components_manifest.csv

projectRoot = Get_project_root();
Require_time_alignment_manifest(projectRoot);
Require_window_semantics_manifest(projectRoot);

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
if exist(analysisDir, 'dir') ~= 7
    mkdir(analysisDir);
end

eampdCandidates = {
    fullfile(projectRoot, 'Raw', 'EA_MPD', 'Dataset_EA-MPD.xlsx');
    fullfile(projectRoot, 'Raw', 'EA_MPD', 'Dataset_EA_MPD.xlsx');
    fullfile(projectRoot, 'Raw', 'EA_MPD', 'EA-MPD.xlsx');
    fullfile(projectRoot, 'Raw', 'EA_MPD', 'EA_MPD.xlsx')};
eampdFile = Locate_first_existing(eampdCandidates);

if strlength(eampdFile) == 0
    error('STEP22_EAMPD_MISSING: no EA-MPD workbook was found under Raw/EA_MPD.');
end

windowSheets = ["Press Release Window", "Press Conference Window", ...
    "Monetary Event Window"];
windowCodes = ["PR", "PC", "ME"];
primaryRotationQuantile = 0.5;
rotationGrid = [0.05, 0.16, 0.50, 0.84, 0.95];

availableSheets = string(sheetnames(eampdFile));
for s = windowSheets
    if ~any(strcmpi(strtrim(availableSheets), s))
        error('STEP22_SHEET_MISSING: required sheet "%s" was not found in %s.', s, eampdFile);
    end
end

projectDates = load_project_event_dates(projectRoot);
if isempty(projectDates)
    warning(['STEP22_PROJECT_DATES_MISSING: project event dates could not be read. ' ...
        'Leave-one-out diagnostics will cover every eligible EA-MPD event.']);
end

components = table();
audit = empty_audit_table();
rotationSensitivity = table();
leaveOneOut = table();
windowFits = cell(numel(windowCodes), 1);

jointAnnouncementDates = datetime([2001, 2001, 2008], [9, 9, 10], ...
    [13, 17, 8])';

fprintf('STEP 22 input: %s\n', eampdFile);

for k = 1:numel(windowCodes)
    code = windowCodes(k);
    sheet = windowSheets(k);
    source = read_eampd_window(eampdFile, sheet);

    excludedJoint = ismember(source.event_date, jointAnnouncementDates);
    nExcludedJoint = sum(excludedJoint);
    source.event_date = source.event_date(~excludedJoint);
    source.ois = source.ois(~excludedJoint, :);
    source.stoxx50 = source.stoxx50(~excludedJoint);
    nSource = numel(source.event_date);

    [distinctDates, ~, dateGroup] = unique(source.event_date);
    dateCounts = accumarray(dateGroup, 1);
    duplicateDates = distinctDates(dateCounts > 1);
    if ~isempty(duplicateDates)
        duplicateText = strjoin(string(duplicateDates, 'yyyy-MM-dd'), ', ');
        error(['STEP22_DUPLICATE_DATES: unexpected duplicate event dates in ' ...
            'sheet "%s" after excluding joint announcements: %s.'], ...
            sheet, duplicateText);
    end

    baseSample = ~isnat(source.event_date);

    [shock, fit] = Build_JK_shock_components(source.ois, ...
        source.stoxx50, baseSample, primaryRotationQuantile);
    windowFits{k} = fit;

    W = table();
    W.event_date = source.event_date;
    W.window = repmat(code, nSource, 1);
    W.source_sheet = repmat(sheet, nSource, 1);
    W.OIS_1M = source.ois(:, 1);
    W.OIS_3M = source.ois(:, 2);
    W.OIS_6M = source.ois(:, 3);
    W.OIS_1Y = source.ois(:, 4);
    W.STOXX50 = source.stoxx50;
    W.policy_indicator = shock.policy_indicator;
    W.curve_PC1_z = shock.curve_pc_z(:, 1);
    W.curve_PC2_z = shock.curve_pc_z(:, 2);
    W.curve_PC3_z = shock.curve_pc_z(:, 3);
    W.curve_PC4_z = shock.curve_pc_z(:, 4);
    W.target_proxy_10bp = source.ois(:, 1) / 10;
    W.path_slope_proxy_10bp = (source.ois(:, 4) - source.ois(:, 1)) / 10;
    W.MP_pm = shock.MP_pm;
    W.CBI_pm = shock.CBI_pm;
    W.MP_median = shock.MP_rotation;
    W.CBI_median = shock.CBI_rotation;
    W.policy_indicator_10bp = shock.policy_indicator / 0.10;
    W.MP_median_10bp = shock.MP_rotation / 0.10;
    W.CBI_median_10bp = shock.CBI_rotation / 0.10;
    W.pca_sample = shock.pca_sample;
    W.estimation_sample = shock.shock_sample;
    W.excluded_joint_announcement = false(nSource, 1);
    W.in_project_sample = ismember(source.event_date, projectDates);
    W.primary_phase_definition = repmat(ismember(code, ["PR", "PC"]), ...
        nSource, 1);
    W.aggregate_benchmark = repmat(code == "ME", nSource, 1);
    components = [components; W]; %#ok<AGROW>

    valid = shock.shock_sample;
    U = [shock.MP_rotation(valid), shock.CBI_rotation(valid)];
    M = [shock.policy_indicator(valid), source.stoxx50(valid)];

    audit = append_audit(audit, code, "n_source_rows", nSource);
    audit = append_audit(audit, code, ...
        "n_joint_announcement_rows_excluded", nExcludedJoint);
    audit = append_audit(audit, code, "n_pca_rows", fit.n_pca);
    audit = append_audit(audit, code, "n_shock_rows", fit.n_shocks);
    audit = append_audit(audit, code, "n_project_shock_rows", ...
        sum(valid & W.in_project_sample));
    audit = append_audit(audit, code, "pc1_explained_share", fit.pca_explained(1));
    maturityNames = ["OIS_1M", "OIS_3M", "OIS_6M", "OIS_1Y"];
    for j = 1:4
        audit = append_audit(audit, code, "pc" + j + "_explained_share", ...
            fit.pca_explained(j));
        audit = append_audit(audit, code, "pc1_loading_" + ...
            maturityNames(j), ...
            fit.pc1_loading(j));
        audit = append_audit(audit, code, "pc2_loading_" + ...
            maturityNames(j), fit.curve_loadings(j, 2));
    end
    audit = append_audit(audit, code, "rotation_angle_radians", fit.rotation_angle);
    audit = append_audit(audit, code, "MP_equity_loading", fit.C(1, 2));
    audit = append_audit(audit, code, "CBI_equity_loading", fit.C(2, 2));
    audit = append_audit(audit, code, "sign_restrictions_pass", ...
        double(fit.C(1, 2) < 0 && fit.C(2, 2) > 0));
    audit = append_audit(audit, code, "max_median_sum_error", ...
        max(abs(sum(U, 2) - M(:, 1))));
    audit = append_audit(audit, code, "max_poor_man_sum_error", ...
        max(abs(shock.MP_pm(valid) + shock.CBI_pm(valid) - M(:, 1))));
    audit = append_audit(audit, code, "max_system_reconstruction_error", ...
        max(abs(U * fit.C - M), [], 'all'));
    audit = append_audit(audit, code, "raw_MP_CBI_cross_moment", ...
        mean(U(:, 1) .* U(:, 2)));
    audit = append_audit(audit, code, "centered_MP_CBI_correlation", ...
        safe_correlation(U(:, 1), U(:, 2)));
    audit = append_audit(audit, code, "condition_number_effect_matrix", cond(fit.C));

    for q = rotationGrid
        [shockQ, fitQ] = Build_JK_shock_components(source.ois, ...
            source.stoxx50, baseSample, q);
        keep = shockQ.shock_sample;
        if ~isempty(projectDates)
            keep = keep & ismember(source.event_date, projectDates);
        end

        R = table();
        R.event_date = source.event_date(keep);
        R.window = repmat(code, sum(keep), 1);
        R.rotation_quantile = repmat(q, sum(keep), 1);
        R.rotation_angle_radians = repmat(fitQ.rotation_angle, sum(keep), 1);
        R.policy_indicator = shockQ.policy_indicator(keep);
        R.MP = shockQ.MP_rotation(keep);
        R.CBI = shockQ.CBI_rotation(keep);
        R.MP_equity_loading = repmat(fitQ.C(1, 2), sum(keep), 1);
        R.CBI_equity_loading = repmat(fitQ.C(2, 2), sum(keep), 1);
        rotationSensitivity = [rotationSensitivity; R]; %#ok<AGROW>
    end

    looTargets = valid;
    if ~isempty(projectDates)
        looTargets = looTargets & ismember(source.event_date, projectDates);
    end
    targetRows = find(looTargets);

    for r = 1:numel(targetRows)
        row = targetRows(r);
        trainingSample = baseSample;
        trainingSample(row) = false;

        try
            [~, looFit] = Build_JK_shock_components(source.ois, ...
                source.stoxx50, trainingSample, primaryRotationQuantile);
            applied = Apply_JK_shock_fit(source.ois(row, :), ...
                source.stoxx50(row), looFit);

            L = table();
            L.event_date = source.event_date(row);
            L.window = code;
            L.full_policy_indicator = shock.policy_indicator(row);
            L.loo_policy_indicator = applied.policy_indicator;
            L.full_MP_median = shock.MP_rotation(row);
            L.loo_MP_median = applied.MP_rotation;
            L.full_CBI_median = shock.CBI_rotation(row);
            L.loo_CBI_median = applied.CBI_rotation;
            L.delta_policy_indicator = applied.policy_indicator - shock.policy_indicator(row);
            L.delta_MP_median = applied.MP_rotation - shock.MP_rotation(row);
            L.delta_CBI_median = applied.CBI_rotation - shock.CBI_rotation(row);
            L.full_MP_pm = shock.MP_pm(row);
            L.loo_MP_pm = applied.MP_pm;
            L.poor_man_classification_flip = ...
                abs(applied.MP_pm - shock.MP_pm(row)) > 1e-12;
            L.full_rotation_angle = fit.rotation_angle;
            L.loo_rotation_angle = looFit.rotation_angle;
            L.loading_distance = norm(looFit.pc1_loading - fit.pc1_loading);
            L.effect_matrix_distance = norm(looFit.C - fit.C, 'fro');
            L.fit_ok = true;
            L.error_message = "";
        catch ME
            L = failed_loo_row(source.event_date(row), code, shock, fit, row, ME.message);
        end

        leaveOneOut = [leaveOneOut; L]; %#ok<AGROW>
    end

    fprintf('%s: PC1 share %.3f; shocks %d; project shocks %d; angle %.3f rad.\n', ...
        code, fit.pca_explained(1), fit.n_shocks, sum(valid & W.in_project_sample), ...
        fit.rotation_angle);
end

windowComparison = build_window_comparison(components, windowCodes);

audit = append_rotation_stability_audit(audit, rotationSensitivity, windowCodes);
audit = append_loo_audit(audit, leaveOneOut, windowCodes);

write_table_with_dates(components, fullfile(analysisDir, ...
    'shock_components_by_event.csv'));
writetable(audit, fullfile(analysisDir, 'shock_components_audit.csv'));
writetable(windowComparison, fullfile(analysisDir, ...
    'shock_components_window_comparison.csv'));
write_table_with_dates(leaveOneOut, fullfile(analysisDir, ...
    'shock_components_leave_one_out.csv'));
write_table_with_dates(rotationSensitivity, fullfile(analysisDir, ...
    'shock_components_rotation_sensitivity.csv'));

manifest = build_step22_manifest(eampdFile, primaryRotationQuantile, ...
    rotationGrid, windowSheets);
writetable(manifest, fullfile(analysisDir, 'shock_components_manifest.csv'));

fprintf('\n================ STEP 22 SUMMARY ================\n');
fprintf('Primary definitions: PR and PC median rotations\n');
fprintf('Aggregate benchmark: ME median rotation\n');
fprintf('Component rows     : %d\n', height(components));
fprintf('LOO rows           : %d\n', height(leaveOneOut));
fprintf('Rotation rows      : %d\n', height(rotationSensitivity));
fprintf('Output directory   : %s\n', analysisDir);
fprintf('=================================================\n');

function source = read_eampd_window(filePath, sheet)
    T = readtable(filePath, 'Sheet', sheet, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    names = string(T.Properties.VariableNames);
    normalized = normalize_names(names);

    dateColumn = find_column(normalized, ["date", "event_date", "meeting_date"]);
    oisColumns = [find_column(normalized, ["ois_1m", "ois1m"]), ...
        find_column(normalized, ["ois_3m", "ois3m"]), ...
        find_column(normalized, ["ois_6m", "ois6m"]), ...
        find_column(normalized, ["ois_1y", "ois1y"])] ;
    stockColumn = find_column(normalized, ["stoxx50", "stoxx_50"]);

    if strlength(dateColumn) == 0 || any(strlength(oisColumns) == 0) || ...
            strlength(stockColumn) == 0
        error(['STEP22_COLUMNS_MISSING: sheet "%s" must contain date, OIS_1M, ' ...
            'OIS_3M, OIS_6M, OIS_1Y and STOXX50.'], sheet);
    end

    source = struct();
    source.event_date = Parse_date_flexible(T.(names(normalized == dateColumn)));
    source.ois = nan(height(T), 4);
    for j = 1:4
        source.ois(:, j) = to_numeric(T.(names(normalized == oisColumns(j))));
    end
    source.stoxx50 = to_numeric(T.(names(normalized == stockColumn)));

    keep = ~isnat(source.event_date);
    source.event_date = source.event_date(keep);
    source.ois = source.ois(keep, :);
    source.stoxx50 = source.stoxx50(keep);
end

function normalized = normalize_names(names)
    normalized = lower(strtrim(names));
    normalized = regexprep(normalized, '[^a-z0-9]+', '_');
    normalized = regexprep(normalized, '_+', '_');
    normalized = regexprep(normalized, '^_|_$', '');
end

function result = find_column(normalizedNames, candidates)
    result = "";
    for c = candidates
        hit = find(normalizedNames == c, 1);
        if ~isempty(hit)
            result = normalizedNames(hit);
            return;
        end
    end
end

function x = to_numeric(x)
    if ~isnumeric(x)
        x = str2double(string(x));
    end
    x = double(x(:));
end

function dates = load_project_event_dates(projectRoot)
    candidates = {
        fullfile(projectRoot, 'Output', 'analysis', 'pr_baseline_panel.csv');
        fullfile(projectRoot, 'Output', 'event_windows', 'event_window_panel.csv')};
    dates = NaT(0, 1);

    for k = 1:numel(candidates)
        if exist(candidates{k}, 'file') ~= 2
            continue;
        end
        T = readtable(candidates{k}, 'TextType', 'string', ...
            'VariableNamingRule', 'preserve');
        names = string(T.Properties.VariableNames);
        normalized = normalize_names(names);
        dateName = find_column(normalized, ["event_date", "trade_date"]);
        if strlength(dateName) > 0
            dates = unique(Parse_date_flexible(T.(names(normalized == dateName))));
            dates = dates(~isnat(dates));
            return;
        end
    end
end

function T = empty_audit_table()
    T = table('Size', [0, 4], ...
        'VariableTypes', {'string', 'string', 'double', 'string'}, ...
        'VariableNames', {'window', 'metric', 'value', 'note'});
end

function T = append_audit(T, window, metric, value, note)
    if nargin < 5
        note = "";
    end
    row = table(string(window), string(metric), double(value), string(note), ...
        'VariableNames', T.Properties.VariableNames);
    T = [T; row];
end

function rho = safe_correlation(x, y)
    ok = isfinite(x) & isfinite(y);
    if sum(ok) < 3 || std(x(ok)) == 0 || std(y(ok)) == 0
        rho = NaN;
        return;
    end
    C = corrcoef(x(ok), y(ok));
    rho = C(1, 2);
end

function L = failed_loo_row(eventDate, code, shock, fit, row, message)
    L = table();
    L.event_date = eventDate;
    L.window = code;
    L.full_policy_indicator = shock.policy_indicator(row);
    L.loo_policy_indicator = NaN;
    L.full_MP_median = shock.MP_rotation(row);
    L.loo_MP_median = NaN;
    L.full_CBI_median = shock.CBI_rotation(row);
    L.loo_CBI_median = NaN;
    L.delta_policy_indicator = NaN;
    L.delta_MP_median = NaN;
    L.delta_CBI_median = NaN;
    L.full_MP_pm = shock.MP_pm(row);
    L.loo_MP_pm = NaN;
    L.poor_man_classification_flip = false;
    L.full_rotation_angle = fit.rotation_angle;
    L.loo_rotation_angle = NaN;
    L.loading_distance = NaN;
    L.effect_matrix_distance = NaN;
    L.fit_ok = false;
    L.error_message = string(message);
end

function comparison = build_window_comparison(components, windowCodes)
    comparison = table('Size', [0, 8], ...
        'VariableTypes', {'string', 'string', 'string', 'double', 'double', ...
        'double', 'double', 'double'}, ...
        'VariableNames', {'window_a', 'window_b', 'component', 'n_common', ...
        'correlation', 'mean_difference_a_minus_b', 'mean_absolute_difference', ...
        'root_mean_squared_difference'});
    variables = ["policy_indicator", "MP_median", "CBI_median", "MP_pm", "CBI_pm"];

    for a = 1:numel(windowCodes)-1
        A = components(components.window == windowCodes(a), :);
        for b = a+1:numel(windowCodes)
            B = components(components.window == windowCodes(b), :);
            [~, ia, ib] = intersect(A.event_date, B.event_date);
            for variable = variables
                x = A.(variable)(ia);
                y = B.(variable)(ib);
                ok = isfinite(x) & isfinite(y);
                d = x(ok) - y(ok);
                row = table(windowCodes(a), windowCodes(b), variable, sum(ok), ...
                    safe_correlation(x(ok), y(ok)), mean(d, 'omitnan'), ...
                    mean(abs(d), 'omitnan'), sqrt(mean(d.^2, 'omitnan')), ...
                    'VariableNames', comparison.Properties.VariableNames);
                comparison = [comparison; row]; %#ok<AGROW>
            end
        end
    end
end

function audit = append_rotation_stability_audit(audit, R, windowCodes)
    for code = windowCodes
        W = R(R.window == code, :);
        [dates, ~, group] = unique(W.event_date);
        mpRange = nan(numel(dates), 1);
        cbiRange = nan(numel(dates), 1);
        for g = 1:numel(dates)
            mp = W.MP(group == g);
            cbi = W.CBI(group == g);
            mpRange(g) = max(mp) - min(mp);
            cbiRange(g) = max(cbi) - min(cbi);
        end
        audit = append_audit(audit, code, "median_rotation_MP_range_across_grid", ...
            safe_median(mpRange));
        audit = append_audit(audit, code, "max_rotation_MP_range_across_grid", ...
            safe_max(mpRange));
        audit = append_audit(audit, code, "median_rotation_CBI_range_across_grid", ...
            safe_median(cbiRange));
        audit = append_audit(audit, code, "max_rotation_CBI_range_across_grid", ...
            safe_max(cbiRange));
    end
end

function audit = append_loo_audit(audit, L, windowCodes)
    for code = windowCodes
        codeRows = L.window == code;
        W = L(codeRows & L.fit_ok, :);
        audit = append_audit(audit, code, "loo_success_rate", ...
            safe_mean(double(L.fit_ok(codeRows))));
        audit = append_audit(audit, code, "loo_max_abs_delta_policy_indicator", ...
            safe_max(abs(W.delta_policy_indicator)));
        audit = append_audit(audit, code, "loo_max_abs_delta_MP", ...
            safe_max(abs(W.delta_MP_median)));
        audit = append_audit(audit, code, "loo_max_abs_delta_CBI", ...
            safe_max(abs(W.delta_CBI_median)));
        audit = append_audit(audit, code, "loo_poor_man_flip_share", ...
            safe_mean(double(W.poor_man_classification_flip)));
    end
end

function value = safe_max(x)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = max(x);
    end
end

function value = safe_mean(x)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = mean(x);
    end
end

function value = safe_median(x)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = median(x);
    end
end

function write_table_with_dates(T, filePath)
    Tcopy = T;
    dateVariables = string(Tcopy.Properties.VariableNames);
    dateVariables = dateVariables(endsWith(dateVariables, "date"));
    for name = dateVariables
        if isdatetime(Tcopy.(name))
            Tcopy.(name) = string(Tcopy.(name), 'yyyy-MM-dd');
        end
    end
    writetable(Tcopy, filePath);
end

function manifest = build_step22_manifest(inputFile, primaryQ, grid, sheets)
    names = [
        "schema_version";
        "created_utc";
        "input_file";
        "input_sha256";
        "primary_windows";
        "aggregate_benchmark_window";
        "primary_rotation_quantile";
        "rotation_grid";
        "pca_maturities";
        "pca_centered";
        "pca_scaling";
        "pc1_sign_anchor";
        "shock_native_unit";
        "joint_dates_excluded";
        "source_sheets";
        "jk_reference_repository";
        "jk_reference_commit";
        "timezone_source_commit";
        "clone_base_commit";
        "code_commit";
        "script_sha256";
        "builder_sha256";
        "rotation_sha256"];

    scriptFile = which('Shock_component_construction');
    if strlength(string(scriptFile)) == 0 || exist(scriptFile, 'file') ~= 2
        error('STEP22_SCRIPT_PATH: unable to resolve Shock_component_construction.m.');
    end
    here = fileparts(scriptFile);
    values = [
        "step22_v1";
        string(datetime('now', 'TimeZone', 'UTC'), 'yyyy-MM-dd''T''HH:mm:ssXXX');
        string(inputFile);
        sha256_file(inputFile);
        "PR|PC";
        "ME";
        string(primaryQ);
        strjoin(string(grid), ",");
        "OIS_1M,OIS_3M,OIS_6M,OIS_1Y";
        "false";
        "divide each maturity by full-sample standard deviation";
        "positive loading on OIS_1Y";
        "percentage points; additional columns divide by 0.10 for 10bp units";
        "2001-09-13,2001-09-17,2008-10-08";
        strjoin(sheets, "|");
        "https://github.com/marekjarocinski/jkshocks_update_ecb_202310";
        "07a8015a11cd2fce0f425794db210d5f9e2e463f";
        "7c6ab69adae1439a6463f8e36480edfc20ae5f14";
        "3d46be255c74c822df31a420cd3341a8a154777b";
        current_git_commit(here);
        sha256_file(scriptFile);
        sha256_file(fullfile(here, 'Build_JK_shock_components.m'));
        sha256_file(fullfile(here, 'JK_median_rotation.m'))];

    manifest = table(names, values, 'VariableNames', {'name', 'value'});
end

function commit = current_git_commit(codePath)
    [status, result] = system(sprintf('git -C "%s" rev-parse HEAD 2>/dev/null', codePath));
    if status == 0
        commit = strtrim(string(result));
    else
        commit = "unavailable";
    end
end

function hash = sha256_file(filePath)
    fid = fopen(filePath, 'r');
    if fid < 0
        error('STEP22_HASH_READ: unable to open %s.', filePath);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid, Inf, '*uint8');
    digest = java.security.MessageDigest.getInstance('SHA-256');
    digest.update(bytes);
    raw = typecast(digest.digest(), 'uint8');
    hash = lower(string(reshape(dec2hex(raw, 2).', 1, [])));
end
