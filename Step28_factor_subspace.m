function subspace = Step28_factor_subspace(levels, rank)

    levels = double(levels);
    if isempty(levels) || any(~isfinite(levels), 'all')
        error('STEP28_SUBSPACE_INPUT: levels must be a finite non-empty matrix.');
    end
    [nRows, dimension] = size(levels);
    if nRows <= dimension
        error(['STEP28_SUBSPACE_SUPPORT: the second moment needs more rows ' 'than coordinates.']);
    end
    if nargin < 2 || isempty(rank)
        error('STEP28_SUBSPACE_RANK_REQUIRED: the frozen rank must be supplied.');
    end
    rank = double(rank);
    if ~isscalar(rank) || ~isfinite(rank) || rank < 1 || rank > dimension || rank ~= floor(rank)
        error('STEP28_SUBSPACE_RANK_DOMAIN: rank must be an integer in 1..d.');
    end

    Omega = (levels' * levels) / nRows;
    Omega = (Omega + Omega') / 2;
    [vectors, values] = eig(Omega, 'vector');
    values = real(values);
    [values, order] = sort(values, 'descend');
    vectors = real(vectors(:, order));
    for j = 1:dimension
        [~, pivot] = max(abs(vectors(:, j)));
        if vectors(pivot, j) < 0
            vectors(:, j) = -vectors(:, j);
        end
    end

    if any(values <= 100 * eps(max(1, values(1))))
        error(['STEP28_SUBSPACE_DEGENERATE: the whitened second moment is ' 'numerically singular.']);
    end

    loadings = vectors(:, 1:rank);
    subspace = struct();
    subspace.schema_version = "step28_factor_subspace_v1";
    subspace.dimension = dimension;
    subspace.rank = rank;
    subspace.n_rows = nRows;
    subspace.second_moment = Omega;
    subspace.eigenvalues = values;
    subspace.eigenvectors = vectors;
    subspace.loadings = loadings;
    subspace.projector = loadings * loadings';
    subspace.explained_share = sum(values(1:rank)) / sum(values);
    if rank < dimension
        subspace.eigengap = values(rank) - values(rank + 1);
    else
        subspace.eigengap = NaN;
    end
end
