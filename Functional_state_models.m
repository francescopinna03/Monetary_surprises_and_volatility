%% STEP 11: FUNCTIONAL STATE MODELS.
%
% Here is extended the state-dependent analysis by allowing the marginal
% effect of the monetary-policy surprise to vary flexibly with the
% pre-announcement state. It is used the long state-dependent PR panel constructed
% in the previous steps.
%
% The script estimates two classes of functional-coefficient models. The first
% class is based on threshold specifications, where the slope of the target
% surprise changes when the state variable crosses an estimated threshold. The
% threshold is selected by searching over event-level quantiles and choosing
% the value that minimizes the residual sum of squares.
%
% The second class is based on spline varying-slope specifications. In these
% models, the effect of the target surprise is allowed to change smoothly with
% the state variable through a truncated cubic spline basis. The script then
% evaluates the implied shock slope over a fixed grid of standardized state
% values.
%
% The state variables considered are the standardized pre-announcement
% realized-volatility state and, for downside volatility outcomes, the
% standardized pre-announcement negative-semivariance state. The dependent
% variables are the absolute PR jump, the inverse hyperbolic sine
% transformation of PR realized variance and the inverse hyperbolic sine
% transformation of PR negative realized semivariance.
%
% The purpose of this step is to test whether the state dependence found in
% the linear interaction models is better described by regime-like thresholds
% or by a smoother functional response. Standard errors are clustered at the
% event-date level.
%
% Input file is Output/analysis/pr_state_dependent_panel.csv. Output files are
% Output/analysis/functional_threshold_coefficients.csv, Output/analysis/functional_threshold_summary.csv,
% Output/analysis/functional_threshold_slopes.csv, Output/analysis/functional_spline_coefficients.csv
% and Output/analysis/functional_spline_slopes.csv.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
panelFile = fullfile(analysisDir, 'pr_state_dependent_panel.csv');

cfg = struct();
cfg.threshold_quantiles = 0.20:0.05:0.80;
cfg.grid_values = (-2:0.5:2)';
cfg.spline_knots = [0.25 0.50 0.75];
cfg.min_regime_share = 0.15;

models = cell(3, 1);
models{1} = struct('name', "FS01_absjump_preRV", 'depvar', "PR_abs_jump", 'qvar', "state_pre_rv_z");
models{2} = struct('name', "FS02_asinhRV_preRV", 'depvar', "asinh_PR_rv", 'qvar', "state_pre_rv_z");
models{3} = struct('name', "FS03_asinhRSVneg_preRSV", 'depvar', "asinh_PR_rsv_neg", 'qvar', "state_pre_rsvneg_z");

T = readtable(panelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

T.event_date = parse_date_flex(T.event_date);
T.root_code = string(T.root_code);

needed = ["shock_target_10bp", "PR_abs_jump", "asinh_PR_rv", "asinh_PR_rsv_neg", "state_pre_rv_z", "state_pre_rsvneg_z", "root_gg"];

for v = needed
    if ismember(v, string(T.Properties.VariableNames)) && ~isnumeric(T.(v))
        T.(v) = str2double(T.(v));
    end
end

if ~ismember("root_gg", string(T.Properties.VariableNames))
    T.root_gg = double(T.root_code == "gg");
end

thCoefCell = cell(numel(models), 1);
thSumCell = cell(numel(models), 1);
thSlopeCell = cell(numel(models), 1);
spCoefCell = cell(numel(models), 1);
spSlopeCell = cell(numel(models), 1);

for i = 1:numel(models)

    m = models{i};

    fprintf('[%d/%d] %s\n', i, numel(models), m.name);

    [thCoefCell{i}, thSumCell{i}, thSlopeCell{i}] = fit_threshold_model(T, m.depvar, m.qvar, m.name, cfg);
    [spCoefCell{i}, spSlopeCell{i}] = fit_spline_model(T, m.depvar, m.qvar, m.name, cfg);
end

thresholdCoefs = vertcat(thCoefCell{:});
thresholdSumm = vertcat(thSumCell{:});
thresholdSlope = vertcat(thSlopeCell{:});
splineCoefs = vertcat(spCoefCell{:});
splineSlope = vertcat(spSlopeCell{:});

writetable(thresholdCoefs, fullfile(analysisDir, 'functional_threshold_coefficients.csv'));
writetable(thresholdSumm, fullfile(analysisDir, 'functional_threshold_summary.csv'));
writetable(thresholdSlope, fullfile(analysisDir, 'functional_threshold_slopes.csv'));
writetable(splineCoefs, fullfile(analysisDir, 'functional_spline_coefficients.csv'));
writetable(splineSlope, fullfile(analysisDir, 'functional_spline_slopes.csv'));

fprintf('\n================ FUNCTIONAL STATE MODELS SUMMARY ================\n');
fprintf('Threshold coefficients : %s\n', fullfile(analysisDir, 'functional_threshold_coefficients.csv'));
fprintf('Threshold summary      : %s\n', fullfile(analysisDir, 'functional_threshold_summary.csv'));
fprintf('Threshold slopes       : %s\n', fullfile(analysisDir, 'functional_threshold_slopes.csv'));
fprintf('Spline coefficients    : %s\n', fullfile(analysisDir, 'functional_spline_coefficients.csv'));
fprintf('Spline slopes          : %s\n', fullfile(analysisDir, 'functional_spline_slopes.csv'));
fprintf('=================================================================\n');

function [coefTbl, sumTbl, slopeTbl] = fit_threshold_model(T, depvar, qvar, modelName, cfg)

    req = [depvar, "shock_target_10bp", qvar, "root_gg", "event_date"];
    mask = true(height(T), 1);

    for v = req
        x = T.(v);

        if isstring(x)
            x = str2double(x);
        end

        if isdatetime(x)
            mask = mask & ~isnat(x);
        else
            mask = mask & ~isnan(x);
        end
    end

    S = T(mask, :);

    y = S.(depvar);
    shock = S.shock_target_10bp;
    q = S.(qvar);
    root_gg = S.root_gg;
    cl = S.event_date;

    Eq = groupsummary(table(cl, q), 'cl', 'mean', 'q');
    qEvent = Eq.mean_q;

    candidates = quantile(qEvent, cfg.threshold_quantiles);
    candidates = unique(candidates(isfinite(candidates)));

    minRegimeSize = max(10, ceil(cfg.min_regime_share * numel(q)));

    bestSSE = inf;
    bestC = NaN;
    bestFit = struct();
    bestLeft = NaN;
    bestRight = NaN;

    for j = 1:numel(candidates)

        c = candidates(j);
        D = double(q > c);

        nLeft = sum(D == 0);
        nRight = sum(D == 1);

        if nLeft < minRegimeSize || nRight < minRegimeSize
            continue;
        end

        X = [ones(numel(y), 1), shock, q, D, shock .* D, root_gg];
        termNames = ["Intercept", "shock_target_10bp", qvar, "threshold_hi", "shock_x_threshold_hi", "root_gg"];

        fit = cluster_ols_matrix(y, X, termNames, cl, modelName + "_threshold", depvar);

        if fit.sse < bestSSE
            bestSSE = fit.sse;
            bestC = c;
            bestFit = fit;
            bestLeft = nLeft;
            bestRight = nRight;
        end
    end

    coefTbl = bestFit.coefTbl;
    coefTbl.state_var = repmat(string(qvar), height(coefTbl), 1);

    sumTbl = table();
    sumTbl.model_name = string(modelName);
    sumTbl.depvar = string(depvar);
    sumTbl.state_var = string(qvar);
    sumTbl.threshold_c = bestC;
    sumTbl.n_left = bestLeft;
    sumTbl.n_right = bestRight;
    sumTbl.n_obs = bestFit.n_obs;
    sumTbl.n_clusters = bestFit.n_clusters;
    sumTbl.r2 = bestFit.r2;
    sumTbl.adj_r2 = bestFit.adj_r2;

    iShock = find(bestFit.termNames == "shock_target_10bp", 1);
    iInt = find(bestFit.termNames == "shock_x_threshold_hi", 1);

    rows = cell(0, 11);

    L = zeros(bestFit.k, 1);
    L(iShock) = 1;
    rows = add_combo(rows, bestFit, "slope_low", NaN, L, "q_le_c");

    L = zeros(bestFit.k, 1);
    L(iShock) = 1;
    L(iInt) = 1;
    rows = add_combo(rows, bestFit, "slope_high", NaN, L, "q_gt_c");

    L = zeros(bestFit.k, 1);
    L(iInt) = 1;
    rows = add_combo(rows, bestFit, "delta_high_minus_low", NaN, L, "threshold_delta");

    slopeTbl = cell2table(rows, 'VariableNames', {'model_name', 'depvar', 'effect_name', 'state_value', 'estimate', 'se', 't_stat', 'p_value', 'ci95_lo', 'ci95_hi', 'note'});
    slopeTbl.threshold_c = repmat(bestC, height(slopeTbl), 1);
    slopeTbl.state_var = repmat(string(qvar), height(slopeTbl), 1);
end

function [coefTbl, slopeTbl] = fit_spline_model(T, depvar, qvar, modelName, cfg)

    req = [depvar, "shock_target_10bp", qvar, "root_gg", "event_date"];
    mask = true(height(T), 1);

    for v = req
        x = T.(v);

        if isstring(x)
            x = str2double(x);
        end

        if isdatetime(x)
            mask = mask & ~isnat(x);
        else
            mask = mask & ~isnan(x);
        end
    end

    S = T(mask, :);

    y = S.(depvar);
    shock = S.shock_target_10bp;
    q = S.(qvar);
    root_gg = S.root_gg;
    cl = S.event_date;

    uq = unique(q(isfinite(q)));
    knots = quantile(uq, cfg.spline_knots);
    knots = unique(knots(:))';

    B = truncated_cubic_basis(q, knots);

    X = [ones(numel(y), 1), q, shock, shock .* q, root_gg];
    termNames = ["Intercept", qvar, "shock_target_10bp", "shock_x_q", "root_gg"];

    for j = 1:size(B, 2)
        X = [X, shock .* B(:, j)];
        termNames(end + 1) = "shock_x_spline_" + string(j);
    end

    fit = cluster_ols_matrix(y, X, termNames, cl, modelName + "_spline", depvar);

    coefTbl = fit.coefTbl;
    coefTbl.state_var = repmat(string(qvar), height(coefTbl), 1);

    rows = cell(0, 11);

    iShock = find(fit.termNames == "shock_target_10bp", 1);
    iShockQ = find(fit.termNames == "shock_x_q", 1);
    idxSpline = find(contains(fit.termNames, "shock_x_spline_"));

    for q0 = cfg.grid_values(:)'

        L = zeros(fit.k, 1);
        L(iShock) = 1;
        L(iShockQ) = q0;

        bq = truncated_cubic_basis(q0, knots);

        for j = 1:numel(idxSpline)
            L(idxSpline(j)) = bq(j);
        end

        rows = add_combo(rows, fit, "slope_q_" + string(q0), q0, L, "spline_grid");
    end

    slopeTbl = cell2table(rows, 'VariableNames', {'model_name', 'depvar', 'effect_name', 'state_value', 'estimate', 'se', 't_stat', 'p_value', 'ci95_lo', 'ci95_hi', 'note'});
    slopeTbl.state_var = repmat(string(qvar), height(slopeTbl), 1);
end

function B = truncated_cubic_basis(q, knots)

    q = q(:);
    B = zeros(numel(q), numel(knots));

    for j = 1:numel(knots)
        B(:, j) = max(q - knots(j), 0) .^ 3;
    end
end

function fit = cluster_ols_matrix(y, X, termNames, cl, modelName, depvar)

    n = numel(y);
    k = size(X, 2);

    beta = X \ y;
    u = y - X * beta;

    ybar = mean(y, 'omitnan');
    sse = u' * u;
    tss = sum((y - ybar) .^ 2);

    if tss > 0
        r2 = 1 - sse / tss;
    else
        r2 = NaN;
    end

    adj_r2 = NaN;

    if ~isnan(r2)
        adj_r2 = 1 - (1 - r2) * (n - 1) / max(n - k, 1);
    end

    clStr = string(cl, 'yyyy-MM-dd');
    clusters = findgroups(clStr);
    G = max(clusters);

    XtXi = pinv(X' * X);
    meat = zeros(k, k);

    for g = 1:G
        idx = clusters == g;
        xu = X(idx, :)' * u(idx);
        meat = meat + xu * xu';
    end

    if G > 1 && n > k
        dfc = (G / (G - 1)) * ((n - 1) / (n - k));
        V = dfc * XtXi * meat * XtXi;
        se = sqrt(diag(V));
        t = beta ./ se;
        p = 2 * tcdf(-abs(t), G - 1);
    else
        V = nan(k, k);
        se = nan(k, 1);
        t = nan(k, 1);
        p = nan(k, 1);
    end

    coefTbl = table();
    coefTbl.model_name = repmat(string(modelName), k, 1);
    coefTbl.depvar = repmat(string(depvar), k, 1);
    coefTbl.term = termNames(:);
    coefTbl.beta = beta;
    coefTbl.se_cluster = se;
    coefTbl.t_stat = t;
    coefTbl.p_value = p;
    coefTbl.n_obs = repmat(n, k, 1);
    coefTbl.n_clusters = repmat(G, k, 1);
    coefTbl.r2 = repmat(r2, k, 1);
    coefTbl.adj_r2 = repmat(adj_r2, k, 1);

    fit = struct();
    fit.beta = beta;
    fit.V = V;
    fit.termNames = termNames(:);
    fit.coefTbl = coefTbl;
    fit.n_clusters = G;
    fit.n_obs = n;
    fit.k = k;
    fit.sse = sse;
    fit.r2 = r2;
    fit.adj_r2 = adj_r2;
    fit.model_name = string(modelName);
    fit.depvar = string(depvar);
end

function rows = add_combo(rows, fit, effectName, stateValue, L, noteTxt)

    est = L' * fit.beta;

    if all(isnan(fit.V(:)))
        se = NaN;
        t = NaN;
        p = NaN;
        lo = NaN;
        hi = NaN;
    else
        se = sqrt(L' * fit.V * L);
        t = est / se;
        df = max(fit.n_clusters - 1, 1);
        p = 2 * tcdf(-abs(t), df);
        crit = tinv(0.975, df);
        lo = est - crit * se;
        hi = est + crit * se;
    end

    rows(end + 1, :) = {fit.model_name, fit.depvar, string(effectName), stateValue, est, se, t, p, lo, hi, string(noteTxt)};
end

function dt = parse_date_flex(x)

    if isdatetime(x)
        dt = dateshift(x, 'start', 'day');
        return;
    end

    if isnumeric(x)
        dt = dateshift(datetime(x, 'ConvertFrom', 'excel'), 'start', 'day');
        return;
    end

    if iscell(x)
        x = string(x);
    end

    if ischar(x)
        x = string(x);
    end

    fmts = {'yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'dd-MMM-yyyy', 'yyyy-MM-dd HH:mm', 'dd/MM/yyyy HH:mm', 'MM/dd/yyyy HH:mm'};
    best = NaT(size(x));
    bestBad = inf;

    for i = 1:numel(fmts)
        try
            dTry = datetime(x, 'InputFormat', fmts{i});
            nBad = sum(isnat(dTry));

            if nBad < bestBad
                bestBad = nBad;
                best = dTry;
            end
        catch
        end
    end

    dt = dateshift(best, 'start', 'day');
end
