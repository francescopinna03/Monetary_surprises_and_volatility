import argparse
import json
import platform
import subprocess
from pathlib import Path
import numpy as np
import pandas as pd
import scipy
from .design_information import EXPONENT_GRID, quadratic_angles, sse_curve, historical_panels
from .exploratory import verify_opened_build
from .minute import GenerationDesign
from .protocol import REPO, digest, dump, timestamp, new_output, code_hashes
from . import fed_replication as fed

TAIL_MULTIPLE = 2.
MIN_TAIL = 30
LR_10 = 2.705543454095404
NOISE_GRID = (0., 0.5, 1., 1.5, 2., 2.5, 3.)
IMPLAUSIBLE_MULTIPLE = 1.5
CRITERIA = dict(
    tail=f'events whose measured radius is at least {TAIL_MULTIPLE} times the median radius of Gaussian noise with the control-day covariance used in the simulation; the artifact is excluded in the tail if the estimated exponent is below one and the likelihood ratio rejects exponent one at the ten percent level; fewer than {MIN_TAIL} tail events leave the criterion undecided',
    simulation=f'a linear radial law with the observed intercept, slope, state effect and residual spread is measured with noise equal to k times the control-day noise; the artifact is implausible if the median simulated exponent reaches the observed exponent only for k at least {IMPLAUSIBLE_MULTIPLE}',
    instrument='isotropic logarithmic law estimated by least squares and by two-stage least squares, instrumenting the log radius with the log radius built from an independent measurement of the policy coordinate; reported, not used in the verdict, because the two measurements share background news',
    verdict='excluded when both the tail and the simulation criteria hold; implausible when only the simulation criterion holds; tail_only when only the tail criterion holds; not_excluded otherwise')


def arrays(T):
    return (T.u.to_numpy(float), T.z.to_numpy(float), T.crossfit_state_z.to_numpy(float), T.crossfit_abnormal_log_BV.to_numpy(float))


def profile(u, z, s, y):
    sse = sse_curve(u, z, s, y, quadratic_angles)
    lr = len(y)*np.log(sse/sse.min())
    at1 = float(lr[np.argmin(np.abs(EXPONENT_GRID-1.))])
    inside = EXPONENT_GRID[lr <= LR_10]
    return float(EXPONENT_GRID[np.argmin(sse)]), at1, float(inside.min()), float(inside.max())


def noise_floor(cov, rng, draws=200000):
    L = np.linalg.cholesky(cov+1e-12*np.eye(2))
    e = rng.standard_normal((draws, 2))@L.T
    return float(np.median(np.hypot(e[:, 0], e[:, 1])))


def tail_sensitivity(T, floor, multiple):
    u, z, s, y = arrays(T)
    keep = np.hypot(u, z) >= multiple*floor
    if keep.sum() < MIN_TAIL:
        return {f'n_tail_x{multiple:g}': int(keep.sum()), f'exponent_tail_x{multiple:g}': np.nan, f'lr_at_1_tail_x{multiple:g}': np.nan}
    e, lr1, lo, hi = profile(u[keep], z[keep], s[keep], y[keep])
    return {f'n_tail_x{multiple:g}': int(keep.sum()), f'exponent_tail_x{multiple:g}': e, f'lr_at_1_tail_x{multiple:g}': lr1}


def tail_test(T, floor):
    u, z, s, y = arrays(T)
    r = np.hypot(u, z); keep = r >= TAIL_MULTIPLE*floor
    row = dict(noise_floor_median_radius=floor, tail_threshold=TAIL_MULTIPLE*floor, n_events=len(y), n_tail=int(keep.sum()))
    if keep.sum() < MIN_TAIL:
        return dict(row, tail_status='undecided_too_few_tail_events', exponent_tail=np.nan, lr_at_1_tail=np.nan,
                    interval90_low=np.nan, interval90_high=np.nan, tail_criterion=np.nan)
    e, lr1, lo, hi = profile(u[keep], z[keep], s[keep], y[keep])
    ok = bool(e < 1. and lr1 > LR_10)
    return dict(row, tail_status='decided', exponent_tail=e, lr_at_1_tail=lr1, interval90_low=lo, interval90_high=hi,
                tail_criterion=ok)


def simulate(T, noise_cov, reps, rng, symmetric_z=True):
    u, z, s, y = arrays(T)
    observed, _, _, _ = profile(u, z, s, y)
    r = np.hypot(u, z)
    X = np.column_stack([np.ones(len(y)), r, s])
    b = np.linalg.lstsq(X, y, rcond=None)[0]
    sd = float(np.std(y-X@b, ddof=3))
    var = np.array([u.var(), z.var()])
    rows = []
    for k in NOISE_GRID:
        noise = k**2*np.diag(noise_cov)
        true_var = var-noise
        if np.any(true_var <= 0.1*var):
            rows.append(dict(noise_multiple=k, status='infeasible_noise_exceeds_spread', median_exponent=np.nan, share_at_or_below_observed=np.nan)); continue
        scale = np.sqrt(true_var/var)
        tu, tz = u*scale[0], z*scale[1]
        rt = np.hypot(tu, tz)
        L = np.linalg.cholesky(k**2*noise_cov+1e-12*np.eye(2)) if k > 0 else np.zeros((2, 2))
        ex = []
        for _ in range(reps):
            e = rng.standard_normal((len(y), 2))@L.T
            ys = b[0]+b[1]*rt+b[2]*s+rng.normal(0, sd, len(y))
            sse = sse_curve(tu+e[:, 0], tz+e[:, 1], s, ys, quadratic_angles)
            ex.append(float(EXPONENT_GRID[np.argmin(sse)]))
        ex = np.array(ex)
        rows.append(dict(noise_multiple=k, status='simulated', median_exponent=float(np.median(ex)),
                         share_at_or_below_observed=float(np.mean(ex <= observed))))
    t = pd.DataFrame(rows)
    ok = t[t.status.eq('simulated')]
    hit = ok[ok.median_exponent <= observed]
    if hit.empty:
        k_star = np.inf
    else:
        i = hit.index[0]
        if i == ok.index[0]:
            k_star = float(ok.loc[i, 'noise_multiple'])
        else:
            j = ok.index[ok.index.get_loc(i)-1]
            k0, k1, m0, m1 = ok.loc[j, 'noise_multiple'], ok.loc[i, 'noise_multiple'], ok.loc[j, 'median_exponent'], ok.loc[i, 'median_exponent']
            k_star = float(k0+(k1-k0)*(m0-observed)/(m0-m1)) if m0 != m1 else float(k1)
    return t, dict(observed_exponent=observed, linear_slope=float(b[1]), residual_sd=sd, noise_multiple_needed=k_star,
                   simulation_criterion=bool(k_star >= IMPLAUSIBLE_MULTIPLE), reps=reps)


def iv_elasticity(T, u_alt):
    u, z, s, y = arrays(T)
    ra = np.hypot(u_alt, z); r = np.hypot(u, z)
    ok = np.isfinite(ra) & (ra > 0) & (r > 0)
    y, s, lr, la = y[ok], s[ok], np.log(r[ok]), np.log(ra[ok])
    n = len(y)
    X = np.column_stack([np.ones(n), s, lr]); Z = np.column_stack([np.ones(n), s, la])
    b_ols = np.linalg.lstsq(X, y, rcond=None)[0]
    first = np.linalg.lstsq(Z, lr, rcond=None)[0]
    fitted = Z@first; res1 = lr-fitted
    base = np.column_stack([np.ones(n), s])
    rss_r = np.sum((lr-base@np.linalg.lstsq(base, lr, rcond=None)[0])**2); rss_u = np.sum(res1**2)
    f_stat = float((rss_r-rss_u)/(rss_u/(n-3)))
    Xh = np.column_stack([np.ones(n), s, fitted])
    b_iv = np.linalg.lstsq(Xh, y, rcond=None)[0]
    e = y-X@b_iv
    A = np.linalg.inv(Xh.T@Xh)
    V = A@(Xh.T*(e**2))@Xh@A*n/(n-3)
    return dict(n_events=n, elasticity_ols=float(b_ols[2]), elasticity_iv=float(b_iv[2]), se_iv_hc1=float(np.sqrt(V[2, 2])),
                first_stage_f=f_stat, corr_log_radius_measures=float(np.corrcoef(lr, la)[0, 1]))


def verdict(tail_ok, sim_ok):
    if tail_ok is True and sim_ok:
        return 'excluded'
    if sim_ok:
        return 'implausible'
    if tail_ok is True:
        return 'tail_only'
    return 'not_excluded'


def analyse(sample, measure, T, noise_cov, u_alt, reps, rng):
    floor = noise_floor(noise_cov, rng)
    tail = dict(tail_test(T, floor), **tail_sensitivity(T, floor, 3.))
    sim, summary = simulate(T, noise_cov, reps, rng)
    row = dict(sample=sample, measure=measure, **tail, **summary)
    if u_alt is not None:
        row.update(iv_elasticity(T, u_alt))
    row['verdict'] = verdict(tail['tail_criterion'], summary['simulation_criterion'])
    return row, sim.assign(sample=sample, measure=measure)


def de2y(ea, dates):
    e = ea[ea.phase.eq('PR')].copy()
    e['trade_date'] = pd.to_datetime(e.event_date)
    x = e.set_index('trade_date').DE2Y.reindex(pd.to_datetime(dates)).to_numpy(float)
    return x


def ecb_samples(build, minute_run, generation_dir, bridge_dir):
    build = Path(build)
    manifest, spec, code_changed = verify_opened_build(build)
    mp = pd.read_csv(Path(minute_run)/'minute_measures_panel.csv', parse_dates=['trade_date'])
    design = GenerationDesign(generation_dir, bridge_dir)
    ea = pd.read_csv(Path(generation_dir)/'ea_source.csv')
    h = historical_panels(build, mp, spec)
    w = pd.read_csv(build/'windows.csv', parse_dates=['trade_date'])
    gm = mp[mp['sample'].eq('G_2013_2025')].drop_duplicates('trade_date')
    g = {'BV5_frozen': design.panel(), 'BV': design.panel(gm, 'BV'), 'VOL': design.panel(gm, 'VOL')}
    out = []
    for name, panels in [('H_2000_2012', {k: h[k] for k in ('BV5_frozen', 'BV', 'VOL')}), ('G_2013_2025', g)]:
        for m, T in panels.items():
            alt = de2y(ea, T.trade_date)
            sd = np.nanstd(alt)
            out.append((name, m, T, np.diag([1., 0.]), alt/sd if sd > 0 else None))
    return out, spec, digest(build/'status.json')


def fed_samples(fed_dir, calendar, protocol):
    proto, proto_sha = fed.check_protocol(protocol)
    bars, windows = fed.load_files(fed_dir)
    reg, fomc = fed.registry(calendar, windows)
    panel = fed.build_panel(reg, bars, windows)
    slow = fed.slow_state(panel, fed.day_rv(bars, windows, sorted(set(panel.day))))
    ctrl = panel[~panel.is_event]
    scales = dict(zt=float(ctrl.zt_net.std()), es=float(ctrl.es_net.std()))
    cu, cz = (-ctrl.zt_net/scales['zt']).to_numpy(float), (ctrl.es_net/scales['es']).to_numpy(float)
    ok = np.isfinite(cu) & np.isfinite(cz)
    cov = np.cov(np.vstack([cu[ok], cz[ok]]))
    out = []
    for m in ('BV', 'VOL'):
        T = fed.event_table(fed.continuation(panel, m, slow, windows.start.min()), scales)
        out.append(('FED_2008_2026', m, T, cov, None))
    return out, proto_sha


def measurement_check(out, build=None, minute_run=None, generation_dir=None, bridge_dir=None,
                      fed_dir=None, fed_calendar=None, fed_protocol=None, smoke=False):
    out = new_output(out)
    dump(out/'run_manifest.json', dict(status='running', mode='post_opening_measurement_check'))
    reps = 19 if smoke else 199
    rng = np.random.default_rng(20260930)
    samples, provenance = [], {}
    if build is not None:
        s, spec, sha = ecb_samples(build, minute_run, generation_dir, bridge_dir)
        samples += s; provenance['ecb_frozen_build_sha256'] = sha
    if fed_dir is not None:
        s, psha = fed_samples(fed_dir, fed_calendar, fed_protocol)
        samples += s; provenance['fed_protocol_sha256'] = psha
    rows, sims = [], []
    for sample, measure, T, cov, alt in samples:
        row, sim = analyse(sample, measure, T, cov, alt, reps, rng)
        rows.append(row); sims.append(sim)
    table = pd.DataFrame(rows)
    table.to_csv(out/'measurement_check.csv', index=False)
    pd.concat(sims, ignore_index=True).to_csv(out/'measurement_simulation_grid.csv', index=False)
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, capture_output=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=REPO, text=True, capture_output=True).stdout)
    result = dict(status='complete_measurement_check' if not smoke else 'complete_smoke_not_for_inference',
                  mode='post_opening_measurement_check', created_utc=timestamp(), git_sha=sha, git_dirty=dirty,
                  criteria=CRITERIA, noise_grid=list(NOISE_GRID), reps=reps, provenance=provenance,
                  noise_model=dict(ecb='noise in the aligned Schatz coordinate only, with unit control variance; the EA-EMPD equity surprise is treated as measured without error',
                                   fed='noise in both aligned coordinates with the control-day covariance'),
                  verdicts=table[['sample', 'measure', 'verdict']].to_dict('records'),
                  code_hashes=code_hashes(), python=platform.python_version(), numpy=np.__version__,
                  pandas=pd.__version__, scipy=scipy.__version__)
    dump(out/'run_manifest.json', result)
    print(json.dumps({k: v for k, v in result.items() if k != 'code_hashes'}, indent=2, default=str), flush=True)
    return result


def main():
    p = argparse.ArgumentParser(prog='python -m confirmation_analysis.measurement_check')
    p.add_argument('--build', type=Path); p.add_argument('--minute-run', type=Path)
    p.add_argument('--generation-dir', type=Path); p.add_argument('--bridge-dir', type=Path)
    p.add_argument('--fed-dir', type=Path); p.add_argument('--fed-calendar', type=Path); p.add_argument('--fed-protocol', type=Path)
    p.add_argument('--output', type=Path, required=True); p.add_argument('--smoke', action='store_true')
    a = p.parse_args()
    measurement_check(a.output, a.build, a.minute_run, a.generation_dir, a.bridge_dir, a.fed_dir, a.fed_calendar, a.fed_protocol, a.smoke)


if __name__ == '__main__':
    main()
