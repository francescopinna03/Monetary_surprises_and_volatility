%% STEP 13: HIERARCHICAL SHRINKAGE MODELS.
%
% The code estimates a hierarchical shrinkage exercise for the main
% state-dependent PR outcomes by using the long state-dependent PR panel and
% applies a sparse-group lasso to assess which blocks of explanatory variables
% survive penalization.
% 
% The blocks where the feature space is organized include the target surprise, 
% the hiking-regime channel, the pre-announcement
% realized-volatility channel, the downside-volatility channel, monetary-policy
% memory, OIS curve variables and the asset-family indicator.
%
% The sparse-group lasso combines variable-level and block-level shrinkage, making
% the exercise useful as a disciplinary check on the empirical
% specification. More precisely, a state channel either contributes enough information to
% survive penalization, or it is shrunk toward zero together with its related
% interaction terms.
%
% The tuning parameter is selected by event-level grouped cross-validation.
% Events, rather than individual asset-family observations, define the folds.
% After selection, the script re-estimates a post-selection OLS model with
% event-date clustered standard errors on the selected variables.
%
% Authors agree this step provides an auxiliary regularization
% check on the stability and relevance of the proposed state channels.
%
% Input file is Output/analysis/pr_state_dependent_panel.csv. Output files are
% Output/analysis/shrinkage_cv_path.csv, Output/analysis/shrinkage_selected_features.csv,
% Output/analysis/shrinkage_postols_coefficients.csv and
% Output/analysis/shrinkage_postols_summary.csv.
clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
panelFile = fullfile(analysisDir, 'pr_state_dependent_panel.csv');

cfg = struct();
cfg.alpha = 0.60;
cfg.nFolds = 10;
cfg.lambda_ratio = 0.05;
cfg.nLambda = 40;
cfg.maxIter = 3000;
cfg.tol = 1e-7;
cfg.outcomes = ["PR_abs_jump", "asinh_PR_rv", "asinh_PR_rsv_neg"];

T = readtable(panelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

T.event_date = parse_date_flex(T.event_date);
T.root_code = string(T.root_code);

need = ["PR_abs_jump", "asinh_PR_rv", "asinh_PR_rsv_neg", "shock_target_10bp", "regime_hike", "target_x_hike", "state_pre_rv_z", "target_x_preRV", "state_pre_rsvneg_z", "target_x_preRSVneg", "M1_e_z", "target_x_M1", "ma3_target_10bp_z", "target_x_memory", "T_e", "target_x_T", "P_e", "target_x_P", "root_gg"];

for v = need
    if ismember(v, string(T.Properties.VariableNames)) && ~isnumeric(T.(v))
        T.(v) = str2double(T.(v));
    end
end

if ~ismember("root_gg", string(T.Properties.VariableNames))
    T.root_gg = double(T.root_code == "gg");
end

blocks = cell(8, 1);
blocks{1} = struct('name', "shock", 'vars', ["shock_target_10bp"]);
blocks{2} = struct('name', "regime", 'vars', ["regime_hike", "target_x_hike"]);
blocks{3} = struct('name', "uncert_rv", 'vars', ["state_pre_rv_z", "target_x_preRV"]);
blocks{4} = struct('name', "uncert_dn", 'vars', ["state_pre_rsvneg_z", "target_x_preRSVneg"]);
blocks{5} = struct('name', "memory_m1", 'vars', ["M1_e_z", "target_x_M1"]);
blocks{6} = struct('name', "memory_ma3", 'vars', ["ma3_target_10bp_z", "target_x_memory"]);
blocks{7} = struct('name', "curve", 'vars', ["T_e", "target_x_T", "P_e", "target_x_P"]);
blocks{8} = struct('name', "asset", 'vars', ["root_gg"]);

cvRows = cell(0, 7);
selRows = cell(0, 5);
coefRows = {};
sumRows = {};

for iy = 1:numel(cfg.outcomes)

    depvar = cfg.outcomes(iy);

    fprintf('\nOutcome: %s\n', depvar);

    [Xraw, y, featureNames, groupId, groupNames, clStr] = build_design(T, depvar, blocks);

    [X, yCtr, xMu, xSd, yMu] = standardize_design(Xraw, y);

    folds = grouped_folds(clStr, cfg.nFolds);

    lamMax = max(abs((X' * yCtr) / numel(yCtr)));
    lamMax = max(lamMax, 1e-6);
    lambdaGrid = exp(linspace(log(lamMax), log(lamMax * cfg.lambda_ratio), cfg.nLambda));

    cvMSE = nan(numel(lambdaGrid), 1);
    cvSE = nan(numel(lambdaGrid), 1);

    for il = 1:numel(lambdaGrid)

        lam = lambdaGrid(il);
        foldMSE = nan(cfg.nFolds, 1);

        for f = 1:cfg.nFolds

            idxTest = folds == f;
            idxTrain = ~idxTest;

            betaStd = sgl_fista(X(idxTrain, :), yCtr(idxTrain), groupId, lam, cfg.alpha, cfg.maxIter, cfg.tol);
            yHat = X(idxTest, :) * betaStd;

            foldMSE(f) = mean((yCtr(idxTest) - yHat) .^ 2, 'omitnan');
        end

        cvMSE(il) = mean(foldMSE, 'omitnan');
        cvSE(il) = std(foldMSE, 0, 'omitnan') / sqrt(sum(~isnan(foldMSE)));

        fprintf('  lambda %2d/%2d done\n', il, numel(lambdaGrid));
    end

    [bestMSE, iMin] = min(cvMSE);
    mse1se = bestMSE + cvSE(iMin);
    iChosen = find(cvMSE <= mse1se, 1, 'last');
    lamChosen = lambdaGrid(iChosen);

    betaStd = sgl_fista(X, yCtr, groupId, lamChosen, cfg.alpha, cfg.maxIter, cfg.tol);
    active = abs(betaStd) > 1e-8;

    betaRaw = betaStd ./ xSd(:);
    intercept = yMu - xMu(:)' * betaRaw;

    activeNames = featureNames(active);
    activeX = Xraw(:, active);

    [coefTbl, sumTbl] = post_selection_cluster_ols(y, activeX, activeNames, clStr, depvar, "SGL_" + depvar);

    for il = 1:numel(lambdaGrid)
        cvRows(end + 1, :) = {string(depvar), lambdaGrid(il), cvMSE(il), cvSE(il), lamChosen, iChosen, bestMSE};
    end

    for j = 1:numel(featureNames)
        selRows(end + 1, :) = {string(depvar), string(featureNames(j)), betaRaw(j), active(j), groupNames(groupId(j))};
    end

    selRows(end + 1, :) = {string(depvar), "Intercept", intercept, true, "intercept"};

    coefRows{end + 1} = coefTbl;
    sumRows{end + 1} = sumTbl;
end

cvTbl = cell2table(cvRows, 'VariableNames', {'depvar', 'lambda', 'cv_mse', 'cv_se', 'lambda_chosen', 'idx_chosen', 'best_mse'});
selTbl = cell2table(selRows, 'VariableNames', {'depvar', 'feature', 'beta_shrunken_raw', 'is_active', 'block_name'});
coefTblAll = vertcat(coefRows{:});
sumTblAll = vertcat(sumRows{:});

writetable(cvTbl, fullfile(analysisDir, 'shrinkage_cv_path.csv'));
writetable(selTbl, fullfile(analysisDir, 'shrinkage_selected_features.csv'));
writetable(coefTblAll, fullfile(analysisDir, 'shrinkage_postols_coefficients.csv'));
writetable(sumTblAll, fullfile(analysisDir, 'shrinkage_postols_summary.csv'));

fprintf('\n================ SHRINKAGE MODELS SUMMARY ================\n');
fprintf('CV path        : %s\n', fullfile(analysisDir, 'shrinkage_cv_path.csv'));
fprintf('Selected vars  : %s\n', fullfile(analysisDir, 'shrinkage_selected_features.csv'));
fprintf('Post-OLS coef  : %s\n', fullfile(analysisDir, 'shrinkage_postols_coefficients.csv'));
fprintf('Post-OLS sum   : %s\n', fullfile(analysisDir, 'shrinkage_postols_summary.csv'));
fprintf('==========================================================\n');

function [Xraw, y, featureNames, groupId, groupNames, clStr] = build_design(T, depvar, blocks)

    y = T.(depvar);

    if isstring(y)
        y = str2double(y);
    end

    cl = T.event_date;
    mask = ~isnan(y) & ~isnat(cl);

    for b = 1:numel(blocks)

        vars = blocks{b}.vars;
        vars = vars(ismember(vars, string(T.Properties.VariableNames)));

        for v = vars
            x = T.(v);

            if isstring(x)
                x = str2double(x);
            end

            mask = mask & ~isnan(x);
        end
    end

    Xraw = [];
    featureNames = strings(0, 1);
    groupId = [];
    groupNames = strings(0, 1);

    g = 0;

    for b = 1:numel(blocks)

        vars = blocks{b}.vars;
        vars = vars(ismember(vars, string(T.Properties.VariableNames)));

        if isempty(vars)
            continue;
        end

        g = g + 1;
        groupNames(g, 1) = blocks{b}.name;

        for v = vars

            x = T.(v);

            if isstring(x)
                x = str2double(x);
            end

            Xraw = [Xraw, x(mask)];
            featureNames(end + 1, 1) = v;
            groupId(end + 1, 1) = g;
        end
    end

    y = y(mask);
    clStr = string(cl(mask), 'yyyy-MM-dd');
end

function [X, yCtr, xMu, xSd, yMu] = standardize_design(Xraw, y)

    xMu = mean(Xraw, 1, 'omitnan');
    xSd = std(Xraw, 0, 1, 'omitnan');
    xSd(~isfinite(xSd) | xSd == 0) = 1;

    X = (Xraw - xMu) ./ xSd;

    yMu = mean(y, 'omitnan');
    yCtr = y - yMu;
end

function folds = grouped_folds(clStr, nFolds)

    u = unique(clStr);
    n = numel(u);
    ord = randperm(n);

    foldsEvent = mod((1:n)' - 1, nFolds) + 1;

    map = containers.Map(cellstr(u(ord)), num2cell(foldsEvent));

    folds = nan(numel(clStr), 1);

    for i = 1:numel(clStr)
        folds(i) = map(char(clStr(i)));
    end
end

function beta = sgl_fista(X, y, groupId, lambda, alpha, maxIter, tol)

    [n, p] = size(X);

    L = normest(X) ^ 2 / n;
    step = 1 / max(L, 1e-10);

    beta = zeros(p, 1);
    z = beta;
    t = 1;

    lamGroup = lambda * (1 - alpha);
    lamL1 = lambda * alpha;

    ug = unique(groupId(:))';

    for it = 1:maxIter

        betaOld = beta;

        grad = (X' * (X * z - y)) / n;
        v = z - step * grad;

        beta = prox_sparse_group(v, groupId, ug, step * lamGroup, step * lamL1);

        tNew = 0.5 * (1 + sqrt(1 + 4 * t ^ 2));
        z = beta + ((t - 1) / tNew) * (beta - betaOld);
        t = tNew;

        if norm(beta - betaOld, 2) <= tol * max(1, norm(betaOld, 2))
            break;
        end
    end
end

function beta = prox_sparse_group(v, groupId, ug, tauGroup, tauL1)

    beta = zeros(size(v));

    for g = ug

        idx = groupId == g;
        s = soft_threshold(v(idx), tauL1);
        ns = norm(s, 2);

        if ns == 0
            beta(idx) = 0;
        else
            beta(idx) = max(1 - tauGroup / ns, 0) * s;
        end
    end
end

function x = soft_threshold(x, tau)

    x = sign(x) .* max(abs(x) - tau, 0);
end

function [coefTbl, sumTbl] = post_selection_cluster_ols(y, Xraw, featureNames, clStr, depvar, modelName)

    n = numel(y);

    X = [ones(n, 1), Xraw];
    termNames = ["Intercept"; featureNames(:)];
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
        t = beta ./ se;
        p = 2 * tcdf(-abs(t), G - 1);
    else
        se = nan(k, 1);
        t = nan(k, 1);
        p = nan(k, 1);
    end

    coefTbl = table();
    coefTbl.model_name = repmat(string(modelName), k, 1);
    coefTbl.depvar = repmat(string(depvar), k, 1);
    coefTbl.term = termNames;
    coefTbl.beta = beta;
    coefTbl.se_cluster = se;
    coefTbl.t_stat = t;
    coefTbl.p_value = p;
    coefTbl.n_obs = repmat(n, k, 1);
    coefTbl.n_clusters = repmat(G, k, 1);
    coefTbl.r2 = repmat(r2, k, 1);
    coefTbl.adj_r2 = repmat(adj_r2, k, 1);

    sumTbl = table();
    sumTbl.model_name = string(modelName);
    sumTbl.depvar = string(depvar);
    sumTbl.selected_rhs = strjoin(featureNames(:)', " + ");
    sumTbl.n_obs = n;
    sumTbl.n_clusters = G;
    sumTbl.n_params = k;
    sumTbl.r2 = r2;
    sumTbl.adj_r2 = adj_r2;
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
