import argparse
import json
import platform
import subprocess
from pathlib import Path
import numpy as np
import pandas as pd
import scipy
from scipy.stats import norm
from final_analysis.models import clustered, wild_test, residual_partial_r2
from .estimate import panel
from .exploratory import verify_opened_build
from .functional_form import design_with_state, cone_means_numeric, equity_design
from .minute import GenerationDesign, outcome_from_minute
from .nuisance import counterfactual_v2
from .protocol import REPO, digest, dump, timestamp, new_output, code_hashes

EXPONENT_GRID = np.round(np.arange(0.05, 3.0001, 0.05), 4)
PANEL_MEASURES = ['BV', 'BV_excl5', 'VOL']
ODD_TERMS = ['u', 'z', 'u_x_state', 'z_x_state']
LR_CRITICAL = 3.841458820694124


def radius(u, z):
    return np.hypot(u, z)


def quadratic_angles(p):
    def basis(u, z):
        u = np.asarray(u, float); z = np.asarray(z, float); r = radius(u, z)
        scale = np.divide(r**p, r**2, out=np.zeros_like(r), where=r > 0)
        return np.column_stack([u*u, z*z, 2*u*z])*scale[:, None]
    return basis


def absolute_angles(p):
    def basis(u, z):
        u = np.asarray(u, float); z = np.asarray(z, float); r = radius(u, z)
        scale = np.divide(r**p, r, out=np.zeros_like(r), where=r > 0)
        uz = u*z
        return np.column_stack([np.abs(u), np.abs(z), np.sign(uz)*np.sqrt(np.abs(uz))])*scale[:, None]
    return basis


ANGULAR = {'quadratic_angles': quadratic_angles, 'absolute_angles': absolute_angles}


def logarithmic(name):
    def basis(u, z):
        u = np.asarray(u, float); z = np.asarray(z, float); r = radius(u, z)
        lr = np.log(np.where(r > 0, r, 1.))
        unit = ANGULAR[name](1.)(u, z)
        radial_one = np.divide(unit, r[:, None], out=np.zeros_like(unit), where=r[:, None] > 0)
        return radial_one*lr[:, None]
    return basis


def fit_sse(u, z, s, y, basis):
    X = design_with_state(basis, u, z, s)
    b = np.linalg.lstsq(X, y, rcond=None)[0]
    return float(np.sum((y-X@b)**2))


def fold_mse(u, z, s, y, years, basis, minimum):
    X = design_with_state(basis, u, z, s); losses = []
    for yr in np.unique(years):
        tr, te = years != yr, years == yr
        if tr.sum() < minimum or not te.any():
            continue
        b = np.linalg.lstsq(X[tr], y[tr], rcond=None)[0]
        losses.append(float(np.mean((y[te]-X[te]@b)**2)))
    return float(np.mean(losses)) if losses else np.nan


def arrays(T):
    return (T.u.to_numpy(float), T.z.to_numpy(float), T.crossfit_state_z.to_numpy(float),
            T.crossfit_abnormal_log_BV.to_numpy(float), T.trade_date.astype(str).to_numpy(),
            pd.to_datetime(T.trade_date).dt.year.to_numpy())


def sse_curve(u, z, s, y, family):
    out = []
    for p in EXPONENT_GRID:
        X = design_with_state(family(p), u, z, s)
        b = np.linalg.lstsq(X, y, rcond=None)[0]
        out.append(float(np.sum((y-X@b)**2)))
    return np.array(out)


def cv_curve(u, z, s, y, years, family, minimum):
    out = []
    for p in EXPONENT_GRID:
        X = design_with_state(family(p), u, z, s); losses = []
        for yr in np.unique(years):
            tr, te = years != yr, years == yr
            if tr.sum() < minimum or not te.any():
                continue
            b = np.linalg.lstsq(X[tr], y[tr], rcond=None)[0]
            losses.append(float(np.mean((y[te]-X[te]@b)**2)))
        out.append(float(np.mean(losses)) if losses else np.nan)
    return np.array(out)


def mean_elasticity(u, z, s, y, g, basis, spec):
    X = design_with_state(basis, u, z, s)
    c = np.zeros(X.shape[1])
    for k in range(3):
        e = np.zeros(3); e[k] = 1.
        c[1+k] = cone_means_numeric(basis, e, r=np.e)['mean_all']
    fit = clustered(y, X, g, spec['minimum_event_clusters'])
    est = float(c@fit['beta']); se = float(np.sqrt(c@fit['V']@c))
    return dict(mean_elasticity_log_radius=est, mean_elasticity_se_cr1=se,
                p_normal_elasticity_equals_0=float(2*norm.sf(abs(est/se))) if se > 0 else np.nan,
                p_normal_elasticity_equals_1=float(2*norm.sf(abs((est-1)/se))) if se > 0 else np.nan)


def exponent_profile(T, spec, reps, rng):
    u, z, s, y, g, years = arrays(T)
    n = len(y); rows, curves = [], []
    for name, family in ANGULAR.items():
        sse = sse_curve(u, z, s, y, family)
        lr = n*np.log(sse/sse.min())
        inside = EXPONENT_GRID[lr <= LR_CRITICAL]
        cv = cv_curve(u, z, s, y, years, family, spec['minimum_event_clusters'])
        boot = []
        for _ in range(reps):
            pick = rng.integers(0, n, n)
            boot.append(float(EXPONENT_GRID[np.argmin(sse_curve(u[pick], z[pick], s[pick], y[pick], family))]))
        boot = np.array(boot)
        at = lambda q: float(lr[np.argmin(np.abs(EXPONENT_GRID-q))])
        log_basis = logarithmic(name)
        sse_log = fit_sse(u, z, s, y, log_basis)
        rows.append(dict(angular_basis=name, n_events=n, exponent_hat=float(EXPONENT_GRID[np.argmin(sse)]),
                         lr_interval_low=float(inside.min()), lr_interval_high=float(inside.max()),
                         lr_at_exponent_1=at(1.), lr_at_exponent_2=at(2.),
                         exponent_cv=float(EXPONENT_GRID[np.nanargmin(cv)]) if np.isfinite(cv).any() else np.nan,
                         bootstrap_q025=float(np.quantile(boot, .025)), bootstrap_q975=float(np.quantile(boot, .975)),
                         bootstrap_share_below_1_5=float(np.mean(boot < 1.5)), bootstrap_reps=reps,
                         lr_log_radius_vs_best_power=float(n*np.log(sse_log/sse.min())),
                         cv_mse_best_power=float(np.nanmin(cv)) if np.isfinite(cv).any() else np.nan,
                         cv_mse_log_radius=fold_mse(u, z, s, y, years, log_basis, spec['minimum_event_clusters']),
                         cv_mse_exponent_1=float(cv[np.argmin(np.abs(EXPONENT_GRID-1.))]),
                         cv_mse_exponent_2=float(cv[np.argmin(np.abs(EXPONENT_GRID-2.))]),
                         **mean_elasticity(u, z, s, y, g, log_basis, spec),
                         lr_interval_on_grid_edge=bool(inside.min() <= EXPONENT_GRID[0] or inside.max() >= EXPONENT_GRID[-1])))
        curves.append(pd.DataFrame(dict(angular_basis=name, exponent=EXPONENT_GRID, sse=sse, lr=lr, cv_mse=cv)))
    return rows, pd.concat(curves, ignore_index=True)


def contrast_vector(basis):
    c = np.zeros(8)
    for k in range(3):
        e = np.zeros(3); e[k] = 1.
        c[1+k] = cone_means_numeric(basis, e)['difference']
    return c


def contrast_information(T, spec, exponent, flips, rng):
    u, z, s, y, g, years = arrays(T)
    rows = []
    for name, family in ANGULAR.items():
        basis = family(exponent)
        X = design_with_state(basis, u, z, s)
        c = contrast_vector(basis)
        fit = clustered(y, X, g, spec['minimum_event_clusters'])
        est = float(c@fit['beta']); se = float(np.sqrt(c@fit['V']@c))
        v_obs = float(c@np.linalg.pinv(X.T@X)@c)
        v_bal = []
        for _ in range(flips):
            zf = z*rng.choice([-1., 1.], size=len(z))
            Xf = design_with_state(basis, u, zf, s)
            v_bal.append(float(c@np.linalg.pinv(Xf.T@Xf)@c))
        retention = float(np.mean(v_bal)/v_obs)
        k = (norm.ppf(.975)+norm.ppf(.8))**2
        n_star = float(len(y)*k*se**2/est**2) if est != 0 else np.inf
        mp = np.sign(u) != np.sign(z)
        rows.append(dict(angular_basis=name, radial_exponent=exponent, n_events=len(y),
                         n_mp=int(((u != 0) & (z != 0) & mp).sum()), n_cbi=int(((u != 0) & (z != 0) & ~mp).sum()),
                         n_axis=int(((u == 0) | (z == 0)).sum()), mp_minus_cbi=est, se_cr1=se,
                         p_normal_two_sided=float(2*norm.sf(abs(est/se))) if se > 0 else np.nan,
                         information_retention_vs_independent_signs=retention,
                         meetings_for_80pct_power_observed_design=n_star,
                         meetings_for_80pct_power_independent_signs=n_star*retention, flips=flips))
    return rows


def odd_block(T, spec, draws, rng):
    u, z, s, y, g, years = arrays(T)
    X, names = equity_design(u, z, s)
    odd = [names.index(t) for t in ODD_TERMS]
    even = [j for j in range(len(names)) if j not in odd]
    p_joint, stat, _ = wild_test(y, X, g, odd, draws, rng, spec['minimum_event_clusters'])
    return dict(n_events=len(y), partial_r2_odd_block=float(residual_partial_r2(y, X[:, even], X[:, odd])),
                p_wild_joint_odd_block=float(p_joint), odd_terms='|'.join(ODD_TERMS), draws=draws)


def historical_panels(build, minute_panel, spec):
    w = pd.read_csv(build/'windows.csv', parse_dates=['trade_date'])
    indicators = pd.read_csv(build/'indicators.csv', parse_dates=['trade_date'])
    u, z = spec['primary_coordinates']['u'], spec['primary_coordinates']['z']
    out = {}
    cf, _ = counterfactual_v2(w, spec)
    out['BV5_frozen'] = panel(cf, indicators, spec, 'gg', 'PR', u, z, 'crossfit_abnormal_log_BV').rename(columns={u: 'u', z: 'z'})
    pm = minute_panel[minute_panel['sample'].eq('H_2000_2012')].drop_duplicates('trade_date')
    for m in PANEL_MEASURES:
        cf = outcome_from_minute(w, pm, spec, m)
        out[m] = panel(cf, indicators, spec, 'gg', 'PR', u, z, 'crossfit_abnormal_log_BV').rename(columns={u: 'u', z: 'z'})
    return out


def generation_panels(design, minute_panel):
    pm = minute_panel[minute_panel['sample'].eq('G_2013_2025')].drop_duplicates('trade_date')
    out = {'BV5_frozen': design.panel()}
    for m in PANEL_MEASURES:
        out[m] = design.panel(pm, m)
    return out


def analyse(panels, sample, spec, reps, flips, draws, seed):
    exp_rows, curves, info_rows, odd_rows = [], [], [], []
    for k, (measure, T) in enumerate(panels.items()):
        rng = np.random.default_rng(seed+100*k)
        rows, curve = exponent_profile(T, spec, reps, rng)
        exp_rows += [dict(sample=sample, measure=measure, **r) for r in rows]
        curves.append(curve.assign(sample=sample, measure=measure))
        for e in (1., 2.):
            info_rows += [dict(sample=sample, measure=measure, **r) for r in contrast_information(T, spec, e, flips, rng)]
        odd_rows.append(dict(sample=sample, measure=measure, **odd_block(T, spec, draws, rng)))
    return exp_rows, curves, info_rows, odd_rows


def design_information(build, minute_run_dir, out, generation_dir=None, bridge_dir=None, smoke=False):
    build = Path(build)
    manifest, spec, code_changed = verify_opened_build(build)
    out = new_output(out)
    dump(out/'run_manifest.json', dict(status='running', mode='post_opening_design_information'))
    minute_panel = pd.read_csv(Path(minute_run_dir)/'minute_measures_panel.csv', parse_dates=['trade_date'])
    minute_manifest = json.loads((Path(minute_run_dir)/'run_manifest.json').read_text())
    reps, flips = (9, 5) if smoke else (999, 999)
    draws = 19 if smoke else spec['secondary_family']['draws']
    parts = [analyse(historical_panels(build, minute_panel, spec), 'H_2000_2012', spec, reps, flips, draws, spec['seed']+11000)]
    if generation_dir is not None:
        design = GenerationDesign(generation_dir, bridge_dir)
        design.reproduction(REPO/'reference_outputs/cross_epoch_20260916/inputs/generation_harmonized_native_state.csv')
        parts.append(analyse(generation_panels(design, minute_panel), 'G_2013_2025', spec, reps, flips, draws, spec['seed']+12000))
    pd.DataFrame([r for p in parts for r in p[0]]).to_csv(out/'radial_exponent_profile.csv', index=False)
    pd.concat([c for p in parts for c in p[1]], ignore_index=True).to_csv(out/'radial_exponent_curves.csv', index=False)
    pd.DataFrame([r for p in parts for r in p[2]]).to_csv(out/'sector_contrast_information.csv', index=False)
    pd.DataFrame([r for p in parts for r in p[3]]).to_csv(out/'central_symmetry_odd_block.csv', index=False)
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, capture_output=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=REPO, text=True, capture_output=True).stdout)
    result = dict(status='complete_design_information_after_opening' if not smoke else 'complete_smoke_not_for_inference',
                  mode='post_opening_design_information', created_utc=timestamp(), git_sha=sha, git_dirty=dirty,
                  code_changed_since_freeze=code_changed,
                  prior_results_seen={'generation_2013_2025': True, 'confirmation_2000_2012': True},
                  confirmation_verdict_unchanged=True, frozen_build_sha256=digest(build/'status.json'),
                  minute_run_manifest_sha256=digest(Path(minute_run_dir)/'run_manifest.json'),
                  minute_run_git_sha=minute_manifest.get('git_sha'),
                  exponent_grid=[float(EXPONENT_GRID[0]), float(EXPONENT_GRID[-1]), 0.05],
                  bootstrap_reps=reps, sign_flips=flips, draws=draws,
                  exponent_note='radial exponent estimated on a grid from 0.05 to 3 with the angular basis fixed; interval from the profile likelihood ratio with one degree of freedom and from a meeting bootstrap of the grid minimiser; the logarithmic radial law is compared separately, since the power family does not nest it',
                  retention_note='information retention compares the homoskedastic variance of the sector contrast under the observed design with its mean under designs in which the sign of the equity coordinate is drawn independently for each meeting, keeping magnitudes and states',
                  sample_size_note='meetings needed for a two-sided five percent test with eighty percent power at the observed contrast and standard error, scaling the observed design',
                  code_hashes=code_hashes(), python=platform.python_version(),
                  numpy=np.__version__, pandas=pd.__version__, scipy=scipy.__version__)
    dump(out/'run_manifest.json', result)
    print(json.dumps({k: v for k, v in result.items() if k != 'code_hashes'}, indent=2), flush=True)
    return result


def main():
    p = argparse.ArgumentParser(prog='python -m confirmation_analysis.design_information')
    p.add_argument('--build', type=Path, required=True)
    p.add_argument('--minute-run', type=Path, required=True)
    p.add_argument('--generation-dir', type=Path)
    p.add_argument('--bridge-dir', type=Path)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--smoke', action='store_true')
    a = p.parse_args()
    design_information(a.build, a.minute_run, a.output, a.generation_dir, a.bridge_dir, a.smoke)


if __name__ == '__main__':
    main()
