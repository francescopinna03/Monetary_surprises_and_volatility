function [u, tangent] = Step27b_risk_vectors(angleRadians)
%STEP27B_RISK_VECTORS Unit Frobenius coordinates for a rank-one risk mode.
%
% If b = [cos(psi); sin(psi)], then u is the symmetric-vectorisation of
% b*b'.  The sqrt(2) convention on the off-diagonal makes the Euclidean
% norm of u equal to the Frobenius norm of b*b'.  tangent is the unit
% tangent to this fixed-rank PSD stratum.

    validateattributes(angleRadians, {'numeric'}, ...
        {'scalar', 'real', 'finite'});
    c = cos(angleRadians);
    s = sin(angleRadians);
    u = [c.^2; sqrt(2) .* c .* s; s.^2];
    derivative = [-2 .* c .* s; sqrt(2) .* (c.^2 - s.^2); ...
        2 .* c .* s];
    tangent = derivative ./ norm(derivative);
end
