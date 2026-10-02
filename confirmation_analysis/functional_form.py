import hashlib
import json
import numpy as np
import pandas as pd
from final_analysis.models import clustered, holm
from .cones import surface_design, cone_functionals
from .inference import wild_contrast

PHI = (np.arange(40000) + .5) * (2*np.pi/40000)
DIAGNOSTIC_VERSION = 'functional_form_v2_20260916'


def degree2_basis(u, z):
    return np.column_stack([u*u, z*z, 2*u*z])


def degree1_basis(u, z):
    uz = u*z
    return np.column_stack([np.abs(u), np.abs(z), np.sign(uz)*np.sqrt(np.abs(uz))])


def quadratic_angles_radial1(u, z):
    r = np.hypot(u, z)
    return np.divide(degree2_basis(u, z), r[:, None],
                     out=np.zeros((len(r), 3)), where=r[:, None] > 0)


def absolute_angles_radial2(u, z):
    return degree1_basis(u, z) * np.hypot(u, z)[:, None]


BASES = {'degree2_quadratic': degree2_basis, 'degree1_absolute': degree1_basis,
         'quadratic_angles_radial1': quadratic_angles_radial1,
         'absolute_angles_radial2': absolute_angles_radial2}


def sector_masks(u, z):
    u, z = np.asarray(u), np.asarray(z)
    mp = ((u < 0) & (z > 0)) | ((u > 0) & (z < 0))
    cbi = ((u > 0) & (z > 0)) | ((u < 0) & (z < 0))
    return mp, cbi, (u == 0) | (z == 0)


def design_with_state(basis_fn, u, z, s):
    B = basis_fn(np.asarray(u, float), np.asarray(z, float))
    s = np.asarray(s, float)
    return np.column_stack([np.ones(len(B)), B, s, B*s[:, None]])


def response_on_circle(basis_fn, coef, r=1.):
    return basis_fn(r*np.cos(PHI), r*np.sin(PHI)) @ coef


def cone_means_numeric(basis_fn, coef, r=1.):
    m = response_on_circle(basis_fn, coef, r)
    mp, cbi, _ = sector_masks(np.cos(PHI), np.sin(PHI))
    return dict(mp=float(m[mp].mean()), cbi=float(m[cbi].mean()), difference=float(m[mp].mean()-m[cbi].mean()),
                mean_all=float(m.mean()), radius=r)


def equity_design(uu, zz, s):
    X = np.column_stack([np.ones(len(uu)), uu, np.abs(uu), zz, np.abs(zz), s,
                         uu*s, np.abs(uu)*s, zz*s, np.abs(zz)*s])
    names = ['const', 'u', 'abs_u', 'z', 'abs_z', 'state',
             'u_x_state', 'abs_u_x_state', 'z_x_state', 'abs_z_x_state']
    return X, names


def mean_branch_with_equity(T, spec, u, z, draws, seed):
    uu, zz, s = T[u].to_numpy(float), T[z].to_numpy(float), T.crossfit_state_z.to_numpy(float)
    y = T.crossfit_abnormal_log_BV.to_numpy(float); g = T.trade_date.astype(str)
    X, names = equity_design(uu, zz, s)
    rows = []
    for j, name in enumerate(names[1:], 1):
        c = np.zeros(X.shape[1]); c[j] = 1
        r = wild_contrast(y, X, g, c, draws, np.random.default_rng(seed+j), alternative='two-sided',
                          min_clusters=spec['minimum_event_clusters'])
        rows.append(dict(family='post_opening_mean_branch_with_equity', term=name,
                         **{k: r[k] for k in ['estimate', 'se_cr1', 'p_wild', 'n_rows', 'n_clusters']},
                         status='observed_after_opening',
                         note='Signed and absolute coordinates, ALL four state interactions; nests the original scalar design'))
    adjusted = holm([r['p_wild'] for r in rows])
    for row, p in zip(rows, adjusted):
        row['p_holm_exploratory_9'] = float(p)
    return rows


def basis_comparison(T, spec, u, z):
    uu, zz, s = T[u].to_numpy(float), T[z].to_numpy(float), T.crossfit_state_z.to_numpy(float)
    y = T.crossfit_abnormal_log_BV.to_numpy(float); years = T.trade_date.dt.year.to_numpy()
    folds, fits = [], []
    for name, fn in BASES.items():
        X = design_with_state(fn, uu, zz, s)
        b = np.linalg.lstsq(X, y, rcond=None)[0]
        cm = cone_means_numeric(fn, b[1:4])
        fit = clustered(y, X, T.trade_date.astype(str), spec['minimum_event_clusters'])
        fits.append(dict(basis=name, n_rows=len(T), in_sample_r2=float(1-np.sum((y-X@b)**2)/np.sum((y-y.mean())**2)),
                         coef_1=b[1], coef_2=b[2], coef_3=b[3], mp_cone_mean_r1=cm['mp'], cbi_cone_mean_r1=cm['cbi'],
                         difference_r1=cm['difference'], status='observed_after_opening_descriptive'))
        for yr in np.unique(years):
            tr, te = years != yr, years == yr
            if tr.sum() < spec['minimum_event_clusters'] or not te.any():
                continue
            bt = np.linalg.lstsq(X[tr], y[tr], rcond=None)[0]
            folds.append(dict(basis=name, year=int(yr), n_test=int(te.sum()), mse=float(np.mean((y[te]-X[te]@bt)**2))))
    folds = pd.DataFrame(folds)
    paired = folds.pivot(index='year', columns='basis', values='mse').reset_index()
    paired['difference_deg1_minus_deg2'] = paired['degree1_absolute']-paired['degree2_quadratic']
    paired['difference_radial1_minus_radial2_quadratic_angles'] = (
        paired.quadratic_angles_radial1-paired.degree2_quadratic)
    paired['difference_radial1_minus_radial2_absolute_angles'] = (
        paired.degree1_absolute-paired.absolute_angles_radial2)
    summary = dict(mean_mse_degree2=float(paired.degree2_quadratic.mean()), mean_mse_degree1=float(paired.degree1_absolute.mean()),
                   mean_paired_difference=float(paired.difference_deg1_minus_deg2.mean()),
                   se_paired_difference=float(paired.difference_deg1_minus_deg2.std(ddof=1)/np.sqrt(len(paired))),
                   folds_won_by_degree1=int((paired.difference_deg1_minus_deg2 < 0).sum()), n_folds=len(paired),
                   mean_mse_quadratic_angles_radial1=float(paired.quadratic_angles_radial1.mean()),
                   mean_mse_absolute_angles_radial2=float(paired.absolute_angles_radial2.mean()),
                   folds_won_by_radial1_quadratic_angles=int((paired.quadratic_angles_radial1 < paired.degree2_quadratic).sum()),
                   note='Equal-weighted annual losses conditional on the existing cross-fitted outcome and indicators. '
                        'Fold losses share training data; the reported SE is descriptive, not an independent-fold test.')
    return pd.DataFrame(fits), paired, summary


def sector_means_by_radius(T, spec, u, z, draws, seed, n_bins=3, min_per_cell=8):
    uu, zz = T[u].to_numpy(float), T[z].to_numpy(float)
    y = T.crossfit_abnormal_log_BV.to_numpy(float); s = T.crossfit_state_z.to_numpy(float)
    r = np.hypot(uu, zz); mp, cbi, axis = sector_masks(uu, zz)
    edges = np.quantile(r, np.linspace(0, 1, n_bins+1)); edges[-1] += 1e-9
    fits = {name: np.linalg.lstsq(design_with_state(fn, uu, zz, s), y, rcond=None)[0] for name, fn in BASES.items()}
    rows = []
    for k in range(n_bins):
        inb = (r >= edges[k]) & (r < edges[k+1])
        n_mp, n_cbi = int((inb & mp).sum()), int((inb & cbi).sum())
        eligible = inb & ~axis
        supported = (n_mp >= min_per_cell and n_cbi >= min_per_cell
                     and eligible.sum() >= spec['minimum_event_clusters'])
        row = dict(radius_bin=k+1, r_low=float(edges[k]), r_high=float(edges[k+1]),
                   r_median=float(np.median(r[inb])) if inb.any() else np.nan,
                   n_total=int(inb.sum()), n_axis=int((inb & axis).sum()),
                   n_mp=n_mp, n_cbi=n_cbi, supported=bool(supported),
                   support_scope='minimum cell and cluster counts only; NOT uniform angular support',
                   contrast_scope='Within-bin association adjusted for state, NOT a fixed-radius cone functional',
                   raw_mp_minus_cbi=np.nan, p_wild_two_sided=np.nan,
                   bin_test_status='insufficient_cell_or_cluster_count',
                   axis_rule='exclude exact u=0 or z=0 from the bin contrast; retain in surface fits')
        for label, mask in [('mp', mp), ('cbi', cbi)]:
            rr = r[inb & mask]
            for suffix, fn in [('min', np.min), ('max', np.max), ('median', np.median)]:
                row[f'r_{label}_{suffix}'] = float(fn(rr)) if len(rr) else np.nan
        row['radial_range_overlap_low'] = max(row['r_mp_min'], row['r_cbi_min'])
        row['radial_range_overlap_high'] = min(row['r_mp_max'], row['r_cbi_max'])
        if row['supported']:
            X = np.column_stack([np.ones(eligible.sum()), mp[eligible].astype(float), s[eligible]])
            c = np.array([0, 1, 0.])
            try:
                res = wild_contrast(y[eligible], X, T.trade_date.astype(str).to_numpy()[eligible], c, draws,
                                    np.random.default_rng(seed+k), alternative='two-sided',
                                    min_clusters=spec['minimum_event_clusters'])
                row.update(raw_mp_minus_cbi=res['estimate'], p_wild_two_sided=res['p_wild'], bin_test_status='estimated')
            except ValueError as exc:
                row.update(bin_test_status='unestimable', note=str(exc))
        for name, fn in BASES.items():
            cm = cone_means_numeric(fn, fits[name][1:4], r=row['r_median'])
            row[f'model_{name}_mp_minus_cbi_at_r_median'] = cm['difference']
        rows.append(row)
    result = pd.DataFrame(rows)
    result['p_holm_exploratory_bins'] = holm(np.where(np.isfinite(result.p_wild_two_sided),
                                                    result.p_wild_two_sided, 1.))
    return result


def _natural_basis(x, knots):
    x = np.asarray(x, float)
    if len(knots) < 3:
        return x[:, None]
    last, penultimate = knots[-1], knots[-2]
    span = knots[-1]-knots[0]
    clipped = np.clip(x, knots[0], knots[-1])
    def d(value, knot):
        return (np.maximum(value-knot, 0.)**3 - np.maximum(value-last, 0.)**3)/(last-knot)
    cols = [x]
    for knot in knots[:-2]:
        val = (d(clipped, knot)-d(clipped, penultimate))/span**2
        slope = 3*((last-knot)-(last-penultimate))/span**2
        val += np.maximum(x-last, 0.)*slope
        cols.append(val)
    return np.column_stack(cols)


def _safe_scale(values):
    sd = np.std(values, axis=0)
    return np.where(sd > 1e-12, sd, 1.)


def _marginal_apply(values, meta):
    raw = _natural_basis((np.asarray(values)-meta['centre'])/meta['scale'], meta['knots'])
    return (raw-meta['basis_mean'])/meta['basis_scale']


def _marginal_fit(values, n_knots):
    values = np.asarray(values, float)
    meta = dict(centre=float(values.mean()), scale=float(_safe_scale(values)))
    scaled = (values-meta['centre'])/meta['scale']
    meta['knots'] = np.unique(np.quantile(scaled, np.linspace(0, 1, n_knots+2)))
    raw = _natural_basis(scaled, meta['knots'])
    meta.update(basis_mean=raw.mean(axis=0), basis_scale=_safe_scale(raw))
    return meta


def spline_transform_apply(u, z, state, meta):
    Bu, Bz = _marginal_apply(u, meta['u']), _marginal_apply(z, meta['z'])
    tensor = np.einsum('ij,ik->ijk', Bu, Bz).reshape(len(Bu), -1)
    B = np.column_stack([Bu, Bz, tensor])
    s = (np.asarray(state)-meta['state_mean'])/meta['state_scale']
    raw = np.column_stack([B, s[:, None]*B])
    features = (raw-meta['feature_mean'])/meta['feature_scale']
    return np.column_stack([np.ones(len(Bu)), s, features])


def spline_transform_fit(u, z, state, n_knots=2):
    meta = {'u': _marginal_fit(u, n_knots), 'z': _marginal_fit(z, n_knots),
            'state_mean': float(np.mean(state)), 'state_scale': float(_safe_scale(state))}
    Bu, Bz = _marginal_apply(u, meta['u']), _marginal_apply(z, meta['z'])
    tensor = np.einsum('ij,ik->ijk', Bu, Bz).reshape(len(Bu), -1)
    B = np.column_stack([Bu, Bz, tensor])
    s = (np.asarray(state)-meta['state_mean'])/meta['state_scale']
    raw = np.column_stack([B, s[:, None]*B])
    meta.update(feature_mean=raw.mean(axis=0), feature_scale=_safe_scale(raw))
    pen = np.ones(2+raw.shape[1])
    pen[[0, 1, 2, 2+Bu.shape[1], 2+B.shape[1], 2+B.shape[1]+Bu.shape[1]]] = 0.
    return spline_transform_apply(u, z, state, meta), pen, meta


def _ridge_fit(X, y, pen, lam):
    if lam <= 0:
        raise ValueError('Spline penalty must be positive')
    augmented = np.vstack([X, np.diag(np.sqrt(lam*len(y)*pen))])
    return np.linalg.lstsq(augmented, np.r_[y, np.zeros(X.shape[1])], rcond=None)[0]


def tensor_spline_reference(T, spec, u, z, lambdas=(1e-3, 1e-2, 1e-1, 1, 10, 100), n_knots=2):
    uu, zz, s = T[u].to_numpy(float), T[z].to_numpy(float), T.crossfit_state_z.to_numpy(float)
    y = T.crossfit_abnormal_log_BV.to_numpy(float); years = T.trade_date.dt.year.to_numpy()
    lambdas = sorted(set(float(lam) for lam in lambdas))
    if not lambdas or any(not np.isfinite(lam) or lam <= 0 for lam in lambdas):
        raise ValueError('Positive finite spline penalty grid required')
    rows = []
    for yr in np.unique(years):
        tr, te = years != yr, years == yr
        if tr.sum() < spec['minimum_event_clusters'] or not te.any():
            continue
        losses = {lam: [] for lam in lambdas}
        for iy in np.unique(years[tr]):
            itr, ite = tr & (years != iy), tr & (years == iy)
            if itr.sum() < spec['minimum_event_clusters'] or not ite.any():
                continue
            Xtr, pen, meta = spline_transform_fit(uu[itr], zz[itr], s[itr], n_knots)
            Xte = spline_transform_apply(uu[ite], zz[ite], s[ite], meta)
            for lam in lambdas:
                b = _ridge_fit(Xtr, y[itr], pen, lam)
                losses[lam].append(float(np.mean((y[ite]-Xte@b)**2)))
        n_inner = len(losses[lambdas[0]])
        if n_inner < 2:
            rows.append(dict(year=int(yr), n_test=int(te.sum()), lambda_inner=np.nan, mse=np.nan,
                             spline_status='insufficient_inner_folds', inner_folds=n_inner))
            continue
        best = min(lambdas, key=lambda lam: (np.mean(losses[lam]), -lam))
        Xtr, pen, meta = spline_transform_fit(uu[tr], zz[tr], s[tr], n_knots)
        Xte = spline_transform_apply(uu[te], zz[te], s[te], meta)
        b = _ridge_fit(Xtr, y[tr], pen, best)
        knots = {key: (meta[key]['knots']*meta[key]['scale']+meta[key]['centre']).tolist()
                 for key in ['u', 'z']}
        rows.append(dict(year=int(yr), n_test=int(te.sum()), lambda_inner=best,
                         mse=float(np.mean((y[te]-Xte@b)**2)), spline_status='estimated', inner_folds=n_inner,
                         inner_cv_mse=float(np.mean(losses[best])), n_features=Xtr.shape[1],
                         knots_training_only=json.dumps(knots, sort_keys=True),
                         training_dates_sha256=hashlib.sha256('\n'.join(T.trade_date[tr].astype(str)).encode()).hexdigest(),
                         test_u_outside_training_range=int(((uu[te] < uu[tr].min()) | (uu[te] > uu[tr].max())).sum()),
                         test_z_outside_training_range=int(((zz[te] < zz[tr].min()) | (zz[te] > zz[tr].max())).sum()),
                         penalty_scope='scaled nonlinear main/tensor terms and their state interactions',
                         inner_losses=json.dumps({str(k): float(np.mean(v)) for k, v in losses.items()}, sort_keys=True)))
    return pd.DataFrame(rows)


def functional_form(T, spec, u, z, draws, seed):
    cols = [u, z, 'crossfit_state_z', 'crossfit_abnormal_log_BV']
    if not np.isfinite(T[cols]).all().all() or T.trade_date.isna().any() or T.trade_date.duplicated().any():
        raise ValueError('Functional diagnostics require finite inputs and one row per event date')
    out = {}
    out['mean_branch_with_equity'] = pd.DataFrame(mean_branch_with_equity(T, spec, u, z, draws, seed))
    fits, paired, summary = basis_comparison(T, spec, u, z)
    spline = tensor_spline_reference(T, spec, u, z)
    paired = paired.merge(spline.rename(columns={'mse': 'tensor_spline_reference'}),
                          on='year', how='left')
    summary['mean_mse_tensor_spline'] = float(paired.tensor_spline_reference.mean())
    out['basis_fits'] = fits
    out['basis_paired_annual_errors'] = paired
    out['basis_summary'] = pd.DataFrame([summary])
    out['sector_means_by_radius'] = sector_means_by_radius(T, spec, u, z, draws, seed+50)
    for t in out.values():
        t['status'] = t.get('status', 'observed_after_opening_descriptive')
        t['diagnostic_version'] = DIAGNOSTIC_VERSION
    return out
