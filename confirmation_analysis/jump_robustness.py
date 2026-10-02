import argparse
import json
import platform
import subprocess
from pathlib import Path
import numpy as np
import pandas as pd
import scipy
from final_analysis.data import exact_returns, MINUTE
from final_analysis.models import clustered
from .estimate import panel
from .exploratory import verify_opened_build
from .functional_form import mean_branch_with_equity, basis_comparison
from .nuisance import counterfactual_v2
from .protocol import REPO, digest, dump, timestamp, new_output, code_hashes
from .windows import read_bars, grid_volume

MEDRV_CONST = np.pi/(6-4*np.sqrt(3)+np.pi)
MINRV_CONST = np.pi/(np.pi-2)


def measures(r, pre_sigma2, threshold_c=3.):
    r = np.asarray(r, float)
    if len(r) < 5 or not np.isfinite(r).all():
        return {k: np.nan for k in ['BV5', 'BV25', 'RV', 'MedRV', 'MinRV', 'TBV']}
    a = np.abs(r); n = len(r)
    prod = a[1:]*a[:-1]
    med = np.array([np.median(a[j-1:j+2]) for j in range(1, n-1)])
    mn = np.minimum(a[1:], a[:-1])
    theta = threshold_c**2*pre_sigma2 if np.isfinite(pre_sigma2) and pre_sigma2 > 0 else np.inf
    keep = (r[1:]**2 <= theta) & (r[:-1]**2 <= theta)
    return dict(BV5=np.pi/2*prod.sum(), BV25=np.pi/2*prod[1:].sum(), RV=float(np.dot(r, r)),
                MedRV=MEDRV_CONST*n/(n-2)*float(np.sum(med**2)), MinRV=MINRV_CONST*n/(n-1)*float(np.sum(mn**2)),
                TBV=np.pi/2*float(np.sum(prod[keep])))


def post_returns_panel(w, quality_dir, spec, root):
    sem = pd.read_csv(Path(quality_dir)/'price_quality_files.csv').set_index('input_path').semantics.to_dict()
    rows = w[w.root_code.eq(root) & w.phase.eq('PR') & w.phase_anchor_utc.astype(str).ne('')
             & w.phase_anchor_utc.notna()].copy()
    post_offsets = np.array(spec['pr_return_endpoints_minutes'])
    pre_offsets = np.array(spec['pre_pr_return_endpoints_minutes'])
    cache, out = {}, []
    for row in rows.itertuples():
        path = row.input_path
        if path not in cache:
            cache[path] = read_bars(path, sem[path])
        times, prices, volume = cache[path]
        anchor = pd.Timestamp(row.phase_anchor_utc).value
        rpost = exact_returns(times, prices, anchor+post_offsets*MINUTE)
        rpre = exact_returns(times, prices, anchor+pre_offsets*MINUTE)
        pre_sigma2 = float(np.nanmean(rpre**2)) if np.isfinite(rpre).any() else np.nan
        m = measures(rpost, pre_sigma2)
        out.append(dict(trade_date=row.trade_date, root_code=root, is_event=bool(row.is_event),
                        r1=rpost[0] if len(rpost) else np.nan, abs_r1=abs(rpost[0]) if len(rpost) else np.nan,
                        net_post=float(np.nansum(rpost)) if np.isfinite(rpost).all() else np.nan,
                        pre_sigma2=pre_sigma2, VOL=grid_volume(times, volume, anchor+post_offsets*MINUTE), **m))
    return pd.DataFrame(out)


def outcome_for(w, extra, spec, root, measure):
    v = w.copy()
    key = ['trade_date', 'root_code']
    e = extra.set_index(key)
    idx = v.root_code.eq(root) & v.phase.eq('PR')
    ix = pd.MultiIndex.from_frame(v.loc[idx, key])
    val = e[measure].reindex(ix).to_numpy(float)
    v.loc[idx, 'BV_post'] = val
    v.loc[idx, 'log_BV_post'] = np.where(np.isfinite(val) & (val > 0), np.log(np.where(val > 0, val, 1.)), np.nan)
    if measure == 'VOL':
        pv = v.loc[idx, 'pre_volume'].to_numpy(float)
        v.loc[idx, 'log_BV_pre'] = np.where(np.isfinite(pv) & (pv > 0), np.log(np.where(pv > 0, pv, 1.)), np.nan)
    cf, _ = counterfactual_v2(v, spec)
    return cf


def mechanical_slope(T_events, measure_values, abs_r1):
    ok = np.isfinite(measure_values) & (measure_values > 0) & np.isfinite(abs_r1) & (abs_r1 > 0)
    if ok.sum() < 20:
        return dict(slope_log_measure_on_log_abs_r1=np.nan, corr_log_measure_log_abs_r1=np.nan, n=int(ok.sum()))
    x = np.log(abs_r1[ok]); y = np.log(measure_values[ok])
    X = np.column_stack([np.ones(ok.sum()), x])
    b = np.linalg.lstsq(X, y, rcond=None)[0]
    return dict(slope_log_measure_on_log_abs_r1=float(b[1]), corr_log_measure_log_abs_r1=float(np.corrcoef(x, y)[0, 1]),
                n=int(ok.sum()))


def jump_robustness(build, quality_dir, out, smoke=False):
    build = Path(build)
    manifest, spec, code_changed = verify_opened_build(build)
    out = new_output(out)
    dump(out/'run_manifest.json', dict(status='running', mode='post_opening_jump_robustness'))
    w = pd.read_csv(build/'windows.csv', parse_dates=['trade_date'])
    indicators = pd.read_csv(build/'indicators.csv', parse_dates=['trade_date'])
    root = spec['primary_root']; u, z = spec['primary_coordinates']['u'], spec['primary_coordinates']['z']
    draws = 19 if smoke else spec['secondary_family']['draws']
    extra = post_returns_panel(w, quality_dir, spec, root)
    extra.to_csv(out/'post_returns_panel.csv', index=False)
    frozen = w[w.root_code.eq(root) & w.phase.eq('PR')][['trade_date', 'root_code', 'BV_post']]
    chk = extra.merge(frozen, on=['trade_date', 'root_code'], how='inner')
    both = np.isfinite(chk.BV5) & np.isfinite(chk.BV_post)
    reproduction = dict(n_compared=int(both.sum()),
                        max_abs_diff_BV5_vs_frozen=float(np.max(np.abs(chk.BV5[both]-chk.BV_post[both]))) if both.any() else np.nan)
    rows = []
    for measure in ['BV5', 'BV25', 'RV', 'MedRV', 'MinRV', 'TBV', 'VOL']:
        cf = outcome_for(w, extra, spec, root, measure)
        T = panel(cf, indicators, spec, root, 'PR', u, z, 'crossfit_abnormal_log_BV')
        if len(T) < spec['minimum_event_clusters']:
            rows.append(dict(measure=measure, n_events=len(T), status='too_few_events')); continue
        mb = pd.DataFrame(mean_branch_with_equity(T, spec, u, z, draws, spec['seed']+8000))
        fits, paired, summary = basis_comparison(T, spec, u, z)
        ev = extra[extra.is_event].set_index('trade_date').reindex(T.trade_date)
        mech = mechanical_slope(T, ev[measure].to_numpy(float), ev.abs_r1.to_numpy(float))
        row = dict(measure=measure, n_events=len(T), status='observed_after_opening')
        for term in ['abs_u', 'abs_z', 'u', 'z']:
            r = mb[mb.term.eq(term)].iloc[0]
            row[f'{term}_estimate'] = r.estimate; row[f'{term}_p_wild'] = r.p_wild
        row.update(mse_degree2=summary['mean_mse_degree2'], mse_degree1=summary['mean_mse_degree1'],
                   folds_won_by_degree1=summary['folds_won_by_degree1'], n_folds=summary['n_folds'],
                   mp_minus_cbi_degree1_r1=float(fits.set_index('basis').loc['degree1_absolute', 'difference_r1']),
                   mp_minus_cbi_degree2_r1=float(fits.set_index('basis').loc['degree2_quadratic', 'difference_r1']),
                   **mech)
        rows.append(row)
        paired.assign(measure=measure).to_csv(out/f'paired_annual_errors_{measure}.csv', index=False)
    table = pd.DataFrame(rows)
    table.to_csv(out/'jump_robustness_measures.csv', index=False)
    ev = extra[extra.is_event]
    ind = indicators[indicators.phase.eq('PR')].set_index('trade_date')[[u]].reindex(ev.trade_date)
    ok = np.isfinite(ind[u].to_numpy(float)) & np.isfinite(ev.abs_r1.to_numpy(float))
    coord = dict(corr_abs_u_abs_r1=float(np.corrcoef(np.abs(ind[u].to_numpy(float)[ok]), ev.abs_r1.to_numpy(float)[ok])[0, 1])
                 if ok.sum() > 3 else np.nan, n=int(ok.sum()))
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, capture_output=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=REPO, text=True, capture_output=True).stdout)
    result = dict(status='complete_jump_robustness_after_opening' if not smoke else 'complete_smoke_not_for_inference',
                  mode='post_opening_jump_robustness', created_utc=timestamp(), git_sha=sha, git_dirty=dirty,
                  code_changed_since_freeze=code_changed,
                  prior_results_seen={'generation_2013_2025': True, 'confirmation_2000_2012': True},
                  confirmation_verdict_unchanged=True, frozen_build_sha256=digest(build/'status.json'),
                  reproduction_check=reproduction, coordinate_check=coord, threshold_c=3.,
                  volume_note='VOL uses log pre-window volume as the continuation regressor in place of log pre-window BV; the slow state is unchanged',
                  code_hashes=code_hashes(), draws=draws, python=platform.python_version(),
                  numpy=np.__version__, pandas=pd.__version__, scipy=scipy.__version__)
    dump(out/'run_manifest.json', result)
    print(json.dumps({k: v for k, v in result.items() if k != 'code_hashes'}, indent=2), flush=True)
    return result


def main():
    p = argparse.ArgumentParser(prog='python -m confirmation_analysis.jump_robustness')
    p.add_argument('--build', type=Path, required=True)
    p.add_argument('--quality-dir', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--smoke', action='store_true')
    a = p.parse_args()
    jump_robustness(a.build, a.quality_dir, a.output, a.smoke)


if __name__ == '__main__':
    main()
