%% STEP 15: BNS VOLATILITY MODELS.
%
% Here is estimated a Barndorff-Nielsen-Shephard type volatility
% decomposition inside the press-release window, by using the bar-level PR
% panel built in the previous step and computes realized variance, bipower
% variation and the residual jump variation for each event and asset family.
%
% The decomposition is used to separate the continuous volatility component
% from the jump-like component of the PR-window price response,and the resulting
% measures are transformed with the inverse hyperbolic sine and then used as
% dependent variables in state-dependent regressions with event-clustered
% standard errors.
%
% The empirical specifications mirror the earlier state-dependent models.
% The monetary surprise is interacted with the hiking-regime indicator,
% pre-announcement realized-volatility state and monetary-policy memory. This
% allows the BNS components to be compared with the baseline realized
% volatility and semivariance results.
%
% Before estimation, the script writes a feasibility report. The BNS exercise
% is only run if enough event groups contain a sufficient number of PR-window
% bar returns, otherwise, the script stops after reporting why the
% decomposition is not considered reliable.
%
% Input files are Output/analysis/pr_state_dependent_panel.csv and
% Output/analysis/pr_bar_panel.csv, output files are
% Output/analysis/pr_bns_component_panel.csv,
% Output/analysis/pr_bns_model_coefficients.csv,
% Output/analysis/pr_bns_model_summary.csv,
% Output/analysis/pr_bns_marginal_effects.csv and
% Output/analysis/pr_bns_feasibility_report.csv.
clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
statePanelFile = fullfile(analysisDir, 'pr_state_dependent_panel.csv');
barFile = fullfile(analysisDir, 'pr_bar_panel.csv');

minBarsForBNS = 5;
minShareGroupsOk = 0.60;
minMedianBars = 6;

T = readtable(statePanelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

T.event_date = parse_date_flex(T.event_date);
T.root_code = string(T.root_code);

numVars = ["shock_target_10bp", "regime_hike", "state_pre_rv_z", "state_pre_rsvneg_z", "ma3_target_10bp_z", "root_gg", "PR_abs_jump", "asinh_PR_rv", "asinh_PR_rsv_neg"];

for v = numVars
    if ismember(v, string(T.Properties.VariableNames)) && ~isnumeric(T.(v))
        T.(v) = str2double(T.(v));
    end
end

T.root_gg = double(T.root_code == "gg");
T.target_x_hike = T.shock_target_10bp .* T.regime_hike;
T.target_x_preRV = T.shock_target_10bp .* T.state_pre_rv_z;
T.target_x_memory = T.shock_target_10bp .* T.ma3_target_10bp_z;

B = readtable(barFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

B.event_date = parse_date_flex(B.event_date);
B.root_code = string(B.root_code);
B.bar_time = parse_datetime_flex(B.bar_time);

if ~isnumeric(B.r_bar)
    B.r_bar = str2double(B.r_bar);
end

B = B(~isnat(B.event_date) & B.root_code ~= "" & ~isnan(B.r_bar), :);

[Comp, reportTbl] = compute_bns_components(B, barFile, minBarsForBNS, minShareGroupsOk, minMedianBars);

reportFile = fullfile(analysisDir, 'pr_bns_feasibility_report.csv');
writetable(reportTbl, reportFile);

if reportTbl.status(1) ~= "ok"
    fprintf('\nBNS non eseguito: %s\n', reportTbl.status(1));
    fprintf('Feasibility report: %s\n', reportFile);
    return;
end

Long = outerjoin(T, Comp, 'Keys', {'event_date', 'root_code'}, 'MergeKeys', true, 'Type', 'left');

allMask = true(height(Long), 1);
clVar = "event_date";

specs = {};
specs{end+1} = mk("BNS01_BV_regime", "asinh_BV_PR", ["shock_target_10bp", "regime_hike", "target_x_hike", "root_gg"], allMask, clVar);
specs{end+1} = mk("BNS02_BV_preuncertainty", "asinh_BV_PR", ["shock_target_10bp", "state_pre_rv_z", "target_x_preRV", "root_gg"], allMask, clVar);
specs{end+1} = mk("BNS03_BV_memory", "asinh_BV_PR", ["shock_target_10bp", "ma3_target_10bp_z", "target_x_memory", "root_gg"], allMask, clVar);
specs{end+1} = mk("BNS04_JV_regime", "asinh_JV_PR", ["shock_target_10bp", "regime_hike", "target_x_hike", "root_gg"], allMask, clVar);
specs{end+1} = mk("BNS05_JV_preuncertainty", "asinh_JV_PR", ["shock_target_10bp", "state_pre_rv_z", "target_x_preRV", "root_gg"], allMask, clVar);
specs{end+1} = mk("BNS06_JV_memory", "asinh_JV_PR", ["shock_target_10bp", "ma3_target_10bp_z", "target_x_memory", "root_gg"], allMask, clVar);

nSpec = numel(specs);

coefCell = cell(nSpec, 1);
modelCell = cell(nSpec, 1);
postCell = cell(nSpec, 1);

for i = 1:nSpec
    s = specs{i};
    fprintf('[%d/%d] %s\n', i, nSpec, s.name);
    [coefCell{i}, modelCell{i}, fit] = cluster_ols(Long, s);
    postCell{i} = compute_marginal_effects(fit);
end

coefResults = sortrows(vertcat(coefCell{:}), {'model_name', 'term'});
modelResults = sortrows(vertcat(modelCell{:}), 'model_name');
postResults = sortrows(vertcat(postCell{:}), {'model_name', 'effect_name'});

panelOut = fullfile(analysisDir, 'pr_bns_component_panel.csv');
coefOut = fullfile(analysisDir, 'pr_bns_model_coefficients.csv');
modelOut = fullfile(analysisDir, 'pr_bns_model_summary.csv');
postOut = fullfile(analysisDir, 'pr_bns_marginal_effects.csv');

writetable(format_long_panel_for_write(Long), panelOut);
writetable(coefResults, coefOut);
writetable(modelResults, modelOut);
writetable(postResults, postOut);

fprintf('\n================ BNS VOLATILITY MODELS SUMMARY ================\n');
fprintf('Component panel    : %s\n', panelOut);
fprintf('Coefficients       : %s\n', coefOut);
fprintf('Model summary      : %s\n', modelOut);
fprintf('Marginal effects   : %s\n', postOut);
fprintf('Feasibility report : %s\n', reportFile);
fprintf('================================================================\n');

function [Comp, reportTbl] = compute_bns_components(B, barFile, minBarsForBNS, minShareGroupsOk, minMedianBars)

    key = string(B.event_date, 'yyyy-MM-dd') + "__" + string(B.root_code);
    G = findgroups(key);
    ug = unique(G);

    mu1 = sqrt(2 / pi);
    cBV = 1 / (mu1 ^ 2);

    nG = numel(ug);

    Comp = table();
    Comp.event_date = NaT(nG, 1);
    Comp.root_code = strings(nG, 1);
    Comp.PR_n_obs_bars_BNS = nan(nG, 1);
    Comp.PR_net_log_return_BNS = nan(nG, 1);
    Comp.RV_PR_BNS = nan(nG, 1);
    Comp.BV_PR = nan(nG, 1);
    Comp.JV_PR = nan(nG, 1);
    Comp.jump_share_BNS = nan(nG, 1);
    Comp.asinh_BV_PR = nan(nG, 1);
    Comp.asinh_JV_PR = nan(nG, 1);

    Mvals = nan(nG, 1);

    for j = 1:nG

        Bj = B(G == ug(j), :);
        Bj = sortrows(Bj, 'bar_time');

        r = Bj.r_bar;
        r = r(isfinite(r));
        M = numel(r);

        Mvals(j) = M;

        Comp.event_date(j) = Bj.event_date(1);
        Comp.root_code(j) = Bj.root_code(1);
        Comp.PR_n_obs_bars_BNS(j) = M;

        if M == 0
            continue;
        end

        RV = sum(r .^ 2, 'omitnan');

        if M >= 2
            BV = cBV * sum(abs(r(2:end)) .* abs(r(1:end - 1)), 'omitnan');
        else
            BV = NaN;
        end

        JV = RV - BV;

        if isfinite(JV) && JV < 0 && JV > -1e-12
            JV = 0;
        end

        JV = max(JV, 0);

        Comp.PR_net_log_return_BNS(j) = sum(r, 'omitnan');
        Comp.RV_PR_BNS(j) = RV;
        Comp.BV_PR(j) = BV;
        Comp.JV_PR(j) = JV;
        Comp.jump_share_BNS(j) = JV / RV;
        Comp.asinh_BV_PR(j) = asinh(BV);
        Comp.asinh_JV_PR(j) = asinh(JV);

        if ~isfinite(Comp.jump_share_BNS(j))
            Comp.jump_share_BNS(j) = NaN;
        end
    end

    nOk = sum(Mvals >= minBarsForBNS, 'omitnan');
    shareOk = nOk / max(nG, 1);
    medM = median(Mvals, 'omitnan');
    minM = min(Mvals, [], 'omitnan');
    maxM = max(Mvals, [], 'omitnan');

    status = "ok";

    if shareOk < minShareGroupsOk
        status = "too_few_groups_with_enough_bars";
    elseif medM < minMedianBars
        status = "median_bar_count_too_small";
    elseif all(~isfinite(Comp.BV_PR)) || all(~isfinite(Comp.JV_PR))
        status = "bns_components_not_computable";
    end

    reportTbl = table();
    reportTbl.status = status;
    reportTbl.bar_file = string(barFile);
    reportTbl.n_groups = nG;
    reportTbl.share_groups_ok = shareOk;
    reportTbl.median_bars = medM;
    reportTbl.min_bars = minM;
    reportTbl.max_bars = maxM;
    reportTbl.n_groups_ok = nOk;
end

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
    end

    iU = find(tn == "target_x_preRV", 1);

    if ~isempty(iU)
        for z = [-1 0 1]
            L = L0;
            L(iU) = z;
            rows = add_effect(rows, fit, "slope_preRV_z_" + string(z), z, L, "preRV");
        end
    end

    iM = find(tn == "target_x_memory", 1);

    if ~isempty(iM)
        for z = [-1 0 1]
            L = L0;
            L(iM) = z;
            rows = add_effect(rows, fit, "slope_memory_z_" + string(z), z, L, "memory");
        end
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

    if ismember("bar_time", string(T.Properties.VariableNames)) && isdatetime(T.bar_time)
        T.bar_time = string(T.bar_time, 'yyyy-MM-dd HH:mm:ss');
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

function dt = parse_datetime_flex(x)

    if isdatetime(x)
        dt = x;
        return;
    end

    if isnumeric(x)
        dt = datetime(x, 'ConvertFrom', 'excel');
        return;
    end

    if iscell(x)
        x = string(x);
    end

    if ischar(x)
        x = string(x);
    end

    fmts = {'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd HH:mm', 'dd/MM/yyyy HH:mm:ss', 'dd/MM/yyyy HH:mm', 'MM/dd/yyyy HH:mm:ss', 'MM/dd/yyyy HH:mm', 'yyyy-MM-dd''T''HH:mm:ss', 'yyyy-MM-dd''T''HH:mm'};
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

    dt = best;
end
