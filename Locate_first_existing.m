function pathOut = Locate_first_existing(candidates)

    pathOut = "";

    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file')
            pathOut = string(candidates{i});
            return;
        end
    end
end
