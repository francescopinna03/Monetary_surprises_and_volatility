function Y = Step27b_bipower_matrix(previousReturns, currentReturns)
%STEP27B_BIPOWER_MATRIX Per-interval multivariate bipower contribution.
%
% previousReturns and currentReturns are N-by-2 synchronized, already
% scaled returns [Stoxx, Bund].  Diagonal elements are the ordinary
% bipower contributions.  The off-diagonal is obtained by polarization:
%
%   BCov_12 = {BV(r1+r2) - BV(r1-r2)} / 4.
%
% Output columns use Frobenius-preserving symmetric vectorisation
% [B11, sqrt(2) B12, B22].

    previousReturns = double(previousReturns);
    currentReturns = double(currentReturns);
    if size(previousReturns, 2) ~= 2 || ...
            ~isequal(size(previousReturns), size(currentReturns))
        error('STEP27B_BIPOWER_DIMENSIONS: returns must be matching N-by-2 arrays.');
    end
    if any(~isfinite(previousReturns), 'all') || ...
            any(~isfinite(currentReturns), 'all')
        error('STEP27B_BIPOWER_NONFINITE: returns must be finite.');
    end

    factor = pi / 2;
    b11 = factor .* abs(previousReturns(:, 1)) .* abs(currentReturns(:, 1));
    b22 = factor .* abs(previousReturns(:, 2)) .* abs(currentReturns(:, 2));
    plusPrevious = previousReturns(:, 1) + previousReturns(:, 2);
    plusCurrent = currentReturns(:, 1) + currentReturns(:, 2);
    minusPrevious = previousReturns(:, 1) - previousReturns(:, 2);
    minusCurrent = currentReturns(:, 1) - currentReturns(:, 2);
    b12 = (pi / 8) .* (abs(plusPrevious) .* abs(plusCurrent) - ...
        abs(minusPrevious) .* abs(minusCurrent));
    Y = [b11, sqrt(2) .* b12, b22];
end
