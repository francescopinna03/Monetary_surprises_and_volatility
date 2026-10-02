function [angles, cosines] = Step28_principal_angles(loadingsA, loadingsB)

    loadingsA = double(loadingsA);
    loadingsB = double(loadingsB);
    if size(loadingsA, 2) ~= size(loadingsB, 2) || size(loadingsA, 1) ~= size(loadingsB, 1) || isempty(loadingsA)
        error('STEP28_ANGLES_SIZE: both bases must be d-by-r with the same r.');
    end
    tolerance = 1e-8 * max(1, size(loadingsA, 1));
    if norm(loadingsA' * loadingsA - eye(size(loadingsA, 2)), 'fro') > tolerance || norm(loadingsB' * loadingsB - eye(size(loadingsB, 2)), 'fro') > tolerance
        error('STEP28_ANGLES_ORTHONORMAL: both bases must have orthonormal columns.');
    end

    cosines = svd(loadingsA' * loadingsB);
    cosines = min(max(cosines, 0), 1);
    angles = acos(cosines);
    angles = sort(angles, 'ascend');
    cosines = sort(cosines, 'descend');
end
