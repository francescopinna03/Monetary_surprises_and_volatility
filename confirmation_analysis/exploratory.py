import json
import platform
import subprocess
from pathlib import Path
import numpy as np
import pandas as pd
import scipy
from final_analysis.models import clustered, wild_test, residual_partial_r2, holm
from .calibrate import primary_power, noise_sampler, wilson_lower
from .cones import surface_design, surface_contrasts, cone_functionals
from .estimate import verify_build, panel, cone_tests, HYPOTHESES
from .inference import wild_contrast
from .nuisance import counterfactual_v2, normal_matrix_v2
from .protocol import REPO, digest, dump, timestamp, new_output, code_hashes


def verify_opened_build(build):
    build = Path(build)
    manifest = json.loads((build/'status.json').read_text())
    if manifest.get('status') not in ('frozen_v2', 'frozen_after_opening'):
        raise ValueError('Exploratory analyses require a frozen build')
    for name, expected in manifest['table_hashes'].items():
        if Path(name).name != name or digest(build/name) != expected:
            raise ValueError(f'Frozen table modified: {name}')
    if digest(build/'specification.json') != manifest['specification_sha256']:
        raise ValueError('Frozen specification modified')
    return manifest, json.loads((build/'specification.json').read_text()), manifest['code_hashes'] != code_hashes()


def holm_declared(p, size):
    p = np.asarray(p, float)
    if len(p) > size:
        raise ValueError(f'{len(p)} tests exceed the declared family size {size}')
    padded = np.concatenate([np.where(np.isfinite(p), p, 1.), np.ones(size-len(p))])
    return holm(padded)[:len(p)]


def mean_branch(T, spec, eps_col, label, draws, seed):
    eps = T[eps_col].to_numpy(float); s = T.crossfit_state_z.to_numpy(float)
    y = T.crossfit_abnormal_log_BV.to_numpy(float); g = T.trade_date.astype(str)
    X = np.column_stack([np.ones(len(T)), eps, np.abs(eps), s, eps*s, np.abs(eps)*s])
    names = ['const', 'eps', 'abs_eps', 'state', 'eps_x_state', 'abs_eps_x_state']
    rows = []
    for j, name in enumerate(names[1:], 1):
        c = np.zeros(X.shape[1]); c[j] = 1
        r = wild_contrast(y, X, g, c, draws, np.random.default_rng(seed+j), alternative='two-sided',
                          min_clusters=spec['minimum_event_clusters'])
        rows.append(dict(family='post_opening_level1_mean', surprise=label, term=name, **{k: r[k] for k in
                         ['estimate', 'p_wild', 'n_rows', 'n_clusters']}, status='observed_after_opening'))
    p_joint, stat, _ = wild_test(y, X, g, [4, 5], draws, np.random.default_rng(seed+9), spec['minimum_event_clusters'])
    rows.append(dict(family='post_opening_level1_mean', surprise=label, term='eps_x_state & abs_eps_x_state (joint)',
                     estimate=stat, p_wild=p_joint, n_rows=len(T), n_clusters=T.trade_date.nunique(),
                     status='observed_after_opening'))
    return rows, X, y, g


def history_interval(T, spec, eps_col, label, draws, seed, calibrated_margin):
    E = T[np.isfinite(T[['lag1', 'history3']]).all(axis=1)]
    eps = E[eps_col].to_numpy(float); s = E.crossfit_state_z.to_numpy(float)
    y = E.crossfit_abnormal_log_BV.to_numpy(float); g = E.trade_date.astype(str)
    base = np.column_stack([np.ones(len(E)), eps, np.abs(eps)])
    state = np.column_stack([s, eps*s, np.abs(eps)*s])
    H = E[['lag1', 'history3']].to_numpy(float)
    model = np.column_stack([base, state]); full = np.column_stack([model, H])
    r2_state = residual_partial_r2(y, base, state)
    r2_hist = residual_partial_r2(y, model, H)
    r2_hist_no_state = residual_partial_r2(y, base, H)
    p_hist, stat, _ = wild_test(y, full, g, [6, 7], draws, np.random.default_rng(seed), spec['minimum_event_clusters'])
    rng = np.random.default_rng(seed+1); boot = []
    dates = E.trade_date.to_numpy()
    for _ in range(spec['history_bootstrap_replications']):
        pick = rng.choice(len(E), len(E), replace=True)
        boot.append(residual_partial_r2(y[pick], model[pick], H[pick]))
    upper = float(np.quantile(boot, .95))
    return dict(family='post_opening_history_interval', surprise=label, n_rows=len(E), n_clusters=int(E.trade_date.nunique()),
                partial_r2_state_block=r2_state, partial_r2_history=r2_hist,
                partial_r2_history_without_state_block=r2_hist_no_state, p_wild_history=p_hist,
                history_upper_95=upper, calibrated_margin=calibrated_margin,
                history_reference_margin=spec['history_reference_margin'],
                verdict=('no_calibrated_margin_supplied' if calibrated_margin is None
                         else 'not_resolved' if upper > calibrated_margin else 'below_calibrated_margin'),
                note='One joint history block. state_block = level plus two interactions, not the level alone. '
                     'Bootstrap upper bound is nominal, pointwise and conditional on the estimated counterfactual. '
                     'An interval on the specified history block, not a sufficiency or absorption claim.',
                status='observed_after_opening')


def bv_zero_diagnostics(W, root, phase):
    T = W[W.root_code.eq(root) & W.phase.eq(phase) & W.window_eligible.fillna(False)].copy()
    T['year'] = T.trade_date.dt.year
    T['bv_zero'] = T.BV_post.eq(0); T['rv_zero'] = T.RV_post.eq(0)
    out = T.groupby(['year', 'is_event']).agg(n=('BV_post', 'size'), bv_zero=('bv_zero', 'sum'),
                                              rv_zero=('rv_zero', 'sum')).reset_index()
    out['bv_zero_share'] = out.bv_zero/out.n
    return out


def ppml(y, X, offset=None, iters=100, tol=1e-9):
    offset = np.zeros(len(y)) if offset is None else offset
    beta = np.zeros(X.shape[1]); beta[0] = np.log(np.mean(y)+1e-12) - np.mean(offset)
    for _ in range(iters):
        eta = X @ beta + offset; mu = np.exp(np.clip(eta, -30, 30))
        z = eta - offset + (y-mu)/mu
        Wsq = np.sqrt(mu)
        new = np.linalg.lstsq(X*Wsq[:, None], z*Wsq, rcond=None)[0]
        if np.max(np.abs(new-beta)) < tol:
            beta = new; break
        beta = new
    eta = X @ beta + offset; mu = np.exp(np.clip(eta, -30, 30))
    return beta, mu


def ppml_cluster_cov(y, X, mu, clusters):
    scores = X*(y-mu)[:, None]
    bread = np.linalg.pinv((X*mu[:, None]).T @ X)
    groups = pd.factorize(clusters)[0]; G = groups.max()+1
    meat = np.zeros((X.shape[1], X.shape[1]))
    for k in range(G):
        sg = scores[groups == k].sum(axis=0); meat += np.outer(sg, sg)
    n, p = X.shape
    return bread @ meat @ bread * (G/(G-1))*((n-1)/(n-p))


def ppml_wild(y, X, offset, clusters, draws, rng):
    beta, mu = ppml(y, X, offset)
    scores = X*(y-mu)[:, None]
    bread = np.linalg.pinv((X*mu[:, None]).T @ X)
    groups = pd.factorize(clusters)[0]; G = groups.max()+1
    S = np.zeros((G, X.shape[1]))
    for k in range(G):
        S[k] = scores[groups == k].sum(axis=0)
    signs = rng.choice([-1., 1.], size=(draws, G))
    return (signs @ S) @ bread.T


def ppml_branch(W, indicators, spec, root, u, z, draws=999, seed=0):
    rows = []
    T = W[W.root_code.eq(root) & W.phase.eq('PR') & W.window_eligible.fillna(False)].copy()
    ok = np.isfinite(T[['log_BV_pre', 'slow_state']]).all(axis=1) & np.isfinite(T.BV_post)
    T = T[ok]
    train = ~T.is_event
    if train.sum() < spec['minimum_controls']:
        return [dict(family='post_opening_ppml', status='too_few_controls')]
    T['cf_log_mean_BV'] = np.nan
    years = T.trade_date.dt.year
    for yr in sorted(years.unique()):
        tr = train & years.ne(yr); te = years.eq(yr)
        if tr.sum() < spec['minimum_controls'] or not te.any():
            continue
        Xn, meta = normal_matrix_v2(T[tr], 'BV')
        b, _ = ppml(T.loc[tr, 'BV_post'].to_numpy(float), Xn)
        T.loc[te, 'cf_log_mean_BV'] = normal_matrix_v2(T[te], 'BV', meta)[0] @ b
    T = T[np.isfinite(T.cf_log_mean_BV)]
    E = T[T.is_event].merge(indicators, on=['trade_date', 'phase'], how='left', validate='one_to_one')
    E = E[np.isfinite(E[[u, z, 'crossfit_state_z']]).all(axis=1)]
    for label, sub in [('ppml_all_eligible_including_zeros', E), ('ppml_positive_bv_common_sample', E[E.BV_post > 0])]:
        if sub.trade_date.nunique() < spec['minimum_event_clusters']:
            rows.append(dict(family='post_opening_ppml', sample=label, status='too_few_clusters')); continue
        X = surface_design(sub[u], sub[z], sub.crossfit_state_z)
        y = sub.BV_post.to_numpy(float); off = sub.cf_log_mean_BV.to_numpy(float)
        beta, mu = ppml(y, X, off)
        V = ppml_cluster_cov(y, X, mu, sub.trade_date.astype(str))
        boot = ppml_wild(y, X, off, sub.trade_date.astype(str), draws, np.random.default_rng(seed))
        for name, idx in HYPOTHESES:
            c = surface_contrasts()[idx]; est = float(c @ beta); se = float(np.sqrt(c @ V @ c))
            from scipy.stats import norm
            t_obs = est/se if se > 0 else np.nan
            t_boot = boot @ c / se if se > 0 else np.full(len(boot), np.nan)
            rows.append(dict(family='post_opening_ppml', sample=label, hypothesis=name, estimate=est, se_cr1=se,
                             p_analytic_one_sided=float(norm.sf(t_obs)) if se > 0 else np.nan,
                             p_wild_one_sided_greater=float((np.sum(t_boot >= t_obs)+1)/(len(t_boot)+1)) if se > 0 else np.nan,
                             p_wild_one_sided_less=float((np.sum(t_boot <= t_obs)+1)/(len(t_boot)+1)) if se > 0 else np.nan,
                             p_wild_two_sided=float((np.sum(np.abs(t_boot) >= abs(t_obs))+1)/(len(t_boot)+1)) if se > 0 else np.nan,
                             n_rows=len(sub), n_clusters=int(sub.trade_date.nunique()),
                             estimand='Poisson QMLE with log link: the contrast is on the log conditional MEAN of BV in levels, '
                                      'not on the mean of log BV and not on the curvature of the level mean; '
                                      'offset = leave-year-out Poisson normal continuation on controls',
                             status='observed_after_opening'))
    return rows


def fold_table(X, y, years, pen, spec, chosen_lambda=3.):
    rows = []
    def fit(Xa, ya, lam):
        return np.linalg.solve(Xa.T @ Xa + lam*np.diag(pen)*len(ya), Xa.T @ ya)
    for yr in np.unique(years):
        tr, te = years != yr, years == yr
        if tr.sum() < spec['minimum_event_clusters'] or not te.any():
            continue
        free = np.mean((y[te]-X[te] @ fit(X[tr], y[tr], 0.))**2)
        ridge = np.mean((y[te]-X[te] @ fit(X[tr], y[tr], chosen_lambda))**2)
        b0 = np.linalg.lstsq(X[tr][:, :5], y[tr], rcond=None)[0]
        excl = np.mean((y[te]-X[te][:, :5] @ b0)**2)
        rows.append(dict(year=int(yr), n_test=int(te.sum()), mse_free=float(free), mse_ridge_1se=float(ridge),
                         mse_block_excluded=float(excl), free_beats_excluded=bool(free < excl)))
    return pd.DataFrame(rows)


def ridge_state_block(T, spec, u, z, lambdas, seed):
    X = surface_design(T[u], T[z], T.crossfit_state_z); y = T.crossfit_abnormal_log_BV.to_numpy(float)
    years = T.trade_date.dt.year.to_numpy()
    pen = np.zeros(X.shape[1]); pen[5] = pen[6] = 1.; pen[7] = 2.
    def fit(Xa, ya, lam):
        return np.linalg.solve(Xa.T @ Xa + lam*np.diag(pen)*len(ya), Xa.T @ ya)
    rows = []
    for lam in lambdas:
        errs = []
        for yr in np.unique(years):
            tr, te = years != yr, years == yr
            if tr.sum() < spec['minimum_event_clusters'] or not te.any():
                continue
            b = fit(X[tr], y[tr], lam); errs.append(np.mean((y[te]-X[te] @ b)**2))
        b_full = fit(X, y, lam)
        A0 = np.array([[b_full[1], b_full[3]], [b_full[3], b_full[2]]])
        A1 = np.array([[b_full[5], b_full[7]], [b_full[7], b_full[6]]])
        f0, f1 = cone_functionals(A0), cone_functionals(A1)
        rows.append(dict(family='post_opening_ridge_A1', lam=lam, cv_mse=float(np.mean(errs)),
                         cv_se=float(np.std(errs, ddof=1)/np.sqrt(len(errs))) if len(errs) > 1 else np.nan,
                         n_folds=len(errs), H1_A0=f0['mp'], H2_A0=f0['difference'],
                         mp_A1=f1['mp'], difference_A1=f1['difference'], frobenius_A1=float(np.linalg.norm(A1)),
                         status='observed_after_opening_descriptive'))
    errs = []
    for yr in np.unique(years):
        tr, te = years != yr, years == yr
        if tr.sum() < spec['minimum_event_clusters'] or not te.any():
            continue
        b = np.linalg.lstsq(X[tr][:, :5], y[tr], rcond=None)[0]; errs.append(np.mean((y[te]-X[te][:, :5] @ b)**2))
    rows.append(dict(family='post_opening_ridge_A1', lam=np.inf, cv_mse=float(np.mean(errs)),
                     cv_se=float(np.std(errs, ddof=1)/np.sqrt(len(errs))) if len(errs) > 1 else np.nan,
                     n_folds=len(errs), H1_A0=np.nan, H2_A0=np.nan, mp_A1=0., difference_A1=0., frobenius_A1=0.,
                     status='observed_after_opening_descriptive_block_excluded'))
    path = pd.DataFrame(rows)
    ridge_state_block.folds = fold_table(X, y, years, pen, spec)
    finite = path[np.isfinite(path.lam)]
    i_min = int(finite.cv_mse.idxmin()); thresh = finite.cv_mse[i_min] + finite.cv_se[i_min]
    chosen = finite[finite.cv_mse <= thresh].lam.max()
    path['chosen_1se_largest_lambda'] = path.lam.eq(chosen)
    path['penalty_weights'] = '1,1,2 (Frobenius: off-diagonal counted twice)'
    return path


def convexity_bootstrap(T, spec, u, z, draws, seed):
    X = surface_design(T[u], T[z], T.crossfit_state_z); y = T.crossfit_abnormal_log_BV.to_numpy(float)
    g = T.trade_date.astype(str)
    fit = clustered(y, X, g, spec['minimum_event_clusters']); b = fit['beta']
    def lam_min(beta):
        A = np.array([[beta[1], beta[3]], [beta[3], beta[2]]]); return float(np.linalg.eigvalsh(A)[0])
    resid = y - X @ b
    groups = pd.factorize(g)[0]; G = groups.max()+1
    rng = np.random.default_rng(seed); XtXi = np.linalg.pinv(X.T @ X)
    draws_lam = []
    for _ in range(draws):
        sign = rng.choice([-1., 1.], size=G)[groups]
        yb = X @ b + resid*sign
        draws_lam.append(lam_min(XtXi @ X.T @ yb))
    draws_lam = np.array(draws_lam)
    return dict(family='post_opening_convexity', lambda_min=lam_min(b), lambda_min_boot_q05=float(np.quantile(draws_lam, .05)),
                lambda_min_boot_q50=float(np.quantile(draws_lam, .5)), share_boot_negative=float(np.mean(draws_lam < 0)),
                n_clusters=int(G), draws=draws,
                note='Wild-cluster bootstrap (unrestricted) of the smallest eigenvalue of A0. Convexity in every direction '
                     'is supported only if the lower band excludes zero; positive point eigenvalues alone do not establish it.',
                status='observed_after_opening')


def design_recalibration(T, spec, u, z, W, seed):
    X = surface_design(T[u], T[z], T.crossfit_state_z)
    years = T.trade_date.dt.year.to_numpy()
    cf = W[W.phase.eq('PR') & W.root_code.eq(spec['primary_root']) & ~W.is_event]
    draw, sigma, n_pool = noise_sampler(cf, np.random.default_rng(seed))
    table = primary_power(X, years, draw, spec, np.random.default_rng(seed+1))
    table['scope'] = 'design_conditional_after_opening_aligned_schatz_metric'
    table['alternative'] = 'isotropic (a11=a22=delta, a12=0 for H1; a12=-delta*pi/4 for H2)'
    y_obs = T.crossfit_abnormal_log_BV.to_numpy(float)
    b = clustered(y_obs, X, T.trade_date.astype(str), spec['minimum_event_clusters'])['beta']
    A_obs = np.array([[b[1], b[3]], [b[3], b[2]]]); mp_obs = cone_functionals(A_obs)['mp']
    rows = []
    if np.isfinite(mp_obs) and mp_obs > 0:
        contrasts = surface_contrasts(); cal = spec['calibration']
        clusters = np.arange(len(X)).astype(str); alpha_worst = spec['primary_family']['alpha']/spec['primary_family']['size']
        rng = np.random.default_rng(seed+2)
        for delta in cal['delta_grid']:
            A = A_obs*(delta/mp_obs); beta = np.array([0, A[0, 0], A[1, 1], A[0, 1], 0, 0, 0, 0.])
            rej = 0
            for _ in range(cal['replications']):
                yy = X @ beta + draw(years)
                r = wild_contrast(yy, X, clusters, contrasts[0], cal['draws'], rng, alternative='greater',
                                  min_clusters=spec['minimum_event_clusters'])
                rej += r['p_wild'] <= alpha_worst
            rate = rej/cal['replications']
            rows.append(dict(hypothesis='H1_MP_cone_mean', delta=delta, rejection_rate=rate,
                             power_lower_95=wilson_lower(rate, cal['replications']), replications=cal['replications'],
                             draws=cal['draws'], rejection_threshold=alpha_worst, n_events=len(X),
                             metric='aligned_schatz', scope='design_conditional_after_opening_aligned_schatz_metric',
                             alternative='observed geometry: A0_hat scaled so that its MP-cone mean equals delta'))
    return pd.concat([table, pd.DataFrame(rows)], ignore_index=True)


def exploratory(build, out, calibration_dir=None, smoke=False):
    build = Path(build)
    manifest, spec, code_changed = verify_opened_build(build)
    out = new_output(out)
    dump(out/'run_manifest.json', dict(status='running', mode='post_opening_exploratory'))
    w = pd.read_csv(build/'windows.csv', parse_dates=['trade_date'])
    indicators = pd.read_csv(build/'indicators.csv', parse_dates=['trade_date'])
    indicators['ois1y_10bp'] = indicators.OIS_1Y/10
    draws = 19 if smoke else spec['secondary_family']['draws']
    spec = dict(spec, calibration=dict(spec['calibration'], replications=6 if smoke else 199, draws=39 if smoke else 999,
                                       delta_grid=[0, .05, .075, .1, .125, .15, .2, .3]))
    W, _ = counterfactual_v2(w, spec)
    root = spec['primary_root']; u, z = spec['primary_coordinates']['u'], spec['primary_coordinates']['z']
    calibrated = None
    if calibration_dir is not None:
        calibrated = json.loads((Path(calibration_dir)/'status.json').read_text()).get('history_calibrated_margin')
    level1, history = [], []
    for eps_col, label in [('ois1y_10bp', 'OIS_1Y_10bp_external'), (u, 'schatz_aligned_u')]:
        T = panel(W, indicators, spec, root, 'PR', u, z, 'crossfit_abnormal_log_BV')
        T = T[np.isfinite(T[eps_col])]
        rows, *_ = mean_branch(T, spec, eps_col, label, draws, spec['seed']+1000)
        level1.extend(rows)
        history.append(history_interval(T, spec, eps_col, label, draws, spec['seed']+2000, calibrated))
    level1 = pd.DataFrame(level1)
    level1['p_holm_declared'] = holm_declared(level1.p_wild, size=len(level1))
    level1.to_csv(out/'level1_mean_branch.csv', index=False)
    pd.DataFrame(history).to_csv(out/'level1_history_interval.csv', index=False)
    bv_zero_diagnostics(W, root, 'PR').to_csv(out/'bv_zero_by_year.csv', index=False)
    Tb = panel(W, indicators, spec, root, 'PR', u, z, 'crossfit_abnormal_log_BV')
    Tr = panel(W, indicators, spec, root, 'PR', u, z, 'crossfit_abnormal_log_RV')
    common = Tb.trade_date.isin(Tr.trade_date) & Tb.trade_date.isin(Tb.trade_date)
    rows = []
    for outcome, Tc in [('crossfit_abnormal_log_BV', Tb[Tb.trade_date.isin(Tr.trade_date)]),
                        ('crossfit_abnormal_log_RV', Tr[Tr.trade_date.isin(Tb.trade_date)])]:
        r, _ = cone_tests(Tc, spec, outcome, u, z, draws, spec['seed']+3000,
                          dict(family='post_opening_common_sample', root_code=root, phase='PR', outcome=outcome,
                               indicator=u, equity=z, sample='bv_rv_common_sample', trimming='none'))
        rows.extend(r)
    pd.DataFrame(rows).to_csv(out/'common_sample_bv_rv.csv', index=False)
    pd.DataFrame(ppml_branch(W, indicators, spec, root, u, z, draws, spec['seed']+5000)).to_csv(out/'ppml_bv_levels.csv', index=False)
    T = panel(W, indicators, spec, root, 'PR', u, z, 'crossfit_abnormal_log_BV')
    lambdas = [0, 1e-3, 3e-3, 1e-2, 3e-2, .1, .3, 1, 3, 10]
    ridge_state_block(T, spec, u, z, lambdas, spec['seed']).to_csv(out/'ridge_state_block_path.csv', index=False)
    ridge_state_block.folds.to_csv(out/'ridge_state_block_folds.csv', index=False)
    from .functional_form import functional_form
    for name, table in functional_form(T, spec, u, z, draws, spec['seed']+7000).items():
        table.to_csv(out/f'functional_form_{name}.csv', index=False)
    pd.DataFrame([convexity_bootstrap(T, spec, u, z, draws, spec['seed']+6000)]).to_csv(out/'convexity_min_eigenvalue.csv', index=False)
    design_recalibration(T, spec, u, z, W, spec['seed']+4000).to_csv(out/'design_recalibration_power.csv', index=False)
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, capture_output=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=REPO, text=True, capture_output=True).stdout)
    result = dict(status='complete_exploratory_after_opening' if not smoke else 'complete_smoke_not_for_inference',
        mode='post_opening_exploratory', created_utc=timestamp(), git_sha=sha, git_dirty=dirty,
        prior_results_seen={'generation_2013_2025': True, 'confirmation_2000_2012': True},
        confirmation_verdict_unchanged='the frozen run of 2026-09-14 remains the confirmation result; these tables are observed after opening',
        code_changed_since_freeze=code_changed,
        surprise_measure_note='OIS_1Y/10 used instead of the plan\'s OIS_1M/10 because OIS_1M is missing on 13 meetings before 2002; chosen after opening',
        frozen_build_sha256=digest(build/'status.json'), code_hashes=code_hashes(),
        n_primary_events=len(T), draws=draws, python=platform.python_version(), numpy=np.__version__,
        pandas=pd.__version__, scipy=scipy.__version__)
    dump(out/'run_manifest.json', result)
    print(json.dumps({k: v for k, v in result.items() if k != 'code_hashes'}, indent=2), flush=True)
    return result
