function Final_window_self_test()
    cfg = Final_window_config();
    t0 = datetime(2023, 2, 2, 13, 15, 0);
    times = t0 + minutes((0:5:30)');
    prices = exp((0:6)' * .01);
    endpoints = t0 + minutes(cfg.prEndpoints);
    r = Canonical_returns_on_grid(times, prices, ones(7,1), endpoints, 5);
    assert(numel(r)==5 && max(abs(r-.01)) < 1e-12);
    assert(abs(sum(r.^2)-.0005) < 1e-12);
    assert(abs((pi/2)*sum(abs(r(2:end).*r(1:end-1)))-(pi/2)*.0004) < 1e-12);
    prices(end) = 1000;
    assert(max(abs(Canonical_returns_on_grid(times, prices, ones(7,1), endpoints,5)-r)) < 1e-12);
    keep = [1,2,4,5,6,7];
    missing = Canonical_returns_on_grid(times(keep), prices(keep), ones(6,1), endpoints,5);
    assert(all(isnan(missing(2:3))), 'Missing bars must not be bridged.');
    assert(max(cfg.preEndpoints) == -5 && min(cfg.prEndpoints)-cfg.barMinutes == 0);
    lambda = [20,10,5,1]; mse = [1.3,1.05,1,1.02]; se = [.1,.1,.1,.1];
    [best,k] = min(mse); accepted = find(mse <= best+se(k));
    assert(lambda(accepted(1)) == max(lambda(accepted)) && lambda(accepted(1))==10);
    fprintf('Final window self-test passed.\n');
end
