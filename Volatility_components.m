%% STEP 12: VOLATILITY COMPONENT MODELS.
%
% In this code PR-window realized variance is decomposed into two simple
% panel-level components and estimates state-dependent models on each
% component.
%
% The decomposition separates a directional component from a residual
% dispersion component, where the first is defined as the squared
% net PR log return divided by the number of observed PR bars, and the latter
% is defined as total PR realized variance minus the directional
% component.
%
% The script estimates state-dependent regressions for the inverse hyperbolic
% sine transformations of the directional and dispersion components. The
% specifications interact the target surprise with the hiking regime,
% pre-announcement realized volatility and monetary-policy memory. When
% available, a downside pre-announcement volatility channel is also included.
%
% Standard errors are clustered at the event-date level. The script also
% reports post-estimation marginal effects for the relevant interaction
% channels.
%
% Input file is Output/analysis/pr_state_dependent_panel.csv. Output files are
% Output/analysis/pr_vol_component_panel.csv, Output/analysis/pr_vol_component_model_coefficients.csv,
% Output/analysis/pr_vol_component_model_summary.csv and
% Output/analysis/pr_vol_component_marginal_effects.csv.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
panelFile = fullfile(analysisDir, 'pr_state_dependent_panel.csv');

T = readtable(panelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

T.event_date = parse_date_flex(T.event_date);
T.root_code = string(T.root_code);

numVars = ["PR_rv", "PR_net_log_return", "PR_n_obs_bars", "PR_abs_jump", "asinh_PR_rv", "asinh_PR_rsv_neg", "shock_target_10bp", "regime_hike", "state_pre_rv_z", "state_pre_rsvneg_z", "ma3_target_10bp_z", "root_gg"];

for v = numVars
    if ismember(v, string(T.Properties.VariableNames)) && ~isnumeric(T.(v))
        T.(v) = str2double(T.(v));
    end
end

T.root_gg = double(T.root_code == "gg");
T.target_x_hike = T.shock_target_10bp .* T.regime_hike;
T.target_x_preRV = T.shock_target_10bp .* T.state_pre_rv_z;
T.target_x_memory = T.shock_target_10bp .* T.ma3_target_10bp_z;

if ismember("state_pre_rsvneg_z", string(T.Properties.VariableNames))
    T.target_x_preRSVneg = T.shock_target_10bp .* T.state_pre_rsvneg_z;
end

M = T.PR_n_obs_bars;
rv = T.PR_rv;
net = T.PR_net_log_return;

T.directional_var = (net .^ 2) ./ max(M, 1);
T.directional_var(M <= 0 | isnan(M)) = NaN;

T.dispersion_var = rv - T.directional_var;
tinyNeg = T.dispersion_var > -1e-12 & T.dispersion_var < 0;
T.dispersion_var(tinyNeg) = 0;

T.directional_share = T.directional_var ./ rv;
T.dispersion_share = T.dispersion_var ./ rv;
T.directional_share(~isfinite(T.directional_share)) = NaN;
T.dispersion_share(~isfinite(T.dispersion_share)) = NaN;

T.asinh_directional_var = asinh(T.directional_var);
T.asinh_dispersion_var = asinh(T.dispersion_var);

allMask = true(height(T), 1);
clVar = "event_date";

specs = {};
specs{end+1} = mk("VC01_dir_regime", "asinh_directional_var", ["shock_target_10bp", "regime_hike", "target_x_hike", "root_gg"], allMask, clVar);
specs{end+1} = mk("VC02_dir_preuncertainty", "asinh_directional_var", ["shock_target_10bp", "state_pre_rv_z", "target_x_preRV", "root_gg"], allMask, clVar);
specs{end+1} = mk("VC03_disp_regime", "asinh_dispersion_var", ["shock_target_10bp", "regime_hike", "target_x_hike", "root_gg"], allMask, clVar);
specs{end+1} = mk("VC04_disp_preuncertainty", "asinh_dispersion_var", ["shock_target_10bp", "state_pre_rv_z", "target_x_preRV", "root_gg"], allMask, clVar);
specs{end+1} = mk("VC05_disp_memory", "asinh_dispersion_var", ["shock_target_10bp", "ma3_target_10bp_z", "target_x_memory", "root_gg"], allMask, clVar);

if ismember("target_x_preRSVneg", string(T.Properties.VariableNames))
    specs{end+1} = mk("VC06_downside_preuncertainty", "asinh_PR_rsv_neg", ["shock_target_10bp", "state_pre_rsvneg_z", "target_x_preRSVneg", "root_gg"], allMask, clVar);
end

nSpec = numel(specs);

coefCell = cell(nSpec, 1);
modelCell = cell(nSpec, 1);
postCell = cell(nSpec, 1);

for i = 1:nSpec
    s = specs{i};
    fprintf('[%d/%d] %s\n', i, nSpec, s.name);
    [coefCell{i}, modelCell{i}, fit] = cluster_ols(T, s);
    postCell{i} = compute_marginal_effects(fit);
end

coefResults = sortrows(vertcat(coefCell{:}), {'model_name', 'term'});
modelResults = sortrows(vertcat(modelCell{:}), 'model_name');
postResults = sortrows(vertcat(postCell{:}), {'model_name', 'effect_name'});

panelOut = fullfile(analysisDir, 'pr_vol_component_panel.csv');
coefOut = fullfile(analysisDir, 'pr_vol_component_model_coefficients.csv');
modelOut = fullfile(analysisDir, 'pr_vol_component_model_summary.csv');
postOut = fullfile(analysisDir, 'pr_vol_component_marginal_effects.csv');

writetable(format_long_panel_for_write(T), panelOut);
writetable(coefResults, coefOut);
writetable(modelResults, modelOut);
writetable(postResults, postOut);

fprintf('\n================ VOLATILITY COMPONENT MODELS SUMMARY ================\n');
fprintf('Panel output      : %s\n', panelOut);
fprintf('Coefficients      : %s\n', coefOut);
fprintf('Model summary     : %s\n', modelOut);
fprintf('Marginal effects  : %s\n', postOut);
fprintf('=====================================================================\n');

function s = mk(name, depvar, rhs, mask, clusterVar)

    s = struct();
    s.name = string(name);
    s.depvar = string(depvar);
    s.rhs = string(rhs);
    s.mask = mask;
    s.clusterVar = string(clusterVar);
end

function [coefTbl, modelTbl, fit] = cluster_ols(T, s)

    y = T.(s.depvar);

    if isstring(y)
        y = str2double(y);
    end

    mask = s.mask & ~isnan(y);

    for v = s.rhs
        x = T.(v);

        if isstring(x)
            x = str2double(x);
        end

        mask = mask & ~isnan(x);
    end

    cl = T.(s.clusterVar);

    if isdatetime(cl)
        mask = mask & ~isnat(cl);
    else
        cl = string(cl);
        mask = mask & ~ismissing(cl);
    end

    y = y(mask);
    n = numel(y);

    X = ones(n, 1);
    termNames = "Intercept";

    for v = s.rhs
        x = T.(v);

        if isstring(x)
            x = str2double(x);
        end

        X = [X, x(mask)];
        termNames(end + 1, 1) = v;
    end

    cl = T.(s.clusterVar);

    if isdatetime(cl)
        clStr = string(cl(mask), 'yyyy-MM-dd');
    else
        clStr = string(cl(mask));
    end

    [beta, V, se, tstat, pval, G, r2, adj_r2, sse] = cluster_vcov(y, X, clStr);

    k = size(X, 2);

    coefTbl = table();
    coefTbl.model_name = repmat(s.name, k, 1);
    coefTbl.depvar = repmat(s.depvar, k, 1);
    coefTbl.term = termNames;
    coefTbl.beta = beta;
    coefTbl.se_cluster = se;
    coefTbl.t_stat = tstat;
    coefTbl.p_value = pval;
    coefTbl.n_obs = repmat(n, k, 1);
    coefTbl.n_clusters = repmat(G, k, 1);
    coefTbl.r2 = repmat(r2, k, 1);
    coefTbl.adj_r2 = repmat(adj_r2, k, 1);

    modelTbl = table();
    modelTbl.model_name = s.name;
    modelTbl.depvar = s.depvar;
    modelTbl.rhs = strjoin(s.rhs, " + ");
    modelTbl.n_obs = n;
    modelTbl.n_clusters = G;
    modelTbl.n_params = k;
    modelTbl.r2 = r2;
    modelTbl.adj_r2 = adj_r2;
    modelTbl.mean_depvar = mean(y, 'omitnan');
    modelTbl.sd_depvar = std(y, 'omitnan');

    fit = struct();
    fit.model_name = s.name;
    fit.depvar = s.depvar;
    fit.term_names = termNames;
    fit.beta = beta;
    fit.V = V;
    fit.n_clusters = G;
    fit.k = k;
    fit.sse = sse;
end

function [beta, V, se, tstat, pval, G, r2, adj_r2, sse] = cluster_vcov(y, X, clStr)

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
        tstat = beta ./ se;
        pval = 2 * tcdf(-abs(tstat), G - 1);
    else
        V = nan(k, k);
        se = nan(k, 1);
        tstat = nan(k, 1);
        pval = nan(k, 1);
    end
end

function outTbl = compute_marginal_effects(fit)

    tn = string(fit.term_names);
    rows = cell(0, 11);

    iShock = find(tn == "shock_target_10bp", 1);

    if isempty(iShock)
        outTbl = empty_effect_table();
        return;
    end

    L0 = zeros(numel(fit.beta), 1);
    L0(iShock) = 1;

    rows = add_effect(rows, fit, "slope_baseline", NaN, L0, "baseline");

    iH = find(tn == "target_x_hike", 1);

    if ~isempty(iH)
        L1 = L0;
        L1(iH) = 1;
        rows = add_effect(rows, fit, "slope_H0", 0, L0, "regime_hike=0");
        rows = add_effect(rows, fit, "slope_H1", 1, L1, "regime_hike=1");
        rows = add_effect(rows, fit, "delta_regime", 1, unit_vector(numel(fit.beta), iH), "interaction");
    end

    iU = find(tn == "target_x_preRV", 1);

    if ~isempty(iU)
        for z = [-1 0 1]
            L = L0;
            L(iU) = z;
            rows = add_effect(rows, fit, "slope_preRV_z_" + string(z), z, L, "preRV");
        end

        rows = add_effect(rows, fit, "delta_preRV_per1sd", 1, unit_vector(numel(fit.beta), iU), "interaction");
    end

    iM = find(tn == "target_x_memory", 1);

    if ~isempty(iM)
        for z = [-1 0 1]
            L = L0;
            L(iM) = z;
            rows = add_effect(rows, fit, "slope_memory_z_" + string(z), z, L, "memory");
        end

        rows = add_effect(rows, fit, "delta_memory_per1sd", 1, unit_vector(numel(fit.beta), iM), "interaction");
    end

    iD = find(tn == "target_x_preRSVneg", 1);

    if ~isempty(iD)
        for z = [-1 0 1]
            L = L0;
            L(iD) = z;
            rows = add_effect(rows, fit, "slope_preRSVneg_z_" + string(z), z, L, "preRSVneg");
        end

        rows = add_effect(rows, fit, "delta_preRSVneg_per1sd", 1, unit_vector(numel(fit.beta), iD), "interaction");
    end

    outTbl = cell2table(rows, 'VariableNames', {'model_name', 'depvar', 'effect_name', 'state_value', 'estimate', 'se', 't_stat', 'p_value', 'ci95_lo', 'ci95_hi', 'note'});
end

function rows = add_effect(rows, fit, effectName, stateValue, L, note)

    est = L' * fit.beta;

    if all(isnan(fit.V(:)))
        se = NaN;
        t = NaN;
        p = NaN;
        lo = NaN;
        hi = NaN;
    else
        vv = L' * fit.V * L;

        if vv < 0
            vv = NaN;
        end

        se = sqrt(vv);
        t = est / se;
        df = max(fit.n_clusters - 1, 1);
        p = 2 * tcdf(-abs(t), df);
        crit = tinv(0.975, df);
        lo = est - crit * se;
        hi = est + crit * se;
    end

    rows(end + 1, :) = {fit.model_name, fit.depvar, string(effectName), stateValue, est, se, t, p, lo, hi, string(note)};
end

function e = unit_vector(n, idx)

    e = zeros(n, 1);
    e(idx) = 1;
end

function T = empty_effect_table()

    T = cell2table(cell(0, 11), 'VariableNames', {'model_name', 'depvar', 'effect_name', 'state_value', 'estimate', 'se', 't_stat', 'p_value', 'ci95_lo', 'ci95_hi', 'note'});
end

function T = format_long_panel_for_write(T)

    if ismember("event_date", string(T.Properties.VariableNames))
        T.event_date = string(T.event_date, 'yyyy-MM-dd');
    end

    if ismember("trade_date", string(T.Properties.VariableNames))
        T.trade_date = string(T.trade_date, 'yyyy-MM-dd');
    end
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
