%% STEP 11: SHOCK PURIFICATION MODELS.
%
% The script purifies the monetary-policy target surprise with respect to a
% small set of pre-announcement event-level states. Here are used the event-state
% panel and the long state-dependent PR panel produced in the previous steps.
%
% The first stage regresses the target surprise, expressed in 10 basis point
% units, on observable pre-announcement states. In the current specification,
% the state controls are the hiking-regime dummy and the standardized
% pre-announcement realized-volatility state. The fitted residual is interpreted
% as the component of the target surprise that is orthogonal to these states.
%
% The script computes both in-sample and leave-one-out first-stage residuals.
% The leave-one-out residual is then merged back into the PR long panel and
% used as the purified monetary-policy surprise. This avoids using the same
% observation both to construct and to evaluate the residualized shock.
%
% The second stage re-estimates the main state-dependent PR models using the
% purified target surprise and its interactions with the hiking regime,
% pre-announcement realized volatility, monetary-policy memory and, when
% available, downside pre-announcement volatility.
%
% The purpose of this step is to check whether the state-dependent results are
% driven by the raw surprise itself or by the component of the surprise that is
% predictable from pre-announcement conditions.
%
% Input files are Output/analysis/event_state_panel.csv and
% Output/analysis/pr_state_dependent_panel.csv, output files are
% Output/analysis/shock_purification_summary.csv, Output/analysis/shock_purification_first_stage_coefficients.csv,
% Output/analysis/shock_purification_event_residuals.csv, Output/analysis/pr_state_purified_panel.csv,
% Output/analysis/pr_state_purified_model_coefficients.csv, Output/analysis/pr_state_purified_model_summary.csv
% and Output/analysis/pr_state_purified_marginal_effects.csv.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
eventFile = fullfile(analysisDir, 'event_state_panel.csv');
longFile = fullfile(analysisDir, 'pr_state_dependent_panel.csv');

E = readtable(eventFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');
T = readtable(longFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

E.event_date = parse_date_flex(E.event_date);
T.event_date = parse_date_flex(T.event_date);
T.root_code = string(T.root_code);

numVarsE = ["shock_target_10bp", "regime_hike", "state_pre_rv_z", "state_pre_rsvneg_z"];

for v = numVarsE
    if ismember(v, string(E.Properties.VariableNames)) && ~isnumeric(E.(v))
        E.(v) = str2double(E.(v));
    end
end

numVarsT = ["PR_abs_jump", "asinh_PR_rv", "asinh_PR_rsv_neg", "shock_target_10bp", "regime_hike", "state_pre_rv_z", "state_pre_rsvneg_z", "ma3_target_10bp_z", "root_gg"];

for v = numVarsT
    if ismember(v, string(T.Properties.VariableNames)) && ~isnumeric(T.(v))
        T.(v) = str2double(T.(v));
    end
end

T.root_gg = double(T.root_code == "gg");

stateVars = ["regime_hike", "state_pre_rv_z"];

mask = ~isnan(E.shock_target_10bp);

for v = stateVars
    mask = mask & ~isnan(E.(v));
end

E1 = E(mask, :);

X = ones(height(E1), 1);
termNames = "Intercept";

for v = stateVars
    X = [X, E1.(v)];
    termNames(end + 1, 1) = v;
end

y = E1.shock_target_10bp;

b = X \ y;
yhat_in = X * b;
resid_in = y - yhat_in;
r2_in = compute_r2(y, resid_in);

n = numel(y);
yhat_loo = nan(n, 1);

for i = 1:n
    idx = true(n, 1);
    idx(i) = false;
    bi = X(idx, :) \ y(idx);
    yhat_loo(i) = X(i, :) * bi;
end

resid_loo = y - yhat_loo;
r2_loo = 1 - sum((y - yhat_loo) .^ 2, 'omitnan') / sum((y - mean(y, 'omitnan')) .^ 2, 'omitnan');

purifTbl = table();
purifTbl.event_date = E1.event_date;
purifTbl.shock_target_10bp = y;
purifTbl.shock_pred_in = yhat_in;
purifTbl.shock_resid_in = resid_in;
purifTbl.shock_pred_loo = yhat_loo;
purifTbl.shock_resid_loo = resid_loo;

summaryTbl = table();
summaryTbl.n_events = height(E1);
summaryTbl.r2_in_sample = r2_in;
summaryTbl.r2_leave_one_out = r2_loo;
summaryTbl.mean_abs_resid_loo = mean(abs(resid_loo), 'omitnan');
summaryTbl.sd_resid_loo = std(resid_loo, 0, 'omitnan');
summaryTbl.first_stage_rhs = strjoin(stateVars, " + ");

coefFirstStage = table();
coefFirstStage.term = termNames;
coefFirstStage.beta = b;

T = outerjoin(T, purifTbl(:, {'event_date', 'shock_resid_loo'}), 'Keys', 'event_date', 'MergeKeys', true, 'Type', 'left');

T.shock_purified_10bp = T.shock_resid_loo;
T.target_purified_x_hike = T.shock_purified_10bp .* T.regime_hike;
T.target_purified_x_preRV = T.shock_purified_10bp .* T.state_pre_rv_z;
T.target_purified_x_memory = T.shock_purified_10bp .* T.ma3_target_10bp_z;

if ismember("state_pre_rsvneg_z", string(T.Properties.VariableNames))
    T.target_purified_x_preRSVneg = T.shock_purified_10bp .* T.state_pre_rsvneg_z;
end

allMask = true(height(T), 1);
clVar = "event_date";

specs = {};

specs{end+1} = mk("PUR01_absjump_regime", "PR_abs_jump", ["shock_purified_10bp", "regime_hike", "target_purified_x_hike", "root_gg"], allMask, clVar);
specs{end+1} = mk("PUR02_absjump_preuncertainty", "PR_abs_jump", ["shock_purified_10bp", "state_pre_rv_z", "target_purified_x_preRV", "root_gg"], allMask, clVar);
specs{end+1} = mk("PUR03_absjump_memory", "PR_abs_jump", ["shock_purified_10bp", "ma3_target_10bp_z", "target_purified_x_memory", "root_gg"], allMask, clVar);
specs{end+1} = mk("PUR04_asinhRV_regime", "asinh_PR_rv", ["shock_purified_10bp", "regime_hike", "target_purified_x_hike", "root_gg"], allMask, clVar);
specs{end+1} = mk("PUR05_asinhRV_preuncertainty", "asinh_PR_rv", ["shock_purified_10bp", "state_pre_rv_z", "target_purified_x_preRV", "root_gg"], allMask, clVar);
specs{end+1} = mk("PUR07_asinhRSVneg_regime", "asinh_PR_rsv_neg", ["shock_purified_10bp", "regime_hike", "target_purified_x_hike", "root_gg"], allMask, clVar);

if ismember("state_pre_rsvneg_z", string(T.Properties.VariableNames))
    specs{end+1} = mk("PUR06_asinhRSVneg_preuncertainty", "asinh_PR_rsv_neg", ["shock_purified_10bp", "state_pre_rsvneg_z", "target_purified_x_preRSVneg", "root_gg"], allMask, clVar);
end

nSpec = numel(specs);
coefCell = cell(nSpec, 1);
modelCell = cell(nSpec, 1);
postCell = cell(nSpec, 1);

for i = 1:nSpec
    s = specs{i};
    fprintf('[%2d/%2d] %s\n', i, nSpec, s.name);
    [coefCell{i}, modelCell{i}, fit] = cluster_ols(T, s);
    postCell{i} = compute_marginal_effects_purified(fit);
end

coefResults = sortrows(vertcat(coefCell{:}), {'model_name', 'term'});
modelResults = sortrows(vertcat(modelCell{:}), 'model_name');
postResults = sortrows(vertcat(postCell{:}), {'model_name', 'effect_name'});

writetable(summaryTbl, fullfile(analysisDir, 'shock_purification_summary.csv'));
writetable(coefFirstStage, fullfile(analysisDir, 'shock_purification_first_stage_coefficients.csv'));
writetable(format_event_panel_for_write(purifTbl), fullfile(analysisDir, 'shock_purification_event_residuals.csv'));
writetable(format_long_panel_for_write(T), fullfile(analysisDir, 'pr_state_purified_panel.csv'));
writetable(coefResults, fullfile(analysisDir, 'pr_state_purified_model_coefficients.csv'));
writetable(modelResults, fullfile(analysisDir, 'pr_state_purified_model_summary.csv'));
writetable(postResults, fullfile(analysisDir, 'pr_state_purified_marginal_effects.csv'));

fprintf('\n================ SHOCK PURIFICATION SUMMARY ================\n');
fprintf('Events used       : %d\n', height(E1));
fprintf('First-stage R2    : %.4f\n', r2_in);
fprintf('LOO R2            : %.4f\n', r2_loo);
fprintf('Models estimated  : %d\n', height(modelResults));
fprintf('===========================================================\n');

function s = mk(name, depvar, rhs, mask, clusterVar)

    s = struct();
    s.name = string(name);
    s.depvar = string(depvar);
    s.rhs = string(rhs);
    s.mask = mask;
    s.clusterVar = string(clusterVar);
end

function r2 = compute_r2(y, u)

    ybar = mean(y, 'omitnan');
    sse = sum(u .^ 2, 'omitnan');
    tss = sum((y - ybar) .^ 2, 'omitnan');

    if tss > 0
        r2 = 1 - sse / tss;
    else
        r2 = NaN;
    end
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

    clusters = findgroups(clStr);
    G = max(clusters);
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

    XtXi = pinv(X' * X);
    meat = zeros(k, k);

    for g = 1:G
        idx = clusters == g;
        xu = X(idx, :)' * u(idx);
        meat = meat + xu * xu';
    end

    if G > 1 && n > k
        dfc = (G / (G - 1)) * ((n - 1) / (n - k));
        Vc = dfc * XtXi * meat * XtXi;
        se = sqrt(diag(Vc));
        tstat = beta ./ se;
        pval = 2 * tcdf(-abs(tstat), G - 1);
    else
        Vc = nan(k, k);
        se = nan(k, 1);
        tstat = nan(k, 1);
        pval = nan(k, 1);
    end

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
    fit.V = Vc;
    fit.n_clusters = G;
end

function outTbl = compute_marginal_effects_purified(fit)

    tn = string(fit.term_names);
    b = fit.beta;
    V = fit.V;
    rows = cell(0, 11);

    iShock = find(tn == "shock_purified_10bp", 1);

    if isempty(iShock)
        outTbl = empty_effect_table();
        return;
    end

    L0 = zeros(numel(b), 1);
    L0(iShock) = 1;

    rows = add_effect(rows, fit, "slope_baseline", L0, NaN, "baseline");

    iH = find(tn == "target_purified_x_hike", 1);

    if ~isempty(iH)
        L1 = L0;
        L1(iH) = 1;
        rows = add_effect(rows, fit, "slope_H0", L0, 0, "regime_hike=0");
        rows = add_effect(rows, fit, "slope_H1", L1, 1, "regime_hike=1");
        rows = add_effect(rows, fit, "delta_regime", unit_vector(numel(b), iH), 1, "interaction");
    end

    iU = find(tn == "target_purified_x_preRV", 1);

    if ~isempty(iU)
        for z = [-1 0 1]
            L = L0;
            L(iU) = z;
            rows = add_effect(rows, fit, "slope_preRV_z_" + string(z), L, z, "preRV");
        end

        rows = add_effect(rows, fit, "delta_preRV_per1sd", unit_vector(numel(b), iU), 1, "interaction");
    end

    iM = find(tn == "target_purified_x_memory", 1);

    if ~isempty(iM)
        for z = [-1 0 1]
            L = L0;
            L(iM) = z;
            rows = add_effect(rows, fit, "slope_memory_z_" + string(z), L, z, "memory");
        end

        rows = add_effect(rows, fit, "delta_memory_per1sd", unit_vector(numel(b), iM), 1, "interaction");
    end

    iD = find(tn == "target_purified_x_preRSVneg", 1);

    if ~isempty(iD)
        for z = [-1 0 1]
            L = L0;
            L(iD) = z;
            rows = add_effect(rows, fit, "slope_preRSVneg_z_" + string(z), L, z, "preRSVneg");
        end

        rows = add_effect(rows, fit, "delta_preRSVneg_per1sd", unit_vector(numel(b), iD), 1, "interaction");
    end

    outTbl = cell2table(rows, 'VariableNames', {'model_name', 'depvar', 'effect_name', 'state_value', 'estimate', 'se', 't_stat', 'p_value', 'ci95_lo', 'ci95_hi', 'note'});
end

function rows = add_effect(rows, fit, effectName, L, stateValue, note)

    b = fit.beta;
    V = fit.V;
    est = L' * b;

    if all(isnan(V(:)))
        se = NaN;
        t = NaN;
        p = NaN;
        ci_lo = NaN;
        ci_hi = NaN;
    else
        se = sqrt(L' * V * L);
        t = est / se;
        df = max(fit.n_clusters - 1, 1);
        p = 2 * tcdf(-abs(t), df);
        crit = tinv(0.975, df);
        ci_lo = est - crit * se;
        ci_hi = est + crit * se;
    end

    rows(end + 1, :) = {fit.model_name, fit.depvar, string(effectName), stateValue, est, se, t, p, ci_lo, ci_hi, string(note)};
end

function T = empty_effect_table()

    T = cell2table(cell(0, 11), 'VariableNames', {'model_name', 'depvar', 'effect_name', 'state_value', 'estimate', 'se', 't_stat', 'p_value', 'ci95_lo', 'ci95_hi', 'note'});
end

function e = unit_vector(n, idx)

    e = zeros(n, 1);
    e(idx) = 1;
end

function T = format_event_panel_for_write(T)

    T.event_date = string(T.event_date, 'yyyy-MM-dd');
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
