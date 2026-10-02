function verdict = Step28_spectral_rank(levels, position, dateKey, options)

    if nargin < 4 || isempty(options)
        options = struct();
    end
    options = apply_defaults(options);

    levels = double(levels);
    position = double(position(:));
    dateKey = string(dateKey(:));
    [nRows, dimension] = size(levels);
    if nRows == 0 || dimension < 2
        error('STEP28_RANK_INPUT: levels must be N-by-d with d at least two.');
    end
    if numel(position) ~= nRows || numel(dateKey) ~= nRows
        error('STEP28_RANK_POSITION: labels must have one entry per row.');
    end
    if any(~isfinite(levels), 'all')
        error('STEP28_RANK_NONFINITE: levels must be finite.');
    end
    if nRows <= dimension
        error('STEP28_RANK_SUPPORT: more rows than coordinates are required.');
    end

    Omega = (levels' * levels) / nRows;
    Omega = (Omega + Omega') / 2;
    [eigenvectors, eigenvalues] = eig(Omega, 'vector');
    eigenvalues = real(eigenvalues);
    [eigenvalues, order] = sort(eigenvalues, 'descend');
    eigenvectors = real(eigenvectors(:, order));

    stream = RandStream('mt19937ar', 'Seed', options.seed);
    [increments, sequence] = increments_by_sequence(levels, position, dateKey);
    [nullInput, nullSequence, separateControlNull] = control_null_input( options, levels, position, dateKey, dimension);
    nullEigenvalues = NaN(options.parallelDraws, dimension);
    nullCaptured = NaN(options.parallelDraws, dimension - 1);
    nullSecondMoment = NaN(dimension, dimension, options.parallelDraws);
    for b = 1:options.parallelDraws
        if separateControlNull
            [drawIncrements, drawSequence] = sample_sequences(nullInput, nullSequence, sequence.n_groups, stream);
        else
            drawIncrements = nullInput;
            drawSequence = nullSequence;
        end
        permuted = permute_increments_across_dates(drawIncrements, drawSequence, stream);
        nullLevels = cumulate(permuted, drawSequence);
        nullOmega = (nullLevels' * nullLevels) / size(nullLevels, 1);
        nullOmega = (nullOmega + nullOmega') / 2;
        nullEigenvalues(b, :) = sort(real(eig(nullOmega)), 'descend')';
        nullSecondMoment(:, :, b) = nullOmega;
        nullCaptured(b, :) = held_out_reconstruction(nullLevels, drawSequence, options.reconstructionFolds, stream)';
    end
    nullThreshold = NaN(dimension, 1);
    parallelRank = dimension;
    for k = 1:dimension
        basis = eigenvectors(:, k:dimension);
        deflated = NaN(options.parallelDraws, 1);
        for b = 1:options.parallelDraws
            deflated(b) = max(real(eig( basis' * nullSecondMoment(:, :, b) * basis)));
        end
        nullThreshold(k) = quantile(deflated, options.parallelQuantile);
        if eigenvalues(k) <= nullThreshold(k)
            parallelRank = k - 1;
            break;
        end
    end

    gaps = eigenvalues(1:dimension - 1) - eigenvalues(2:dimension);
    [~, gapRank] = max(gaps);
    observedCaptured = held_out_reconstruction(levels, sequence, options.reconstructionFolds, stream);
    capturedThreshold = quantile(nullCaptured, options.parallelQuantile, 1)';

    confirmed = observedCaptured(gapRank) > capturedThreshold(gapRank);
    if gapRank < dimension - 1
        nextGain = observedCaptured(gapRank + 1) - observedCaptured(gapRank);
        nullGain = nullCaptured(:, gapRank + 1) - nullCaptured(:, gapRank);
        confirmed = confirmed && nextGain <= quantile(nullGain, options.parallelQuantile);
    end
    if confirmed
        eigenRank = gapRank;
    else
        eigenRank = NaN;
    end

    if parallelRank == 0
        status = "no_signal_terminal";
        acceptedRank = 0;
    elseif parallelRank == dimension
        if isnan(eigenRank)
            status = "full_rank_terminal";
            acceptedRank = dimension;
        else
            status = "unstable_subspace";
            acceptedRank = NaN;
        end
    elseif isnan(eigenRank) || eigenRank ~= parallelRank
        status = "unstable_subspace";
        acceptedRank = NaN;
    else
        status = "low_rank_accepted";
        acceptedRank = parallelRank;
    end

    verdict = struct();
    verdict.schema_version = "step28_spectral_rank_v1";
    verdict.status = status;
    verdict.accepted_rank = acceptedRank;
    verdict.dimension = dimension;
    verdict.n_rows = nRows;
    verdict.eigenvalues = eigenvalues';
    verdict.null_threshold = nullThreshold';
    verdict.parallel_rank = parallelRank;
    verdict.eigengap_rank = gapRank;
    verdict.eigengap = gaps';
    verdict.held_out_reconstruction = observedCaptured';
    verdict.reconstruction_threshold = capturedThreshold';
    verdict.reconstruction_passes = confirmed;
    if separateControlNull
        verdict.null_source = "exact_clock_controls";
    else
        verdict.null_source = "synthetic_self_null";
    end
    verdict.n_null_sequences = nullSequence.n_groups;
end

function [increments, sequence, separate] = control_null_input(options, levels, position, dateKey, dimension)
    fields = ["controlLevels", "controlPosition", "controlDateKey"];
    present = arrayfun(@(name) isfield(options, char(name)), fields);
    if any(present) && ~all(present)
        error(['STEP28_RANK_CONTROL_NULL: controlLevels, controlPosition and ' 'controlDateKey must be supplied together.']);
    end
    separate = all(present);
    if separate
        controlLevels = double(options.controlLevels);
        controlPosition = double(options.controlPosition(:));
        controlDateKey = string(options.controlDateKey(:));
        if isempty(controlLevels) || size(controlLevels, 2) ~= dimension ||                 size(controlLevels, 1) ~= numel(controlPosition) ||                 size(controlLevels, 1) ~= numel(controlDateKey) || any(~isfinite(controlLevels), 'all')
            error(['STEP28_RANK_CONTROL_NULL: the control panel must be finite ' 'and have the same dimension as the event panel.']);
        end
        [increments, sequence] = increments_by_sequence(controlLevels, controlPosition, controlDateKey);
        if sequence.n_groups < 2
            error('STEP28_RANK_CONTROL_NULL: at least two control paths are required.');
        end
    else
        [increments, sequence] = increments_by_sequence(levels, position, dateKey);
    end
end

function [sampled, sequence] = sample_sequences(increments, source, targetGroups, stream)
    if targetGroups <= source.n_groups
        chosen = randperm(stream, source.n_groups, targetGroups);
    else
        chosen = randi(stream, source.n_groups, targetGroups, 1)';
    end
    sampled = zeros(0, size(increments, 2));
    sampledPosition = zeros(0, 1);
    order = cell(targetGroups, 1);
    for g = 1:targetGroups
        sourceRows = source.order{chosen(g)};
        first = size(sampled, 1) + 1;
        sampled = [sampled; increments(sourceRows, :)];
        sampledPosition = [sampledPosition; source.position(sourceRows)];
        order{g} = (first:size(sampled, 1))';
    end
    sequence = struct('group_index', zeros(size(sampledPosition)),         'n_groups', targetGroups, 'position', sampledPosition, 'order', {order});
end

function [increments, sequence] = increments_by_sequence(levels, position, dateKey)
    nRows = size(levels, 1);
    increments = NaN(size(levels));
    [groupIndex, groupNames] = findgroups(dateKey);
    sequence = struct('group_index', groupIndex, 'n_groups', numel(groupNames), 'position', position, 'order', cell(1, 1));
    order = cell(numel(groupNames), 1);
    for g = 1:numel(groupNames)
        rows = find(groupIndex == g);
        [~, byPosition] = sort(position(rows));
        rows = rows(byPosition);
        order{g} = rows;
        increments(rows, :) = [levels(rows(1), :); diff(levels(rows, :), 1, 1)];
    end
    sequence.order = order;
    if any(~isfinite(increments), 'all')
        error('STEP28_RANK_INCREMENTS: the levels do not form complete sequences.');
    end
    if nRows == 0
        error('STEP28_RANK_INCREMENTS: no rows to differentiate.');
    end
end

function permuted = permute_increments_across_dates(increments, sequence, stream)
    permuted = increments;
    positions = unique(sequence.position);
    for q = 1:numel(positions)
        rows = find(sequence.position == positions(q));
        permuted(rows, :) = increments(rows(randperm(stream, numel(rows))), :);
    end
end

function levels = cumulate(increments, sequence)
    levels = NaN(size(increments));
    for g = 1:sequence.n_groups
        rows = sequence.order{g};
        levels(rows, :) = cumsum(increments(rows, :), 1);
    end
end

function options = apply_defaults(options)
    if ~isfield(options, 'parallelDraws') || isempty(options.parallelDraws)
        options.parallelDraws = 199;
    end
    if ~isfield(options, 'parallelQuantile') || isempty(options.parallelQuantile)
        options.parallelQuantile = 0.95;
    end
    if ~isfield(options, 'reconstructionFolds') || isempty(options.reconstructionFolds)
        options.reconstructionFolds = 5;
    end
    if ~isfield(options, 'seed') || isempty(options.seed)
        error('STEP28_RANK_SEED: the parallel-analysis seed must be frozen.');
    end
    if options.parallelQuantile <= 0.5 || options.parallelQuantile >= 1
        error('STEP28_RANK_QUANTILE: parallelQuantile must lie in (0.5, 1).');
    end
end

function share = held_out_reconstruction(levels, sequence, nFolds, stream)
    dimension = size(levels, 2);
    nGroups = sequence.n_groups;
    foldOfGroup = mod(randperm(stream, nGroups) - 1, nFolds) + 1;
    foldOfRow = zeros(size(levels, 1), 1);
    for g = 1:nGroups
        foldOfRow(sequence.order{g}) = foldOfGroup(g);
    end

    captured = zeros(dimension - 1, 1);
    total = 0;
    for f = 1:nFolds
        train = levels(foldOfRow ~= f, :);
        test = levels(foldOfRow == f, :);
        if size(train, 1) <= dimension || isempty(test)
            continue;
        end
        trainOmega = (train' * train) / size(train, 1);
        trainOmega = (trainOmega + trainOmega') / 2;
        [vectors, values] = eig(trainOmega, 'vector');
        [~, order] = sort(real(values), 'descend');
        vectors = real(vectors(:, order));
        total = total + sum(test .^ 2, 'all');
        for r = 1:dimension - 1
            projected = test * vectors(:, 1:r);
            captured(r) = captured(r) + sum(projected .^ 2, 'all');
        end
    end
    if total <= 0
        error('STEP28_RANK_RECONSTRUCTION: held-out energy is not positive.');
    end
    share = captured / total;
end
