function dt = Parse_date_flexible(x)

    if isdatetime(x)
        dt = dateshift(x, 'start', 'day');
        return;
    end

    if isnumeric(x)
        dt = dateshift(datetime(x, 'ConvertFrom', 'excel'), 'start', 'day');
        return;
    end

    if iscell(x) || ischar(x)
        x = string(x);
    end

    fmts = {'yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'dd-MMM-yyyy', 'yyyy-MM-dd HH:mm', 'yyyy-MM-dd HH:mm:ss', 'dd/MM/yyyy HH:mm', 'MM/dd/yyyy HH:mm', 'dd-MMM-yyyy HH:mm'};
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

            if bestBad == 0
                break;
            end
        catch
        end
    end

    dt = dateshift(best, 'start', 'day');
end
