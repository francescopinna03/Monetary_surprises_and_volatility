function B = Read_certification_bars(filePath, declaredTimeZone)
%READ_CERTIFICATION_BARS Read an OHLCV export with an explicit wall-clock zone.

    filePath = char(string(filePath));
    declaredTimeZone = string(declaredTimeZone);
    if exist(filePath, 'file') ~= 2
        error('CERTIFICATION_FILE_MISSING: %s', filePath);
    end

    T = readtable(filePath, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    names = string(T.Properties.VariableNames);
    normalized = lower(regexprep(names, '[^a-zA-Z0-9]+', '_'));
    normalized = regexprep(normalized, '_+', '_');
    normalized = regexprep(normalized, '^_|_$', '');

    timeName = resolve_name(names, normalized, ...
        ["time", "timestamp", "datetime", "date_time"]);
    openName = resolve_name(names, normalized, ["open"]);
    highName = resolve_name(names, normalized, ["high"]);
    lowName = resolve_name(names, normalized, ["low"]);
    closeName = resolve_name(names, normalized, ...
        ["latest", "close", "last", "settle"]);
    volumeName = resolve_name(names, normalized, ["volume", "vol"]);

    required = [timeName, openName, highName, lowName, closeName, volumeName];
    if any(strlength(required) == 0)
        error(['CERTIFICATION_COLUMNS_MISSING: %s must contain Time, Open, ' ...
            'High, Low, Latest/Close and Volume.'], filePath);
    end

    B = table();
    B.wall_time = Parse_datetime_flexible(T.(timeName));
    B.time_utc = Wall_clock_to_utc(B.wall_time, declaredTimeZone);
    B.Open = numeric_column(T.(openName));
    B.High = numeric_column(T.(highName));
    B.Low = numeric_column(T.(lowName));
    B.Latest = numeric_column(T.(closeName));
    B.Volume = numeric_column(T.(volumeName));
    B.source_file = repmat(string(filePath), height(T), 1);
    B.declared_time_zone = repmat(declaredTimeZone, height(T), 1);

    valid = ~isnat(B.wall_time) & ~isnat(B.time_utc) & ...
        all(isfinite([B.Open, B.High, B.Low, B.Latest, B.Volume]), 2);
    B = B(valid, :);
    B = sortrows(B, 'time_utc');
    [~, keep] = unique(B.time_utc, 'last');
    B = B(sort(keep), :);
end

function name = resolve_name(names, normalized, candidates)
    name = "";
    for candidate = candidates
        hit = find(normalized == candidate, 1);
        if ~isempty(hit)
            name = names(hit);
            return;
        end
    end
end

function x = numeric_column(x)
    if ~isnumeric(x)
        x = str2double(erase(string(x), ','));
    end
    x = double(x(:));
end
