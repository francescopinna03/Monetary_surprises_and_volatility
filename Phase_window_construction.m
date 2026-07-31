%% PHASE WINDOWS: NON-OVERLAPPING PR, PC AND MONETARY-EVENT OUTCOMES.
%
% This extension leaves the legacy Step-5 files unchanged. It converts every
% cleaned provider timestamp to a certified interval-end UTC time and builds:
%   PR: fixed 25-minute response after the rate decision;
%   PC: fixed 45-minute response after the press-conference start;
%   ME: rate decision through 45 minutes after the press-conference start.
%
% PR ends at least five minutes before PC in both calendar regimes. Phase
% clocks are scheduled ex ante; realized volume never selects a window.

projectRoot = Get_project_root();
Require_time_alignment_manifest(projectRoot);
semanticsManifest = Require_window_semantics_manifest(projectRoot);
barSemantics = semanticsManifest.bar_label_semantics(1);

cleanDir = fullfile(projectRoot, 'Output', 'cleaned');
diagnosticsDir = fullfile(projectRoot, 'Output', 'diagnostics');
phaseDir = fullfile(projectRoot, 'Output', 'phase_windows');
manifestDir = fullfile(projectRoot, 'Output', 'manifests');
preferredFile = fullfile(diagnosticsDir, 'preferred_contract_by_event.csv');
if exist(phaseDir, 'dir') ~= 7; mkdir(phaseDir); end

if exist(preferredFile, 'file') ~= 2
    error('PHASE_WINDOWS_INPUT_MISSING: %s', preferredFile);
end

P = readtable(preferredFile, 'TextType', 'string', ...
    'VariableNamingRule', 'preserve');
required = ["event_date", "event_id", "root_code", "file_name_clean", ...
    "pr_datetime_local", "pc_datetime_local", "pr_datetime_utc", ...
    "pc_datetime_utc", "prelim_eligible"];
missing = required(~ismember(required, string(P.Properties.VariableNames)));
if ~isempty(missing)
    error('PHASE_WINDOWS_COLUMNS_MISSING: %s', strjoin(missing, ', '));
end

P.event_date = Parse_date_flexible(P.event_date);
P.pr_datetime_local = Parse_datetime_flexible(P.pr_datetime_local);
P.pc_datetime_local = Parse_datetime_flexible(P.pc_datetime_local);
P.pr_datetime_utc = Parse_utc_datetime(P.pr_datetime_utc);
P.pc_datetime_utc = Parse_utc_datetime(P.pc_datetime_utc);
P.event_id = string(P.event_id);
P.root_code = lower(string(P.root_code));
P.file_name_clean = string(P.file_name_clean);
if ~islogical(P.prelim_eligible)
    P.prelim_eligible = String_to_boolean(P.prelim_eligible);
end
P = P(P.prelim_eligible & ~isnat(P.pr_datetime_utc) & ...
    ~isnat(P.pc_datetime_utc), :);

cfg = struct();
cfg.barMinutes = 5;
cfg.minimumCoverage = 0.80;
cfg.minimumReturns = 5;
cfg.prPreEndpoints = -55:5:-5;
cfg.prPostEndpoints = 5:5:25;
cfg.pcPreEndpoints = -25:5:-5;
cfg.pcPostEndpoints = 5:5:45;
cfg.mePostAfterPcMinutes = 45;

uniqueFiles = unique(P.file_name_clean);
fileCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
for i = 1:numel(uniqueFiles)
    name = char(uniqueFiles(i));
    filePath = fullfile(cleanDir, name);
    if exist(filePath, 'file') ~= 2
        warning('PHASE_WINDOWS_CLEANED_FILE_MISSING: %s', filePath);
        continue;
    end
    fileCache(name) = read_cleaned(filePath, cfg.barMinutes, barSemantics);
end

summaryCells = cell(height(P) * 3, 1);
returnCells = cell(height(P) * 3, 1);
overlapCells = cell(height(P), 1);
cursor = 0;

for i = 1:height(P)
    fileName = char(P.file_name_clean(i));
    if ~isKey(fileCache, fileName)
        continue;
    end
    C = fileCache(fileName);
    phaseDefinitions = define_phases(P(i, :), cfg);
    overlapCells{i} = overlap_audit(P(i, :), phaseDefinitions);

    for j = 1:height(phaseDefinitions)
        cursor = cursor + 1;
        [summaryCells{cursor}, returnCells{cursor}] = measure_phase( ...
            C, P(i, :), phaseDefinitions(j, :), cfg, barSemantics);
    end
end

if cursor == 0
    error('PHASE_WINDOWS_EMPTY: no event-contract phase windows were constructed.');
end

phaseSummary = vertcat(summaryCells{1:cursor});
phaseReturns = vertcat(returnCells{1:cursor});
overlapAudit = vertcat(overlapCells{~cellfun(@isempty, overlapCells)});

if any(overlapAudit.pr_pc_overlap_minutes > 0)
    error('PHASE_WINDOWS_OVERLAP: PR and PC response intervals overlap.');
end

phaseSummary = sortrows(phaseSummary, {'event_date', 'root_code', 'phase'});
phaseReturns = sortrows(phaseReturns, ...
    {'event_date', 'root_code', 'phase', 'segment', 'return_endpoint_utc'});

writetable(format_dates(phaseSummary), fullfile(phaseDir, ...
    'phase_window_summary.csv'));
writetable(format_dates(phaseReturns), fullfile(phaseDir, ...
    'phase_window_returns.csv'));
writetable(format_dates(overlapAudit), fullfile(phaseDir, ...
    'phase_window_overlap_audit.csv'));

manifest = table();
manifest.schema_version = "phase_windows_v1";
manifest.status = "complete";
manifest.bar_label_semantics = barSemantics;
manifest.canonical_bar_time = "interval_end_utc";
manifest.pr_response_endpoints_minutes = strjoin(string(cfg.prPostEndpoints), ',');
manifest.pc_response_endpoints_minutes = strjoin(string(cfg.pcPostEndpoints), ',');
manifest.me_response_end = "pc_start_plus_45_minutes";
manifest.minimum_coverage = cfg.minimumCoverage;
manifest.minimum_returns = cfg.minimumReturns;
manifest.n_summary_rows = height(phaseSummary);
manifest.n_eligible_rows = sum(phaseSummary.window_eligible);
manifest.n_distinct_events = numel(unique(phaseSummary.event_date));
manifest.preferred_contract_sha256 = File_sha256(preferredFile);
manifest.window_semantics_sha256 = File_sha256(fullfile(manifestDir, ...
    'window_semantics_manifest.csv'));
manifest.generated_at_utc = string(datetime('now', 'TimeZone', 'UTC'), ...
    'yyyy-MM-dd HH:mm:ss');
writetable(manifest, fullfile(manifestDir, 'phase_windows_manifest.csv'));

fprintf('\n================ PHASE WINDOW CONSTRUCTION ================\n');
fprintf('Summary rows       : %d\n', height(phaseSummary));
fprintf('Eligible rows      : %d\n', sum(phaseSummary.window_eligible));
fprintf('Distinct events    : %d\n', numel(unique(phaseSummary.event_date)));
fprintf('PR-PC max overlap  : %.1f minutes\n', ...
    max(overlapAudit.pr_pc_overlap_minutes));
fprintf('Output directory   : %s\n', phaseDir);
fprintf('===========================================================\n');

function C = read_cleaned(filePath, barMinutes, barSemantics)
    T = readtable(filePath, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    required = ["Time", "Latest", "Volume"];
    missing = required(~ismember(required, string(T.Properties.VariableNames)));
    if ~isempty(missing)
        error('PHASE_WINDOWS_CLEANED_COLUMNS: %s missing %s.', ...
            filePath, strjoin(missing, ', '));
    end
    if ~isnumeric(T.Latest); T.Latest = str2double(T.Latest); end
    if ~isnumeric(T.Volume); T.Volume = str2double(T.Volume); end
    C = table();
    C.bar_end_utc = Canonical_bar_end_time(T.Time, barMinutes, barSemantics);
    C.price = double(T.Latest);
    C.volume = double(T.Volume);
    valid = ~isnat(C.bar_end_utc) & isfinite(C.price) & C.price > 0;
    C = sortrows(C(valid, :), 'bar_end_utc');
    [~, keep] = unique(C.bar_end_utc, 'last');
    C = C(sort(keep), :);
end

function D = define_phases(row, cfg)
    gap = minutes(row.pc_datetime_utc - row.pr_datetime_utc);
    if ~isfinite(gap) || gap < 30
        error('PHASE_WINDOWS_CLOCK_GAP: invalid PR-PC gap for %s.', ...
            string(row.event_date, 'yyyy-MM-dd'));
    end

    D = table();
    D.phase = ["PR"; "PC"; "ME"];
    D.anchor_local = [row.pr_datetime_local; row.pc_datetime_local; ...
        row.pr_datetime_local];
    D.anchor_utc = [row.pr_datetime_utc; row.pc_datetime_utc; ...
        row.pr_datetime_utc];
    D.pre_start_endpoint = [-55; -25; -55];
    D.pre_end_endpoint = [-5; -5; -5];
    D.post_start_endpoint = [cfg.prPostEndpoints(1); ...
        cfg.pcPostEndpoints(1); cfg.barMinutes];
    D.post_end_endpoint = [cfg.prPostEndpoints(end); ...
        cfg.pcPostEndpoints(end); gap + cfg.mePostAfterPcMinutes];
    D.pr_pc_gap_minutes = repmat(gap, 3, 1);
end

function O = overlap_audit(row, D)
    pr = D(D.phase == "PR", :);
    pc = D(D.phase == "PC", :);
    prStart = pr.anchor_utc;
    prEnd = pr.anchor_utc + minutes(pr.post_end_endpoint);
    pcStart = pc.anchor_utc;
    pcEnd = pc.anchor_utc + minutes(pc.post_end_endpoint);
    overlap = max(0, minutes(min(prEnd, pcEnd) - max(prStart, pcStart)));

    O = table();
    O.event_date = row.event_date;
    O.root_code = row.root_code;
    O.pr_start_utc = prStart;
    O.pr_end_utc = prEnd;
    O.pc_start_utc = pcStart;
    O.pc_end_utc = pcEnd;
    O.pr_pc_gap_minutes = minutes(pcStart - prStart);
    O.pr_pc_buffer_minutes = minutes(pcStart - prEnd);
    O.pr_pc_overlap_minutes = overlap;
end

function [S, R] = measure_phase(C, row, D, cfg, barSemantics)
    preEndpoints = transpose(D.anchor_utc + ...
        minutes(D.pre_start_endpoint:cfg.barMinutes:D.pre_end_endpoint));
    postEndpoints = transpose(D.anchor_utc + ...
        minutes(D.post_start_endpoint:cfg.barMinutes:D.post_end_endpoint));

    [preReturns, preVolume, prePresent] = returns_on_grid(C, preEndpoints, cfg.barMinutes);
    [postReturns, postVolume, postPresent] = returns_on_grid(C, postEndpoints, cfg.barMinutes);
    preVariation = variation_components(preReturns, cfg.minimumReturns);
    postVariation = variation_components(postReturns, cfg.minimumReturns);

    preCoverage = mean(prePresent);
    postCoverage = mean(postPresent);
    preEligible = preCoverage >= cfg.minimumCoverage && ...
        sum(isfinite(preReturns)) >= cfg.minimumReturns && isfinite(preVariation.BV);
    postEligible = postCoverage >= cfg.minimumCoverage && ...
        sum(isfinite(postReturns)) >= cfg.minimumReturns && isfinite(postVariation.BV);

    S = table();
    S.event_date = row.event_date;
    S.event_id = row.event_id;
    S.root_code = row.root_code;
    S.file_name_clean = row.file_name_clean;
    S.phase = D.phase;
    S.anchor_local = D.anchor_local;
    S.anchor_utc = D.anchor_utc;
    S.bar_label_semantics = barSemantics;
    S.canonical_bar_time = "interval_end_utc";
    S.pr_pc_gap_minutes = D.pr_pc_gap_minutes;
    S.pre_start_endpoint_minutes = D.pre_start_endpoint;
    S.pre_end_endpoint_minutes = D.pre_end_endpoint;
    S.post_start_endpoint_minutes = D.post_start_endpoint;
    S.post_end_endpoint_minutes = D.post_end_endpoint;
    S.n_pre_expected = numel(preEndpoints);
    S.n_post_expected = numel(postEndpoints);
    S.n_pre_returns = sum(isfinite(preReturns));
    S.n_post_returns = sum(isfinite(postReturns));
    S.pre_coverage = preCoverage;
    S.post_coverage = postCoverage;
    S.pre_volume = sum(preVolume, 'omitnan');
    S.post_volume = sum(postVolume, 'omitnan');
    S.pre_eligible = preEligible;
    S.post_eligible = postEligible;
    S.window_eligible = preEligible && postEligible;
    S.RV_pre = preVariation.RV;
    S.BV_pre = preVariation.BV;
    S.JV_pre = preVariation.JV;
    S.jump_share_pre = preVariation.jumpShare;
    S.RV_post = postVariation.RV;
    S.BV_post = postVariation.BV;
    S.JV_post = postVariation.JV;
    S.jump_share_post = postVariation.jumpShare;
    S.RV_post_per_return = postVariation.RV / max(S.n_post_returns, 1);
    S.BV_post_per_return = postVariation.BV / max(S.n_post_returns, 1);
    S.log_RV_post_per_return = positive_log(S.RV_post_per_return);
    S.log_BV_post_per_return = positive_log(S.BV_post_per_return);
    S.net_return_post = sum(postReturns, 'omitnan');

    Rpre = return_rows(row, D, "pre", preEndpoints, preReturns, ...
        preVolume, prePresent, barSemantics);
    Rpost = return_rows(row, D, "post", postEndpoints, postReturns, ...
        postVolume, postPresent, barSemantics);
    R = [Rpre; Rpost];
end

function [returns, volumes, present] = returns_on_grid(C, endpoints, barMinutes)
    previous = endpoints - minutes(barMinutes);
    [hasCurrent, currentLoc] = ismember(endpoints, C.bar_end_utc);
    [hasPrevious, previousLoc] = ismember(previous, C.bar_end_utc);
    present = hasCurrent & hasPrevious;
    returns = nan(numel(endpoints), 1);
    volumes = nan(numel(endpoints), 1);
    if any(present)
        currentPrice = C.price(currentLoc(present));
        previousPrice = C.price(previousLoc(present));
        good = isfinite(currentPrice) & isfinite(previousPrice) & ...
            currentPrice > 0 & previousPrice > 0;
        positions = find(present);
        returns(positions(good)) = log(currentPrice(good)) - log(previousPrice(good));
        volumes(positions) = C.volume(currentLoc(present));
    end
end

function V = variation_components(r, minimumReturns)
    V = struct('RV', NaN, 'BV', NaN, 'JV', NaN, 'jumpShare', NaN);
    valid = isfinite(r);
    if sum(valid) < minimumReturns
        return;
    end
    V.RV = sum(r(valid).^2);
    adjacent = isfinite(r(2:end)) & isfinite(r(1:end-1));
    if sum(adjacent) < max(minimumReturns - 1, 1)
        return;
    end
    products = abs(r(2:end)) .* abs(r(1:end-1));
    V.BV = (pi / 2) * sum(products(adjacent));
    V.JV = max(V.RV - V.BV, 0);
    if V.RV > 0
        V.jumpShare = V.JV / V.RV;
    end
end

function R = return_rows(row, D, segment, endpoints, returns, volumes, present, semantics)
    n = numel(endpoints);
    R = table();
    R.event_date = repmat(row.event_date, n, 1);
    R.event_id = repmat(row.event_id, n, 1);
    R.root_code = repmat(row.root_code, n, 1);
    R.file_name_clean = repmat(row.file_name_clean, n, 1);
    R.phase = repmat(D.phase, n, 1);
    R.segment = repmat(string(segment), n, 1);
    R.anchor_utc = repmat(D.anchor_utc, n, 1);
    R.return_endpoint_utc = endpoints;
    R.relative_endpoint_minutes = minutes(endpoints - D.anchor_utc);
    R.log_return = returns;
    R.volume = volumes;
    R.exact_return_pair = present;
    R.bar_label_semantics = repmat(string(semantics), n, 1);
end

function y = positive_log(x)
    if isfinite(x) && x > 0
        y = log(x);
    else
        y = NaN;
    end
end

function T = format_dates(T)
    variables = string(T.Properties.VariableNames);
    for variable = variables
        if isdatetime(T.(variable))
            if variable == "event_date"
                T.(variable) = string(T.(variable), 'yyyy-MM-dd');
            else
                T.(variable) = string(T.(variable), 'yyyy-MM-dd HH:mm:ss');
            end
        end
    end
end
