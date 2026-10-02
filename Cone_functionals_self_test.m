function Cone_functionals_self_test()
    phi = linspace(-pi/2, 0, 100001);
    direction = [cos(phi); sin(phi)];
    for A = {[2, -.7; -.7, 1], [-1, .4; .4, 3], eye(2)}
        matrix = A{1};
        result = Cone_functionals(matrix);
        numeric = trapz(phi, sum(direction .* (matrix * direction), 1))/(pi/2);
        assert(abs(result.mp - numeric) < 1e-9, 'CONE_INTEGRATION_MISMATCH');
        assert(abs(result.mp-result.cbi-result.difference) < 1e-12);
        angle = .37;
        R = [cos(angle), -sin(angle); sin(angle), cos(angle)];
        rotated = R.' * direction;
        B = R.' * matrix * R;
        same = trapz(phi, sum(rotated .* (B * rotated), 1))/(pi/2);
        assert(abs(same - numeric) < 1e-12, 'CONE_BASIS_INVARIANCE_FAILED');
    end
    fprintf('Cone_functionals_self_test passed.\n');
end
