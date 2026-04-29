%% STEP 6: FRACTIONAL RESPONSE MODELS.
%
% The script estimates the first dedicated econometric battery on the
% negative semivariance share of the PR window. The dependent variable is
% PR_neg_share, which is bounded between zero and one and is therefore modeled
% with a fractional-response logit QMLE.
%
% It is used the baseline PR panel built in the previous step and
% constructs monetary-policy surprise regressors from EA-MPD and OIS changes.
% When the relevant OIS maturities are available, target and path factors are
% extracted through a PCA-based rotation inspired by the high-frequency
% monetary policy shock literature. The path factor is then orthogonalized
% with respect to the target factor.
%
% The model battery includes pooled specifications, asset-family interactions,
% asymmetric positive and negative shock components, regime interactions for
% the hiking phase, and separate estimates for STOXX and Bund futures. Standard
% errors are clustered at the event-date level. The script also reports average
% partial effects, RESET-type diagnostics, asymmetry tests and a QAIC-like
% model comparison statistic.
%
% Input file is Output/analysis/pr_baseline_panel.csv, output files are
% Output/analysis/pr_fractional_coefficients.csv, Output/analysis/pr_fractional_model_summary.csv
% and Output/analysis/pr_fractional_diagnostics.csv.

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
panelFile = fullfile(analysisDir, 'pr_baseline_panel.csv');

T = readtable(panelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

requiredVars = ["event_date", "root_code", "PR_neg_share", "shock_target"];
missingVars = requiredVars(~ismember(requiredVars, string(T.Properties.VariableNames)));

if ~isempty(missingVars)
    error('Mancano colonne: %s', strjoin(missingVars, ', '));
end

T.event_date = parse_date_flex(T.event_date);
T.root_code = string(T.root_code);

numVars = ["PR_neg_share", "shock_target", "ois_1m_raw", "ois_3m_raw", "ois_6m_raw", "ois_1y_raw", "ois_2y_raw", "ois_3y_raw", "ois_4y_raw", "ois_5y_raw", "ois_10y_raw"];

for v = numVars
    if ismember(v, string(T.Properties.VariableNames)) && ~isnumeric(T.(v))
        T.(v) = str2double(T.(v));
    end
end

T = T(~isnat(T.event_date) & T.root_code ~= "", :);

prns = T.PR_neg_share;
badShare = ~isnan(prns) & (prns < 0 | prns > 1);

if any(badShare)
    error('PR_neg_share fuori [0,1].');
end

oisCols = ["ois_6m_raw", "ois_1y_raw", "ois_2y_raw", "ois_3y_raw"];
hasOis = all(ismember(oisCols, string(T.Properties.VariableNames)));

if hasOis
    [T.target_pca_10bp, T.path_pca_10bp] = gss_factor_extraction(T);
    fprintf('GSS factors extracted: target and path (PCA-rotated, orthogonal).\n');
else
    T.target_pca_10bp = T.shock_target / 10;
    T.path_pca_10bp = nan(height(T), 1);
    warning('OIS columns mancanti: fallback a shock_target come target factor.');
end

T.root_gg = double(T.root_code == "gg");
T.shock_target_10bp = T.shock_target / 10;
T.shock_target_x_gg = T.shock_target_10bp .* T.root_gg;
T.target_pca_x_gg = T.target_pca_10bp .* T.root_gg;
T.shock_pos_10bp = max(T.shock_target_10bp, 0);
T.shock_neg_mag_10bp = max(-T.shock_target_10bp, 0);
T.pos_pca_10bp = max(T.target_pca_10bp, 0);
T.neg_mag_pca_10bp = max(-T.target_pca_10bp, 0);
T.regime_fg = double(T.event_date >= datetime(2013, 7, 1));
T.regime_app = double(T.event_date >= datetime(2015, 3, 1) & T.event_date < datetime(2022, 7, 1));
T.regime_hike = double(T.event_date >= datetime(2022, 7, 1));
T.target_x_hike = T.shock_target_10bp .* T.regime_hike;

allMask = true(height(T), 1);
isFx = T.root_code == "fx";
isGg = T.root_code == "gg";
cl = "event_date";

specs = {};
specs{end+1} = mk("FR01_target_pooled", "PR_neg_share", ["shock_target_10bp", "root_gg"], allMask, cl);
specs{end+1} = mk("FR02_target_path_pooled", "PR_neg_share", ["target_pca_10bp", "path_pca_10bp", "root_gg"], allMask, cl);
specs{end+1} = mk("FR03_interaction_pooled", "PR_neg_share", ["shock_target_10bp", "root_gg", "shock_target_x_gg"], allMask, cl);
specs{end+1} = mk("FR04_asymmetry_pooled", "PR_neg_share", ["shock_pos_10bp", "shock_neg_mag_10bp", "root_gg"], allMask, cl);
specs{end+1} = mk("FR05_pca_asymmetry_pooled", "PR_neg_share", ["pos_pca_10bp", "neg_mag_pca_10bp", "root_gg"], allMask, cl);
specs{end+1} = mk("FR06_regime_hike", "PR_neg_share", ["shock_target_10bp", "regime_hike", "target_x_hike", "root_gg"], allMask, cl);
specs{end+1} = mk("FR07_target_fx", "PR_neg_share", ["shock_target_10bp"], isFx, cl);
specs{end+1} = mk("FR08_target_gg", "PR_neg_share", ["shock_target_10bp"], isGg, cl);
specs{end+1} = mk("FR09_asymmetry_fx", "PR_neg_share", ["shock_pos_10bp", "shock_neg_mag_10bp"], isFx, cl);
specs{end+1} = mk("FR10_asymmetry_gg", "PR_neg_share", ["shock_pos_10bp", "shock_neg_mag_10bp"], isGg, cl);

if hasOis
    specs{end+1} = mk("FR11_pca_fx", "PR_neg_share", ["target_pca_10bp", "path_pca_10bp"], isFx, cl);
    specs{end+1} = mk("FR12_pca_gg", "PR_neg_share", ["target_pca_10bp", "path_pca_10bp"], isGg, cl);
end

nSpec = numel(specs);
coefCell = cell(nSpec, 1);
modelCell = cell(nSpec, 1);
diagCell = cell(nSpec, 1);

for i = 1:nSpec
    s = specs{i};
    fprintf('[%2d/%2d] %s\n', i, nSpec, s.name);
    [coefCell{i}, modelCell{i}, diagCell{i}] = fractional_logit_cluster(T, s);
end

coefResults = sortrows(vertcat(coefCell{:}), {'model_name', 'term'});
modelResults = sortrows(vertcat(modelCell{:}), 'model_name');
diagResults = sortrows(vertcat(diagCell{:}), 'model_name');

coefFile = fullfile(analysisDir, 'pr_fractional_coefficients.csv');
modelFile = fullfile(analysisDir, 'pr_fractional_model_summary.csv');
diagFile = fullfile(analysisDir, 'pr_fractional_diagnostics.csv');

writetable(coefResults, coefFile);
writetable(modelResults, modelFile);
writetable(diagResults, diagFile);

fprintf('\n================ PR FRACTIONAL-RESPONSE MODELS ================\n');
fprintf('Models estimated : %d\n', height(modelResults));
fprintf('Coefficient rows : %d\n', height(coefResults));
fprintf('Coefficients     : %s\n', coefFile);
fprintf('Model summary    : %s\n', modelFile);
fprintf('Diagnostics      : %s\n', diagFile);
fprintf('================================================================\n');

keyTerms = ["shock_target_10bp", "target_pca_10bp", "path_pca_10bp", "shock_target_x_gg", "shock_pos_10bp", "shock_neg_mag_10bp", "pos_pca_10bp", "neg_mag_pca_10bp", "target_x_hike"];
idx = ismember(coefResults.term, keyTerms);

disp(coefResults(idx, {'model_name', 'term', 'beta', 'se_cluster', 'ape', 'ape_se', 'z_stat', 'p_value'}));

fprintf('\nDiagnostics:\n');
disp(diagResults(:, {'model_name', 'reset_p', 'wald_asym_p', 'qaic_like', 'pseudo_r2'}));

function s = mk(name, depvar, rhs, mask, clusterVar)

    s.name = string(name);
    s.depvar = string(depvar);
    s.rhs = string(rhs);
    s.mask = mask;
    s.clusterVar = string(clusterVar);
end

function [target_10bp, path_10bp] = gss_factor_extraction(T)

    evStr = string(T.event_date, 'yyyy-MM-dd');
    [g, uEv] = findgroups(evStr);
    nEv = numel(uEv);

    oisShort = "ois_1m_raw";
    oisPath = ["ois_6m_raw", "ois_1y_raw", "ois_2y_raw", "ois_3y_raw"];

    tgt_ev = splitapply(@first_nonmissing_num, T.(oisShort), g);
    tgt_ev(isnan(tgt_ev)) = 0;

    pathMat = nan(nEv, numel(oisPath));

    for j = 1:numel(oisPath)
        pathMat(:, j) = splitapply(@first_nonmissing_num, T.(oisPath(j)), g);
    end

    ok = all(~isnan(pathMat), 2);
    mu = mean(pathMat(ok, :), 1);
    sigma = std(pathMat(ok, :), 0, 1);
    sigma(sigma == 0) = 1;
    Zs = (pathMat(ok, :) - mu) ./ sigma;

    [~, ~, V] = svd(Zs, 'econ');

    pc1_raw = nan(nEv, 1);
    pc1_raw(ok) = Zs * V(:, 1);

    avgLong = mean(pathMat(ok, :), 2, 'omitnan');

    if corr(pc1_raw(ok), avgLong, 'rows', 'complete') < 0
        pc1_raw = -pc1_raw;
    end

    path_ev = nan(nEv, 1);
    ok2 = ok & ~isnan(tgt_ev);

    if sum(ok2) >= 5
        Xm = [ones(sum(ok2), 1), tgt_ev(ok2)];
        b = Xm \ pc1_raw(ok2);
        path_ev(ok2) = pc1_raw(ok2) - Xm * b;
    end

    target_10bp = tgt_ev(g) / 10;
    path_10bp = path_ev(g);

    if any(~isnan(path_10bp))
        sPath = std(path_10bp, 'omitnan');
        sTgt = std(target_10bp, 'omitnan');

        if isfinite(sPath) && sPath > 0 && isfinite(sTgt)
            path_10bp = path_10bp / sPath * sTgt;
        end
    end
end

function v = first_nonmissing_num(x)

    x = x(~isnan(x));

    if isempty(x)
        v = NaN;
    else
        v = x(1);
    end
end

function [coefTbl, modelTbl, diagTbl] = fractional_logit_cluster(T, s)

    y = T.(s.depvar);

    if isstring(y)
        y = str2double(y);
    end

    mask = s.mask & ~isnan(y) & y >= 0 & y <= 1;

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
    k = 1 + numel(s.rhs);

    X = ones(n, 1);
    termNames = strings(k, 1);
    termNames(1) = "Intercept";

    for j = 1:numel(s.rhs)
        v = s.rhs(j);
        x = T.(v);

        if isstring(x)
            x = str2double(x);
        end

        X = [X, x(mask)];
        termNames(j + 1) = v;
    end

    cl = cl(mask);

    if isdatetime(cl)
        clStr = string(cl, 'yyyy-MM-dd');
    else
        clStr = string(cl);
    end

    [clusters, ~] = findgroups(clStr);
    G = max(clusters);

    [beta, mu, ll, converged, nIter] = fit_frac_logit(X, y);
    [~, ~, ll0, ~, ~] = fit_frac_logit(ones(n, 1), y);

    pseudo_r2 = 1 - ll / ll0;

    Vc = cluster_vcov(X, y, mu, clusters, G);
    se = sqrt(diag(Vc));
    zstat = beta ./ se;
    pval = 2 * tcdf(-abs(zstat), max(G - 1, 1));

    [ape, ape_se, ape_type] = compute_ape_delta(X, beta, mu, Vc);

    reset_p = reset_test_frac(X, y, beta, clusters, G);
    wald_asym_p = wald_asymmetry_test(beta, Vc, termNames, G);
    qaic_like = -2 * ll + 2 * k;

    coefTbl = table();
    coefTbl.model_name = repmat(s.name, k, 1);
    coefTbl.depvar = repmat(s.depvar, k, 1);
    coefTbl.term = termNames;
    coefTbl.beta = beta;
    coefTbl.se_cluster = se;
    coefTbl.z_stat = zstat;
    coefTbl.p_value = pval;
    coefTbl.ape = ape;
    coefTbl.ape_se = ape_se;
    coefTbl.ape_type = ape_type;
    coefTbl.n_obs = repmat(n, k, 1);
    coefTbl.n_clusters = repmat(G, k, 1);
    coefTbl.pseudo_r2 = repmat(pseudo_r2, k, 1);

    modelTbl = table();
    modelTbl.model_name = s.name;
    modelTbl.depvar = s.depvar;
    modelTbl.rhs = strjoin(s.rhs, " + ");
    modelTbl.n_obs = n;
    modelTbl.n_clusters = G;
    modelTbl.n_params = k;
    modelTbl.loglik = ll;
    modelTbl.loglik_null = ll0;
    modelTbl.pseudo_r2 = pseudo_r2;
    modelTbl.qaic_like = qaic_like;
    modelTbl.converged = converged;
    modelTbl.n_iter = nIter;
    modelTbl.mean_depvar = mean(y, 'omitnan');
    modelTbl.sd_depvar = std(y, 'omitnan');
    modelTbl.mean_fitted = mean(mu, 'omitnan');

    diagTbl = table();
    diagTbl.model_name = s.name;
    diagTbl.reset_p = reset_p;
    diagTbl.wald_asym_p = wald_asym_p;
    diagTbl.qaic_like = qaic_like;
    diagTbl.pseudo_r2 = pseudo_r2;
    diagTbl.n_obs = n;
    diagTbl.n_clusters = G;
end

function [beta, mu, ll, converged, nIter] = fit_frac_logit(X, y)

    k = size(X, 2);
    beta = zeros(k, 1);
    converged = false;
    maxIter = 300;
    tol = 1e-10;
    nIter = 0;

    ll = frac_ll(y, sigm(X * beta));

    for it = 1:maxIter

        eta = X * beta;
        mu = sigm(eta);
        W = max(mu .* (1 - mu), 1e-12);

        score = X' * (y - mu);
        H = X' * (X .* W);
        step = (H + 1e-10 * eye(k)) \ score;
        betaNew = beta + step;
        llNew = frac_ll(y, sigm(X * betaNew));

        nh = 0;

        while llNew < ll && nh < 30
            step = step / 2;
            betaNew = beta + step;
            llNew = frac_ll(y, sigm(X * betaNew));
            nh = nh + 1;
        end

        if norm(betaNew - beta, inf) < tol * (1 + norm(beta, inf))
            beta = betaNew;
            ll = llNew;
            converged = true;
            nIter = it;
            break;
        end

        beta = betaNew;
        ll = llNew;
        nIter = it;
    end

    mu = sigm(X * beta);
end

function Vc = cluster_vcov(X, y, mu, clusters, G)

    n = size(X, 1);
    k = size(X, 2);

    W = max(mu .* (1 - mu), 1e-12);
    A = X' * (X .* W);
    Ainv = pinv(A);
    u = y - mu;

    B = zeros(k, k);

    for g = 1:G
        idx = clusters == g;
        sg = X(idx, :)' * u(idx);
        B = B + sg * sg';
    end

    dfc = 1;

    if G > 1 && n > k
        dfc = (G / (G - 1)) * ((n - 1) / (n - k));
    end

    Vc = dfc * (Ainv * B * Ainv);
end

function [ape, ape_se, ape_type] = compute_ape_delta(X, beta, mu, Vc)

    k = numel(beta);

    ape = nan(k, 1);
    ape_se = nan(k, 1);
    ape_type = strings(k, 1);
    ape_type(1) = "intercept";

    eta = X * beta;
    lam1 = mu .* (1 - mu);
    lam2 = lam1 .* (1 - 2 * mu);

    for j = 2:k

        xj = X(:, j);
        uvals = unique(xj(~isnan(xj)));
        isBin = all(ismember(uvals, [0 1])) && numel(uvals) <= 2;

        if isBin

            eta1 = eta + beta(j) * (1 - xj);
            eta0 = eta - beta(j) * xj;
            dmu = sigm(eta1) - sigm(eta0);
            ape(j) = mean(dmu);
            ape_type(j) = "discrete";

            lam1_1 = sigm(eta1) .* (1 - sigm(eta1));
            lam1_0 = sigm(eta0) .* (1 - sigm(eta0));

            dAPE_dbeta = zeros(k, 1);

            for l = 1:k
                if l == j
                    dAPE_dbeta(l) = mean(lam1_1 .* (1 - xj) + lam1_0 .* xj);
                else
                    dAPE_dbeta(l) = mean((lam1_1 - lam1_0) .* X(:, l));
                end
            end

        else

            ape(j) = mean(lam1) * beta(j);
            ape_type(j) = "marginal";

            dAPE_dbeta = zeros(k, 1);

            for l = 1:k
                dAPE_dbeta(l) = mean(lam2 .* beta(j) .* X(:, l));

                if l == j
                    dAPE_dbeta(l) = dAPE_dbeta(l) + mean(lam1);
                end
            end
        end

        ape_se(j) = sqrt(max(dAPE_dbeta' * Vc * dAPE_dbeta, 0));
    end
end

function p = reset_test_frac(X, y, beta, clusters, G)

    eta = X * beta;
    Xa = [X, eta.^2, eta.^3];

    k_a = size(Xa, 2);
    k_0 = size(X, 2);

    [beta_a, mu_a, ~, conv_a, ~] = fit_frac_logit(Xa, y);

    if ~conv_a
        p = NaN;
        return;
    end

    Vc_a = cluster_vcov(Xa, y, mu_a, clusters, G);

    idx_test = (k_0 + 1):k_a;
    R = zeros(numel(idx_test), k_a);

    for i = 1:numel(idx_test)
        R(i, idx_test(i)) = 1;
    end

    Rb = R * beta_a;
    RVR = R * Vc_a * R';
    W = Rb' * (pinv(RVR) * Rb);

    df = numel(idx_test);

    if G > 1
        F = W / df;
        p = 1 - fcdf(F, df, G - 1);
    else
        p = 1 - chi2cdf(W, df);
    end
end

function p = wald_asymmetry_test(beta, Vc, termNames, G)

    p = NaN;

    posTerms = ["shock_pos_10bp", "pos_pca_10bp"];
    negTerms = ["shock_neg_mag_10bp", "neg_mag_pca_10bp"];

    idxPos = NaN;
    idxNeg = NaN;

    for i = 1:numel(posTerms)

        ip = find(termNames == posTerms(i));
        in = find(termNames == negTerms(i));

        if ~isempty(ip) && ~isempty(in)
            idxPos = ip;
            idxNeg = in;
            break;
        end
    end

    if isnan(idxPos)
        return;
    end

    k = numel(beta);
    R = zeros(1, k);
    R(idxPos) = 1;
    R(idxNeg) = -1;

    Rb = R * beta;
    RVR = R * Vc * R';

    if RVR <= 0
        return;
    end

    W = Rb^2 / RVR;
    p = 2 * tcdf(-abs(sqrt(W)), max(G - 1, 1));
end

function ll = frac_ll(y, mu)

    eps0 = 1e-12;
    mu = min(max(mu, eps0), 1 - eps0);

    ll = sum(y .* log(mu) + (1 - y) .* log(1 - mu));
end

function m = sigm(z)

    z = max(min(z, 35), -35);
    m = 1 ./ (1 + exp(-z));
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
