import argparse
import json
import platform
import re
import subprocess
from pathlib import Path
import numpy as np
import pandas as pd
import scipy
from .design_information import exponent_profile
from .fed_replication import (load_files, registry, build_panel, day_rv, slow_state, continuation, event_table,
                              contract_for, check_protocol, in_zlb)
from .functional_form import mean_branch_with_equity, basis_comparison
from .minute import (read_provider_csv, minute_measures, bipower, returns_at, volume_between, minute_string,
                     EXPORT_CAP, POST_ENDPOINTS, PRE_ENDPOINTS, FIVE_MINUTE_ENDPOINTS, MEASURE_KEYS)
from .protocol import REPO, digest, dump, timestamp, new_output, code_hashes

MINUTE_NAME = re.compile(r'^(zn[hmuz]\d\d)_1min_(\d{4}-\d\d-\d\d)_(\d{4}-\d\d-\d\d)\.csv$')
VARIATION_MEASURES = ['BV5_from_1min', 'BV', 'BV_excl1', 'BV_excl2', 'BV_excl5', 'RV', 'RV_excl1', 'RV_excl5',
                      'MedRV', 'MinRV', 'TBV_prewindow', 'TBV_postwindow']
VOLUME_MEASURES = ['VOL', 'VOL_minute1', 'VOL_minutes2_5', 'VOL_minutes6_25']
REGRESSION_MEASURES = VARIATION_MEASURES+VOLUME_MEASURES
PROFILE_MEASURES = ['BV', 'BV_excl1', 'BV_excl5', 'VOL']
PERIODS = ['all', 'zero_lower_bound', 'positive_rates']
FIVE_MINUTE_COLUMNS = ['BV', 'BV25', 'RV', 'MedRV', 'MinRV', 'VOL', 'VOL1', 'VOL25', 'RV25']


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
        raise ValueError(f'FED_MINUTE_DATA_MISSING: no files named zn-contract_1min_start_end.csv in {directory}')
    bars = {}
    for contract, parts in frames.items():
        t = pd.concat(parts, ignore_index=True)
        dup = t[t.duplicated('label', keep=False)]
        if len(dup) and (dup.groupby('label')[['Latest', 'Volume']].nunique() > 1).any().any():
            raise ValueError(f'FED_MINUTE_CONFLICT: overlapping slices of {contract} disagree on the same minute')
        t = t.drop_duplicates('label').sort_values('label').reset_index(drop=True)
        vol = t.Volume.to_numpy(float)
        bars[contract] = dict(label=t.label.to_numpy(np.int64), latest=t.Latest.to_numpy(float), volume=vol,
                              cumvol=np.concatenate([[0.], np.cumsum(vol)]))
    return bars, pd.DataFrame(rows)


def certify_against_five_minutes(bars, manifest, five_bars, windows, min_bars=200):
    intervals = manifest.dropna(subset=['first_label']).groupby('contract')[['first_label', 'last_label']].apply(
        lambda g: list(zip(g.first_label.astype(np.int64), g.last_label.astype(np.int64))))
    files = windows[windows.root.eq('zn')].set_index('contract')
    rows = []
    for contract, b in sorted(bars.items()):
        if contract not in five_bars:
            rows.append(dict(contract=contract, five_minute_file='', status='five_minute_file_missing')); continue
        f = five_bars[contract]
        L = f['label']
        inside = np.zeros(len(L), bool)
        for lo, hi in intervals.get(contract, []):
            inside |= (L >= lo) & (L+5 <= hi+1)
        L, V, P = L[inside], f['volume'][inside], f['latest'][inside]
        res = dict(contract=contract, five_minute_file=files.loc[contract, 'file'], five_minute_sha256=files.loc[contract, 'sha256'],
                   n_compared=int(len(L)))
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
    if table.status.isin(['conflict', 'interval_end', 'five_minute_file_missing']).any():
        verdict = 'not_certified'
    return table, verdict


def minute_panel(reg, bars, windows, stale):
    out = []
    for r in reg.itertuples():
        contract = contract_for(windows, 'zn', r.day)
        row = dict(day=r.day, clock=r.clock, is_event=bool(r.is_event), anchor=int(r.anchor), contract=contract or '')
        b = bars.get(contract)
        if b is None:
            row.update(coverage_status='contract_not_downloaded', **{k: np.nan for k in MEASURE_KEYS})
            out.append(row); continue
        post, filled_post = returns_at(b, r.anchor, POST_ENDPOINTS, stale)
        pre, filled_pre = returns_at(b, r.anchor, PRE_ENDPOINTS, stale)
        vol, n_post_bars = volume_between(b, r.anchor, r.anchor+25)
        vol_pre, n_pre_bars = volume_between(b, r.anchor-60, r.anchor-5)
        vol_m1, _ = volume_between(b, r.anchor, r.anchor+1)
        vol_m2_5, _ = volume_between(b, r.anchor+1, r.anchor+5)
        finite = bool(np.isfinite(post).all())
        row.update(minute_measures(post, pre), VOL=vol, VOL_pre=vol_pre, VOL_minute1=vol_m1, VOL_minutes2_5=vol_m2_5,
                   VOL_minutes6_25=vol-vol_m1-vol_m2_5, n_post_bars=n_post_bars, n_pre_bars=n_pre_bars,
                   filled_post_endpoints=filled_post, filled_pre_endpoints=filled_pre,
                   post_complete=finite, post_complete_strict=bool(finite and filled_post == 0),
                   pre_complete=bool(np.isfinite(pre).all()),
                   RV_excl1=float(post[1:]@post[1:]) if finite else np.nan,
                   RV_excl5=float(post[5:]@post[5:]) if finite else np.nan,
                   BV_pre_1min=bipower(pre) if np.isfinite(pre).all() else np.nan,
                   abs_r1=abs(post[0]) if finite else np.nan,
                   coverage_status='complete' if finite else ('empty' if n_post_bars == 0 else 'stale_or_partial'))
        r5, _ = returns_at(b, r.anchor, FIVE_MINUTE_ENDPOINTS, 5)
        row['BV5_from_1min'] = bipower(r5) if np.isfinite(r5).all() else np.nan
        out.append(row)
    return pd.DataFrame(out)


def merged_panel(panel5, pm):
    five = panel5.rename(columns={c: f'{c}_5min' for c in FIVE_MINUTE_COLUMNS})
    m = five.merge(pm.drop(columns=['is_event', 'anchor']), on=['day', 'clock'], how='left', validate='one_to_one')
    strict = m.post_complete_strict.fillna(False).astype(bool)
    for c in REGRESSION_MEASURES:
        m[c] = m[c].where(strict)
    return m


def outcome_table(merged, measure, slow, origin, scales):
    pre_col = 'VOL_pre' if measure in VOLUME_MEASURES else 'pre_BV'
    return event_table(continuation(merged, measure, slow, origin, pre_col), scales)


def regression_row(measure, period, T, spec, draws, out):
    row = dict(measure=measure, period=period, n_events=len(T))
    if len(T) < spec['minimum_event_clusters']:
        row['status'] = 'too_few_events'
        return row
    mb = pd.DataFrame(mean_branch_with_equity(T, spec, 'u', 'z', draws, spec['seed']+9100))
    row['status'] = 'post_protocol_descriptive'
    for term in ['abs_u', 'abs_z', 'u', 'z']:
        t = mb[mb.term.eq(term)].iloc[0]
        row[f'{term}_estimate'] = t.estimate; row[f'{term}_p_wild'] = t.p_wild
    if period == 'all':
        fits, paired, summary = basis_comparison(T, spec, 'u', 'z')
        row.update(mse_degree2=summary['mean_mse_degree2'], mse_degree1=summary['mean_mse_degree1'],
                   mse_quadratic_angles_radial1=summary['mean_mse_quadratic_angles_radial1'],
                   folds_won_by_degree1=summary['folds_won_by_degree1'],
                   folds_won_by_radial1_quadratic_angles=summary['folds_won_by_radial1_quadratic_angles'],
                   n_folds=summary['n_folds'])
        paired.assign(measure=measure).to_csv(out/f'fed_minute_paired_annual_errors_{measure}.csv', index=False)
    return row


def window_descriptives(pm):
    rows = []
    for ev, g in pm[pm.post_complete_strict.fillna(False).astype(bool)].groupby('is_event'):
        bv = g.BV.to_numpy(float); vol = g.VOL.to_numpy(float)

        def ratio(num, den):
            num = np.asarray(num, float); den = np.asarray(den, float)
            r = np.divide(num, den, out=np.full(len(den), np.nan), where=den > 0)
            return float(np.nanmedian(r)) if np.isfinite(r).any() else np.nan
        rows.append(dict(is_event=bool(ev), n=len(g), median_RV=float(g.RV.median()), median_BV=float(g.BV.median()),
                         median_jump_share=float(g.jump_share.median()), share_bns_1pct=float((g.bns_z > 2.326).mean()),
                         share_bns_5pct=float((g.bns_z > 1.645).mean()),
                         median_BV_excl1_over_BV=ratio(g.BV_excl1, bv), median_BV_excl5_over_BV=ratio(g.BV_excl5, bv),
                         median_VOL=float(g.VOL.median()), median_VOL_minute1_share=ratio(g.VOL_minute1, vol),
                         median_VOL_first_five_share=ratio(g.VOL_minute1+g.VOL_minutes2_5, vol),
                         share_bv_zero=float((g.BV == 0).mean())))
    return pd.DataFrame(rows)


def excluded_events(merged, bv_table):
    kept = set(bv_table.trade_date.dt.date)
    rows = []
    for r in merged[merged.is_event].itertuples():
        if r.day in kept:
            continue
        if not r.contract:
            reason = 'contract_not_downloaded'
        elif not bool(r.post_complete_strict):
            reason = 'post_window_incomplete_at_one_minute'
        elif not np.isfinite(r.BV) or r.BV <= 0:
            reason = 'zero_bipower'
        elif not (np.isfinite(r.zt_net) and np.isfinite(r.es_net)):
            reason = 'coordinate_missing'
        else:
            reason = 'continuation_undefined'
        rows.append(dict(day=str(r.day), clock=r.clock, contract=r.contract, n_post_bars=int(r.n_post_bars),
                         filled_post_endpoints=int(r.filled_post_endpoints), reason=reason))
    return pd.DataFrame(rows)


def reproduction_checks(merged, run_dir, rows):
    ev = merged[merged.is_event]
    both = np.isfinite(ev.BV5_from_1min) & np.isfinite(ev.BV_5min) & (ev.BV_5min > 0)
    rel = np.abs(ev.BV5_from_1min[both]-ev.BV_5min[both])/ev.BV_5min[both]
    out = dict(bv5_from_1min=dict(n_compared=int(both.sum()), max_relative_difference=float(rel.max()) if both.any() else np.nan,
                                  share_exact=float((rel < 1e-9).mean()) if both.any() else np.nan))
    if run_dir is not None:
        ref = pd.read_csv(Path(run_dir)/'fed_mean_branch.csv')
        ref = ref[ref.period.eq('all') & ref.measure.eq('BV')].iloc[0]
        here = next(r for r in rows if r['measure'] == 'BV5_from_1min' and r['period'] == 'all')
        out['five_minute_mean_branch'] = dict(replication_run=str(run_dir), n_events_reference=int(ref.n_events),
                                              n_events_here=int(here['n_events']),
                                              abs_u_difference=float(abs(here['abs_u_estimate']-ref.abs_u_estimate)),
                                              abs_z_difference=float(abs(here['abs_z_estimate']-ref.abs_z_estimate)))
    return out


def fed_minute_run(fed_dir, minute_dir, calendar, protocol, out, run_dir=None, stale=5, smoke=False):
    proto, proto_sha = check_protocol(protocol)
    if run_dir is not None:
        run = json.loads((Path(run_dir)/'run_manifest.json').read_text())
        if run.get('protocol_sha256') != proto_sha:
            raise ValueError('PROTOCOL_DIFFERS_FROM_REPLICATION')
    out = new_output(out)
    dump(out/'run_manifest.json', dict(status='running', mode='fed_minute_descriptive'))
    spec = dict(minimum_event_clusters=proto['inference']['minimum_event_clusters'], seed=proto['inference']['seed'])
    draws = 19 if smoke else proto['primary_family']['tests'][0]['draws']
    reps = 9 if smoke else proto['inference']['bootstrap_reps']
    five_bars, windows = load_files(fed_dir)
    bars, files = load_minute_dir(minute_dir)
    files.to_csv(out/'fed_minute_file_manifest.csv', index=False)
    cert, verdict = certify_against_five_minutes(bars, files, five_bars, windows)
    cert.to_csv(out/'fed_minute_bar_label_certification.csv', index=False)
    if verdict != 'interval_start':
        dump(out/'run_manifest.json', dict(status='stopped_minute_labels_not_certified', verdict=verdict))
        raise ValueError(f'FED_MINUTE_LABELS_NOT_CERTIFIED: {verdict}')
    reg, fomc = registry(calendar, windows)
    panel5 = build_panel(reg, five_bars, windows)
    slow = slow_state(panel5, day_rv(five_bars, windows, sorted(set(panel5.day))))
    origin = windows.start.min()
    ctrl = panel5[~panel5.is_event]
    scales = dict(zt=float(ctrl.zt_net.std()), es=float(ctrl.es_net.std()))
    pm = minute_panel(reg, bars, windows, stale)
    pm.to_csv(out/'fed_minute_measures_panel.csv', index=False)
    pm.groupby(['is_event', 'coverage_status']).size().rename('n').reset_index().to_csv(out/'fed_minute_coverage_summary.csv', index=False)
    window_descriptives(pm).to_csv(out/'fed_minute_window_descriptives.csv', index=False)
    merged = merged_panel(panel5, pm)
    tables = {m: outcome_table(merged, m, slow, origin, scales) for m in REGRESSION_MEASURES}
    tables['BV'].to_csv(out/'fed_minute_primary_event_panel.csv', index=False)
    rows, prof_rows, curves = [], [], []
    for measure, T in tables.items():
        for period in PERIODS:
            sub = T if period == 'all' else (T[T.trade_date.map(in_zlb)] if period == 'zero_lower_bound' else T[~T.trade_date.map(in_zlb)])
            rows.append(regression_row(measure, period, sub, spec, draws, out))
        if measure in PROFILE_MEASURES and len(T) >= spec['minimum_event_clusters']:
            pr, cv = exponent_profile(T, spec, reps, np.random.default_rng(spec['seed']+31))
            prof_rows += [dict(measure=measure, **x) for x in pr]; curves.append(cv.assign(measure=measure))
    pd.DataFrame(rows).to_csv(out/'fed_minute_robustness_measures.csv', index=False)
    pd.DataFrame(prof_rows).to_csv(out/'fed_minute_radial_exponent_profile.csv', index=False)
    pd.concat(curves, ignore_index=True).to_csv(out/'fed_minute_radial_exponent_curves.csv', index=False)
    excluded = excluded_events(merged, tables['BV'])
    excluded.to_csv(out/'fed_minute_excluded_events.csv', index=False)
    checks = reproduction_checks(merged, run_dir, rows)
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, capture_output=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=REPO, text=True, capture_output=True).stdout)
    result = dict(status='complete_fed_minute_descriptive' if not smoke else 'complete_smoke_not_for_inference',
                  mode='fed_minute_descriptive', created_utc=timestamp(), git_sha=sha, git_dirty=dirty,
                  protocol_sha256=proto_sha, calendar_sha256=digest(calendar),
                  minute_bar_label_verdict=verdict, n_minute_files=int(len(files)),
                  n_files_export_cap_reached=int(files.export_cap_reached.sum()), stale_minutes=stale,
                  n_events_in_registry=int(reg.is_event.sum()), n_events_estimated_BV=int(len(tables['BV'])),
                  n_events_estimated_VOL=int(len(tables['VOL'])), n_control_rows=int((~panel5.is_event).sum()),
                  excluded_events=excluded.to_dict('records'), scales=scales, reproduction=checks,
                  draws=draws, bootstrap_reps=reps,
                  note='descriptive tables computed after the pre-registered replication and outside the declared family; one-minute outcomes on the ten-year contract with the five-minute continuation regressor, slow state and coordinates of the replication',
                  completeness_note='an event or control enters a one-minute regression only if all 25 post-window minutes carry their own bar; the pre-window may be carried forward within the staleness cap',
                  continuation_note='variation measures use the five-minute pre-window bipower as continuation regressor; volume measures use the one-minute pre-window volume',
                  code_hashes=code_hashes(), python=platform.python_version(), numpy=np.__version__,
                  pandas=pd.__version__, scipy=scipy.__version__)
    dump(out/'run_manifest.json', result)
    print(json.dumps({k: v for k, v in result.items() if k not in ('code_hashes', 'excluded_events')}, indent=2, default=str), flush=True)
    return result


def main():
    p = argparse.ArgumentParser(prog='python -m confirmation_analysis.fed_minute')
    p.add_argument('--fed-dir', type=Path, required=True)
    p.add_argument('--minute-dir', type=Path, required=True)
    p.add_argument('--calendar', type=Path, required=True)
    p.add_argument('--protocol', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--run', type=Path)
    p.add_argument('--stale-minutes', type=int, default=5)
    p.add_argument('--smoke', action='store_true')
    a = p.parse_args()
    fed_minute_run(a.fed_dir, a.minute_dir, a.calendar, a.protocol, a.output, a.run, a.stale_minutes, a.smoke)


if __name__ == '__main__':
    main()
