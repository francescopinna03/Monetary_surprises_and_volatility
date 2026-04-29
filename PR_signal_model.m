%% STEP 7: PRESS RELEASE SIGNAL MODELS.
%
% Here is built the PR-only signal panel and estimates the first set of
% linear signal regressions. It starts from the baseline PR panel and adds
% outcome variables that summarize the immediate market reaction around the
% press release.
%
% The main outcomes are the signed PR jump, the absolute PR jump, the inverse
% hyperbolic sine transformation of PR realized variance and the inverse
% hyperbolic sine transformation of negative realized semivariance. The script
% also constructs a placebo pre-PR window from the bar-level event-window file,
% using observations in the interval from 15 to 5 minutes before the press
% release.
%
% Monetary policy surprises are expressed in 10 basis point units. The script
% constructs absolute, positive and negative shock components, asset-family
% interactions and, when OIS maturities are available, PCA-based target and
% path factors at the event level.
%
% The regression battery estimates pooled, asset-specific, asymmetric and
% target-path specifications with event-date clustered standard errors. The
% placebo specifications are included to check whether the estimated PR signal
% is already present before the press release window.
%
% Input files are Output/analysis/pr_baseline_panel.csv and
% Output/event_windows/event_window_bars.csv. Output files are
% Output/analysis/pr_signal_panel.csv, Output/analysis/pr_signal_regression_coefficients.csv
% and Output/analysis/pr_signal_regression_model_summary.csv.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
windowDir = fullfile(projectRoot, 'Output', 'event_windows');

panelFile = fullfile(analysisDir, 'pr_baseline_panel.csv');
barsFile = fullfile(windowDir, 'event_window_bars.csv');

P = readtable(panelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

requiredP = ["event_date", "trade_date", "event_id", "root_code", "file_name_clean", "expiry_code", "contract_year", "PR_signed_jump", "PR_rv", "PR_rsv_neg", "shock_target"];
missingP = requiredP(~ismember(requiredP, string(P.Properties.VariableNames)));

if ~isempty(missingP)
    error('Mancano colonne in pr_baseline_panel.csv: %s', strjoin(missingP, ', '));
end

P.event_date = parse_date_flex(P.event_date);
P.trade_date = parse_date_flex(P.trade_date);
P.root_code = string(P.root_code);
P.event_id = string(P.event_id);
P.file_name_clean = string(P.file_name_clean);
P.expiry_code = string(P.expiry_code);

numVarsP = ["contract_year", "PR_signed_jump", "PR_rv", "PR_rsv_neg", "PR_rsv_pos", "shock_target", "ois_1m_raw", "ois_3m_raw", "ois_6m_raw", "ois_1y_raw", "ois_2y_raw", "ois_3y_raw", "ois_4y_raw", "ois_5y_raw", "ois_10y_raw"];

for v = numVarsP
    if ismember(v, string(P.Properties.VariableNames)) && ~isnumeric(P.(v))
        P.(v) = str2double(P.(v));
    end
end

P = P(~isnat(P.event_date) & P.root_code ~= "", :);

P.PR_abs_jump = abs(P.PR_signed_jump);
P.asinh_PR_rv = asinh(P.PR_rv);
P.asinh_PR_rsv_neg = asinh(P.PR_rsv_neg);

B = readtable(barsFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

requiredB = ["event_date", "trade_date", "event_id", "root_code", "file_name_clean", "expiry_code", "contract_year", "window_name", "Time", "Latest", "rel_event_minutes"];
missingB = requiredB(~ismember(requiredB, string(B.Properties.VariableNames)));

if ~isempty(missingB)
    error('Mancano colonne in event_window_bars.csv: %s', strjoin(missingB, ', '));
end

B.event_date = parse_date_flex(B.event_date);
B.trade_date = parse_date_flex(B.trade_date);
B.root_code = string(B.root_code);
B.event_id = string(B.event_id);
B.file_name_clean = string(B.file_name_clean);
B.expiry_code = string(B.expiry_code);
B.window_name = string(B.window_name);
B.Time = parse_datetime_flex(B.Time);

numVarsB = ["contract_year", "Latest", "rel_event_minutes"];

for v = numVarsB
    if ~isnumeric(B.(v))
        B.(v) = str2double(B.(v));
    end
end

B = B(B.window_name == "PR", :);
Bpre = B(B.rel_event_minutes >= -15 & B.rel_event_minutes <= -5, :);

placebo = build_placebo_panel(Bpre);

joinKeys = intersect(["event_date", "trade_date", "event_id", "root_code", "file_name_clean", "expiry_code", "contract_year"], string(P.Properties.VariableNames));
joinKeys = intersect(joinKeys, string(placebo.Properties.VariableNames));

P = outerjoin(P, placebo, 'Keys', joinKeys, 'MergeKeys', true, 'Type', 'left');

P.root_gg = double(P.root_code == "gg");
P.shock_target_10bp = P.shock_target / 10;
P.abs_target_10bp = abs(P.shock_target_10bp);
P.shock_target_x_gg = P.shock_target_10bp .* P.root_gg;
P.shock_pos_10bp = max(P.shock_target_10bp, 0);
P.shock_neg_mag_10bp = max(-P.shock_target_10bp, 0);

oisColsShort = "ois_1m_raw";
oisColsPath = ["ois_6m_raw", "ois_1y_raw", "ois_2y_raw", "ois_3y_raw"];
hasOis = all(ismember([oisColsShort oisColsPath], string(P.Properties.VariableNames)));

if hasOis
    [P.target_pca_10bp, P.path_pca_10bp] = build_event_level_target_path(P);
    P.abs_target_pca_10bp = abs(P.target_pca_10bp);
    P.abs_path_pca_10bp = abs(P.path_pca_10bp);
else
    P.target_pca_10bp = nan(height(P), 1);
    P.path_pca_10bp = nan(height(P), 1);
    P.abs_target_pca_10bp = nan(height(P), 1);
    P.abs_path_pca_10bp = nan(height(P), 1);
end

signalPanelFile = fullfile(analysisDir, 'pr_signal_panel.csv');

writetable(format_panel_for_write(P), signalPanelFile);

allMask = true(height(P), 1);
isFx = P.root_code == "fx";
isGg = P.root_code == "gg";
clVar = "event_date";

specs = {};

specs{end+1} = mk("S01_jump_signed_pooled", "PR_signed_jump", ["shock_target_10bp", "root_gg", "shock_target_x_gg"], allMask, clVar);
specs{end+1} = mk("S02_jump_signed_fx", "PR_signed_jump", ["shock_target_10bp"], isFx, clVar);
specs{end+1} = mk("S03_jump_signed_gg", "PR_signed_jump", ["shock_target_10bp"], isGg, clVar);
specs{end+1} = mk("S04_jump_abs_pooled", "PR_abs_jump", ["abs_target_10bp", "root_gg"], allMask, clVar);
specs{end+1} = mk("S05_asinh_rv_pooled", "asinh_PR_rv", ["abs_target_10bp", "root_gg"], allMask, clVar);
specs{end+1} = mk("S06_asinh_rv_fx", "asinh_PR_rv", ["abs_target_10bp"], isFx, clVar);
specs{end+1} = mk("S07_asinh_rv_gg", "asinh_PR_rv", ["abs_target_10bp"], isGg, clVar);
specs{end+1} = mk("S08_asinh_rsvneg_pooled", "asinh_PR_rsv_neg", ["abs_target_10bp", "root_gg"], allMask, clVar);
specs{end+1} = mk("S09_asinh_rsvneg_asym_pooled", "asinh_PR_rsv_neg", ["shock_pos_10bp", "shock_neg_mag_10bp", "root_gg"], allMask, clVar);

if hasOis
    specs{end+1} = mk("S10_asinh_rv_target_path", "asinh_PR_rv", ["abs_target_pca_10bp", "abs_path_pca_10bp", "root_gg"], allMask, clVar);
    specs{end+1} = mk("S11_asinh_rsvneg_target_path", "asinh_PR_rsv_neg", ["abs_target_pca_10bp", "abs_path_pca_10bp", "root_gg"], allMask, clVar);
end

if ismember("pre_PR_signed_jump", string(P.Properties.VariableNames))
    specs{end+1} = mk("S12_placebo_pre_jump", "pre_PR_signed_jump", ["shock_target_10bp", "root_gg", "shock_target_x_gg"], allMask, clVar);
end

if ismember("pre_asinh_PR_rv", string(P.Properties.VariableNames))
    specs{end+1} = mk("S13_placebo_pre_asinh_rv", "pre_asinh_PR_rv", ["abs_target_10bp", "root_gg"], allMask, clVar);
end

nSpec = numel(specs);
coefCell = cell(nSpec, 1);
modelCell = cell(nSpec, 1);

for i = 1:nSpec
    s = specs{i};
    fprintf('[%2d/%2d] %s\n', i, nSpec, s.name);
    [coefCell{i}, modelCell{i}] = cluster_ols(P, s);
end

coefResults = sortrows(vertcat(coefCell{:}), {'model_name', 'term'});
modelResults = sortrows(vertcat(modelCell{:}), 'model_name');

coefFile = fullfile(analysisDir, 'pr_signal_regression_coefficients.csv');
modelFile = fullfile(analysisDir, 'pr_signal_regression_model_summary.csv');

writetable(coefResults, coefFile);
writetable(modelResults, modelFile);

fprintf('\n================ PR SIGNAL MODELS ================\n');
fprintf('Signal panel rows : %d\n', height(P));
fprintf('Models estimated  : %d\n', height(modelResults));
fprintf('Signal panel      : %s\n', signalPanelFile);
fprintf('Coefficients      : %s\n', coefFile);
fprintf('Model summary     : %s\n', modelFile);
fprintf('==================================================\n');

keyTerms = ["shock_target_10bp", "abs_target_10bp", "shock_target_x_gg", "shock_pos_10bp", "shock_neg_mag_10bp", "abs_target_pca_10bp", "abs_path_pca_10bp"];

disp(coefResults(ismember(coefResults.term, keyTerms), {'model_name', 'term', 'beta', 'se_cluster', 't_stat', 'p_value', 'n_obs', 'n_clusters'}));

function s = mk(name, depvar, rhs, mask, clusterVar)

    s = struct();
    s.name = string(name);
    s.depvar = string(depvar);
    s.rhs = string(rhs);
    s.mask = mask;
    s.clusterVar = string(clusterVar);
end

function placebo = build_placebo_panel(Bpre)

    if isempty(Bpre)
        placebo = table();
        return;
    end

    keys = {'event_date', 'trade_date', 'event_id', 'root_code', 'file_name_clean', 'expiry_code', 'contract_year'};
    [G, keyTbl] = findgroups(Bpre(:, keys));

    nG = max(G);

    pre_PR_n_bars = nan(nG, 1);
    pre_PR_signed_jump = nan(nG, 1);
    pre_PR_abs_jump = nan(nG, 1);
    pre_PR_rv = nan(nG, 1);
    pre_PR_rsv_neg = nan(nG, 1);
    pre_asinh_PR_rv = nan(nG, 1);
    pre_asinh_PR_rsvneg = nan(nG, 1);

    for g = 1:nG

        X = Bpre(G == g, :);
        X = sortrows(X, 'Time');

        pre_PR_n_bars(g) = height(X);

        if height(X) >= 2

            pre_PR_signed_jump(g) = log(X.Latest(end) / X.Latest(1));
            pre_PR_abs_jump(g) = abs(pre_PR_signed_jump(g));

            r = diff(log(X.Latest));

            pre_PR_rv(g) = sum(r .^ 2, 'omitnan');
            pre_PR_rsv_neg(g) = sum((r < 0) .* (r .^ 2), 'omitnan');
            pre_asinh_PR_rv(g) = asinh(pre_PR_rv(g));
            pre_asinh_PR_rsvneg(g) = asinh(pre_PR_rsv_neg(g));
        end
    end

    placebo = keyTbl;
    placebo.pre_PR_n_bars = pre_PR_n_bars;
    placebo.pre_PR_signed_jump = pre_PR_signed_jump;
    placebo.pre_PR_abs_jump = pre_PR_abs_jump;
    placebo.pre_PR_rv = pre_PR_rv;
    placebo.pre_PR_rsv_neg = pre_PR_rsv_neg;
    placebo.pre_asinh_PR_rv = pre_asinh_PR_rv;
    placebo.pre_asinh_PR_rsvneg = pre_asinh_PR_rsvneg;
end

function [target_10bp, path_10bp] = build_event_level_target_path(T)

    evStr = string(T.event_date, 'yyyy-MM-dd');
    [g, uEv] = findgroups(evStr);
    nEv = numel(uEv);

    tgt_ev = splitapply(@first_nonmissing_num, T.ois_1m_raw, g);

    pathVars = ["ois_6m_raw", "ois_1y_raw", "ois_2y_raw", "ois_3y_raw"];
    pathMat = nan(nEv, numel(pathVars));

    for j = 1:numel(pathVars)
        pathMat(:, j) = splitapply(@first_nonmissing_num, T.(pathVars(j)), g);
    end

    ok = all(~isnan(pathMat), 2) & ~isnan(tgt_ev);
    pc1 = nan(nEv, 1);

    if sum(ok) >= 5

        mu = mean(pathMat(ok, :), 1);
        sd = std(pathMat(ok, :), 0, 1);
        sd(sd == 0) = 1;

        Z = (pathMat(ok, :) - mu) ./ sd;

        [~, ~, V] = svd(Z, 'econ');

        pc1(ok) = Z * V(:, 1);

        avgLong = mean(pathMat(ok, :), 2, 'omitnan');

        if corr(pc1(ok), avgLong, 'rows', 'complete') < 0
            pc1 = -pc1;
        end

        Xo = [ones(sum(ok), 1), tgt_ev(ok) / 10];
        b = Xo \ pc1(ok);

        pc1(ok) = pc1(ok) - Xo * b;
    end

    target_10bp = tgt_ev / 10;
    path_10bp = pc1;

    sp = std(path_10bp, 'omitnan');
    st = std(target_10bp, 'omitnan');

    if isfinite(sp) && sp > 0 && isfinite(st)
        path_10bp = path_10bp / sp * st;
    end

    target_10bp = target_10bp(g);
    path_10bp = path_10bp(g);
end

function v = first_nonmissing_num(x)

    x = x(~isnan(x));

    if isempty(x)
        v = NaN;
    else
        v = x(1);
    end
end

function [coefTbl, modelTbl] = cluster_ols(T, s)

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
    elseif isstring(cl)
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
end

function T = format_panel_for_write(T)

    if isempty(T)
        return;
    end

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
        try
            dt = dateshift(datetime(x, 'ConvertFrom', 'excel'), 'start', 'day');
            return;
        catch
        end
    end

    if iscell(x)
        x = string(x);
    end

    if ischar(x)
        x = string(x);
    end

    if ~isstring(x)
        error('Formato data non supportato.');
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
        try
            dt = datetime(x, 'ConvertFrom', 'excel');
            return;
        catch
        end
    end

    if iscell(x)
        x = string(x);
    end

    if ischar(x)
        x = string(x);
    end

    if ~isstring(x)
        error('Formato datetime non supportato.');
    end

    fmts = {'yyyy-MM-dd HH:mm', 'dd/MM/yyyy HH:mm', 'MM/dd/yyyy HH:mm', 'dd-MMM-yyyy HH:mm'};
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
