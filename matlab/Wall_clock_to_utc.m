function dtUtc = Wall_clock_to_utc(x, sourceTimeZone)
%WALL_CLOCK_TO_UTC Localize wall-clock values and return UTC clock values.
%
% The returned datetime is intentionally timezone-neutral. Its displayed
% year/month/day/hour/minute is UTC, which makes the value stable when written
% to and read from CSV on computers configured in different local timezones.

    if nargin < 2 || strlength(string(sourceTimeZone)) == 0
        error('Wall_clock_to_utc requires an explicit IANA source timezone.');
    end

    dt = Parse_datetime_flexible(x);
    dtUtc = NaT(size(dt));
    valid = ~isnat(dt);

    if ~any(valid(:))
        return;
    end

    sourceTimeZone = char(string(sourceTimeZone));

    if isempty(dt.TimeZone)
        dt.TimeZone = sourceTimeZone;
    elseif ~strcmp(dt.TimeZone, sourceTimeZone)
        error('Datetime already has timezone %s; expected %s.', dt.TimeZone, sourceTimeZone);
    end

    dt.TimeZone = 'UTC';
    utcText = string(dt(valid), 'yyyy-MM-dd HH:mm:ss');
    dtUtc(valid) = datetime(utcText, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
end
