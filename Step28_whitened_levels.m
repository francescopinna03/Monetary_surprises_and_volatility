function [levels, meta] = Step28_whitened_levels(panel, minimumDates)

    dateKey = string(panel.date_key(:));
    role = string(panel.role(:));
    phase = string(panel.phase(:));
    position = double(panel.position(:));
    foldKey = string(panel.fold_key(:));
    isControl = role == "matched_control";

    key = dateKey + "|" + phase;
    [whitened, moments] = Step28_whiten_increments(panel.returns, key, position, foldKey, isControl, minimumDates);

    [~, back] = ismember(key + "|" + string(position), whitened.date_key + "|" + string(whitened.position));
    levels = whitened.level(back, :);

    meta = struct();
    meta.date_key = dateKey;
    meta.role = role;
    meta.phase = phase;
    meta.position = position;
    meta.fold_key = foldKey;
    meta.is_control = isControl;
    meta.moments = moments;
end
