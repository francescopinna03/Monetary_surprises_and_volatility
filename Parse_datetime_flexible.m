function dt = Parse_datetime_flexible(x)

    if isdatetime(x)
        dt = x;
        return;
    end

    if isnumeric(x)
        dt = datetime(x, 'ConvertFrom', 'excel');
        return;
    end

    if iscell(x) || ischar(x)
        x = string(x);
    end

    fmts = {'yyyy-MM-dd HH:mm', 'yyyy-MM-dd HH:mm:ss', 'dd/MM/yyyy HH:mm', 'dd/MM/yyyy HH:mm:ss', 'MM/dd/yyyy HH:mm', 'MM/dd/yyyy HH:mm:ss', 'dd-MMM-yyyy HH:mm', 'dd-MMM-yyyy HH:mm:ss', 'yyyy-MM-dd''T''HH:mm:ss', 'yyyy-MM-dd''T''HH:mm', 'yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'dd-MMM-yyyy'};
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

    dt = best;
end
