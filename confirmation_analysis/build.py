import json
from pathlib import Path
import numpy as np
import pandas as pd
from .decisions import load_decisions
from .protocol import digest, dump, timestamp, new_output, code_hashes
from .windows import build_windows, load_ea_v2, external_scales


def slow_state_validation(generation_build):
    b = Path(generation_build)
    w = pd.read_csv(b/'windows.csv', parse_dates=['trade_date'])
    pr = w[w.phase.eq('PR')]
    rows = []
    for root, g in pr.groupby('root_code'):
        g = g.sort_values('trade_date')
        controls = g[~g.is_event].copy()
        controls['rolling5'] = controls.log_day_rv.rolling(5, min_periods=5).mean()
        m = pd.merge_asof(g[['trade_date', 'slow5_log_rv', 'is_event']], controls[['trade_date', 'rolling5']],
                          on='trade_date', allow_exact_matches=False, direction='backward')
        ok = np.isfinite(m[['slow5_log_rv', 'rolling5']]).all(axis=1)
        for scope, mask in [('all_days', ok), ('event_days', ok & m.is_event), ('control_days', ok & ~m.is_event)]:
            s = m[mask]
            rows.append(dict(root_code=root, scope=scope, n=len(s),
                             correlation=float(s.slow5_log_rv.corr(s.rolling5)) if len(s) > 2 else np.nan,
                             mean_abs_difference=float((s.slow5_log_rv-s.rolling5).abs().mean()) if len(s) else np.nan))
    return pd.DataFrame(rows)


def control_build(quality_dir, data_root, out, spec, generation_build=None):
    decisions = load_decisions()
    out = new_output(out)
    dump(out/'status.json', dict(status='building_controls_only', confirmation_outcomes_computed=False))
    w, quality_manifest = build_windows(quality_dir, data_root, spec, decisions, blinded=True)
    ea = load_ea_v2(data_root, spec)
    scales = external_scales(ea, spec)
    events = w[w.is_event].copy()
    controls = w[~w.is_event].copy()
    registry = events[['trade_date', 'root_code', 'phase', 'calendar_status', 'pre_coverage',
                       'certified_event_price_eligibility', 'state_log_BV_pre', 'slow_state', 'us_0830_candidate']].copy()
    registry['event_post_blinded'] = True
    covariates = ea[['event_date', 'phase', 'OIS_1M', 'OIS_3M', 'OIS_6M', 'OIS_1Y', 'STOXX50E', 'lag1', 'history3']].copy()
    covariates['stoxx50e_z'] = (covariates.STOXX50E/100)/scales['stoxx50e_fraction']
    covariates['ois1y_z'] = (covariates.OIS_1Y/10)/scales['ois1y_10bp']
    tables = {'control_windows': controls, 'event_pre_registry': registry, 'ea_covariates': covariates}
    if generation_build is not None:
        tables['slow_state_validation_generation'] = slow_state_validation(generation_build)
    for name, t in tables.items():
        t.to_csv(out/f'{name}.csv', index=False)
    dump(out/'decisions.json', decisions)
    dump(out/'specification.json', spec)
    status = dict(status='control_build_not_frozen', created_utc=timestamp(),
        confirmation_outcomes_computed=False, event_post_windows_read=False,
        n_control_root_days=int(controls.groupby(['trade_date', 'root_code']).ngroups),
        n_event_dates=int(events.trade_date.nunique()),
        n_certified_pr_bund_events=int((events.phase.eq('PR') & events.root_code.eq('gg')
                                       & events.certified_event_price_eligibility).sum()),
        external_scales=scales, decisions={k: v['choice'] for k, v in decisions.items()},
        quality_manifest_sha256=digest(Path(quality_dir)/'status.json'),
        quality_source_hashes=quality_manifest['source_hashes'], code_hashes=code_hashes(),
        table_hashes={p.name: digest(p) for p in out.glob('*.csv')},
        specification_sha256=digest(out/'specification.json'), decisions_sha256=digest(out/'decisions.json'))
    dump(out/'status.json', status)
    print(json.dumps({k: v for k, v in status.items() if k not in ['code_hashes', 'quality_source_hashes', 'table_hashes']}, indent=2), flush=True)
    return status
