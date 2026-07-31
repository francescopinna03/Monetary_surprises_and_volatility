function summary = Audit_timezone_provenance(archiveCentral, premierCentral, tolerance)
%AUDIT_TIMEZONE_PROVENANCE Reproduce archived Barchart wall clocks and OHLCV.
%
% Inputs are standardized tables returned by Read_certification_bars. Barchart
% publishes Central Time (CT) as the clock convention for futures data. This
% audit checks that a fresh Premier export reproduces the archived project
% export after both wall clocks are localized in America/Chicago.

    if nargin < 3 || isempty(tolerance)
        tolerance = 1e-10;
    end

    summary = compare_exports(archiveCentral, premierCentral, ...
        "archive_vs_premier_ct_reexport", tolerance);
    minimumRows = 100;
    pass = all(summary.n_common >= minimumRows) && ...
        all(summary.common_share_smaller_file >= 0.95) && ...
        all(summary.ohlcv_exact_share >= 0.999);
    summary.overall_pass = repmat(pass, height(summary), 1);
end

function row = compare_exports(A, B, label, tolerance)
    [common, ia, ib] = intersect(A.time_utc, B.time_utc);
    XA = [A.Open(ia), A.High(ia), A.Low(ia), A.Latest(ia), A.Volume(ia)];
    XB = [B.Open(ib), B.High(ib), B.Low(ib), B.Latest(ib), B.Volume(ib)];

    scale = max(1, max(abs(XA), abs(XB)));
    fieldMatch = abs(XA - XB) <= tolerance .* scale;
    if isempty(fieldMatch)
        exactShare = NaN;
        maxRelativeError = NaN;
    else
        exactShare = mean(all(fieldMatch, 2));
        maxRelativeError = max(abs(XA - XB) ./ scale, [], 'all');
    end

    row = table();
    row.comparison = string(label);
    row.n_left = height(A);
    row.n_right = height(B);
    row.n_common = numel(common);
    row.common_share_left = numel(common) / max(height(A), 1);
    row.common_share_right = numel(common) / max(height(B), 1);
    row.common_share_smaller_file = numel(common) / ...
        max(min(height(A), height(B)), 1);
    row.ohlcv_exact_share = exactShare;
    row.max_relative_error = maxRelativeError;
end
