function dt = Parse_utc_datetime(x)
%PARSE_UTC_DATETIME Parse canonical UTC clock values without locale shifts.
%
% Cleaned Barchart files and all *_datetime_utc columns are serialized as
% timezone-neutral strings displaying UTC. If an already-zoned datetime is
% supplied, it is first converted to UTC and then made timezone-neutral.

    dt = Parse_datetime_flexible(x);

    if isempty(dt.TimeZone)
        return;
    end

    dt.TimeZone = 'UTC';
    valid = ~isnat(dt);
    out = NaT(size(dt));

    if any(valid(:))
        utcText = string(dt(valid), 'yyyy-MM-dd HH:mm:ss');
        out(valid) = datetime(utcText, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
    end

    dt = out;
end
