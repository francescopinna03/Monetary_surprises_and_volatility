%% STEP 9: STATE-DEPENDENT PR MODELS
%
% The code estimates the first battery of state-dependent PR-only models,
% using the long state-dependent panel constructed in the previous step, and
% studies whether the response of PR-window volatility measures to monetary
% policy surprises changes with observable event-level states.
%
% The dependent variables are the absolute PR jump, the inverse hyperbolic
% sine transformation of press release realized variance and the inverse hyperbolic sine
% transformation of PR negative realized semivariance. The main shock variable
% is the target surprise expressed in 10 basis point units.
%
% The state-dependent specifications interact the target surprise with three
% state channels. The first is the hiking-regime dummy, the second is the
% pre-announcement realized-volatility state and the third is the recent
% monetary-policy memory measure based on lagged target surprises. When
% available, the script also includes the downside pre-announcement state
% based on negative realized semivariance.
%
% All regressions are estimated by OLS with event-date clustered standard
% errors. The script also computes post-estimation marginal effects, including
% baseline slopes, slopes across regimes and slopes evaluated at different
% standardized state values.
%
% Input file is Output/analysis/pr_state_dependent_panel.csv. Output files are
% Output/analysis/pr_state_model_coefficients.csv, Output/analysis/pr_state_model_summary.csv
% and Output/analysis/pr_state_marginal_effects.csv.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
panelFile = fullfile(analysisDir, 'pr_state_dependent_panel.csv');

T = readtable(panelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

requiredVars = ["event_date", "root_code", "PR_abs_jump", "asinh_PR_rv", "asinh_PR_rsv_neg", "shock_target_10bp", "regime_hike", "state_pre_rv_z", "ma3_target_10bp_z"];
missingVars = requiredVars(~ismember(requiredVars, string(T.Properties.VariableNames)));

if ~isempty(missingVars)
    error('Mancano colonne nel pannello state-dependent: %s', strjoin(missingVars, ', '));
end

T.event_date = parse_date_flex(T.event_date);
T.root_code = string(T.root_code);

numVars = ["PR_abs_jump", "asinh_PR_rv", "asinh_PR_rsv_neg", "shock_target_10bp", "regime_hike", "state_pre_rv_z", "state_pre_rsvneg_z", "ma3_target_10bp_z"];

for v = numVars
    if ismember(v, string(T.Properties.VariableNames)) && ~isnumeric(T.(v))
        T.(v) = str2double(T.(v));
    end
end

T.root_gg = double(T.root_code == "gg");
T.target_x_hike = T.shock_target_10bp .* T.regime_hike;
T.target_x_preRV = T.shock_target_10bp .* T.state_pre_rv_z;
T.target_x_memory = T.shock_target_10bp .* T.ma3_target_10bp_z;

allMask = true(height(T), 1);
clVar = "event_date";

specs = {};

specs{end+1} = mk("SD01_absjump_regime", "PR_abs_jump", ["shock_target_10bp", "regime_hike", "target_x_hike", "root_gg"], allMask, clVar);
specs{end+1} = mk("SD02_absjump_preuncertainty", "PR_abs_jump", ["shock_target_10bp", "state_pre_rv_z", "target_x_preRV", "root_gg"], allMask, clVar);
specs{end+1} = mk("SD03_absjump_memory", "PR_abs_jump", ["shock_target_10bp", "ma3_target_10bp_z", "target_x_memory", "root_gg"], allMask, clVar);
specs{end+1} = mk("SD04_asinhRV_regime", "asinh_PR_rv", ["shock_target_10bp", "regime_hike", "target_x_hike", "root_gg"], allMask, clVar);
specs{end+1} = mk("SD05_asinhRV_preuncertainty", "asinh_PR_rv", ["shock_target_10bp", "state_pre_rv_z", "target_x_preRV", "root_gg"], allMask, clVar);
specs{end+1} = mk("SD07_asinhRSVneg_regime", "asinh_PR_rsv_neg", ["shock_target_10bp", "regime_hike", "target_x_hike", "root_gg"], allMask, clVar);

if ismember("state_pre_rsvneg_z", string(T.Properties.VariableNames))
    T.target_x_preRSVneg = T.shock_target_10bp .* T.state_pre_rsvneg_z;
    specs{end+1} = mk("SD06_asinhRSVneg_preuncertainty", "asinh_PR_rsv_neg", ["shock_target_10bp", "state_pre_rsvneg_z", "target_x_preRSVneg", "root_gg"], allMask, clVar);
end

nSpec = numel(specs);

coefCell = cell(nSpec, 1);
modelCell = cell(nSpec, 1);
postCell = cell(nSpec, 1);

for i = 1:nSpec
    s = specs{i};
    fprintf('[%2d/%2d] %s\n', i, nSpec, s.name);
    [coefCell{i}, modelCell{i}, fit] = cluster_ols(T, s);
    postCell{i} = compute_marginal_effects(fit);
end

coefResults = sortrows(vertcat(coefCell{:}), {'model_name', 'term'});
modelResults = sortrows(vertcat(modelCell{:}), 'model_name');
postResults = sortrows(vertcat(postCell{:}), {'model_name', 'effect_name'});

coefFile = fullfile(analysisDir, 'pr_state_model_coefficients.csv');
modelFile = fullfile(analysisDir, 'pr_state_model_summary.csv');
postFile = fullfile(analysisDir, 'pr_state_marginal_effects.csv');

writetable(coefResults, coefFile);
writetable(modelResults, modelFile);
writetable(postResults, postFile);

fprintf('\n================ STATE-DEPENDENT MODELS SUMMARY ================\n');
fprintf('Models estimated   : %d\n', height(modelResults));
fprintf('Coefficients file  : %s\n', coefFile);
fprintf('Model summary file : %s\n', modelFile);
fprintf('Marginal effects   : %s\n', postFile);
fprintf('================================================================\n');

keyTerms = ["shock_target_10bp", "regime_hike", "target_x_hike", "state_pre_rv_z", "target_x_preRV", "ma3_target_10bp_z", "target_x_memory", "state_pre_rsvneg_z", "target_x_preRSVneg"];

disp(coefResults(ismember(coefResults.term, keyTerms), {'model_name', 'term', 'beta', 'se_cluster', 't_stat', 'p_value', 'n_obs', 'n_clusters'}));

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
    fit.n_obs = n;
    fit.n_clusters = G;
end

function outTbl = compute_marginal_effects(fit)

    tn = string(fit.term_names);
    b = fit.beta;
    V = fit.V;

    rows = cell(0, 11);

    iShock = find(tn == "shock_target_10bp", 1);

    if isempty(iShock)
        outTbl = empty_effect_table();
        return;
    end

    L = zeros(numel(b), 1);
    L(iShock) = 1;
    rows = add_effect(rows, fit, "slope_baseline", L, NaN, "baseline");

    iH = find(tn == "target_x_hike", 1);

    if ~isempty(iH)
        L0 = zeros(numel(b), 1);
        L0(iShock) = 1;
        L1 = L0;
        L1(iH) = 1;
        rows = add_effect(rows, fit, "slope_H0", L0, 0, "regime_hike=0");
        rows = add_effect(rows, fit, "slope_H1", L1, 1, "regime_hike=1");
        rows = add_effect(rows, fit, "delta_regime", unit_vector(numel(b), iH), 1, "interaction");
    end

    iU = find(tn == "target_x_preRV", 1);

    if ~isempty(iU)
        for z = [-1 0 1]
            L = zeros(numel(b), 1);
            L(iShock) = 1;
            L(iU) = z;
            rows = add_effect(rows, fit, "slope_preRV_z_" + string(z), L, z, "preRV");
        end

        rows = add_effect(rows, fit, "delta_preRV_per1sd", unit_vector(numel(b), iU), 1, "interaction");
    end

    iM = find(tn == "target_x_memory", 1);

    if ~isempty(iM)
        for z = [-1 0 1]
            L = zeros(numel(b), 1);
            L(iShock) = 1;
            L(iM) = z;
            rows = add_effect(rows, fit, "slope_memory_z_" + string(z), L, z, "memory");
        end

        rows = add_effect(rows, fit, "delta_memory_per1sd", unit_vector(numel(b), iM), 1, "interaction");
    end

    iD = find(tn == "target_x_preRSVneg", 1);

    if ~isempty(iD)
        for z = [-1 0 1]
            L = zeros(numel(b), 1);
            L(iShock) = 1;
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
