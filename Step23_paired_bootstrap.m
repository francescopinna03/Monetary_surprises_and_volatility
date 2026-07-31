function [summary, draws] = Step23_paired_bootstrap(eventLoss, B)
%STEP23_PAIRED_BOOTSTRAP Resample event-level cross-fitted loss differences.

    loss = double(eventLoss.loss_improvement(:));
    loss = loss(isfinite(loss));
    G = numel(loss);
    if G < 2
        error('STEP23_BOOTSTRAP_CLUSTERS: at least two event losses are required.');
    end

    draws = nan(B, 1);
    for b = 1:B
        sample = randi(G, G, 1);
        draws(b) = mean(loss(sample));
    end

    observed = mean(loss);
    summary = table();
    summary.n_clusters = G;
    summary.bootstrap_draws = B;
    summary.mean_loss_improvement = observed;
    summary.ci95_lo = prctile(draws, 2.5);
    summary.ci95_hi = prctile(draws, 97.5);
    summary.p_one_sided_improvement = (1 + sum(draws <= 0)) / (B + 1);
end
