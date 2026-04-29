%% STEP 9: STATE VECTOR PANEL.
%
% The code constructs the event-level state vector and merges it back into
% the PR-only long panel, starting from the PR signal panel produced in the
% previous step and aggregating selected variables at the ECB event-date level.
%
% The event-level state vector contains the target surprise, optional
% target-path PCA factors, pre-announcement realized-volatility states,
% pre-announcement downside-volatility states, pre-announcement absolute jump
% states, average PR outcomes and available OIS curve changes.
%
% The script also constructs monetary-policy regime indicators for the
% pre-APP period, the APP and negative-rate period, and the hiking phase.
% It then adds lagged target surprises, rolling memory measures, cumulative
% absolute surprises and within-regime cumulative target surprises.
%
% All main state variables are standardized using z-scores computed at the
% event level. These standardized states are then merged into the PR long
% panel and interacted with the monetary-policy target surprise. The resulting
% panel is the baseline dataset for the state-dependent regressions.
%
% Input file is Output/analysis/pr_signal_panel.csv, while outputs are
% Output/analysis/event_state_panel.csv and
% Output/analysis/pr_state_dependent_panel.csv.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

analysisDir = fullfile(projectRoot, 'Output', 'analysis');
signalFile = fullfile(analysisDir, 'pr_signal_panel.csv');

T = readtable(signalFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

T.event_date = parse_date_flex(T.event_date);
T.root_code = string(T.root_code);
T.event_id = string(T.event_id);

numVars = ["shock_target", "shock_target_10bp", "target_pca_10bp", "path_pca_10bp", "PR_abs_jump", "asinh_PR_rv", "asinh_PR_rsv_neg", "pre_PR_signed_jump", "pre_PR_abs_jump", "pre_PR_rv", "pre_PR_rsv_neg", "pre_asinh_PR_rv", "pre_asinh_PR_rsvneg", "ois_1m_raw", "ois_3m_raw", "ois_6m_raw", "ois_1y_raw", "ois_2y_raw", "ois_3y_raw", "ois_4y_raw", "ois_5y_raw", "ois_10y_raw"];

for v = numVars
    if ismember(v, string(T.Properties.VariableNames)) && ~isnumeric(T.(v))
        T.(v) = str2double(T.(v));
    end
end

if ~ismember("shock_target_10bp", string(T.Properties.VariableNames))
    T.shock_target_10bp = T.shock_target / 10;
end

T = T(~isnat(T.event_date), :);

evStr = string(T.event_date, 'yyyy-MM-dd');
[g, evKey] = findgroups(evStr);
nEv = numel(evKey);

E = table();
E.event_date = datetime(evKey, 'InputFormat', 'yyyy-MM-dd');
E.event_id = splitapply(@first_str, T.event_id, g);
E.shock_target_10bp = splitapply(@first_num, T.shock_target_10bp, g);
E.target_pca_10bp = get_event_num(T, g, "target_pca_10bp", nEv);
E.path_pca_10bp = get_event_num(T, g, "path_pca_10bp", nEv);
E.state_pre_rv = splitapply(@mean_nan, T.pre_asinh_PR_rv, g);
E.state_pre_rsvneg = splitapply(@mean_nan, T.pre_asinh_PR_rsvneg, g);
E.state_pre_absjump = splitapply(@mean_nan, T.pre_PR_abs_jump, g);
E.mean_PR_abs_jump = splitapply(@mean_nan, T.PR_abs_jump, g);
E.mean_asinh_PR_rv = splitapply(@mean_nan, T.asinh_PR_rv, g);
E.mean_asinh_PR_rsvneg = splitapply(@mean_nan, T.asinh_PR_rsv_neg, g);

oisVars = ["ois_1m_raw", "ois_3m_raw", "ois_6m_raw", "ois_1y_raw", "ois_2y_raw", "ois_3y_raw", "ois_4y_raw", "ois_5y_raw", "ois_10y_raw"];

for v = oisVars
    if ismember(v, string(T.Properties.VariableNames))
        E.(v) = splitapply(@first_num, T.(v), g);
    end
end

E.regime_preapp = double(E.event_date < datetime(2015, 3, 1));
E.regime_app = double(E.event_date >= datetime(2015, 3, 1) & E.event_date < datetime(2022, 7, 1));
E.regime_hike = double(E.event_date >= datetime(2022, 7, 1));
E = sortrows(E, 'event_date');

E.lag1_target_10bp = lagv(E.shock_target_10bp, 1);
E.lag2_target_10bp = lagv(E.shock_target_10bp, 2);
E.ma3_target_10bp = roll_mean_lag(E.shock_target_10bp, 3);
E.ma3_abs_target_10bp = roll_mean_lag(abs(E.shock_target_10bp), 3);
E.cumabs_target_10bp = roll_sum_lag(abs(E.shock_target_10bp), 3);
E.lag1_pre_rv_state = lagv(E.state_pre_rv, 1);
E.lag1_pre_rsvneg_state = lagv(E.state_pre_rsvneg, 1);
E.cum_target_within_regime_10bp = cum_regime(E.shock_target_10bp, regime_id(E));

zVars = ["shock_target_10bp", "target_pca_10bp", "path_pca_10bp", "state_pre_rv", "state_pre_rsvneg", "state_pre_absjump", "lag1_target_10bp", "ma3_target_10bp", "ma3_abs_target_10bp", "cumabs_target_10bp", "lag1_pre_rv_state", "lag1_pre_rsvneg_state", "cum_target_within_regime_10bp"];

for v = zVars
    E.(v + "_z") = znan(E.(v));
end

mergeVars = string(E.Properties.VariableNames);
mergeVars = mergeVars(~ismember(mergeVars, "event_id"));
dupVars = intersect(mergeVars, string(T.Properties.VariableNames));
dupVars = setdiff(dupVars, "event_date");
mergeVars = mergeVars(~ismember(mergeVars, dupVars));

Long = outerjoin(T, E(:, mergeVars), 'Keys', 'event_date', 'MergeKeys', true, 'Type', 'left');

Long.root_gg = double(Long.root_code == "gg");
Long.target_x_hike = Long.shock_target_10bp .* Long.regime_hike;
Long.target_x_preRV = Long.shock_target_10bp .* Long.state_pre_rv_z;
Long.target_x_memory = Long.shock_target_10bp .* Long.ma3_target_10bp_z;

eventStateFile = fullfile(analysisDir, 'event_state_panel.csv');
longStateFile = fullfile(analysisDir, 'pr_state_dependent_panel.csv');

writetable(format_event(E), eventStateFile);
writetable(format_long(Long), longStateFile);

fprintf('\n================ STATE VECTOR SUMMARY ================\n');
fprintf('Event-level rows : %d\n', height(E));
fprintf('Long-panel rows  : %d\n', height(Long));
fprintf('Event output     : %s\n', eventStateFile);
fprintf('Long output      : %s\n', longStateFile);
fprintf('======================================================\n');

function out = get_event_num(T, g, varName, nEv)

    if ismember(varName, string(T.Properties.VariableNames))
        out = splitapply(@first_num, T.(varName), g);
    else
        out = nan(nEv, 1);
    end
end

function xlag = lagv(x, L)

    xlag = nan(size(x));

    if numel(x) > L
        xlag((L + 1):end) = x(1:end - L);
    end
end

function m = roll_mean_lag(x, K)

    n = numel(x);
    m = nan(n, 1);

    for t = 1:n
        lo = max(1, t - K);
        hi = t - 1;

        if hi >= lo
            m(t) = mean(x(lo:hi), 'omitnan');
        end
    end
end

function s = roll_sum_lag(x, K)

    n = numel(x);
    s = nan(n, 1);

    for t = 1:n
        lo = max(1, t - K);
        hi = t - 1;

        if hi >= lo
            s(t) = sum(x(lo:hi), 'omitnan');
        end
    end
end

function gid = regime_id(E)

    gid = nan(height(E), 1);
    gid(E.regime_preapp == 1) = 1;
    gid(E.regime_app == 1) = 2;
    gid(E.regime_hike == 1) = 3;
end

function c = cum_regime(x, gid)

    c = nan(size(x));
    ug = unique(gid(~isnan(gid)));

    for j = 1:numel(ug)
        idx = find(gid == ug(j));
        vals = x(idx);
        c(idx) = [nan; cumsum(vals(1:end - 1), 'omitnan')];
    end
end

function z = znan(x)

    mu = mean(x, 'omitnan');
    sd = std(x, 0, 'omitnan');

    if ~isfinite(sd) || sd == 0
        z = nan(size(x));
    else
        z = (x - mu) ./ sd;
    end
end

function v = first_num(x)

    x = x(~isnan(x));

    if isempty(x)
        v = NaN;
    else
        v = x(1);
    end
end

function s = first_str(x)

    x = string(x);
    x = x(~ismissing(x) & strlength(strtrim(x)) > 0);

    if isempty(x)
        s = "";
    else
        s = x(1);
    end
end

function m = mean_nan(x)

    m = mean(x, 'omitnan');
end

function T = format_event(T)

    T.event_date = string(T.event_date, 'yyyy-MM-dd');
end

function T = format_long(T)

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
