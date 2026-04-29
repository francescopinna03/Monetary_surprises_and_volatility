%% STEP 5: PRESS RELEASE BASELINE PANEL.
%
% Here is built the baseline press-release panel used in the first
% empirical layer of the project. The code starts from the wide event-window panel
% produced in the previous step and keeps only PR windows that satisfy the
% event-window eligibility criteria.
%
% The script constructs baseline realized-measure variables for the PR window, 
% which include log realized variance, log positive and negative realized
% semivariance, absolute and signed PR returns, the negative and positive
% semivariance shares, the semivariance imbalance and the positive-to-negative
% semivariance ratio.
%
% The script then merges the PR event-window panel with the EA-MPD monetary
% policy surprise dataset. The merge is performed at the event-date level.
% EA-MPD variables are prefixed with eampd_, while selected OIS changes are
% also copied into canonical columns such as ois_1m_raw, ois_2y_raw and
% ois_5y_raw. The one-month OIS change is used as the baseline target
% surprise whenever available.
%
% The resulting dataset is the baseline PR-level analysis panel, which provides
% the link between intraday realized volatility measures and high-frequency
% monetary policy surprises, and it is used by the fractional-response models,
% the PR signal regressions and the later state-dependent specifications.
%
% Input files are Output/event_windows/event_window_panel.csv and the EA-MPD
% dataset located in Raw/EA_MPD when available. Output files are
% Output/analysis/pr_baseline_panel.csv and
% Output/analysis/pr_baseline_match_summary.csv.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

windowDir = fullfile(projectRoot, 'Output', 'event_windows');
analysisDir = fullfile(projectRoot, 'Output', 'analysis');
panelFile = fullfile(windowDir, 'event_window_panel.csv');

if ~exist(analysisDir, 'dir'); mkdir(analysisDir); end

eampdCandidates = cell(6, 1);
eampdCandidates{1} = fullfile(projectRoot, 'Raw', 'EA_MPD', 'Dataset_EA-MPD.xlsx');
eampdCandidates{2} = fullfile(projectRoot, 'Raw', 'EA_MPD', 'Dataset_EA_MPD.xlsx');
eampdCandidates{3} = fullfile(projectRoot, 'Raw', 'EA_MPD', 'EA_MPD_clean.csv');
eampdCandidates{4} = fullfile(projectRoot, 'Raw', 'EA_MPD', 'ea_mpd_clean.csv');
eampdCandidates{5} = fullfile(projectRoot, 'Raw', 'EA_MPD', 'Dataset_EA-MPD.csv');
eampdCandidates{6} = fullfile(projectRoot, 'Raw', 'EA_MPD', 'Dataset_EA_MPD.csv');

eampdFile = locate_first_existing(eampdCandidates);

P = readtable(panelFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');

requiredVars = ["event_date", "trade_date", "event_id", "root_code", "file_name_clean", "expiry_code", "contract_year", "pr_datetime_local", "pc_datetime_local", "PR_n_obs_bars", "PR_pct_expected_bars", "PR_share_low_volume", "PR_max_gap_minutes", "PR_window_eligible", "PR_rv", "PR_rsv_pos", "PR_rsv_neg", "PR_net_log_return"];
missingVars = requiredVars(~ismember(requiredVars, string(P.Properties.VariableNames)));

if ~isempty(missingVars)
    error('Mancano colonne in event_window_panel.csv: %s', strjoin(missingVars, ', '));
end

P.event_date = parse_date_flex(P.event_date);
P.trade_date = parse_date_flex(P.trade_date);
P.pr_datetime_local = parse_datetime_flex(P.pr_datetime_local);
P.pc_datetime_local = parse_datetime_flex(P.pc_datetime_local);
P.root_code = string(P.root_code);
P.file_name_clean = string(P.file_name_clean);
P.event_id = string(P.event_id);
P.expiry_code = string(P.expiry_code);

numVars = ["contract_year", "PR_n_obs_bars", "PR_pct_expected_bars", "PR_share_low_volume", "PR_max_gap_minutes", "PR_rv", "PR_rsv_pos", "PR_rsv_neg", "PR_net_log_return"];

for v = numVars
    if ~isnumeric(P.(v))
        P.(v) = str2double(P.(v));
    end
end

if ~islogical(P.PR_window_eligible)
    P.PR_window_eligible = string_to_bool(P.PR_window_eligible);
end

PR = P(P.PR_window_eligible, :);

if isempty(PR)
    error('Nessuna finestra PR eleggibile trovata nel pannello.');
end

PR.log_PR_rv = safe_log(PR.PR_rv);
PR.log_PR_rsv_pos = safe_log(PR.PR_rsv_pos);
PR.log_PR_rsv_neg = safe_log(PR.PR_rsv_neg);
PR.PR_abs_net_return = abs(PR.PR_net_log_return);
PR.PR_signed_jump = PR.PR_net_log_return;

PR.PR_neg_share = nan(height(PR), 1);
PR.PR_pos_share = nan(height(PR), 1);

okRV = PR.PR_rv > 0 & ~isnan(PR.PR_rv);

PR.PR_neg_share(okRV) = PR.PR_rsv_neg(okRV) ./ PR.PR_rv(okRV);
PR.PR_pos_share(okRV) = PR.PR_rsv_pos(okRV) ./ PR.PR_rv(okRV);

PR.PR_semivariance_imbalance = PR.PR_rsv_pos - PR.PR_rsv_neg;
PR.PR_semivariance_ratio = nan(height(PR), 1);

okNeg = PR.PR_rsv_neg > 0 & ~isnan(PR.PR_rsv_neg);

PR.PR_semivariance_ratio(okNeg) = PR.PR_rsv_pos(okNeg) ./ PR.PR_rsv_neg(okNeg);
PR.analysis_sample = repmat("PR_baseline", height(PR), 1);

if strlength(eampdFile) > 0

    fprintf('Reading EA-MPD from:\n%s\n\n', eampdFile);

    E = load_eampd_file(eampdFile);

    PR = outerjoin(PR, E, 'Keys', 'event_date', 'MergeKeys', true, 'Type', 'left');

    hasAnyEA = rows_with_eampd_data(PR);

    matchSummary = table();
    matchSummary.eampd_file = string(eampdFile);
    matchSummary.n_pr_rows = height(PR);
    matchSummary.n_rows_matched = sum(hasAnyEA);
    matchSummary.n_rows_unmatched = sum(~hasAnyEA);
    matchSummary.match_rate = mean(hasAnyEA);

else

    warning('EA-MPD non trovato: pannello PR senza merge shock.');

    matchSummary = table();
    matchSummary.eampd_file = "";
    matchSummary.n_pr_rows = height(PR);
    matchSummary.n_rows_matched = 0;
    matchSummary.n_rows_unmatched = height(PR);
    matchSummary.match_rate = 0;
end

PR = sortrows(PR, {'event_date', 'root_code'});

panelOutFile = fullfile(analysisDir, 'pr_baseline_panel.csv');
matchOutFile = fullfile(analysisDir, 'pr_baseline_match_summary.csv');

writetable(format_pr_panel_for_write(PR), panelOutFile);
writetable(matchSummary, matchOutFile);

fprintf('\n================ PR BASELINE PANEL SUMMARY ================\n');
fprintf('PR-eligible rows              : %d\n', height(PR));
fprintf('Distinct event dates          : %d\n', numel(unique(PR.event_date)));
fprintf('Distinct root families        : %d\n', numel(unique(PR.root_code)));
fprintf('Mean PR coverage              : %.4f\n', mean(PR.PR_pct_expected_bars, 'omitnan'));
fprintf('Mean PR low-volume share      : %.4f\n', mean(PR.PR_share_low_volume, 'omitnan'));
fprintf('Mean |PR return|              : %.6f\n', mean(PR.PR_abs_net_return, 'omitnan'));
fprintf('Output panel                  : %s\n', panelOutFile);
fprintf('Output match summary          : %s\n', matchOutFile);
fprintf('===========================================================\n');

fprintf('\nCoverage by root:\n');
disp(groupsummary(PR, 'root_code', 'mean', {'PR_pct_expected_bars', 'PR_share_low_volume', 'PR_abs_net_return', 'PR_rv'}));

if ismember("shock_target", string(PR.Properties.VariableNames))

    fprintf('\nTop 10 PR windows by |shock_target|:\n');

    tmp = PR;
    tmp.abs_shock_target = abs(tmp.shock_target);
    tmp = sortrows(tmp, 'abs_shock_target', 'descend');

    disp(tmp(1:min(10, height(tmp)), {'event_date', 'root_code', 'shock_target', 'PR_signed_jump', 'PR_rv', 'PR_rsv_pos', 'PR_rsv_neg'}));
end

oisCols = ["ois_1m_raw", "ois_3m_raw", "ois_6m_raw", "ois_1y_raw", "ois_2y_raw", "ois_5y_raw"];
presentOis = oisCols(ismember(oisCols, string(PR.Properties.VariableNames)));

if ~isempty(presentOis)

    fprintf('\nOIS canonical columns found: %s\n', strjoin(presentOis, ', '));

    for c = presentOis
        fprintf('%-14s non-missing: %d / %d\n', c, sum(~isnan(PR.(c))), height(PR));
    end
end

function pathOut = locate_first_existing(candidates)

    pathOut = "";

    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file')
            pathOut = string(candidates{i});
            return;
        end
    end
end

function flag = rows_with_eampd_data(T)

    flag = false(height(T), 1);
    cols = string(T.Properties.VariableNames);
    cols = cols(startsWith(cols, "eampd_"));

    for c = cols

        col = T.(c);

        if isnumeric(col)
            flag = flag | ~isnan(col);
        else
            flag = flag | ~ismissing(col);
        end
    end
end

function E = load_eampd_file(eampdFile)

    [~, ~, ext] = fileparts(eampdFile);

    if strcmpi(ext, '.xlsx') || strcmpi(ext, '.xls')
        T = read_first_valid_sheet(eampdFile);
    else
        T = readtable(eampdFile, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    end

    names = string(T.Properties.VariableNames);
    dateVar = find_col(names, ["event_date", "date", "Date", "meeting_date", "meetingday", "meeting_day", "govc_date", "eventday", "date_meeting"]);

    if strlength(dateVar) == 0
        error('Colonna data non trovata in EA-MPD.');
    end

    E = table();
    E.event_date = parse_date_flex(T.(dateVar));

    for col = names(names ~= dateVar)
        newName = matlab.lang.makeValidName("eampd_" + col);
        E.(newName) = coerce_column(T.(col));
    end

    E = E(~isnat(E.event_date), :);
    E = sortrows(E, 'event_date');

    [~, ia] = unique(E.event_date, 'stable');
    E = E(ia, :);

    E = add_canonical_ois_columns(E);

    if ismember("ois_1m_raw", string(E.Properties.VariableNames))
        E.shock_target = E.ois_1m_raw;
    end

    longCols = ["ois_2y_raw", "ois_3y_raw", "ois_5y_raw"];
    availLong = longCols(ismember(longCols, string(E.Properties.VariableNames)));

    if ~isempty(availLong)
        E.shock_path_proxy_mean = row_mean(E, availLong);
    end

    medCols = ["ois_6m_raw", "ois_1y_raw", "ois_2y_raw"];
    availMed = medCols(ismember(medCols, string(E.Properties.VariableNames)));

    if ~isempty(availMed)
        E.shock_path_proxy_med = row_mean(E, availMed);
    end
end

function E = add_canonical_ois_columns(E)

    names = string(E.Properties.VariableNames);
    normNames = normalize_names(names);

    outNames = ["ois_1m_raw", "ois_3m_raw", "ois_6m_raw", "ois_1y_raw", "ois_2y_raw", "ois_3y_raw", "ois_4y_raw", "ois_5y_raw", "ois_10y_raw"];

    patterns = cell(numel(outNames), 1);
    patterns{1} = ["ois_1m", "ois1m", "ois_01m"];
    patterns{2} = ["ois_3m", "ois3m"];
    patterns{3} = ["ois_6m", "ois6m"];
    patterns{4} = ["ois_1y", "ois1y"];
    patterns{5} = ["ois_2y", "ois2y"];
    patterns{6} = ["ois_3y", "ois3y"];
    patterns{7} = ["ois_4y", "ois4y"];
    patterns{8} = ["ois_5y", "ois5y"];
    patterns{9} = ["ois_10y", "ois10y"];

    for k = 1:numel(outNames)

        idx = find_any_pattern(normNames, patterns{k});

        if ~isempty(idx)
            E.(outNames(k)) = to_numeric_vector(E.(names(idx(1))));
        end
    end
end

function idx = find_any_pattern(normNames, patterns)

    idx = [];

    for p = 1:numel(patterns)

        hit = find(normNames == patterns(p), 1);

        if ~isempty(hit)
            idx = hit;
            return;
        end
    end
end

function out = normalize_names(names)

    out = lower(string(names));
    out = regexprep(out, '^eampd_', '');
    out = regexprep(out, '[^a-z0-9]+', '_');
    out = regexprep(out, '_+', '_');
    out = regexprep(out, '^_|_$', '');
end

function v = row_mean(T, cols)

    X = nan(height(T), numel(cols));

    for j = 1:numel(cols)
        X(:, j) = to_numeric_vector(T.(cols(j)));
    end

    v = mean(X, 2, 'omitnan');
end

function T = read_first_valid_sheet(fpath)

    sh = sheetnames(fpath);

    for i = 1:numel(sh)

        try

            T = readtable(fpath, 'Sheet', sh{i}, 'TextType', 'string', 'VariableNamingRule', 'preserve');

            if width(T) >= 2
                return;
            end

        catch
        end
    end

    error('Nessun foglio utile in %s', fpath);
end

function col = coerce_column(col)

    if isnumeric(col)
        return;
    end

    num = str2double(string(col));

    if sum(~isnan(num)) >= max(3, round(0.5 * numel(num)))
        col = num;
    else
        col = string(col);
    end
end

function x = to_numeric_vector(x)

    if isnumeric(x)
        return;
    end

    x = str2double(string(x));
end

function out = find_col(allNames, candidates)

    out = "";
    a = lower(allNames);

    for c = lower(candidates)

        idx = find(a == c, 1);

        if ~isempty(idx)
            out = allNames(idx);
            return;
        end
    end
end

function y = safe_log(x)

    y = nan(size(x));
    ok = ~isnan(x) & x > 0;
    y(ok) = log(x(ok));
end

function T = format_pr_panel_for_write(T)

    if isempty(T)
        return;
    end

    for c = ["event_date", "trade_date"]

        if ismember(c, string(T.Properties.VariableNames))
            T.(c) = string(T.(c), 'yyyy-MM-dd');
        end
    end

    for c = ["pr_datetime_local", "pc_datetime_local"]

        if ismember(c, string(T.Properties.VariableNames))
            T.(c) = string(T.(c), 'yyyy-MM-dd HH:mm');
        end
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

function y = string_to_bool(x)

    x = lower(strtrim(string(x)));
    y = x == "true" | x == "1";
end
