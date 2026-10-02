function distance = Step28_projector_distance(projector, reference)

    projector = double(projector);
    reference = double(reference);
    if ~isequal(size(projector), size(reference)) || isempty(projector)
        error('STEP28_PROJECTOR_SIZE: projectors must be equal non-empty squares.');
    end
    if any(~isfinite(projector), 'all') || any(~isfinite(reference), 'all')
        error('STEP28_PROJECTOR_NONFINITE: projectors must be finite.');
    end
    distance = norm(projector - reference, 'fro') / sqrt(2);
end
