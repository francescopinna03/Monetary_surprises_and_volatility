function [U, C, angle] = JK_median_rotation(M, rotationQuantile)
%JK_MEDIAN_ROTATION Two-shock sign-restricted Jarocinski-Karadi rotation.
%
% M must contain the policy indicator in column 1 and the equity surprise
% in column 2. The returned shocks satisfy M = U*C and
% U(:,1) + U(:,2) = M(:,1). C(1,2) is the equity response to the monetary
% policy shock and C(2,2) is the equity response to the information shock.
%
% rotationQuantile = 0.5 selects the median admissible rotation. The
% implementation follows the algorithm in the public ECB update code:
% https://github.com/marekjarocinski/jkshocks_update_ecb_202310

    if nargin < 2 || isempty(rotationQuantile)
        rotationQuantile = 0.5;
    end

    validateattributes(M, {'numeric'}, {'2d', 'ncols', 2});
    validateattributes(rotationQuantile, {'numeric'}, ...
        {'scalar', 'real', 'finite', '>', 0, '<', 1});

    valid = all(isfinite(M), 2);
    MM = M(valid, :);

    if size(MM, 1) < 4
        error('JK_ROTATION_TOO_FEW_ROWS: at least four complete observations are required.');
    end

    if rank(MM) < 2
        error('JK_ROTATION_RANK_DEFICIENT: policy and equity surprises must span two dimensions.');
    end

    [Q, R] = qr(MM, 0);
    diagonalSigns = sign(diag(R));
    diagonalSigns(diagonalSigns == 0) = 1;
    S = diag(diagonalSigns);
    Q = Q * S;
    R = S * R;

    if R(1, 2) > 0
        lowerAngle = atan(R(1, 2) / R(2, 2));
        upperAngle = pi / 2;
    else
        lowerAngle = 0;
        if R(1, 2) == 0
            upperAngle = pi / 2;
        else
            upperAngle = atan(-R(2, 2) / R(1, 2));
        end
    end

    angle = (1 - rotationQuantile) * lowerAngle + ...
        rotationQuantile * upperAngle;

    P = [cos(angle), sin(angle); -sin(angle), cos(angle)];
    D = diag([R(1, 1) * cos(angle), R(1, 1) * sin(angle)]);

    if rcond(D) < 1e-12
        error('JK_ROTATION_SINGULAR: the selected rotation is numerically singular.');
    end

    UU = Q * P * D;
    C = D \ (P' * R);

    U = nan(size(M));
    U(valid, :) = UU;

    tolerance = 1e-10 * max(1, norm(MM, 'fro'));
    if norm(UU * C - MM, 'fro') > tolerance
        error('JK_ROTATION_RECONSTRUCTION: M = U*C failed numerical verification.');
    end

    if max(abs(sum(UU, 2) - MM(:, 1))) > tolerance
        error('JK_ROTATION_SUM: MP + CBI does not reconstruct the policy indicator.');
    end

    if ~(C(1, 2) < 0 && C(2, 2) > 0)
        error('JK_ROTATION_SIGNS: the selected rotation violates the equity sign restrictions.');
    end
end

