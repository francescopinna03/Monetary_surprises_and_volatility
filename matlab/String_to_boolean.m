function y = String_to_boolean(x)

    x = lower(strtrim(string(x)));
    y = x == "true" | x == "1";
end
