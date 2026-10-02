import json
from pathlib import Path
import numpy as np
import pandas as pd
from final_analysis.data import exact_returns, variation, MINUTE
from .quality import read_prices
from .readiness import checked_manifest

REGULAR_WALL = {'PR': '13:45', 'PC': '14:30'}
ROOT_WEIGHT = {'hf': 1., 'hr': 1.}


def load_quality(quality_dir):
    quality_dir = Path(quality_dir)
    manifest = checked_manifest(quality_dir, 'complete_quality_audit_not_frozen')
    tables = {name: pd.read_csv(quality_dir/f'{name}.csv', dtype={'trade_date': str, 'event_date': str})
              for name in ['primary_files', 'price_quality_files', 'preferred_contracts',
                           'phase_eligibility', 'calendar_review']}
    if not manifest['all_nonempty_files_label_verified']:
        raise ValueError('BAR_LABEL_UNVERIFIED: deep-archive evidence is required before building windows')
    return manifest, tables


def anchors_for(date, calendar_rows, is_event):
    out, status = {}, {}
    for phase in ('PR', 'PC'):
        regular = pd.Timestamp(f'{date} {REGULAR_WALL[phase]}').tz_localize('Europe/Berlin').tz_convert('UTC')
        if not is_event:
            out[phase], status[phase] = regular, 'control_regular_schedule'
            continue
        row = calendar_rows.get(phase)
        state = row.calendar_status if row is not None else 'missing_source_row'
        if state == 'verified_present':
            out[phase] = pd.Timestamp(row.event_datetime_utc).tz_convert('UTC')
        elif state == 'verified_absent':
            out[phase] = None
        else:
            out[phase] = regular
        status[phase] = state
    return out, status


def read_bars(path, semantics):
    t, _ = read_prices(path)
    t = t[t.valid_core].copy()
    end = t.label_utc + pd.Timedelta(minutes=5 if semantics == 'interval_start' else 0)
    times = end.astype('int64').to_numpy()
    order = np.argsort(times)
    return times[order], t.Latest.to_numpy(float)[order], t.Volume.to_numpy(float)[order]


def grid_volume(times, volume, grid):
    loc = np.minimum(np.searchsorted(times, grid), max(len(times)-1, 0))
    return float(np.sum(volume[loc][times[loc] == grid])) if len(times) else 0.


def candidate_0830(date):
    return (pd.Timestamp(date)+pd.Timedelta(hours=8, minutes=30)).tz_localize('America/New_York').tz_convert('UTC')


def intersects(anchor, endpoints, instant):
    return bool(anchor+pd.Timedelta(minutes=endpoints[0]-5) <= instant <= anchor+pd.Timedelta(minutes=endpoints[-1]))


def load_releases(data_root):
    path = Path(data_root)/'Raw/Certification/us_releases.csv'
    if not path.exists():
        return pd.DataFrame(columns=['release_id', 'timestamp_utc', 'source_url', 'instant'])
    r = pd.read_csv(path)
    if not {'release_id', 'timestamp_utc', 'source_url'}.issubset(r) or r.isna().any().any():
        raise ValueError('Malformed US release calendar')
    r['instant'] = pd.to_datetime(r.timestamp_utc, utc=True)
    return r


def build_windows(quality_dir, data_root, spec, decisions, blinded):
    manifest, q = load_quality(quality_dir)
    if decisions['pc_normal_pre_support']['choice'] != 'v1_grid_endpoints_minus25_to_minus5_support_minus30_to_minus5':
        raise ValueError('Unsupported PC normal-pre decision')
    semantics = q['price_quality_files'].set_index('input_path').semantics.to_dict()
    eligibility = q['phase_eligibility'].set_index(['trade_date', 'root_code', 'phase'])
    calendar = {d: {r.phase: r for r in g.itertuples()} for d, g in q['calendar_review'].groupby('event_date')}
    preferred = q['preferred_contracts']
    preferred = preferred[preferred.selection_status.eq('selected_pre_only') & preferred.root_code.isin(spec['roots'])]
    start, stop = spec['samples']['confirmation']
    preferred = preferred[(preferred.trade_date >= start) & (preferred.trade_date <= stop)]
    weekday = pd.to_datetime(preferred.trade_date).dt.weekday < 5
    preferred = preferred[weekday | preferred.is_event].copy()
    releases = load_releases(data_root)
    pre_offsets = np.array(spec['pre_pr_return_endpoints_minutes'])
    pc_pre_offsets = np.array(spec['pc_normal_pre_return_endpoints_minutes'])
    cache, rows = {}, []
    for i, row in enumerate(preferred.sort_values(['trade_date', 'root_code']).itertuples()):
        path = row.input_path
        if path not in cache:
            cache[path] = read_bars(path, semantics[path])
        times, prices, volume = cache[path]
        anchors, status = anchors_for(row.trade_date, calendar.get(row.trade_date, {}), bool(row.is_event))
        pr_anchor = anchors['PR']
        if pr_anchor is None:
            continue
        pre_grid = pr_anchor.value + pre_offsets*MINUTE
        rpre = exact_returns(times, prices, pre_grid)
        vp = variation(rpre)
        pre_coverage = float(np.isfinite(rpre).mean())
        base = dict(trade_date=row.trade_date, root_code=row.root_code, input_path=path,
                    is_event=bool(row.is_event), pr_anchor_utc=pr_anchor.isoformat(),
                    pre_coverage=pre_coverage, pre_volume=grid_volume(times, volume, pre_grid),
                    n_pre_returns=int(np.isfinite(rpre).sum()), selection_BV_pre=vp['BV'], selection_RV_pre=vp['RV'])
        day_rv = np.nan
        if not row.is_event:
            day = pd.Timestamp(row.trade_date).tz_localize('Europe/Berlin').tz_convert('UTC')
            nxt = (pd.Timestamp(row.trade_date)+pd.Timedelta(days=1)).tz_localize('Europe/Berlin').tz_convert('UTC')
            idx = np.flatnonzero((times >= day.value) & (times < nxt.value))
            day_rv = float(np.nansum(exact_returns(times, prices, times[idx])**2)) if len(idx) else np.nan
        for phase in ('PR', 'PC'):
            anchor = anchors[phase]
            key = (row.trade_date, row.root_code, phase)
            certified = bool(eligibility.certified_event_price_eligibility.get(key, False)) if row.is_event else False
            record = dict(**base, phase=phase, calendar_status=status[phase], day_rv=day_rv,
                          certified_event_price_eligibility=certified, event_post_blinded=bool(row.is_event and blinded))
            if anchor is None:
                rows.append(dict(**record, phase_anchor_utc='', window_eligible=False, post_coverage=np.nan,
                                 normal_pre_coverage=np.nan, us_0830_candidate=False, verified_us_release=False))
                continue
            offsets = spec[f'{phase.lower()}_return_endpoints_minutes']
            record.update(phase_anchor_utc=anchor.isoformat(),
                          us_0830_candidate=intersects(anchor, offsets, candidate_0830(row.trade_date)),
                          verified_us_release=bool([1 for r in releases.itertuples() if intersects(anchor, offsets, r.instant)]))
            if row.is_event and blinded:
                rows.append(dict(**record, window_eligible=certified, normal_pre_coverage=np.nan,
                                 BV_pre=np.nan, RV_pre=np.nan, post_coverage=np.nan, n_post_returns=np.nan,
                                 BV_post=np.nan, RV_post=np.nan, net_post=np.nan, rv_minus_bv=np.nan))
                continue
            normal_grid = pre_grid if phase == 'PR' else anchor.value + pc_pre_offsets*MINUTE
            normal_pre = exact_returns(times, prices, normal_grid)
            vn = variation(normal_pre)
            record.update(normal_pre_coverage=float(np.isfinite(normal_pre).mean()), BV_pre=vn['BV'], RV_pre=vn['RV'])
            grid = anchor.value + np.array(offsets)*MINUTE
            rpost = exact_returns(times, prices, grid)
            v = variation(rpost)
            complete = pre_coverage == 1 and np.isfinite(rpost).all() and np.isfinite(normal_pre).all()
            eligible = complete and (certified or not row.is_event)
            rows.append(dict(**record, window_eligible=bool(eligible), post_coverage=float(np.isfinite(rpost).mean()),
                             n_post_returns=int(np.isfinite(rpost).sum()), BV_post=v['BV'], RV_post=v['RV'],
                             net_post=v['net'], rv_minus_bv=v['residual']))
        if (i+1) % 2000 == 0:
            print(f'Built {i+1} root-days', flush=True)
    w = pd.DataFrame(rows)
    w['trade_date'] = pd.to_datetime(w.trade_date)
    w = w.sort_values(['root_code', 'phase', 'trade_date']).reset_index(drop=True)
    for kind in ['BV', 'RV']:
        for window in ['pre', 'post']:
            col = f'{kind}_{window}'
            w['log_'+col] = np.log(w[col].where(w[col] > 0))
    w['state_log_BV_pre'] = np.log(w.selection_BV_pre.where(w.selection_BV_pre > 0))
    w['log_day_rv'] = np.log(w.day_rv.where(w.day_rv > 0))
    w = slow_state(w, decisions)
    if blinded:
        posts = w.loc[w.is_event, ['BV_post', 'RV_post', 'net_post', 'rv_minus_bv', 'day_rv', 'log_BV_post', 'log_RV_post']]
        if np.isfinite(posts.to_numpy(float)).any():
            raise ValueError('BLINDING_VIOLATION: an event post-window quantity was computed')
        pc_pre = w.loc[w.is_event & w.phase.eq('PC'), ['BV_pre', 'RV_pre']]
        if np.isfinite(pc_pre.to_numpy(float)).any():
            raise ValueError('BLINDING_VIOLATION: an event PC pre-window quantity (after the release) was computed')
    return w, manifest


def slow_state(w, decisions):
    if decisions['slow_state_rule']['choice'] != 'event_day_excluded_previous_five_control_days':
        raise ValueError('Unsupported slow-state decision')
    daily = w[w.phase.eq('PR')][['trade_date', 'root_code', 'is_event', 'log_day_rv']].copy()
    parts = []
    for root, g in daily.groupby('root_code'):
        controls = g[~g.is_event].sort_values('trade_date').copy()
        controls['rolling5'] = controls.log_day_rv.rolling(5, min_periods=5).mean()
        target = g[['trade_date']].sort_values('trade_date').copy()
        merged = pd.merge_asof(target, controls[['trade_date', 'rolling5']], on='trade_date',
                               allow_exact_matches=False, direction='backward')
        merged['root_code'] = root
        parts.append(merged)
    slow = pd.concat(parts).rename(columns={'rolling5': 'slow_state'})
    return w.merge(slow, on=['trade_date', 'root_code'], how='left', validate='many_to_one')


def load_ea_v2(data_root, spec):
    e = pd.read_excel(Path(data_root)/'Raw/EA-EMPD/EA-EMPD.xlsx', sheet_name='EA-EMPD')
    e['event_date'] = pd.to_datetime(e.Date_time).dt.normalize()
    e['phase'] = e.Event_type.str.replace('GC_', '', regex=False)
    e = e[e.phase.isin(['PR', 'PC'])].copy()
    if e.duplicated(['event_date', 'phase']).any():
        raise ValueError('Duplicate EA-EMPD phase dates')
    ind = spec['history_indicator']
    pr = e[e.phase.eq('PR')].sort_values('event_date').copy()
    pr['lag1'] = pr[ind].shift(1)/10
    pr['history3'] = pr[ind].shift(1).rolling(3, min_periods=3).mean()/10
    e = e.merge(pr[['event_date', 'lag1', 'history3']], on='event_date', how='left', validate='many_to_one')
    start, stop = spec['samples']['confirmation']
    return e[(e.event_date >= start) & (e.event_date <= stop)].copy()


def external_scales(ea, spec):
    pr = ea[ea.phase.eq('PR')]
    scales = dict(stoxx50e_fraction=float((pr.STOXX50E/100).std(ddof=1)),
                  ois1y_10bp=float((pr.OIS_1Y/10).std(ddof=1)))
    if not all(np.isfinite(v) and v > 0 for v in scales.values()):
        raise ValueError('Degenerate external coordinate scales')
    return scales


def ea_pc1(ea, phase):
    E = ea[ea.phase.eq(phase) & ea.event_date.ne('2008-10-08')].copy()
    ois = ['OIS_1M', 'OIS_3M', 'OIS_6M', 'OIS_1Y']
    ok = np.isfinite(E[ois]).all(axis=1)
    M = E.loc[ok, ois].to_numpy(float)
    sd = M.std(axis=0, ddof=1)
    if len(M) < 8 or np.any(sd <= 0):
        raise ValueError('EA PCA scale/rank gate')
    Z = M/sd
    _, _, vt = np.linalg.svd(Z, full_matrices=False)
    loading = vt[0] if vt[0][-1] >= 0 else -vt[0]
    score = Z @ loading
    score = score/score.std(ddof=1)*M[:, -1].std(ddof=1)/10
    return pd.Series(score, index=E.loc[ok, 'event_date'])


def indicators_v2(w, ea, spec, rule):
    nets = w.pivot(index=['trade_date', 'phase'], columns='root_code', values='net_post')
    flags = w.groupby(['trade_date', 'phase']).is_event.first()
    pr_controls = nets[(~flags) & (nets.index.get_level_values('phase') == 'PR')]
    scales = pr_controls.std()
    for root in ['hf', 'hr']:
        if not np.isfinite(scales.get(root, np.nan)) or scales[root] <= 0:
            raise ValueError(f'degenerate_curve_scale_{root}')
    z = nets/scales
    out = nets.reset_index()[['trade_date', 'phase']]
    out['schatz_aligned_u'] = -z.hf.to_numpy()
    out['schatz_bobl_aligned_u'] = -(z.hf+z.hr).to_numpy()/2
    out['fx_aligned_z'] = z.fx.to_numpy() if 'fx' in z else np.nan
    src = ea.rename(columns={'event_date': 'trade_date'})
    out = out.merge(src[['trade_date', 'phase', 'OIS_1M', 'OIS_1Y', 'STOXX50E', 'lag1', 'history3']],
                    on=['trade_date', 'phase'], how='left', validate='one_to_one')
    ext = external_scales(ea, spec)
    out['stoxx50e_z'] = (out.STOXX50E/100)/ext['stoxx50e_fraction']
    out['ois1y_expost_u'] = (out.OIS_1Y/10)/ext['ois1y_10bp']
    for phase in ['PR', 'PC']:
        ix = out.phase.eq(phase)
        out.loc[ix, 'ea_pc1_expost_u'] = out.loc[ix, 'trade_date'].map(ea_pc1(ea, phase))
    if rule == 'homogeneous_external_stoxx50e_2000_2012':
        out['z_primary'] = out.stoxx50e_z
        out['equity_source'] = 'ea_empd_stoxx50e'
    else:
        use_fx = np.isfinite(out.fx_aligned_z)
        out['z_primary'] = np.where(use_fx, out.fx_aligned_z, out.stoxx50e_z)
        out['equity_source'] = np.where(use_fx, 'fx_futures', 'ea_empd_stoxx50e')
    out['u_primary'] = out.schatz_aligned_u
    dates = pr_controls.index.get_level_values('trade_date')
    scale_table = pd.DataFrame({'root_code': scales.index, 'pr_control_sd': scales.values,
                                'n_pr_controls': [int(pr_controls[r].notna().sum()) for r in scales.index],
                                'period_start': str(dates.min().date()), 'period_end': str(dates.max().date()),
                                'rule': 'sd_over_PR_control_root_days_no_centering_same_as_bridge'})
    return out, scale_table, ext
