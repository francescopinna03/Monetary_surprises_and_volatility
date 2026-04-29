%% STEP 1: AUDIT OF BARCHART FILES.
%
% The file scans Raw/Barchart_futures/*.csv and constructs a file-level
% manifest for all raw intraday futures contracts used in the project. The
% audit checks whether filenames follow the expected Barchart convention,
% extracts contract metadata such as root code, expiry code, contract year,
% bar frequency and download date, and verifies the basic structure of each
% file.
%
% The checks include header consistency, presence of the Barchart footer,
% number of data rows, first and last timestamps, timestamp ordering,
% duplicated timestamps, non-parsable datetimes, missing core fields,
% non-positive prices, negative volumes and internal OHLC consistency. The
% script also builds a coverage table over the expected contract grid by
% root, expiry and year.
%
% For this project, the raw data consist of 104 Barchart intraday files
% sampled at 5-minute frequency. These files cover the futures contracts
% used to construct event-window realized volatility measures over the
% 2013-2025 ECB monetary policy sample.
%
% Output files are Output/manifests/raw_manifest_barchart.csv, Output/manifests/coverage_barchart.csv
% and Output/diagnostics/raw_audit_flags.csv.
%
% The directory indicated below is purely indicative.

clear; clc;

projectRoot = '/Users/francescopinna/Desktop/Econometrics_data';

rawDir = fullfile(projectRoot, 'Raw', 'Barchart_futures');
manifestDir = fullfile(projectRoot, 'Output', 'manifests');
diagDir = fullfile(projectRoot, 'Output', 'diagnostics');

if ~exist(manifestDir, 'dir'); mkdir(manifestDir); end
if ~exist(diagDir, 'dir'); mkdir(diagDir); end

files = dir(fullfile(rawDir, '*.csv'));
files = files(~[files.isdir]);
nFiles = numel(files);

fprintf('Found %d raw CSV files.\n', nFiles);

file_name = cell(nFiles, 1);
file_size_mb = nan(nFiles, 1);
parse_ok = false(nFiles, 1);
root_code = cell(nFiles, 1);
expiry_code = cell(nFiles, 1);
contract_year = nan(nFiles, 1);
bar_minutes = nan(nFiles, 1);
download_date = NaT(nFiles, 1);
header_ok = false(nFiles, 1);
footer_present = false(nFiles, 1);
n_rows = nan(nFiles, 1);
first_ts = NaT(nFiles, 1);
last_ts = NaT(nFiles, 1);
sort_order = cell(nFiles, 1);
n_duplicates = nan(nFiles, 1);
n_bad_dt = nan(nFiles, 1);
n_missing_core = nan(nFiles, 1);
n_nonpositive_price = nan(nFiles, 1);
n_negative_volume = nan(nFiles, 1);
ohlc_ok = false(nFiles, 1);
status = cell(nFiles, 1);
flags = cell(nFiles, 1);

for i = 1:nFiles

    fname = files(i).name;
    fpath = fullfile(files(i).folder, fname);

    file_name{i} = fname;
    file_size_mb(i) = files(i).bytes / (1024^2);

    fprintf('[%3d/%3d] %s\n', i, nFiles, fname);

    meta = parse_filename(fname);

    parse_ok(i) = meta.ok;
    root_code{i} = meta.root;
    expiry_code{i} = meta.expiry;
    contract_year(i) = meta.year;
    bar_minutes(i) = meta.minutes;
    download_date(i) = meta.dl_date;

    a = audit_file(fpath);

    header_ok(i) = a.header_ok;
    footer_present(i) = a.footer_present;
    n_rows(i) = a.n_rows;
    first_ts(i) = a.first_ts;
    last_ts(i) = a.last_ts;
    sort_order{i} = a.sort_order;
    n_duplicates(i) = a.n_duplicates;
    n_bad_dt(i) = a.n_bad_dt;
    n_missing_core(i) = a.n_missing_core;
    n_nonpositive_price(i) = a.n_nonpositive_price;
    n_negative_volume(i) = a.n_negative_volume;
    ohlc_ok(i) = a.ohlc_ok;

    f = {};

    if ~parse_ok(i); f{end+1} = 'filename_parse_failed'; end
    if ~header_ok(i); f{end+1} = 'header_unexpected'; end
    if ~footer_present(i); f{end+1} = 'footer_missing'; end
    if n_duplicates(i) > 0; f{end+1} = 'duplicate_timestamps'; end
    if n_bad_dt(i) > 0; f{end+1} = 'bad_datetime'; end
    if n_missing_core(i) > 0; f{end+1} = 'missing_core_fields'; end
    if n_nonpositive_price(i) > 0; f{end+1} = 'nonpositive_price'; end
    if n_negative_volume(i) > 0; f{end+1} = 'negative_volume'; end
    if strcmp(sort_order{i}, 'unsorted'); f{end+1} = 'timestamp_unsorted'; end
    if ~ohlc_ok(i); f{end+1} = 'ohlc_inconsistency'; end
    if isnan(n_rows(i)) || n_rows(i) == 0; f{end+1} = 'empty'; end

    if isempty(f)
        status{i} = 'ok';
        flags{i} = '';
    else
        status{i} = 'review';
        flags{i} = strjoin(f, ';');
    end
end

manifest = table(file_name, file_size_mb, parse_ok, root_code, expiry_code, contract_year, bar_minutes, download_date, header_ok, footer_present, n_rows, first_ts, last_ts, sort_order, n_duplicates, n_bad_dt, n_missing_core, n_nonpositive_price, n_negative_volume, ohlc_ok, status, flags);
manifest = sortrows(manifest, {'root_code', 'contract_year', 'expiry_code'});

roots = {'fx'; 'gg'};
expiries = {'H'; 'M'; 'U'; 'Z'};
years = (2013:2025)';

nCov = numel(roots) * numel(expiries) * numel(years);

cov_root = cell(nCov, 1);
cov_expiry = cell(nCov, 1);
cov_year = nan(nCov, 1);
cov_n = nan(nCov, 1);
cov_file = cell(nCov, 1);
cov_status = cell(nCov, 1);

k = 0;

for r = 1:numel(roots)
    for e = 1:numel(expiries)
        for y = 1:numel(years)

            k = k + 1;

            rr = roots{r};
            ee = expiries{e};
            yy = years(y);

            idx = strcmp(manifest.root_code, rr) & strcmp(manifest.expiry_code, ee) & manifest.contract_year == yy;
            n = sum(idx);

            cov_root{k} = rr;
            cov_expiry{k} = ee;
            cov_year(k) = yy;
            cov_n(k) = n;

            if n == 0
                cov_file{k} = '';
                cov_status{k} = 'missing';
            elseif n == 1
                cov_file{k} = manifest.file_name{find(idx, 1)};
                cov_status{k} = 'ok';
            else
                cov_file{k} = strjoin(manifest.file_name(idx), ' | ');
                cov_status{k} = 'duplicate';
            end
        end
    end
end

coverage = table(cov_root, cov_expiry, cov_year, cov_n, cov_file, cov_status, 'VariableNames', {'root', 'expiry', 'year', 'n_files', 'file_name', 'coverage_status'});
coverage = sortrows(coverage, {'root', 'year', 'expiry'});

writetable(manifest, fullfile(manifestDir, 'raw_manifest_barchart.csv'));
writetable(coverage, fullfile(manifestDir, 'coverage_barchart.csv'));
writetable(manifest(~strcmp(manifest.status, 'ok'), :), fullfile(diagDir, 'raw_audit_flags.csv'));

fprintf('\n================ SUMMARY ================\n');
fprintf('Total files      : %d\n', nFiles);
fprintf('Status ok        : %d\n', sum(strcmp(manifest.status, 'ok')));
fprintf('Status review    : %d\n', sum(strcmp(manifest.status, 'review')));
fprintf('Coverage missing : %d\n', sum(strcmp(coverage.coverage_status, 'missing')));
fprintf('Coverage dupl.   : %d\n', sum(strcmp(coverage.coverage_status, 'duplicate')));
fprintf('=========================================\n');

function meta = parse_filename(fname)

    meta = struct('ok', false, 'root', '', 'expiry', '', 'year', NaN, 'minutes', NaN, 'dl_date', NaT);

    tok = regexp(lower(fname), '^([a-z]+)([hmuz])(\d{2})_intraday-(\d+)min_historical-data-(\d{2})-(\d{2})-(\d{4})\.csv$', 'tokens', 'once');

    if isempty(tok)
        return;
    end

    meta.root = tok{1};
    meta.expiry = upper(tok{2});
    meta.year = 2000 + str2double(tok{3});
    meta.minutes = str2double(tok{4});
    meta.dl_date = datetime(str2double(tok{7}), str2double(tok{5}), str2double(tok{6}));
    meta.ok = true;
end

function a = audit_file(fpath)

    a = struct('header_ok', false, 'footer_present', false, 'n_rows', NaN, 'first_ts', NaT, 'last_ts', NaT, 'sort_order', '', 'n_duplicates', NaN, 'n_bad_dt', NaN, 'n_missing_core', NaN, 'n_nonpositive_price', NaN, 'n_negative_volume', NaN, 'ohlc_ok', false);

    fid = fopen(fpath, 'r');
    lines = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);

    lines = lines{1};

    if numel(lines) < 2
        a.n_rows = 0;
        return;
    end

    a.header_ok = strcmpi(strrep(strtrim(lines{1}), '"', ''), 'Time,Open,High,Low,Latest,Change,%Change,Volume');
    a.footer_present = ~isempty(regexpi(lines{end}, 'Downloaded from Barchart', 'once'));

    dataLines = lines(2:end - double(a.footer_present));
    a.n_rows = numel(dataLines);

    if a.n_rows == 0
        return;
    end

    dataText = strjoin(dataLines, newline);

    C = textscan(dataText, '%q%f%f%f%f%*s%*s%f', 'Delimiter', ',', 'ReturnOnError', false);

    timeCol = C{1};
    O = C{2};
    H = C{3};
    L = C{4};
    X = C{5};
    V = C{6};

    dt = datetime(timeCol, 'InputFormat', 'yyyy-MM-dd HH:mm');

    a.n_bad_dt = sum(isnat(dt));

    dtV = dt(~isnat(dt));

    if ~isempty(dtV)

        a.first_ts = min(dtV);
        a.last_ts = max(dtV);
        a.n_duplicates = numel(dtV) - numel(unique(dtV));

        d = diff(dtV);

        if isempty(d)
            a.sort_order = 'single';
        elseif all(d > duration(0, 0, 0))
            a.sort_order = 'strict_ascending';
        elseif all(d < duration(0, 0, 0))
            a.sort_order = 'strict_descending';
        elseif all(d >= duration(0, 0, 0))
            a.sort_order = 'ascending_with_duplicates';
        elseif all(d <= duration(0, 0, 0))
            a.sort_order = 'descending_with_duplicates';
        else
            a.sort_order = 'unsorted';
        end
    end

    core = [O, H, L, X, V];

    a.n_missing_core = sum(any(isnan(core), 2));
    a.n_nonpositive_price = sum(any([O, H, L, X] <= 0, 2));
    a.n_negative_volume = sum(V < 0);

    ok = ~any(isnan([O, H, L, X]), 2);

    if any(ok)
        a.ohlc_ok = all(H(ok) >= O(ok) & H(ok) >= L(ok) & H(ok) >= X(ok) & L(ok) <= O(ok) & L(ok) <= H(ok) & L(ok) <= X(ok));
    end
end
