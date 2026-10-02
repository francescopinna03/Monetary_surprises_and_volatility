function [basis, diagnostics] = Step28_common_basis(loadingsPR, loadingsPC)

    loadingsPR = double(loadingsPR);
    loadingsPC = double(loadingsPC);
    if ~isequal(size(loadingsPR), size(loadingsPC)) || isempty(loadingsPR)
        error('STEP28_COMMON_BASIS_SIZE: both bases must be d-by-r with equal r.');
    end
    [dimension, rank] = size(loadingsPR);
    if rank > dimension
        error('STEP28_COMMON_BASIS_RANK: the rank cannot exceed the dimension.');
    end

    projectorPR = loadingsPR * loadingsPR';
    projectorPC = loadingsPC * loadingsPC';
    average = (projectorPR + projectorPC) / 2;
    average = (average + average') / 2;

    [vectors, values] = eig(average, 'vector');
    values = real(values);
    [values, order] = sort(values, 'descend');
    vectors = real(vectors(:, order));
    basis = vectors(:, 1:rank);
    for j = 1:rank
        [~, pivot] = max(abs(basis(:, j)));
        if basis(pivot, j) < 0
            basis(:, j) = -basis(:, j);
        end
    end

    if rank < dimension && values(rank) - values(rank + 1) <= 1e-12
        error(['STEP28_COMMON_BASIS_DEGENERATE: the average projector has no ' 'separated leading subspace, so no common space is defined.']);
    end

    commonProjector = basis * basis';
    diagnostics = struct();
    diagnostics.schema_version = "step28_common_basis_v1";
    diagnostics.rank = rank;
    diagnostics.eigenvalues = values';
    diagnostics.distance_to_pr = Step28_projector_distance(commonProjector, projectorPR);
    diagnostics.distance_to_pc = Step28_projector_distance(commonProjector, projectorPC);
    diagnostics.pr_pc_distance = Step28_projector_distance(projectorPR, projectorPC);
end
