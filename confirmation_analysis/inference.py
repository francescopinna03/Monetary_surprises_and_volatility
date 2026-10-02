import numpy as np
from final_analysis.models import design


def wild_contrast(y, x, clusters, contrast, draws, rng, alternative='greater',
                  min_clusters=30, batch_size=256):
    if alternative not in ('greater', 'less', 'two-sided'):
        raise ValueError('Unknown alternative')
    if draws < 1 or int(draws) != draws or batch_size < 1:
        raise ValueError('Positive integer draws and batch size required')
    y, z, g, scale, a, inv, correction = design(y, x, clusters, min_clusters)
    c = np.asarray(contrast, float)
    if c.shape != (z.shape[1],) or not np.isfinite(c).all() or not np.any(c):
        raise ValueError('Invalid linear contrast')
    r = c / scale
    b = a @ y
    direction = inv @ r
    b0 = b - direction * (r @ b) / (r @ direction)
    fitted = z @ b0
    errors = y - fitted
    groups = int(g.max() + 1)

    def statistic(ys):
        bs = a @ ys
        residual = ys - z @ bs
        scores = np.zeros((groups, ys.shape[1]))
        np.add.at(scores, g, (z @ direction)[:, None] * residual)
        se = np.sqrt(correction * np.sum(scores*scores, axis=0))
        if not np.isfinite(se).all() or np.any(se <= 0):
            raise ValueError('Degenerate contrast studentization')
        return (r @ bs) / se, se

    observed, se = statistic(y[:, None])
    t = float(observed[0])
    exceed = 0
    for start in range(0, draws, batch_size):
        n = min(batch_size, draws-start)
        signs = rng.choice([-1., 1.], (n, groups)).T
        tb, _ = statistic(fitted[:, None] + errors[:, None] * signs[g])
        if alternative == 'greater':
            exceed += int(np.count_nonzero(tb >= t))
        elif alternative == 'less':
            exceed += int(np.count_nonzero(tb <= t))
        else:
            exceed += int(np.count_nonzero(np.abs(tb) >= abs(t)))
    return dict(estimate=float(r @ b), se_cr1=float(se[0]), t_stat=t,
                p_wild=(exceed+1)/(draws+1), alternative=alternative,
                draws=int(draws), n_clusters=groups, n_rows=len(y))
