import argparse
import json
import platform
import subprocess
from pathlib import Path
import numpy as np
import pandas as pd
import scipy
from final_analysis.models import counterfactual
from .estimate import panel
from .exploratory import verify_opened_build
from .minute import GenerationDesign
from .nuisance import counterfactual_v2
from .protocol import REPO, digest, dump, timestamp, new_output, code_hashes
from . import fed_replication as fed

TOLERANCE = 1e-9
DESIGN = dict(
    comparison='announcement rows and control rows at the same clock pooled in one regression, every coefficient interacted with an announcement indicator',
    mean_branch='absolute and signed coordinates and the state, each with its interaction with the announcement indicator',
    log_amplitude='log of the amplitude and the state, each with its interaction with the announcement indicator',
    inference='restricted wild bootstrap with Rademacher signs drawn by trade date, two-sided, one coefficient at a time',
    support='all rows, and the rows whose amplitude does not exceed the 99th percentile of control amplitudes',
    coordinates='u alone in every sample; u and z where an aligned equity coordinate exists on control days',
    status='post-opening placebo outside every declared family')


def check_events(frame, reference, columns, label):
    ev = frame[frame.is_event].set_index('trade_date')
    ref = reference.set_index('trade_date')
    common = ev.index.intersection(ref.index)
    if len(common) != len(ref):
        raise ValueError(f'PLACEBO_EVENTS_NOT_REPRODUCED: {label}, {len(common)} of {len(ref)} reference events')
    worst = max(float(np.abs(ev.loc[common, c].to_numpy(float)-ref.loc[common, c].to_numpy(float)).max()) for c in columns)
    if worst > TOLERANCE:
        raise ValueError(f'PLACEBO_EVENTS_NOT_REPRODUCED: {label}, difference {worst}')
    return dict(sample_measure=label, reference_events=int(len(ref)), max_abs_difference=worst)


def fomc_frames(fed_dir, calendar):
    bars, windows = fed.load_files(fed_dir)
    reg, _ = fed.registry(calendar, windows)
    p = fed.build_panel(reg, bars, windows)
    slow = fed.slow_state(p, fed.day_rv(bars, windows, sorted(set(p.day))))
    ctrl = p[~p.is_event]
    scales = dict(zt=float(ctrl.zt_net.std()), es=float(ctrl.es_net.std()))
    frames, checks = {}, []
    for measure in ('BV', 'VOL'):
        t = fed.continuation(p, measure, slow, windows.start.min())
        ok = np.isfinite(t[['y', 's', 'zt_net', 'es_net']].to_numpy(float)).all(axis=1)
        f = t[ok]
        frame = pd.DataFrame(dict(trade_date=pd.to_datetime(f.day).to_numpy(), cluster=[str(d) for d in f.day],
                                  is_event=f.is_event.astype(bool).to_numpy(), u=(-f.zt_net/scales['zt']).to_numpy(float),
                                  z=(f.es_net/scales['es']).to_numpy(float), s=f.s.to_numpy(float), y=f.y.to_numpy(float)))
        ref = fed.event_table(t, scales).rename(columns={'crossfit_state_z': 's', 'crossfit_abnormal_log_BV': 'y'})
        checks.append(check_events(frame, ref, ['u', 'z', 's', 'y'], f'FED_2008_2026 {measure}'))
        frames[('FED_2008_2026', measure)] = frame
    return frames, checks, dict(fed_scales=scales, calendar_sha256=digest(calendar))


def generation_frames(generation_dir, bridge_dir):
    d = GenerationDesign(generation_dir, bridge_dir)
    rev, _ = counterfactual(d.windows.copy(), d.spec)
    b = rev[rev.phase.eq('PR') & rev.root_code.eq('gg')]
    pr = d.windows[d.windows.phase.eq('PR')]
    nets = pr.pivot_table(index='trade_date', columns='root_code', values='net_post', aggfunc='first')
    flags = pr.groupby('trade_date').is_event.first().astype(bool)
    fx_sd = float(nets.loc[~flags.reindex(nets.index).to_numpy(), 'fx'].std())
    t = b[['trade_date', 'is_event', 'window_eligible', 'crossfit_state_z', 'crossfit_abnormal_log_BV']].merge(
        nets[['hf', 'fx']].reset_index(), on='trade_date', how='left', validate='one_to_one')
    t = t[t.window_eligible.astype(bool)]
    frame = pd.DataFrame(dict(trade_date=t.trade_date.to_numpy(), cluster=t.trade_date.dt.strftime('%Y-%m-%d').to_numpy(),
                              is_event=t.is_event.astype(bool).to_numpy(), u=(-t.hf/d.schatz_sd).to_numpy(float),
                              z=(t.fx/fx_sd).to_numpy(float), s=t.crossfit_state_z.to_numpy(float),
                              y=t.crossfit_abnormal_log_BV.to_numpy(float)))
    frame = frame[np.isfinite(frame[['u', 's', 'y']].to_numpy(float)).all(axis=1)].reset_index(drop=True)
    ref = d.panel().rename(columns={'crossfit_state_z': 's', 'crossfit_abnormal_log_BV': 'y'})
    check = check_events(frame, ref, ['u', 's', 'y'], 'G_2013_2025 BV5_frozen')
    return {('G_2013_2025', 'BV5_frozen'): frame}, [check], dict(generation_schatz_sd=d.schatz_sd, generation_fx_sd=fx_sd)


def historical_frames(build):
    build = Path(build)
    manifest, spec, code_changed = verify_opened_build(build)
    w = pd.read_csv(build/'windows.csv', parse_dates=['trade_date'])
    indicators = pd.read_csv(build/'indicators.csv', parse_dates=['trade_date'])
    cu = spec['primary_coordinates']['u']
    cf, _ = counterfactual_v2(w, spec)
    ref = panel(cf, indicators, spec, 'gg', 'PR', cu, spec['primary_coordinates']['z'], 'crossfit_abnormal_log_BV')
    hf = w[w.phase.eq('PR') & w.root_code.eq('hf')].drop_duplicates('trade_date').set_index('trade_date').net_post
    ratio = (-hf.reindex(ref.trade_date).to_numpy(float))/ref[cu].to_numpy(float)
    ratio = ratio[np.isfinite(ratio)]
    if not len(ratio) or np.ptp(ratio) > 1e-9*abs(np.median(ratio)):
        raise ValueError('PLACEBO_HISTORICAL_SCALE_NOT_UNIQUE')
    scale = float(np.median(ratio))
    b = cf[cf.phase.eq('PR') & cf.root_code.eq('gg') & cf.window_eligible.astype(bool)]
    u = -hf.reindex(b.trade_date).to_numpy(float)/scale
    frame = pd.DataFrame(dict(trade_date=b.trade_date.to_numpy(), cluster=b.trade_date.dt.strftime('%Y-%m-%d').to_numpy(),
                              is_event=b.is_event.astype(bool).to_numpy(), u=u, z=np.nan,
                              s=b.crossfit_state_z.to_numpy(float), y=b.crossfit_abnormal_log_BV.to_numpy(float)))
    frame = frame[np.isfinite(frame[['u', 's', 'y']].to_numpy(float)).all(axis=1)].reset_index(drop=True)
    reference = ref.rename(columns={cu: 'u', 'crossfit_state_z': 's', 'crossfit_abnormal_log_BV': 'y'})[['trade_date', 'u', 's', 'y']]
    check = check_events(frame, reference, ['u', 's', 'y'], 'H_2000_2012 BV5_frozen')
    hfw = w[w.phase.eq('PR') & w.root_code.eq('hf')].drop_duplicates('trade_date').set_index('trade_date')
    ctrl_sd = float(hfw.loc[~hfw.is_event.astype(bool), 'net_post'].std())
    return {('H_2000_2012', 'BV5_frozen'): frame}, [check], dict(historical_u_scale=scale, historical_hf_control_sd=ctrl_sd,
                                                                 historical_build_status_sha256=digest(build/'status.json'))


def design(frame, coordinates, spec):
    u = frame.u.to_numpy(float)
    z = frame.z.to_numpy(float) if coordinates == 'u_z' else np.zeros(len(frame))
    s = frame.s.to_numpy(float)
    if spec == 'mean':
        base = [('abs_u', np.abs(u)), ('u', u)]
        if coordinates == 'u_z':
            base += [('abs_z', np.abs(z)), ('z', z)]
        tested = ['abs_u'] + (['abs_z'] if coordinates == 'u_z' else [])
    else:
        base = [('log_r', np.log(np.hypot(u, z)))]
        tested = ['log_r']
    base.append(('state', s))
    e = frame.is_event.to_numpy(float)
    names, cols = ['constant', 'event'], [np.ones(len(frame)), e]
    for n, x in base:
        names += [n, 'event_x_'+n]; cols += [x, e*x]
    return np.column_stack(cols), names, tested


def cr1(X, resid, groups):
    n, k = X.shape
    G = groups.max()+1
    inv = np.linalg.inv(X.T@X)
    scores = np.zeros((G, k)); np.add.at(scores, groups, X*resid[:, None])
    c = G/(G-1)*(n-1)/(n-k)
    return c*inv@scores.T@scores@inv


def wild_p(y, X, groups, j, draws, rng, batch=250):
    n, k = X.shape
    G = groups.max()+1
    inv = np.linalg.inv(X.T@X)
    beta = inv@X.T@y
    se = np.sqrt(cr1(X, y-X@beta, groups)[j, j])
    t0 = beta[j]/se
    Xr = np.delete(X, j, axis=1)
    fitted = Xr@np.linalg.lstsq(Xr, y, rcond=None)[0]
    e = y-fitted
    a = (inv@X.T)[j]
    c = G/(G-1)*(n-1)/(n-k)
    hits, done = 0, 0
    while done < draws:
        m = min(batch, draws-done)
        signs = rng.choice([-1., 1.], size=(G, m))
        ys = fitted[:, None]+e[:, None]*signs[groups]
        bs = inv@X.T@ys
        res = ys-X@bs
        sc = np.zeros((G, m)); np.add.at(sc, groups, a[:, None]*res)
        t = bs[j]/np.sqrt(c*np.sum(sc**2, axis=0))
        hits += int(np.count_nonzero(np.abs(t) >= abs(t0)))
        done += m
    return float(beta[j]), float(se), float((1+hits)/(draws+1))


def estimate(frame, coordinates, spec, support, draws, rng):
    f = frame
    if coordinates == 'u_z':
        f = f[np.isfinite(f.z.to_numpy(float))]
    r = np.hypot(f.u.to_numpy(float), f.z.to_numpy(float) if coordinates == 'u_z' else 0.)
    keep = r > 0 if spec == 'log' else np.ones(len(f), bool)
    if support == 'common':
        keep &= r <= np.quantile(r[~f.is_event.to_numpy(bool)], .99)
    f = f[keep]
    X, names, tested = design(f, coordinates, spec)
    y = f.y.to_numpy(float)
    groups = pd.factorize(f.cluster)[0]
    beta = np.linalg.lstsq(X, y, rcond=None)[0]
    V = cr1(X, y-X@beta, groups)
    rows = []
    for term in tested+(['level'] if spec == 'log' else []):
        if term == 'level':
            jc, je = names.index('constant'), names.index('event')
        else:
            jc, je = names.index(term), names.index('event_x_'+term)
        ev = beta[jc]+beta[je]
        ev_se = float(np.sqrt(V[jc, jc]+V[je, je]+2*V[jc, je]))
        diff, diff_se, p = wild_p(y, X, groups, je, draws, rng)
        rows.append(dict(coordinates=coordinates, spec=spec, support=support, term=term,
                         control_estimate=float(beta[jc]), control_se=float(np.sqrt(V[jc, jc])),
                         event_estimate=float(ev), event_se=ev_se, difference=diff, difference_se=diff_se,
                         p_wild_difference=p, n_events=int(f.is_event.sum()), n_controls=int((~f.is_event).sum()),
                         n_clusters=int(groups.max()+1)))
    return rows


def amplitude_bins(frame, coordinates, edges=5):
    f = frame if coordinates == 'u' else frame[np.isfinite(frame.z.to_numpy(float))]
    r = np.hypot(f.u.to_numpy(float), f.z.to_numpy(float) if coordinates == 'u_z' else 0.)
    ev = f.is_event.to_numpy(bool)
    q = np.unique(np.quantile(r[ev], np.linspace(0, 1, edges+1)))
    rows = []
    for k in range(len(q)-1):
        lo, hi = q[k], q[k+1]
        inside = (r >= lo) & ((r <= hi) if k == len(q)-2 else (r < hi))
        rows.append(dict(coordinates=coordinates, bin=k+1, amplitude_low=float(lo), amplitude_high=float(hi),
                         n_events=int((inside & ev).sum()), n_controls=int((inside & ~ev).sum()),
                         mean_y_events=float(f.y[inside & ev].mean()) if (inside & ev).any() else np.nan,
                         mean_y_controls=float(f.y[inside & ~ev].mean()) if (inside & ~ev).any() else np.nan))
    return rows


def placebo(out, fed_dir=None, fed_calendar=None, generation_dir=None, bridge_dir=None, build=None, smoke=False):
    out = new_output(out)
    dump(out/'run_manifest.json', dict(status='running', mode='post_opening_placebo'))
    draws = 49 if smoke else 4999
    frames, checks, provenance = {}, [], {}
    if fed_dir is not None:
        f, c, p = fomc_frames(fed_dir, fed_calendar); frames.update(f); checks += c; provenance.update(p)
    if generation_dir is not None:
        f, c, p = generation_frames(generation_dir, bridge_dir); frames.update(f); checks += c; provenance.update(p)
    if build is not None:
        f, c, p = historical_frames(build); frames.update(f); checks += c; provenance.update(p)
    rows, bins = [], []
    for k, ((sample, measure), frame) in enumerate(sorted(frames.items())):
        options = ['u', 'u_z'] if np.isfinite(frame.z.to_numpy(float)).any() else ['u']
        for coordinates in options:
            rng = np.random.default_rng(20261109+k)
            for spec in ('mean', 'log'):
                for support in ('all', 'common'):
                    rows += [dict(sample=sample, measure=measure, **r) for r in estimate(frame, coordinates, spec, support, draws, rng)]
            bins += [dict(sample=sample, measure=measure, **b) for b in amplitude_bins(frame, coordinates)]
    pd.DataFrame(rows).to_csv(out/'placebo_tests.csv', index=False)
    pd.DataFrame(bins).to_csv(out/'placebo_amplitude_bins.csv', index=False)
    pd.DataFrame(checks).to_csv(out/'placebo_event_reproduction.csv', index=False)
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, capture_output=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=REPO, text=True, capture_output=True).stdout)
    result = dict(status='complete_placebo' if not smoke else 'complete_smoke_not_for_inference', mode='post_opening_placebo',
                  created_utc=timestamp(), git_sha=sha, git_dirty=dirty, design=DESIGN, draws=draws, provenance=provenance,
                  event_reproduction=checks, code_hashes=code_hashes(), python=platform.python_version(),
                  numpy=np.__version__, pandas=pd.__version__, scipy=scipy.__version__)
    dump(out/'run_manifest.json', result)
    print(json.dumps({k: v for k, v in result.items() if k != 'code_hashes'}, indent=2, default=str), flush=True)
    return result


def main():
    p = argparse.ArgumentParser(prog='python -m confirmation_analysis.placebo')
    p.add_argument('--fed-dir', type=Path); p.add_argument('--fed-calendar', type=Path)
    p.add_argument('--generation-dir', type=Path); p.add_argument('--bridge-dir', type=Path)
    p.add_argument('--build', type=Path)
    p.add_argument('--output', type=Path, required=True); p.add_argument('--smoke', action='store_true')
    a = p.parse_args()
    placebo(a.output, a.fed_dir, a.fed_calendar, a.generation_dir, a.bridge_dir, a.build, a.smoke)


if __name__ == '__main__':
    main()
