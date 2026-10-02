import argparse
import json
import platform
import re
import subprocess
from datetime import date
from pathlib import Path
import numpy as np
import pandas as pd
import scipy
from scipy.stats import norm
from final_analysis.models import holm
from .design_information import exponent_profile, contrast_information, odd_block
from .fomc_calendar import SCHEDULE_CHANGE
from .functional_form import mean_branch_with_equity, basis_comparison, equity_design
from .inference import wild_contrast
from .protocol import REPO, digest, dump, timestamp, new_output, code_hashes

NS_PER_MINUTE = 60_000_000_000
FILE = re.compile(r'^(zn|zt|es)([hmuz]\d\d)_5min_(\d{4}-\d\d-\d\d)_(\d{4}-\d\d-\d\d)\.csv$')
POST = np.arange(0, 26, 5)
PRE = np.arange(-60, -4, 5)
STALE = 5
DAY_START, DAY_END = '08:00', '16:00'
ZLB = [(date(2008, 12, 16), date(2015, 12, 15)), (date(2020, 3, 16), date(2022, 3, 15))]
MEASURES = ['BV', 'BV25', 'RV', 'MedRV', 'MinRV', 'VOL']
PRIMARY_MEASURE = 'BV'
MEDRV_CONST = np.pi/(6-4*np.sqrt(3)+np.pi)
MINRV_CONST = np.pi/(np.pi-2)
PROTOCOL_TEMPLATE = dict(
    schema='fed_replication_protocol_v1',
    purpose='Out-of-sample replication on FOMC announcements of the amplitude law found on ECB press releases',
    sample=dict(calendar='Raw/Certification/fomc_calendar_verified.csv', events='decision == include_primary',
                period='2008-12-01 to 2026-03-19', unscheduled='kept in the calendar, excluded from estimation because no control day shares their clock'),
    data=dict(outcome_root='zn, 10-Year T-Note futures, five-minute bars',
              policy_coordinate='zt, 2-Year T-Note futures: u = minus the log return over (0,25] minutes, scaled by the control standard deviation',
              equity_coordinate='es, E-mini S&P 500 futures: z = log return over (0,25] minutes, scaled by the control standard deviation',
              contract='the file whose non-overlapping front-month window contains the date',
              bar_labels='interval_start, certified by the FOMC calendar market check',
              stale_minutes=STALE),
    outcome=dict(primary='log bipower variation of zn over five returns in (0,25] minutes, relative to a leave-year-out continuation fitted on control days at the same clock',
                 continuation='log pre-window bipower over (-60,-5] and its square, slow state (mean log day realized variance over the five previous control days), linear trend, weekday and month indicators',
                 completeness='an event or control enters only if every endpoint price of zn, zt and es is available within the staleness cap and the continuation is defined',
                 controls='weekdays in the contract windows that are not FOMC dates, anchored at 14:15 and 12:30 ET before 13 March 2013 and at 14:00 ET afterwards'),
    primary_family=dict(alpha=0.05, correction='Holm over the declared size', size=3, tests=[
        dict(id='F1', statement='coefficient on |u| > 0 in the mean branch with both coordinates and state interactions', test='restricted wild cluster bootstrap, one-sided', draws=19999),
        dict(id='F2', statement='coefficient on |z| > 0 in the same regression', test='restricted wild cluster bootstrap, one-sided', draws=19999),
        dict(id='F3', statement='0 < mean elasticity < 1 under the logarithmic radial law with quadratic angles', test='intersection-union of the two one-sided CR1 normal tests; the p-value is the larger of the two')]),
    descriptive=['radial exponent profile and intervals', 'mean elasticity for every measure', 'paired leave-year-out errors of degree-one and degree-two bases',
                 'mean branch for BV25, RV, MedRV, MinRV and volume', 'split into zero-lower-bound and positive-rate periods',
                 'sector contrast information and meetings needed', 'central symmetry odd block'],
    exposure_before_signature='FOMC release times were checked against the reaction of zt and es at the release bar, and bar counts per window were tallied to assess coverage; no zn post-window price, no outcome and no regression was computed before signature.',
    inference=dict(minimum_event_clusters=30, seed=20260929, bootstrap_reps=999, sign_flips=999),
    reviewer='', reviewed_on='')


def to_minutes(ts):
    return ts.dt.as_unit('ns').astype('int64')//NS_PER_MINUTE


def load_files(directory):
    bars, windows = {}, []
    for path in sorted(Path(directory).glob('*.csv')):
        m = FILE.match(path.name)
        if not m:
            continue
        t = pd.read_csv(path, usecols=['Time', 'Latest', 'Volume'])
        t = t[pd.to_numeric(t.Latest, errors='coerce').notna()].copy()
        utc = pd.to_datetime(t.Time, format='mixed').dt.tz_localize('America/Chicago', ambiguous='raise', nonexistent='raise').dt.tz_convert('UTC')
        t['label'] = to_minutes(utc)
        t = t.sort_values('label').drop_duplicates('label')
        key = m.group(1)+m.group(2)
        vol = pd.to_numeric(t.Volume, errors='coerce').fillna(0.).to_numpy(float)
        bars[key] = dict(label=t.label.to_numpy(np.int64), latest=t.Latest.astype(float).to_numpy(), volume=vol,
                         cumvol=np.concatenate([[0.], np.cumsum(vol)]))
        windows.append(dict(root=m.group(1), contract=key, start=date.fromisoformat(m.group(3)),
                            end=date.fromisoformat(m.group(4)), file=path.name, sha256=digest(path)))
    if not windows:
        raise ValueError(f'FED_DATA_MISSING: no files named root+contract_5min_start_end.csv in {directory}')
    return bars, pd.DataFrame(windows)


def contract_for(windows, root, day):
    w = windows[windows.root.eq(root) & (windows.start <= day) & (windows.end >= day)]
    return w.contract.iloc[0] if len(w) == 1 else None


def prices_at(b, endpoints, stale=STALE):
    target = endpoints-5
    idx = np.searchsorted(b['label'], target, side='right')-1
    ok = idx >= 0
    safe = np.where(ok, idx, 0)
    ok &= b['label'][safe] >= target-stale
    return np.where(ok, b['latest'][safe], np.nan)


def returns_at(b, anchor, offsets):
    with np.errstate(divide='ignore', invalid='ignore'):
        return np.diff(np.log(prices_at(b, anchor+offsets)))


def bars_between(b, lo, hi):
    s = np.searchsorted(b['label'], lo, side='left'); e = np.searchsorted(b['label'], hi, side='left')
    return int(e-s), float(b['cumvol'][e]-b['cumvol'][s])


def measures(r, volume):
    out = {k: np.nan for k in MEASURES}
    out['VOL'] = volume
    if len(r) != 5 or not np.isfinite(r).all():
        return out
    a = np.abs(r); prod = a[1:]*a[:-1]; n = len(r)
    med = np.array([np.median(a[j-1:j+2]) for j in range(1, n-1)])
    out.update(BV=np.pi/2*float(prod.sum()), BV25=np.pi/2*float(prod[1:].sum()), RV=float(r@r),
               MedRV=MEDRV_CONST*n/(n-2)*float(np.sum(med**2)),
               MinRV=MINRV_CONST*n/(n-1)*float(np.sum(np.minimum(a[1:], a[:-1])**2)))
    return out


def et_anchor(day, clock):
    return int(to_minutes(pd.Series([pd.Timestamp(f'{day.isoformat()} {clock}').tz_localize('America/New_York').tz_convert('UTC')])).iloc[0])


def control_clocks(day):
    return ['14:00'] if day >= SCHEDULE_CHANGE else ['14:15', '12:30']


def registry(calendar, windows):
    cal = pd.read_csv(calendar, dtype=str).fillna('')
    events = cal[cal.decision.eq('include_primary')].copy()
    events['day'] = pd.to_datetime(events.event_date).dt.date
    rel = pd.to_datetime(events.release_utc, utc=True)
    events['anchor'] = to_minutes(rel)
    events['clock'] = rel.dt.tz_convert('America/New_York').dt.strftime('%H:%M')
    all_fomc = set(pd.to_datetime(cal.event_date).dt.date)
    first, last = windows.start.min(), windows.end.max()
    days = [d.date() for d in pd.bdate_range(first, last)]
    rows = [dict(day=r.day, clock=r.clock, anchor=int(r.anchor), is_event=True) for r in events.itertuples()]
    for d in days:
        if d in all_fomc:
            continue
        for c in control_clocks(d):
            rows.append(dict(day=d, clock=c, anchor=et_anchor(d, c), is_event=False))
    return pd.DataFrame(rows), all_fomc


def coverage(reg, bars, windows):
    out = []
    for r in reg.itertuples():
        row = dict(day=r.day, clock=r.clock, is_event=r.is_event)
        for root in ['zn', 'zt', 'es']:
            c = contract_for(windows, root, r.day)
            n_post, _ = bars_between(bars[c], r.anchor, r.anchor+25) if c in bars else (0, 0.)
            n_pre, _ = bars_between(bars[c], r.anchor-60, r.anchor-5) if c in bars else (0, 0.)
            row.update({f'{root}_contract': c or '', f'{root}_post_bars': n_post, f'{root}_pre_bars': n_pre})
        out.append(row)
    return pd.DataFrame(out)


def day_rv(bars, windows, days):
    out = {}
    for d in days:
        c = contract_for(windows, 'zn', d)
        if c not in bars:
            out[d] = np.nan; continue
        lo, hi = et_anchor(d, DAY_START), et_anchor(d, DAY_END)
        b = bars[c]; s = np.searchsorted(b['label'], lo); e = np.searchsorted(b['label'], hi)
        p = b['latest'][s:e]
        out[d] = float(np.sum(np.diff(np.log(p))**2)) if len(p) > 20 else np.nan
    return out


def build_panel(reg, bars, windows):
    rows = []
    for r in reg.itertuples():
        row = dict(day=r.day, clock=r.clock, is_event=r.is_event, anchor=r.anchor)
        c = {root: contract_for(windows, root, r.day) for root in ['zn', 'zt', 'es']}
        if not all(c[k] in bars for k in c):
            rows.append(row); continue
        zn = bars[c['zn']]
        post = returns_at(zn, r.anchor, POST); pre = returns_at(zn, r.anchor, PRE)
        _, vol = bars_between(zn, r.anchor, r.anchor+25); _, vol_pre = bars_between(zn, r.anchor-60, r.anchor-5)
        _, vol_first = bars_between(zn, r.anchor, r.anchor+5)
        row.update(measures(post, vol))
        row.update(VOL1=vol_first, VOL25=vol-vol_first, RV25=float(post[1:]@post[1:]) if np.isfinite(post).all() else np.nan)
        a = np.abs(pre)
        row['pre_BV'] = np.pi/2*float(np.sum(a[1:]*a[:-1])) if np.isfinite(pre).all() else np.nan
        row['pre_VOL'] = vol_pre
        for root in ['zt', 'es']:
            p = prices_at(bars[c[root]], r.anchor+np.array([0, 25]))
            row[f'{root}_net'] = float(np.log(p[1])-np.log(p[0])) if np.isfinite(p).all() else np.nan
        rows.append(row)
    return pd.DataFrame(rows)


def slow_state(panel, rv):
    ctrl_days = sorted({d for d, e in zip(panel.day, panel.is_event) if not e})
    series = pd.Series({d: rv.get(d, np.nan) for d in ctrl_days}, dtype=float)
    logs = np.log(series.where(series > 0))
    slow = {}
    days = sorted(set(panel.day))
    arr = np.array(ctrl_days)
    for d in days:
        prev = logs[arr < d].dropna().iloc[-5:] if len(arr) else pd.Series(dtype=float)
        slow[d] = float(prev.mean()) if len(prev) == 5 else np.nan
    return slow


def design_matrix(t, origin):
    pre = t.log_pre.to_numpy(float); slow = t.slow.to_numpy(float)
    trend = np.array([(d-origin).days/365.25 for d in t.day])
    wd = pd.get_dummies(pd.Categorical([d.weekday() for d in t.day], categories=range(5)), drop_first=True).to_numpy(float)
    mo = pd.get_dummies(pd.Categorical([d.month for d in t.day], categories=range(1, 13)), drop_first=True).to_numpy(float)
    return np.column_stack([np.ones(len(t)), pre, pre**2, slow, trend, wd, mo])


def continuation(panel, measure, slow, origin, pre_col=None):
    t = panel.copy()
    pre_col = pre_col or ('pre_VOL' if measure == 'VOL' else 'pre_BV')
    t['log_post'] = np.log(t[measure].where(t[measure] > 0))
    t['log_pre'] = np.log(t[pre_col].where(t[pre_col] > 0))
    t['slow'] = [slow.get(d, np.nan) for d in t.day]
    t['year'] = [d.year for d in t.day]
    t['y'] = np.nan; t['s'] = np.nan
    ok = np.isfinite(t[['log_post', 'log_pre', 'slow']]).all(axis=1)
    for clock in sorted(t.clock.unique()):
        for yr in sorted(t.year.unique()):
            target = t.clock.eq(clock) & t.year.eq(yr) & ok
            train = t.clock.eq(clock) & t.year.ne(yr) & ~t.is_event & ok
            if not target.any() or train.sum() < 60:
                continue
            m, sd = t.loc[train, 'log_pre'].mean(), t.loc[train, 'log_pre'].std()
            Xtr = design_matrix(t[train], origin)
            b = np.linalg.lstsq(Xtr, t.loc[train, 'log_post'].to_numpy(float), rcond=None)[0]
            t.loc[target, 'y'] = t.loc[target, 'log_post'].to_numpy(float)-design_matrix(t[target], origin)@b
            t.loc[target, 's'] = (t.loc[target, 'log_pre']-m)/sd
    return t


def event_table(t, scales):
    e = t[t.is_event & np.isfinite(t[['y', 's', 'zt_net', 'es_net']]).all(axis=1)].copy()
    e['u'] = -e.zt_net/scales['zt']; e['z'] = e.es_net/scales['es']
    e['trade_date'] = pd.to_datetime(e.day)
    return e.rename(columns={'y': 'crossfit_abnormal_log_BV', 's': 'crossfit_state_z'})[
        ['trade_date', 'clock', 'u', 'z', 'crossfit_state_z', 'crossfit_abnormal_log_BV']].sort_values('trade_date').reset_index(drop=True)


def in_zlb(ts):
    d = ts.date()
    return any(a <= d <= b for a, b in ZLB)


def check_protocol(path):
    p = Path(path); proto = json.loads(p.read_text())
    if proto.get('schema') != PROTOCOL_TEMPLATE['schema']:
        raise ValueError('PROTOCOL_SCHEMA')
    if not proto.get('reviewer') or not proto.get('reviewed_on'):
        raise ValueError('PROTOCOL_UNSIGNED: sign the protocol before any outcome is computed')
    return proto, digest(p)


def replication(fed_dir, calendar, protocol, out, smoke=False):
    proto, proto_sha = check_protocol(protocol)
    out = new_output(out)
    dump(out/'run_manifest.json', dict(status='running', mode='fed_replication'))
    spec = dict(minimum_event_clusters=proto['inference']['minimum_event_clusters'], seed=proto['inference']['seed'])
    draws = 19 if smoke else proto['primary_family']['tests'][0]['draws']
    reps, flips = (9, 5) if smoke else (proto['inference']['bootstrap_reps'], proto['inference']['sign_flips'])
    bars, windows = load_files(fed_dir)
    reg, fomc = registry(calendar, windows)
    panel = build_panel(reg, bars, windows)
    rv = day_rv(bars, windows, sorted(set(panel.day)))
    slow = slow_state(panel, rv)
    origin = windows.start.min()
    ctrl = panel[~panel.is_event]
    scales = dict(zt=float(ctrl.zt_net.std()), es=float(ctrl.es_net.std()))
    tables = {m: event_table(continuation(panel, m, slow, origin), scales) for m in MEASURES}
    T = tables[PRIMARY_MEASURE]
    tables[PRIMARY_MEASURE].to_csv(out/'fed_primary_event_panel.csv', index=False)
    mb = pd.DataFrame(mean_branch_with_equity(T, spec, 'u', 'z', draws, spec['seed']))
    rng = np.random.default_rng(spec['seed']+1)
    prof, curves = exponent_profile(T, spec, reps, rng)
    q = next(r for r in prof if r['angular_basis'] == 'quadratic_angles')
    el, se = q['mean_elasticity_log_radius'], q['mean_elasticity_se_cr1']
    X, names = equity_design(T.u.to_numpy(float), T.z.to_numpy(float), T.crossfit_state_z.to_numpy(float))
    y, g = T.crossfit_abnormal_log_BV.to_numpy(float), T.trade_date.astype(str)
    def one_sided(term, seed):
        c = np.zeros(X.shape[1]); c[names.index(term)] = 1.
        r = wild_contrast(y, X, g, c, draws, np.random.default_rng(seed), alternative='greater',
                          min_clusters=spec['minimum_event_clusters'])
        return float(r['estimate']), float(r['p_wild'])
    f1, f2 = one_sided('abs_u', spec['seed']+101), one_sided('abs_z', spec['seed']+102)
    f3 = (el, float(max(norm.cdf((el-1)/se), norm.sf(el/se))) if se > 0 else np.nan)
    primary = pd.DataFrame([dict(id='F1', estimate=f1[0], p_one_sided=f1[1]), dict(id='F2', estimate=f2[0], p_one_sided=f2[1]),
                            dict(id='F3', estimate=f3[0], p_one_sided=f3[1])])
    primary['p_holm'] = holm(primary.p_one_sided.to_numpy())
    primary['rejected_at_5pct'] = primary.p_holm < proto['primary_family']['alpha']
    primary['n_events'] = len(T)
    primary.to_csv(out/'fed_primary_family.csv', index=False)
    rows, prof_rows, curves_all, info_rows, odd_rows, basis_rows = [], [], [], [], [], []
    for measure, Tm in tables.items():
        for label, sub in [('all', Tm), ('zero_lower_bound', Tm[Tm.trade_date.map(in_zlb)]), ('positive_rates', Tm[~Tm.trade_date.map(in_zlb)])]:
            if len(sub) < spec['minimum_event_clusters']:
                rows.append(dict(measure=measure, period=label, n_events=len(sub), status='too_few_events')); continue
            m = pd.DataFrame(mean_branch_with_equity(sub, spec, 'u', 'z', draws, spec['seed']+7))
            row = dict(measure=measure, period=label, n_events=len(sub), status='replication')
            for term in ['abs_u', 'abs_z', 'u', 'z']:
                r = m[m.term.eq(term)].iloc[0]; row[f'{term}_estimate'] = r.estimate; row[f'{term}_p_wild'] = r.p_wild
            rows.append(row)
            valid_folds = int(sum(len(sub)-k >= spec['minimum_event_clusters'] for k in sub.trade_date.dt.year.value_counts()))
            if label == 'all' and valid_folds >= 3:
                pr, cv = exponent_profile(sub, spec, reps, np.random.default_rng(spec['seed']+11))
                prof_rows += [dict(measure=measure, **x) for x in pr]; curves_all.append(cv.assign(measure=measure))
                fits, paired, summary = basis_comparison(sub, spec, 'u', 'z')
                basis_rows.append(dict(measure=measure, **summary))
                paired.assign(measure=measure).to_csv(out/f'fed_paired_annual_errors_{measure}.csv', index=False)
                for ex in (1., 2.):
                    info_rows += [dict(measure=measure, **x) for x in contrast_information(sub, spec, ex, flips, np.random.default_rng(spec['seed']+13))]
                odd_rows.append(dict(measure=measure, **odd_block(sub, spec, draws, np.random.default_rng(spec['seed']+17))))
    pd.DataFrame(rows).to_csv(out/'fed_mean_branch.csv', index=False)
    pd.DataFrame(prof_rows).to_csv(out/'fed_radial_exponent_profile.csv', index=False)
    pd.concat(curves_all, ignore_index=True).to_csv(out/'fed_radial_exponent_curves.csv', index=False)
    pd.DataFrame(basis_rows).to_csv(out/'fed_basis_summary.csv', index=False)
    pd.DataFrame(info_rows).to_csv(out/'fed_sector_contrast_information.csv', index=False)
    pd.DataFrame(odd_rows).to_csv(out/'fed_central_symmetry_odd_block.csv', index=False)
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, capture_output=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=REPO, text=True, capture_output=True).stdout)
    result = dict(status='complete_fed_replication' if not smoke else 'complete_smoke_not_for_inference',
                  mode='fed_replication', created_utc=timestamp(), git_sha=sha, git_dirty=dirty,
                  protocol_sha256=proto_sha, protocol_reviewer=proto['reviewer'], protocol_reviewed_on=proto['reviewed_on'],
                  calendar_sha256=digest(calendar), n_files=int(len(windows)), n_primary_events=int(len(T)),
                  n_control_rows=int((~panel.is_event).sum()), scales=scales,
                  primary_family=primary.to_dict('records'), draws=draws, bootstrap_reps=reps, sign_flips=flips,
                  code_hashes=code_hashes(), python=platform.python_version(), numpy=np.__version__,
                  pandas=pd.__version__, scipy=scipy.__version__)
    dump(out/'run_manifest.json', result)
    print(json.dumps({k: v for k, v in result.items() if k != 'code_hashes'}, indent=2, default=str), flush=True)
    return result


POST_REPLICATION = [('BV', 'pre_BV'), ('BV25', 'pre_BV'), ('RV25', 'pre_BV'), ('VOL', 'pre_VOL'), ('VOL1', 'pre_VOL'), ('VOL25', 'pre_VOL')]


def post_replication(fed_dir, calendar, protocol, run_dir, out, smoke=False):
    proto, proto_sha = check_protocol(protocol)
    run = json.loads((Path(run_dir)/'run_manifest.json').read_text())
    if run.get('status') not in ('complete_fed_replication', 'complete_smoke_not_for_inference'):
        raise ValueError('REPLICATION_NOT_COMPLETE')
    if run.get('protocol_sha256') != proto_sha:
        raise ValueError('PROTOCOL_DIFFERS_FROM_REPLICATION')
    out = new_output(out)
    spec = dict(minimum_event_clusters=proto['inference']['minimum_event_clusters'], seed=proto['inference']['seed'])
    draws = 19 if smoke else proto['primary_family']['tests'][0]['draws']
    bars, windows = load_files(fed_dir)
    reg, fomc = registry(calendar, windows)
    panel = build_panel(reg, bars, windows)
    slow = slow_state(panel, day_rv(bars, windows, sorted(set(panel.day))))
    ctrl = panel[~panel.is_event]
    scales = dict(zt=float(ctrl.zt_net.std()), es=float(ctrl.es_net.std()))
    rows = []
    for measure, pre in POST_REPLICATION:
        T = event_table(continuation(panel, measure, slow, windows.start.min(), pre), scales)
        m = pd.DataFrame(mean_branch_with_equity(T, spec, 'u', 'z', draws, spec['seed']+23))
        row = dict(measure=measure, continuation_regressor=pre, n_events=len(T), status='post_replication_descriptive')
        for term in ['abs_u', 'abs_z', 'u', 'z']:
            r = m[m.term.eq(term)].iloc[0]; row[f'{term}_estimate'] = r.estimate; row[f'{term}_p_wild'] = r.p_wild
        rows.append(row)
    table = pd.DataFrame(rows)
    table.to_csv(out/'fed_post_replication_split.csv', index=False)
    ref = pd.read_csv(Path(run_dir)/'fed_mean_branch.csv')
    ref = ref[ref.period.eq('all')].set_index('measure')
    check = {m: float(abs(table.set_index('measure').loc[m, 'abs_u_estimate']-ref.loc[m, 'abs_u_estimate'])) for m in ('BV', 'VOL') if m in ref.index}
    ev = panel[panel.is_event]
    share = dict(events=float((ev.VOL1/ev.VOL).median()), controls=float((ctrl.VOL1/ctrl.VOL).median()))
    result = dict(status='complete_post_replication_descriptive' if not smoke else 'complete_smoke_not_for_inference',
                  created_utc=timestamp(), replication_run=str(run_dir), replication_git_sha=run.get('git_sha'),
                  protocol_sha256=proto_sha, reproduction_abs_u_difference=check,
                  median_first_bar_share_of_post_volume=share, draws=draws,
                  note='descriptive tables computed after the confirmatory run; not part of the declared family',
                  code_hashes=code_hashes())
    dump(out/'run_manifest.json', result)
    print(json.dumps({k: v for k, v in result.items() if k != 'code_hashes'}, indent=2), flush=True)
    return result


def blinded_coverage(fed_dir, calendar, out):
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    bars, windows = load_files(fed_dir)
    reg, fomc = registry(calendar, windows)
    cov = coverage(reg, bars, windows)
    cov.to_csv(out/'fed_coverage.csv', index=False)
    full = cov[[f'{r}_post_bars' for r in ['zn', 'zt', 'es']]].ge(5).all(axis=1) & cov.zn_pre_bars.ge(11)
    summary = dict(status='coverage_only_no_prices_read', n_files=int(len(windows)),
                   n_events=int(cov.is_event.sum()), n_events_complete=int((full & cov.is_event).sum()),
                   n_controls=int((~cov.is_event).sum()), n_controls_complete=int((full & ~cov.is_event).sum()),
                   events_incomplete=[str(d) for d in cov[cov.is_event & ~full].day])
    dump(out/'coverage_status.json', summary)
    print(json.dumps(summary, indent=2), flush=True)
    return summary


def main():
    p = argparse.ArgumentParser(prog='python -m confirmation_analysis.fed_replication')
    sub = p.add_subparsers(dest='mode', required=True)
    t = sub.add_parser('protocol-template'); t.add_argument('--output', type=Path, required=True)
    c = sub.add_parser('coverage')
    for a in (c,):
        a.add_argument('--fed-dir', type=Path, required=True); a.add_argument('--calendar', type=Path, required=True)
        a.add_argument('--output', type=Path, required=True)
    r = sub.add_parser('run')
    r.add_argument('--fed-dir', type=Path, required=True); r.add_argument('--calendar', type=Path, required=True)
    r.add_argument('--protocol', type=Path, required=True); r.add_argument('--output', type=Path, required=True)
    r.add_argument('--smoke', action='store_true')
    q = sub.add_parser('post-replication')
    q.add_argument('--fed-dir', type=Path, required=True); q.add_argument('--calendar', type=Path, required=True)
    q.add_argument('--protocol', type=Path, required=True); q.add_argument('--run', type=Path, required=True)
    q.add_argument('--output', type=Path, required=True); q.add_argument('--smoke', action='store_true')
    x = p.parse_args()
    if x.mode == 'protocol-template':
        if x.output.exists():
            raise ValueError('PROTOCOL_EXISTS')
        x.output.parent.mkdir(parents=True, exist_ok=True)
        x.output.write_text(json.dumps(PROTOCOL_TEMPLATE, indent=2)+'\n')
        print(f'Protocol template written: {x.output}')
    elif x.mode == 'coverage':
        blinded_coverage(x.fed_dir, x.calendar, x.output)
    elif x.mode == 'post-replication':
        post_replication(x.fed_dir, x.calendar, x.protocol, x.run, x.output, x.smoke)
    else:
        replication(x.fed_dir, x.calendar, x.protocol, x.output, x.smoke)


if __name__ == '__main__':
    main()
