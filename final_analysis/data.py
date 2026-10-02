from __future__ import annotations
import hashlib
import json
from pathlib import Path
import numpy as np
import pandas as pd

MINUTE = 60_000_000_000

def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''):
            h.update(b)
    return h.hexdigest()

def read_dates(s, utc=False):
    return pd.to_datetime(s, format='mixed', utc=utc)

def exact_returns(times, prices, endpoints, minutes=5):
    times, endpoints = np.asarray(times, dtype=np.int64), np.asarray(endpoints, dtype=np.int64)
    if len(times) == 0:
        return np.full(len(endpoints), np.nan)
    if np.any(np.diff(times) <= 0):
        raise ValueError('Bar times must be strictly increasing and unique')
    now, prev = np.searchsorted(times, endpoints), np.searchsorted(times, endpoints-minutes*MINUTE)
    a, b = np.minimum(now, len(times)-1), np.minimum(prev, len(times)-1)
    valid = (now < len(times)) & (prev < len(times)) & (times[a] == endpoints) & (times[b] == endpoints-minutes*MINUTE)
    valid &= np.isfinite(prices[a]) & np.isfinite(prices[b]) & (prices[a] > 0) & (prices[b] > 0)
    r = np.full(len(endpoints), np.nan)
    r[valid] = np.log(prices[a[valid]]) - np.log(prices[b[valid]])
    return r

def variation(r):
    r = np.asarray(r)
    if len(r) < 5 or not np.isfinite(r).all():
        return dict(RV=np.nan, BV=np.nan, net=np.nan, residual=np.nan)
    rv = np.dot(r, r)
    bv = np.pi / 2 * np.sum(np.abs(r[1:] * r[:-1]))
    return dict(RV=rv, BV=bv, net=r.sum(), residual=max(rv-bv, 0))

def clocks(date, event=None):
    d = pd.Timestamp(date).normalize()
    if event is not None:
        return {p: pd.Timestamp(event[f'{p.lower()}_datetime_utc']) for p in ('PR','PC')}
    late = d >= pd.Timestamp('2022-07-21')
    return {p: (d + pd.Timedelta(minutes=m)).tz_localize('Europe/Berlin').tz_convert('UTC')
            for p, m in [('PR', 855 if late else 825), ('PC', 885 if late else 870)]}

def candidate_0830(date):
    return (pd.Timestamp(date).normalize() + pd.Timedelta(hours=8, minutes=30)).tz_localize('America/New_York').tz_convert('UTC')

def intersects(anchor, endpoints, instant):
    return bool(anchor + pd.Timedelta(minutes=endpoints[0]-5) <= instant <= anchor + pd.Timedelta(minutes=endpoints[-1]))

def load_calendar(root):
    e = pd.read_csv(root/'Output/diagnostics/ecb_event_panel.csv')
    e['event_date'] = read_dates(e.event_date).dt.normalize()
    if e.event_date.duplicated().any():
        raise ValueError('Duplicate ECB calendar dates')
    for p in ('pr','pc'):
        e[f'{p}_datetime_utc'] = read_dates(e[f'{p}_datetime_utc'], utc=True)
        local = read_dates(e[f'{p}_datetime_local']).dt.tz_localize('Europe/Berlin').dt.tz_convert('UTC')
        if not (local == e[f'{p}_datetime_utc']).all():
            raise ValueError('Event UTC/Europe-Berlin mismatch')
    return e

def certify(root, spec_path):
    spec = json.loads(spec_path.read_text())
    mfile = root/'Output/manifests/window_semantics_manifest.csv'
    m = pd.read_csv(mfile).iloc[0]
    expected = dict(schema_version='window_semantics_v1', status='certified', raw_time_zone='America/Chicago',
                    analysis_time_zone='UTC', bar_label_status='certified', canonical_bar_time='interval_end_utc')
    if any(m.get(k) != v for k,v in expected.items()) or m.bar_label_semantics not in ('interval_start','interval_end'):
        raise ValueError('Uncertified time / bar semantics')
    tm = pd.read_csv(root/'Output/manifests/time_alignment_manifest.csv')
    if not len(tm) or 'status' in tm and not tm.status.eq('complete').all():
        raise ValueError('Invalid time alignment manifest')
    files = [spec_path, mfile, root/'Output/manifests/time_alignment_manifest.csv',
             root/'Output/diagnostics/ecb_event_panel.csv', root/'Output/diagnostics/contract_day_quality.csv',
             root/'Raw/EA-EMPD/EA-EMPD.xlsx']
    files += sorted((root/'Output/cleaned').glob('*_clean.csv'))
    macro = root/'Raw/Certification/us_releases.csv'
    if macro.exists(): files.append(macro)
    hashes = {str(f.relative_to(root)) if f.is_relative_to(root) else 'specification': sha256(f) for f in files}
    return spec, str(m.bar_label_semantics), hashes

def load_ea(root):
    e = pd.read_excel(root/'Raw/EA-EMPD/EA-EMPD.xlsx', sheet_name='EA-EMPD')
    e['event_date'] = pd.to_datetime(e.Date_time).dt.normalize()
    e['phase'] = e.Event_type.str.replace('GC_', '', regex=False)
    e = e[e.phase.isin(['PR','PC'])].copy()
    if e.duplicated(['event_date','phase']).any():
        raise ValueError('Duplicate EA-EMPD phase dates')
    pr = e[e.phase.eq('PR')].sort_values('event_date').copy()
    pr['lag1'] = pr.OIS_1M.shift(1)/10
    pr['history3'] = pr.OIS_1M.shift(1).rolling(3, min_periods=3).mean()/10
    return e.merge(pr[['event_date','lag1','history3']], on='event_date', how='left', validate='many_to_one')

def build_windows(root, spec, semantics):
    e = load_calendar(root)
    events = {d: row for d,row in e.set_index('event_date').iterrows()}
    q = pd.read_csv(root/'Output/diagnostics/contract_day_quality.csv')
    q['trade_date'] = read_dates(q.trade_date).dt.normalize()
    q = q[q.root_code.isin(spec['robustness_roots']) & (q.trade_date.dt.weekday < 5)]
    q = q[(q.trade_date >= e.event_date.min()-pd.Timedelta(days=60)) & (q.trade_date <= e.event_date.max())]
    if q.duplicated(['trade_date','root_code','file_name_clean']).any():
        raise ValueError('Duplicate candidate contract-days')
    cache = {}
    for f in sorted(q.file_name_clean.unique()):
        p = root/'Output/cleaned'/f
        t = pd.read_csv(p, usecols=['Time','Latest','Volume'])
        dt = read_dates(t.Time, utc=True) + pd.Timedelta(minutes=5 if semantics == 'interval_start' else 0)
        times = dt.astype('int64').to_numpy()
        prices, volume = t.Latest.to_numpy(float), t.Volume.to_numpy(float)
        order = np.argsort(times)
        if len(np.unique(times)) != len(times):
            raise ValueError(f'Duplicate cleaned price timestamps: {f}')
        cache[f] = times[order], prices[order], volume[order]
    print(f'Certified cache: {len(cache)} files, {sum(len(x[0]) for x in cache.values())} bars', flush=True)
    macro_file = root/'Raw/Certification/us_releases.csv'
    releases = pd.read_csv(macro_file) if macro_file.exists() else pd.DataFrame(columns=['release_id','timestamp_utc','source_url'])
    if not set(['release_id','timestamp_utc','source_url']).issubset(releases):
        raise ValueError('Malformed US release calendar')
    if len(releases) and (releases.isna().any().any() or releases.source_url.str.strip().eq('').any()):
        raise ValueError('Every actual release needs a timestamp and source URL')
    releases['instant'] = read_dates(releases.timestamp_utc, utc=True)
    pre_offsets = np.array(spec['pre_pr_return_endpoints_minutes'])
    rows, candidates = [], []
    for i, ((date, root_code), group) in enumerate(q.groupby(['trade_date','root_code'], sort=True)):
        c = clocks(date, events.get(date))
        pre_grid = c['PR'].value + pre_offsets*MINUTE
        rank = []
        for f in group.file_name_clean:
            times, prices, volume = cache[f]
            r = exact_returns(times, prices, pre_grid)
            coverage = np.isfinite(r).mean()
            loc = np.searchsorted(times, pre_grid)
            loc = np.minimum(loc, len(times)-1)
            vol = np.sum(volume[loc][times[loc] == pre_grid])
            rank.append((coverage == 1, coverage, np.nan_to_num(vol), f, r))
        rank.sort(key=lambda z: (-int(z[0]), -z[1], -z[2], z[3]))
        for complete, coverage, volume, f, _ in rank:
            candidates.append(dict(event_date=date, root_code=root_code, file_name_clean=f,
                                   selected=f==rank[0][3], pre_coverage=coverage, pre_volume=volume))
        complete, coverage, vol, f, rpre = rank[0]
        times, prices, volume = cache[f]
        vp = variation(rpre)
        day = pd.Timestamp(date).tz_localize('Europe/Berlin').tz_convert('UTC')
        nextday = (pd.Timestamp(date)+pd.Timedelta(days=1)).tz_localize('Europe/Berlin').tz_convert('UTC')
        idx = np.flatnonzero((times >= day.value) & (times < nextday.value))
        rd = exact_returns(times, prices, times[idx])
        day_rv = np.nansum(rd**2)
        for phase in ('PR','PC'):
            offsets = spec[f'{phase.lower()}_return_endpoints_minutes']
            grid = c[phase].value + np.array(offsets)*MINUTE
            rpost = exact_returns(times, prices, grid)
            v = variation(rpost)
            normal_grid = pre_grid if phase == 'PR' else c['PC'].value + np.arange(-25,0,5)*MINUTE
            normal_pre = exact_returns(times, prices, normal_grid)
            vn = variation(normal_pre)
            verified = [row.release_id for row in releases.itertuples() if intersects(c[phase], offsets, row.instant)]
            rows.append(dict(trade_date=date, root_code=root_code, phase=phase, file_name_clean=f,
                is_event=date in events, event_id=events[date].event_id if date in events else '',
                pr_anchor_utc=c['PR'].isoformat(), phase_anchor_utc=c[phase].isoformat(),
                post_first_endpoint_utc=pd.Timestamp(grid[0], tz='UTC').isoformat(),
                post_last_endpoint_utc=pd.Timestamp(grid[-1], tz='UTC').isoformat(),
                pre_last_endpoint_utc=pd.Timestamp(pre_grid[-1], tz='UTC').isoformat(),
                normal_pre_last_endpoint_utc=pd.Timestamp(normal_grid[-1], tz='UTC').isoformat(),
                pre_coverage=coverage, normal_pre_coverage=np.isfinite(normal_pre).mean(), post_coverage=np.isfinite(rpost).mean(), pre_volume=vol,
                n_pre_returns=int(np.isfinite(rpre).sum()), n_post_returns=int(np.isfinite(rpost).sum()),
                window_eligible=bool(complete and np.isfinite(rpost).all() and np.isfinite(normal_pre).all()),
                selection_BV_pre=vp['BV'], selection_RV_pre=vp['RV'], BV_pre=vn['BV'], RV_pre=vn['RV'], BV_post=v['BV'], RV_post=v['RV'],
                net_post=v['net'], rv_minus_bv=v['residual'], day_rv=day_rv,
                us_0830_candidate=intersects(c[phase], offsets, candidate_0830(date)),
                verified_us_release=bool(verified), verified_release_ids=';'.join(verified),
                us_calendar_status='provided_calendar' if len(releases) else 'candidate_screen_only'))
        if (i+1) % 3000 == 0: print(f'Built {i+1} root-days', flush=True)
    w = pd.DataFrame(rows).sort_values(['root_code','phase','trade_date']).reset_index(drop=True)
    for kind in ['BV','RV']:
        for window in ['pre','post']:
            col = f'{kind}_{window}'
            w['log_'+col] = np.log(w[col].where(w[col] > 0))
    w['log_day_rv'] = np.log(w.day_rv.where(w.day_rv > 0))
    w['state_log_BV_pre'] = np.log(w.selection_BV_pre.where(w.selection_BV_pre > 0))
    w['slow5_log_rv'] = w.groupby(['root_code','phase']).log_day_rv.transform(lambda s: s.shift(1).rolling(5,min_periods=5).mean())
    reg = pd.MultiIndex.from_product([e.event_date, spec['robustness_roots'], ['PR','PC']], names=['trade_date','root_code','phase']).to_frame(index=False)
    reg = reg.merge(w[w.is_event], on=['trade_date','root_code','phase'], how='left', validate='one_to_one')
    reg['price_status'] = np.select([reg.file_name_clean.isna(),reg.pre_coverage.lt(1),reg.post_coverage.lt(1),reg.normal_pre_coverage.lt(1)],
                                   ['no_candidate_contract','missing_pre_pair','missing_post_pair','missing_normal_pre_pair'], default='eligible')
    reg['primary_asset'] = reg.root_code.isin(spec['primary_roots'])
    return w, reg, pd.DataFrame(candidates)
