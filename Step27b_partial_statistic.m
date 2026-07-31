function [statistic, sseNull, gain] = Step27b_partial_statistic(y, Q, gResidual)
%STEP27B_PARTIAL_STATISTIC Normalized nested-model gain after QR residualization.

    y = double(y(:));
    Q = double(Q);
    gResidual = double(gResidual(:));
    if size(Q, 1) ~= numel(y) || numel(gResidual) ~= numel(y)
        error('STEP27B_PARTIAL_DIMENSIONS: y, Q and gResidual are inconsistent.');
    end
    residual = y - Q * (Q' * y);
    sseNull = residual' * residual;
    denominator = gResidual' * gResidual;
    if denominator <= 1e-12 * max(1, gResidual' * gResidual + norm(y).^2)
        statistic = NaN;
        gain = NaN;
        return;
    end
    gain = (gResidual' * y).^2 ./ denominator;
    gain = min(max(gain, 0), max(sseNull, 0));
    statistic = gain ./ max(sseNull, eps);
end
