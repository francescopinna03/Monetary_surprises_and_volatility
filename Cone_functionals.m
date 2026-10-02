function result = Cone_functionals(A)
    assert(isequal(size(A), [2, 2]) && isreal(A) && all(isfinite(A), 'all'), 'CONE_MATRIX_INVALID');
    assert(max(abs(A - A.'), [], 'all') <= 1e-12, 'CONE_MATRIX_NOT_SYMMETRIC');
    result.mp = trace(A)/2 - 2/pi*A(1,2);
    result.cbi = trace(A)/2 + 2/pi*A(1,2);
    result.difference = -4/pi*A(1,2);
end
