function [r, volumes, present, currentPrice, previousPrice] = Canonical_returns_on_grid(times, prices, volume, endpoints, barMinutes)
    times = times(:); endpoints = endpoints(:); prices = prices(:);
    assert(numel(unique(times)) == numel(times), 'WINDOW_DUPLICATE_TIME: ambiguous bar.');
    [hc, ic] = ismember(endpoints, times);
    [hp, ip] = ismember(endpoints - minutes(barMinutes), times);
    r = nan(size(endpoints)); volumes = r; currentPrice = r; previousPrice = r;
    currentPrice(hc) = prices(ic(hc)); previousPrice(hp) = prices(ip(hp));
    if ~isempty(volume); volumes(hc) = volume(ic(hc)); end
    present = hc & hp & isfinite(currentPrice) & isfinite(previousPrice) & currentPrice > 0 & previousPrice > 0;
    r(present) = log(currentPrice(present)) - log(previousPrice(present));
end
