function [basis, intensity, reactivation] = Step27b_temporal_basis(minutesFromPc)
%STEP27B_TEMPORAL_BASIS Frozen continuous null and two jump profiles.
%
% The null is quadratic on each side of conference time and continuous at
% zero.  No intercept shift is available under the null.  The primary
% intensity alternative is a permanent post-PC step.  The reactivation
% alternative peaks at the first eligible post-PC bipower contribution
% (+10 minutes) and decays with a frozen 15-minute time constant.

    t = double(minutesFromPc(:));
    if any(~isfinite(t))
        error('STEP27B_TIME_NONFINITE: event times must be finite.');
    end
    x = t ./ 45;
    positive = max(x, 0);
    basis = [ones(numel(t), 1), x, x.^2, positive, positive.^2];
    intensity = double(t > 0);
    reactivation = intensity .* exp(-max(t - 10, 0) ./ 15);
end
