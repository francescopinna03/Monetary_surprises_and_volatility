function [conditionalMean, conditionalCovariance, diagnostics] = Step28_conditional_gaussian_predict(model, conditioning, group)

    conditioning = double(conditioning);
    group = string(group(:));
    nRows = size(conditioning, 1);
    if nRows == 0
        error('STEP28_LAW_PREDICT_EMPTY: conditioning must be non-empty.');
    end
    if numel(group) ~= nRows
        error('STEP28_LAW_PREDICT_LABELS: group must have one entry per row.');
    end
    if size(conditioning, 2) ~= model.n_conditioning
        error(['STEP28_LAW_PREDICT_WIDTH: conditioning has %d columns, the '             'model was fitted with %d.'], size(conditioning, 2), model.n_conditioning);
    end
    if any(~isfinite(conditioning), 'all')
        error('STEP28_LAW_PREDICT_NONFINITE: conditioning must be finite.');
    end

    [isKnown, groupIndex] = ismember(group, model.group_names);
    if ~all(isKnown)
        error('STEP28_LAW_PREDICT_GROUP: unseen groups %s.', strjoin(unique(group(~isKnown)), ', '));
    end

    dimension = model.dimension;
    conditionalMean = predict_affine_block(model.mean_block, conditioning, groupIndex);
    logScale = predict_affine_block(model.scale_block, conditioning, groupIndex);
    scale = exp(logScale);
    if any(~isfinite(scale), 'all') || any(scale <= 0, 'all')
        error('STEP28_LAW_PREDICT_SCALE: the predicted scale is not positive.');
    end

    if model.correlation_scope == "per_group"
        correlationIndex = groupIndex;
    else
        correlationIndex = ones(nRows, 1);
    end

    conditionalCovariance = zeros(dimension, dimension, nRows);
    for i = 1:nRows
        D = diag(scale(i, :));
        Sigma = D * model.correlation(:, :, correlationIndex(i)) * D;
        Sigma = (Sigma + Sigma') / 2;
        conditionalCovariance(:, :, i) = Sigma;
    end

    diagnostics = struct();
    diagnostics.scale = scale;
    diagnostics.log_scale = logScale;
    diagnostics.group_index = groupIndex;
    diagnostics.correlation_index = correlationIndex;
end

function fitted = predict_affine_block(block, conditioning, groupIndex)
    if block.pooling == "per_group"
        fitted = zeros(size(conditioning, 1), size(block.intercept, 2));
        for g = 1:block.n_groups
            rows = groupIndex == g;
            if ~any(rows); continue; end
            fitted(rows, :) = block.intercept(g, :) + conditioning(rows, :) * block.slope(:, :, g);
        end
        return;
    end
    fitted = block.intercept(groupIndex, :) + conditioning * block.slope;
end
