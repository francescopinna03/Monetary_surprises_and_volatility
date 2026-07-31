function test = Step24_wald_test(fit, R)
%STEP24_WALD_TEST Cluster-robust Wald F test of R * beta = 0.

    R = double(R);
    if size(R, 2) ~= numel(fit.beta)
        error('STEP24_WALD_DIMENSIONS: R does not match the coefficient vector.');
    end
    restriction = R * fit.beta;
    covariance = R * fit.V * R';
    df1 = rank(R);
    statistic = restriction' * pinv(covariance) * restriction;
    fStatistic = statistic / max(df1, 1);
    pValue = 1 - fcdf(fStatistic, max(df1, 1), max(fit.G - 1, 1));

    test = struct();
    test.restriction = restriction;
    test.wald_statistic = statistic;
    test.f_statistic = fStatistic;
    test.df1 = df1;
    test.df2 = max(fit.G - 1, 1);
    test.p_value = pValue;
end
