function adjusted = Step23_holm_adjust(p)
%STEP23_HOLM_ADJUST Holm family-wise adjusted p-values.

    p = double(p(:));
    adjusted = nan(size(p));
    valid = isfinite(p);
    pv = p(valid);
    m = numel(pv);
    if m == 0
        return;
    end

    [sorted, order] = sort(pv);
    scaled = (m - (1:m)' + 1) .* sorted;
    scaled = cummax(scaled);
    scaled = min(scaled, 1);
    restored = nan(m, 1);
    restored(order) = scaled;
    adjusted(valid) = restored;
end
