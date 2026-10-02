import argparse
import json
import platform
import re
import subprocess
from datetime import date, timedelta
from pathlib import Path
import numpy as np
import pandas as pd
import scipy
from scipy.special import gamma
from final_analysis.models import counterfactual
from .estimate import panel
from .exploratory import verify_opened_build
from .functional_form import mean_branch_with_equity, basis_comparison
from .nuisance import counterfactual_v2
from .protocol import REPO, digest, dump, timestamp, new_output, code_hashes

NS_PER_MINUTE = 60_000_000_000
EXPORT_CAP = 19999
MONTHS = {'h': 3, 'm': 6, 'u': 9, 'z': 12}
NEXT = {'h': 'm', 'm': 'u', 'u': 'z', 'z': 'h'}
POST_ENDPOINTS = np.arange(0, 26)
PRE_ENDPOINTS = np.arange(-60, -4)
FIVE_MINUTE_ENDPOINTS = np.arange(0, 26, 5)
MEDRV_CONST = np.pi/(6-4*np.sqrt(3)+np.pi)
MINRV_CONST = np.pi/(np.pi-2)
MU43 = 2**(2/3)*gamma(7/6)/gamma(1/2)
THETA_BNS = (np.pi/2)**2+np.pi-5
MEASURE_KEYS = ['BV', 'BV_excl1', 'BV_excl2', 'BV_excl5', 'RV', 'MedRV', 'MinRV', 'TBV_prewindow', 'TBV_postwindow',
                'jump_share', 'bns_z']
REGRESSION_MEASURES = ['BV', 'BV_excl1', 'BV_excl2', 'BV_excl5', 'RV', 'MedRV', 'MinRV', 'TBV_prewindow', 'TBV_postwindow',
                       'VOL', 'BV5_from_1min']
GENERATION_REFERENCE = 'reference_outputs/cross_epoch_20260916/inputs/generation_harmonized_native_state.csv'
MINUTE_NAME = re.compile(r'^(gg[hmuz]\d\d)_1min_(\d{4}-\d\d-\d\d)_(\d{4}-\d\d-\d\d)\.csv$')
FIVE_NAME = re.compile(r'^(gg[hmuz]\d\d)_intraday-5min_historical-data-.*\.csv$')
CONTRACT = re.compile(r'(gg[hmuz]\d\d)')


def to_minutes(ts):
    ns = ts.dt.as_unit('ns').astype('int64')
    return ns//NS_PER_MINUTE


def minute_string(m):
    return str(pd.to_datetime(int(m)*60, unit='s', utc=True))


def read_provider_csv(path, fmt=None):
    t = pd.read_csv(path, usecols=['Time', 'Latest', 'Volume'])
    t = t[pd.to_numeric(t.Latest, errors='coerce').notna()].copy()
    t['Latest'] = t.Latest.astype(float); t['Volume'] = pd.to_numeric(t.Volume, errors='coerce').fillna(0.).astype(float)
    local = pd.to_datetime(t.Time, format=fmt if fmt else 'mixed')
    utc = local.dt.tz_localize('America/Chicago', ambiguous='raise', nonexistent='raise').dt.tz_convert('UTC')
    t['label'] = to_minutes(utc)
    return t[['label', 'Latest', 'Volume']].sort_values('label', kind='stable').reset_index(drop=True)


def load_minute_dir(directory):
    rows, frames = [], {}
    for path in sorted(Path(directory).glob('*.csv')):
        m = MINUTE_NAME.match(path.name)
        if not m:
            continue
        t = read_provider_csv(path, '%Y-%m-%d %H:%M')
        contract = m.group(1)
        rows.append(dict(file=path.name, contract=contract, requested_start=m.group(2), requested_end=m.group(3),
                         rows=len(t), first_label=int(t.label.min()) if len(t) else np.nan,
                         last_label=int(t.label.max()) if len(t) else np.nan,
                         first_utc=minute_string(t.label.min()) if len(t) else '',
                         last_utc=minute_string(t.label.max()) if len(t) else '',
                         export_cap_reached=bool(len(t) >= EXPORT_CAP), sha256=digest(path)))
        frames.setdefault(contract, []).append(t)
    if not rows:
        raise ValueError(f'MINUTE_DATA_MISSING: no files named contract_1min_start_end.csv in {directory}')
    bars = {}
    for contract, parts in frames.items():
        t = pd.concat(parts, ignore_index=True)
        dup = t[t.duplicated('label', keep=False)]
        if len(dup) and (dup.groupby('label')[['Latest', 'Volume']].nunique() > 1).any().any():
            raise ValueError(f'MINUTE_CONFLICT: overlapping slices of {contract} disagree on the same minute')
        t = t.drop_duplicates('label').sort_values('label').reset_index(drop=True)
        vol = t.Volume.to_numpy(float)
        bars[contract] = dict(label=t.label.to_numpy(np.int64), latest=t.Latest.to_numpy(float), volume=vol,
                              cumvol=np.concatenate([[0.], np.cumsum(vol)]))
    return bars, pd.DataFrame(rows)


def last_trading_day(contract):
    year = 2000+int(contract[3:5]); d = date(year, MONTHS[contract[2]], 10)
    while d.weekday() >= 5:
        d += timedelta(days=1)
    k = 0
    while k < 2:
        d -= timedelta(days=1)
        if d.weekday() < 5:
            k += 1
    return d


def next_contract(contract):
    m = contract[2]; year = int(contract[3:5])
    return f'{contract[:2]}{NEXT[m]}{(year+1) % 100 if m == "z" else year:02d}'


def select_contract(trade_date, frozen):
    if frozen is None:
        return None, False
    if pd.Timestamp(trade_date).date() >= last_trading_day(frozen):
        return next_contract(frozen), True
    return frozen, False


def prices_at(b, endpoints, stale):
    target = endpoints-1
    idx = np.searchsorted(b['label'], target, side='right')-1
    ok = idx >= 0
    safe = np.where(ok, idx, 0)
    ok &= b['label'][safe] >= target-stale
    price = np.where(ok, b['latest'][safe], np.nan)
    filled = ok & (b['label'][safe] != target)
    return price, int(filled.sum())


def returns_at(b, anchor, endpoints, stale):
    p, filled = prices_at(b, anchor+endpoints, stale)
    with np.errstate(divide='ignore', invalid='ignore'):
        return np.diff(np.log(p)), filled


def volume_between(b, lo, hi):
    s = np.searchsorted(b['label'], lo, side='left'); e = np.searchsorted(b['label'], hi, side='left')
    return float(b['cumvol'][e]-b['cumvol'][s]), int(e-s)


def bipower(r):
    a = np.abs(r)
    return np.pi/2*float(np.sum(a[1:]*a[:-1]))


def truncated_bipower(r, prod, local_variance, threshold_c):
    if not np.isfinite(local_variance) or local_variance <= 0:
        return np.nan
    theta = threshold_c**2*local_variance
    keep = (r[1:]**2 <= theta) & (r[:-1]**2 <= theta)
    return np.pi/2*float(np.sum(prod[keep]))


def minute_measures(r, pre, threshold_c=3.):
    empty = {k: np.nan for k in MEASURE_KEYS}
    r = np.asarray(r, float)
    if len(r) < 6 or not np.isfinite(r).all():
        return empty
    a = np.abs(r); n = len(r)
    prod = a[1:]*a[:-1]
    out = dict(BV=np.pi/2*float(prod.sum()), BV_excl1=np.pi/2*float(prod[1:].sum()),
               BV_excl2=np.pi/2*float(prod[2:].sum()), BV_excl5=np.pi/2*float(prod[5:].sum()),
               RV=float(np.dot(r, r)))
    med = np.array([np.median(a[j-1:j+2]) for j in range(1, n-1)])
    out['MedRV'] = MEDRV_CONST*n/(n-2)*float(np.sum(med**2))
    out['MinRV'] = MINRV_CONST*n/(n-1)*float(np.sum(np.minimum(a[1:], a[:-1])**2))
    pre = np.asarray(pre, float)
    out['TBV_prewindow'] = truncated_bipower(r, prod, bipower(pre)/(len(pre)-1), threshold_c) if (
        len(pre) > 2 and np.isfinite(pre).all()) else np.nan
    out['TBV_postwindow'] = truncated_bipower(r, prod, out['MedRV']/n, threshold_c)
    tq = n*MU43**-3*n/(n-2)*float(np.sum((a[2:]*a[1:-1]*a[:-2])**(4/3)))
    rv, bv = out['RV'], out['BV']
    out['jump_share'] = max(rv-bv, 0.)/rv if rv > 0 else np.nan
    out['bns_z'] = ((rv-bv)/rv)/np.sqrt(THETA_BNS/n*max(1., tq/bv**2)) if rv > 0 and bv > 0 else np.nan
    return out


def registry_from_windows(w, sample, contract_column):
    rows = w[w.root_code.eq('gg') & w.phase.eq('PR')].copy()
    anchor = rows['phase_anchor_utc'] if 'phase_anchor_utc' in rows else rows['pr_anchor_utc']
    if 'pr_anchor_utc' in rows:
        anchor = anchor.where(anchor.notna() & anchor.astype(str).ne(''), rows['pr_anchor_utc'])
    rows['anchor_utc'] = pd.to_datetime(anchor, utc=True, errors='coerce')
    rows = rows[rows.anchor_utc.notna()].copy()
    if (rows.anchor_utc.dt.as_unit('ns').astype('int64') % NS_PER_MINUTE != 0).any():
        raise ValueError('ANCHOR_NOT_ON_MINUTE')
    rows['anchor'] = to_minutes(rows.anchor_utc)
    rows['frozen_contract'] = rows[contract_column].astype(str).map(lambda p: (CONTRACT.search(p) or [None, None])[1])
    rows['sample'] = sample
    keep = ['sample', 'trade_date', 'is_event', 'anchor', 'anchor_utc', 'frozen_contract']
    extra = [c for c in ['window_eligible', 'BV_post'] if c in rows]
    return rows[keep+extra].reset_index(drop=True)


def measure_panel(registry, bars, stale):
    out = []
    for r in registry.itertuples():
        chosen, switched = select_contract(r.trade_date, r.frozen_contract)
        row = dict(sample=r.sample, trade_date=r.trade_date, is_event=bool(r.is_event), anchor_utc=str(r.anchor_utc),
                   frozen_contract=r.frozen_contract, contract=chosen, switched_for_expiry=switched,
                   frozen_contract_last_trading_day=str(last_trading_day(r.frozen_contract)) if r.frozen_contract else '')
        b = bars.get(chosen)
        if b is None:
            row.update(coverage_status='contract_not_downloaded', **{k: np.nan for k in MEASURE_KEYS})
            out.append(row); continue
        post, filled_post = returns_at(b, r.anchor, POST_ENDPOINTS, stale)
        pre, filled_pre = returns_at(b, r.anchor, PRE_ENDPOINTS, stale)
        vol, n_post_bars = volume_between(b, r.anchor, r.anchor+25)
        vol_pre, n_pre_bars = volume_between(b, r.anchor-60, r.anchor-5)
        m = minute_measures(post, pre)
        row.update(m, VOL=vol, VOL_pre=vol_pre, n_post_bars=n_post_bars, n_pre_bars=n_pre_bars,
                   filled_post_endpoints=filled_post, filled_pre_endpoints=filled_pre,
                   post_complete=bool(np.isfinite(post).all()), pre_complete=bool(np.isfinite(pre).all()),
                   BV_pre_1min=bipower(pre) if np.isfinite(pre).all() else np.nan, abs_r1=abs(post[0]) if len(post) else np.nan,
                   coverage_status='complete' if np.isfinite(post).all() else ('empty' if n_post_bars == 0 else 'stale_or_partial'))
        fb = bars.get(r.frozen_contract)
        if fb is not None:
            r5, _ = returns_at(fb, r.anchor, FIVE_MINUTE_ENDPOINTS, 5)
            row['BV5_from_1min'] = bipower(r5) if np.isfinite(r5).all() else np.nan
        else:
            row['BV5_from_1min'] = np.nan
        out.append(row)
    return pd.DataFrame(out)


def five_minute_files(directories):
    found = {}
    for d in directories:
        for path in sorted(Path(d).glob('gg*_intraday-5min_*.csv')):
            m = FIVE_NAME.match(path.name)
            if not m:
                continue
            c = m.group(1)
            if c not in found or ('_clean' in found[c].name and '_clean' not in path.name):
                found[c] = path
    return found


def certify_against_five_minutes(bars, manifest, directories, min_bars=200):
    files = five_minute_files(directories)
    intervals = manifest.dropna(subset=['first_label']).groupby('contract')[['first_label', 'last_label']].apply(
        lambda g: list(zip(g.first_label.astype(np.int64), g.last_label.astype(np.int64))))
    rows = []
    for contract, b in sorted(bars.items()):
        path = files.get(contract)
        if path is None:
            rows.append(dict(contract=contract, five_minute_file='', status='five_minute_file_missing')); continue
        f = read_provider_csv(path)
        L = f.label.to_numpy(np.int64)
        inside = np.zeros(len(L), bool)
        for lo, hi in intervals.get(contract, []):
            inside |= (L >= lo) & (L+5 <= hi+1)
        L, V, P = L[inside], f.Volume.to_numpy(float)[inside], f.Latest.to_numpy(float)[inside]
        res = dict(contract=contract, five_minute_file=path.name, five_minute_sha256=digest(path), n_compared=int(len(L)))
        for name, off in [('interval_start', 0), ('interval_end', 1)]:
            s = np.searchsorted(b['label'], L+off, side='left'); e = np.searchsorted(b['label'], L+off+5, side='left')
            vol = b['cumvol'][e]-b['cumvol'][s]
            last = e-1; ok = last >= s
            price = np.where(ok, b['latest'][np.where(ok, last, 0)], np.nan)
            res[f'volume_match_{name}'] = float(np.mean(np.abs(vol-V) < 1e-9)) if len(L) else np.nan
            res[f'price_match_{name}'] = float(np.mean(np.abs(price-P) < 1e-9)) if len(L) else np.nan
        if len(L) < min_bars:
            res['status'] = 'too_few_comparable_bars'
        elif res['volume_match_interval_start'] >= .98 and res['price_match_interval_start'] >= .98 and res['volume_match_interval_end'] <= .5:
            res['status'] = 'interval_start'
        elif res['volume_match_interval_end'] >= .98 and res['price_match_interval_end'] >= .98 and res['volume_match_interval_start'] <= .5:
            res['status'] = 'interval_end'
        else:
            res['status'] = 'conflict'
        rows.append(res)
    table = pd.DataFrame(rows)
    decided = table[table.status.isin(['interval_start', 'interval_end'])]
    verdict = decided.status.iloc[0] if len(decided) and decided.status.nunique() == 1 else 'not_certified'
    if table.status.isin(['conflict', 'interval_end']).any():
        verdict = 'not_certified'
    return table, verdict


def outcome_from_minute(w, pm, spec, measure):
    v = w.copy()
    idx = v.root_code.eq('gg') & v.phase.eq('PR')
    m = pm.set_index('trade_date')
    val = m[measure].reindex(v.loc[idx, 'trade_date']).to_numpy(float)
    v.loc[idx, 'BV_post'] = val
    v.loc[idx, 'log_BV_post'] = np.log(np.where(np.isfinite(val) & (val > 0), val, np.nan))
    if measure == 'VOL':
        pv = m['VOL_pre'].reindex(v.loc[idx, 'trade_date']).to_numpy(float)
        v.loc[idx, 'log_BV_pre'] = np.log(np.where(np.isfinite(pv) & (pv > 0), pv, np.nan))
    cf, _ = counterfactual_v2(v, spec)
    return cf


def regression_row(sample, measure, T, spec, draws, out):
    if len(T) < spec['minimum_event_clusters']:
        return dict(sample=sample, measure=measure, n_events=len(T), status='too_few_events')
    mb = pd.DataFrame(mean_branch_with_equity(T, spec, 'u', 'z', draws, spec['seed']+9000))
    fits, paired, summary = basis_comparison(T, spec, 'u', 'z')
    f = fits.set_index('basis')
    row = dict(sample=sample, measure=measure, n_events=len(T), status='observed_after_opening')
    for term in ['abs_u', 'abs_z', 'u', 'z']:
        t = mb[mb.term.eq(term)].iloc[0]
        row[f'{term}_estimate'] = t.estimate; row[f'{term}_p_wild'] = t.p_wild
    row.update(mse_degree2=summary['mean_mse_degree2'], mse_degree1=summary['mean_mse_degree1'],
               mse_quadratic_angles_radial1=summary['mean_mse_quadratic_angles_radial1'],
               folds_won_by_degree1=summary['folds_won_by_degree1'],
               folds_won_by_radial1_quadratic_angles=summary['folds_won_by_radial1_quadratic_angles'],
               n_folds=summary['n_folds'], mp_minus_cbi_degree1_r1=float(f.loc['degree1_absolute', 'difference_r1']),
               mp_minus_cbi_degree2_r1=float(f.loc['degree2_quadratic', 'difference_r1']))
    paired.assign(sample=sample, measure=measure).to_csv(out/f'minute_paired_annual_errors_{sample}_{measure}.csv', index=False)
    return row


def historical_regressions(w, indicators, spec, pm, draws, out):
    u, z = spec['primary_coordinates']['u'], spec['primary_coordinates']['z']
    rows = []
    for measure in REGRESSION_MEASURES:
        cf = outcome_from_minute(w, pm, spec, measure)
        T = panel(cf, indicators, spec, 'gg', 'PR', u, z, 'crossfit_abnormal_log_BV').rename(columns={u: 'u', z: 'z'})
        rows.append(regression_row('H_2000_2012', measure, T, spec, draws, out))
    return rows


def control_slow(w):
    parts = []
    for root, t in w[w.phase.eq('PR')].groupby('root_code'):
        ctrl = t[~t.is_event].sort_values('trade_date').copy()
        ctrl['slow_state_new'] = ctrl.log_day_rv.rolling(5, min_periods=5).mean()
        j = pd.merge_asof(t[['trade_date']].sort_values('trade_date'), ctrl[['trade_date', 'slow_state_new']],
                          on='trade_date', direction='backward', allow_exact_matches=False)
        j['root_code'] = root
        parts.append(j)
    return w.merge(pd.concat(parts), on=['trade_date', 'root_code'], how='left', validate='many_to_one')


class GenerationDesign:
    def __init__(self, generation_dir, bridge_dir=None):
        g = Path(generation_dir)
        status = json.loads((g/'status.json').read_text())
        if status.get('status') != 'frozen':
            raise ValueError('GENERATION_BUILD_NOT_FROZEN')
        for name in ['windows.csv', 'ea_source.csv']:
            if digest(g/name) != status['table_hashes'][name]:
                raise ValueError(f'GENERATION_TABLE_MODIFIED: {name}')
        if digest(g/'specification.json') != status['specification_sha256']:
            raise ValueError('GENERATION_SPECIFICATION_MODIFIED')
        self.status_sha = digest(g/'status.json')
        self.spec = json.loads((g/'specification.json').read_text())
        w = pd.read_csv(g/'windows.csv', parse_dates=['trade_date'])
        self.full_windows = w
        w = w[w.trade_date.between('2013-01-01', '2025-12-31')].copy()
        ea = pd.read_csv(g/'ea_source.csv', parse_dates=['event_date'])
        ea = ea[ea.phase.eq('PR') & ea.event_date.between('2013-01-01', '2025-12-31')]
        pr = w[w.phase.eq('PR')]
        nets = pr.pivot(index='trade_date', columns='root_code', values='net_post')
        flags = pr.groupby('trade_date').is_event.first()
        self.schatz_sd = float(nets.loc[~flags, 'hf'].std())
        self.equity_sd = float((ea.STOXX50E/100).std())
        if bridge_dir is not None:
            scales = json.loads((Path(bridge_dir)/'bridge_decision.json').read_text())['scales']
            if not (np.isclose(self.schatz_sd, scales['hf_pr_control_sd'], rtol=1e-12)
                    and np.isclose(self.equity_sd, scales['external_pr_generation_event_sd_fractional_return'], rtol=1e-12)):
                raise ValueError('GENERATION_SCALES_NOT_REPRODUCED')
        c = nets.loc[flags, ['hf', 'fx']].reset_index().merge(ea[['event_date', 'STOXX50E']], left_on='trade_date',
                                                              right_on='event_date', validate='one_to_one')
        c['u'] = -c.hf/self.schatz_sd
        c['z'] = c.STOXX50E/100/self.equity_sd
        self.coords = c[np.isfinite(c[['u', 'z', 'fx']]).all(axis=1)][['trade_date', 'u', 'z']]
        cw = control_slow(w)
        cw['slow5_log_rv'] = cw.slow_state_new
        self.windows = cw

    def panel(self, pm=None, measure=None):
        v = self.windows.copy()
        if measure is not None:
            idx = v.root_code.eq('gg') & v.phase.eq('PR')
            m = pm.set_index('trade_date')
            val = m[measure].reindex(v.loc[idx, 'trade_date']).to_numpy(float)
            v.loc[idx, 'BV_post'] = val
            v.loc[idx, 'log_BV_post'] = np.log(np.where(np.isfinite(val) & (val > 0), val, np.nan))
            if measure == 'VOL':
                pv = m['VOL_pre'].reindex(v.loc[idx, 'trade_date']).to_numpy(float)
                v.loc[idx, 'log_BV_pre'] = np.log(np.where(np.isfinite(pv) & (pv > 0), pv, np.nan))
        rev, _ = counterfactual(v, self.spec)
        b = rev[rev.is_event & rev.phase.eq('PR') & rev.root_code.eq('gg')]
        t = self.coords.merge(b[['trade_date', 'window_eligible', 'crossfit_state_z', 'crossfit_abnormal_log_BV']],
                              on='trade_date', validate='one_to_one')
        keep = t.window_eligible.astype(bool) & np.isfinite(t[['crossfit_state_z', 'crossfit_abnormal_log_BV']]).all(axis=1)
        return t[keep].drop(columns='window_eligible').sort_values('trade_date').reset_index(drop=True)

    def reproduction(self, reference):
        if reference is None or not Path(reference).exists():
            return dict(reference='', n_events=np.nan, max_abs_difference=np.nan)
        ref = pd.read_csv(reference, parse_dates=['trade_date'])
        t = self.panel()
        m = ref.merge(t, on='trade_date', suffixes=('_ref', ''))
        diff = max(float(np.abs(m[c+'_ref']-m[c]).max()) for c in ['u', 'z', 'crossfit_state_z', 'crossfit_abnormal_log_BV'])
        result = dict(reference=str(reference), n_events=int(len(t)), n_reference=int(len(ref)), max_abs_difference=diff)
        if len(m) != len(ref) or len(t) != len(ref) or diff > 1e-8:
            raise ValueError(f'GENERATION_PANEL_NOT_REPRODUCED: {result}')
        return result


def generation_regressions(design, spec, pm, draws, out):
    return [regression_row('G_2013_2025', measure, design.panel(pm, measure), spec, draws, out)
            for measure in REGRESSION_MEASURES]


def jump_descriptives(pm):
    rows = []
    for (sample, ev), g in pm[pm.post_complete.fillna(False).astype(bool)].groupby(['sample', 'is_event']):
        bv = g.BV.to_numpy(float)

        def ratio(c):
            num = g[c].to_numpy(float)
            r = np.divide(num, bv, out=np.full(len(bv), np.nan), where=bv > 0)
            return float(np.nanmedian(r)) if np.isfinite(r).any() else np.nan
        rows.append(dict(sample=sample, is_event=bool(ev), n=len(g), median_RV=float(g.RV.median()), median_BV=float(g.BV.median()),
                         median_jump_share=float(g.jump_share.median()), share_bns_1pct=float((g.bns_z > 2.326).mean()),
                         share_bns_5pct=float((g.bns_z > 1.645).mean()), median_BV_excl1_over_BV=ratio('BV_excl1'),
                         median_BV_excl5_over_BV=ratio('BV_excl5'), median_VOL=float(g.VOL.median()),
                         share_bv_zero=float((g.BV == 0).mean())))
    return pd.DataFrame(rows)


def minute_run(build, minute_dir, five_minute_dirs, out, generation_dir=None, bridge_dir=None, stale=5, smoke=False):
    build = Path(build)
    manifest, spec, code_changed = verify_opened_build(build)
    out = new_output(out)
    dump(out/'run_manifest.json', dict(status='running', mode='post_opening_minute'))
    bars, files = load_minute_dir(minute_dir)
    files.to_csv(out/'minute_file_manifest.csv', index=False)
    cert, verdict = certify_against_five_minutes(bars, files, five_minute_dirs)
    cert.to_csv(out/'minute_bar_label_certification.csv', index=False)
    if verdict != 'interval_start':
        dump(out/'run_manifest.json', dict(status='stopped_minute_labels_not_certified', verdict=verdict))
        raise ValueError(f'MINUTE_LABELS_NOT_CERTIFIED: {verdict}')
    w = pd.read_csv(build/'windows.csv', parse_dates=['trade_date'])
    indicators = pd.read_csv(build/'indicators.csv', parse_dates=['trade_date'])
    registries = [registry_from_windows(w, 'H_2000_2012', 'input_path')]
    design = None
    if generation_dir is not None:
        design = GenerationDesign(generation_dir, bridge_dir)
        registries.append(registry_from_windows(design.full_windows, 'G_2013_2025', 'file_name_clean'))
    pm = pd.concat([measure_panel(r, bars, stale) for r in registries], ignore_index=True)
    pm.to_csv(out/'minute_measures_panel.csv', index=False)
    pm.groupby(['sample', 'is_event', 'coverage_status']).size().rename('n').reset_index().to_csv(
        out/'minute_coverage_summary.csv', index=False)
    jump_descriptives(pm).to_csv(out/'minute_jump_descriptives.csv', index=False)
    h = pm[pm['sample'].eq('H_2000_2012')].merge(registries[0][['trade_date', 'BV_post']], on='trade_date', how='left')
    both = np.isfinite(h.BV5_from_1min) & np.isfinite(h.BV_post) & (h.BV_post > 0)
    rel = np.abs(h.BV5_from_1min[both]-h.BV_post[both])/h.BV_post[both]
    reproduction = dict(n_compared=int(both.sum()), max_relative_difference=float(rel.max()) if both.any() else np.nan,
                        share_exact=float((rel < 1e-9).mean()) if both.any() else np.nan)
    draws = 19 if smoke else spec['secondary_family']['draws']
    hm = pm[pm['sample'].eq('H_2000_2012')].drop_duplicates('trade_date')
    rows = historical_regressions(w, indicators, spec, hm, draws, out)
    generation_reproduction = None
    if design is not None:
        generation_reproduction = design.reproduction(REPO/GENERATION_REFERENCE)
        gm = pm[pm['sample'].eq('G_2013_2025')].drop_duplicates('trade_date')
        rows += generation_regressions(design, spec, gm, draws, out)
    pd.DataFrame(rows).to_csv(out/'minute_robustness_measures.csv', index=False)
    switched = pm[pm.switched_for_expiry]
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, capture_output=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=REPO, text=True, capture_output=True).stdout)
    result = dict(status='complete_minute_after_opening' if not smoke else 'complete_smoke_not_for_inference',
                  mode='post_opening_minute', created_utc=timestamp(), git_sha=sha, git_dirty=dirty,
                  code_changed_since_freeze=code_changed,
                  prior_results_seen={'generation_2013_2025': True, 'confirmation_2000_2012': True},
                  confirmation_verdict_unchanged=True, frozen_build_sha256=digest(build/'status.json'),
                  generation_build_sha256=design.status_sha if design is not None else '',
                  generation_panel_reproduction=generation_reproduction,
                  minute_bar_label_verdict=verdict, n_minute_files=int(len(files)),
                  n_files_export_cap_reached=int(files.export_cap_reached.sum()),
                  stale_minutes=stale, bv5_reproduction=reproduction,
                  expiry_rule='Eurex fixed income: delivery on the 10th of the quarter month or the next weekday; last trading day two weekdays earlier, trading ends 12:30 CET; a contract is never used on or after its last trading day',
                  n_rows_switched_for_expiry=int(len(switched)),
                  events_switched_for_expiry=[str(d.date()) for d in switched[switched.is_event].trade_date],
                  threshold_note='TBV_prewindow truncates at 3 times the pre-window per-minute bipower variance; TBV_postwindow at 3 times the post-window per-minute MedRV',
                  eligibility_note='regressions keep the frozen window_eligible flags of each build; meetings recovered by the expiry rule are reported in the panel only',
                  continuation_note='outcome replaced by the one-minute measure; the continuation regressor stays the frozen five-minute pre-window bipower, except VOL, which uses one-minute pre-window volume; the generation sample uses the harmonized control-only slow state',
                  code_hashes=code_hashes(), draws=draws, python=platform.python_version(),
                  numpy=np.__version__, pandas=pd.__version__, scipy=scipy.__version__)
    dump(out/'run_manifest.json', result)
    print(json.dumps({k: v for k, v in result.items() if k != 'code_hashes'}, indent=2), flush=True)
    return result


def main():
    p = argparse.ArgumentParser(prog='python -m confirmation_analysis.minute')
    p.add_argument('--build', type=Path, required=True)
    p.add_argument('--minute-dir', type=Path, required=True)
    p.add_argument('--five-minute-dir', type=Path, action='append', required=True)
    p.add_argument('--generation-dir', type=Path)
    p.add_argument('--bridge-dir', type=Path)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--stale-minutes', type=int, default=5)
    p.add_argument('--smoke', action='store_true')
    a = p.parse_args()
    minute_run(a.build, a.minute_dir, a.five_minute_dir, a.output, a.generation_dir, a.bridge_dir, a.stale_minutes, a.smoke)


if __name__ == '__main__':
    main()
