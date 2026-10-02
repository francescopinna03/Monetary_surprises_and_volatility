import json
from pathlib import Path
import numpy as np
import pandas as pd
from scipy import stats
from final_analysis.models import clustered
from .cones import surface_design, surface_contrasts
from .inference import wild_contrast
from .nuisance import counterfactual_v2
from .protocol import digest, dump, timestamp, new_output, code_hashes


def wilson_lower(rate, n, level=.975):
    z = stats.norm.ppf(level)
    return (rate+z*z/(2*n)-z*np.sqrt(rate*(1-rate)/n+z*z/(4*n*n)))/(1+z*z/n)


def checked_build(build_dir, expected_status):
    build_dir = Path(build_dir)
    manifest = json.loads((build_dir/'status.json').read_text())
    if manifest.get('status') != expected_status:
        raise ValueError(f'Expected {expected_status}, found {manifest.get("status")}')
    for name, expected in manifest['table_hashes'].items():
        if Path(name).name != name or digest(build_dir/name) != expected:
            raise ValueError(f'Build table changed: {name}')
    if digest(build_dir/'specification.json') != manifest['specification_sha256']:
        raise ValueError('Build specification changed')
    return manifest


def event_state(controls, registry, year_col='trade_date'):
    c = controls[controls.phase.eq('PR') & controls.root_code.eq('gg') & controls.pre_coverage.eq(1)]
    c = c[np.isfinite(c.state_log_BV_pre)]
    e = registry[registry.phase.eq('PR') & registry.root_code.eq('gg')].copy()
    e['trade_date'] = pd.to_datetime(e.trade_date)
    years = c.trade_date.dt.year
    out = []
    for row in e.itertuples():
        s = c.loc[years.ne(row.trade_date.year), 'state_log_BV_pre']
        out.append((row.state_log_BV_pre-s.mean())/s.std() if s.std() > 0 and np.isfinite(row.state_log_BV_pre) else np.nan)
    e['state_z'] = out
    return e


def noise_sampler(controls_cf, rng, minimum=20):
    pool = controls_cf[np.isfinite(controls_cf.crossfit_abnormal_log_BV)]
    by_year = {y: g.crossfit_abnormal_log_BV.to_numpy() for y, g in pool.groupby(pool.trade_date.dt.year)}
    all_values = pool.crossfit_abnormal_log_BV.to_numpy()
    if len(all_values) < minimum:
        raise ValueError('Too few control residuals for calibration')
    def draw(years):
        return np.array([rng.choice(by_year[y]) if len(by_year.get(y, ())) >= minimum else rng.choice(all_values) for y in years])
    return draw, float(np.std(all_values)), len(all_values)


def primary_power(X, years, draw, spec, rng):
    cal = spec['calibration']
    contrasts = surface_contrasts()
    rows = []
    alpha_worst = spec['primary_family']['alpha']/spec['primary_family']['size']
    clusters = np.arange(len(X)).astype(str)
    for name, idx, beta_of in [('H1_MP_cone_mean', 0, lambda d: np.array([0, d, d, 0, 0, 0, 0, 0.])),
                               ('H2_MP_minus_CBI', 2, lambda d: np.array([0, 0, 0, -d*np.pi/4, 0, 0, 0, 0.]))]:
        for delta in cal['delta_grid']:
            beta = beta_of(delta)
            rejections = 0
            for r in range(cal['replications']):
                y = X @ beta + draw(years)
                result = wild_contrast(y, X, clusters, contrasts[idx], cal['draws'], rng,
                                       alternative='greater', min_clusters=spec['minimum_event_clusters'])
                rejections += result['p_wild'] <= alpha_worst
            rate = rejections/cal['replications']
            rows.append(dict(hypothesis=name, delta=delta, rejection_rate=rate,
                             power_lower_95=wilson_lower(rate, cal['replications']),
                             replications=cal['replications'], draws=cal['draws'],
                             rejection_threshold=alpha_worst, n_events=len(X),
                             metric='external_EA_coordinates_SD_units_log_BV'))
    return pd.DataFrame(rows)


def history_power(E, spec, rng, draw):
    cal = spec['calibration']
    eps = E.ois1y_z.to_numpy(); s = E.state_z.to_numpy(); years = E.trade_date.dt.year.to_numpy()
    base = np.column_stack([np.ones(len(E)), eps, np.abs(eps)])
    state = np.column_stack([s, eps*s, np.abs(eps)*s])
    H = E[['lag1', 'history3']].to_numpy(float)
    model = np.column_stack([base, state]); full = np.column_stack([model, H])
    g = np.arange(len(E)).astype(str)
    Hres = H-model @ np.linalg.lstsq(model, H, rcond=None)[0]
    Hres = Hres/np.sqrt(np.mean(Hres*Hres, axis=0))
    def wald(y):
        f = clustered(y, full, g, spec['minimum_event_clusters'])
        d = f['beta'][-2:]; v = f['V'][-2:, -2:]
        return float(d @ np.linalg.solve(v, d)/2)
    critical = float(np.quantile([wald(draw(years)) for _ in range(cal['replications'])], .95))
    rows = []
    for direction in range(Hres.shape[1]):
        for r2 in cal['power_partial_r2_grid']:
            rejections = 0
            for _ in range(cal['replications']):
                noise = draw(years); sigma = np.std(noise)
                y = noise + sigma*np.sqrt(r2/(1-r2))*Hres[:, direction]
                rejections += wald(y) > critical
            rate = rejections/cal['replications']
            rows.append(dict(direction=direction+1, partial_r2=r2, rejection_rate=rate,
                             power_lower_95=wilson_lower(rate, cal['replications']),
                             n_events=len(E), replications=cal['replications'], critical_value=critical))
    return pd.DataFrame(rows)


def floor_of(table, key, value_col, spec):
    floors = {}
    for name, S in table.groupby(key):
        ok = S[(S[value_col] > 0) & (S.power_lower_95 >= spec['calibration']['power_target'])]
        floors[str(name)] = float(ok[value_col].min()) if len(ok) else None
    return floors


def calibrate(build_dir, out, spec, bridge_dir=None):
    build_dir = Path(build_dir)
    manifest = checked_build(build_dir, 'control_build_not_frozen')
    out = new_output(out)
    dump(out/'status.json', dict(status='calibrating_outcome_free', confirmation_outcomes_computed=False))
    controls = pd.read_csv(build_dir/'control_windows.csv', parse_dates=['trade_date'])
    registry = pd.read_csv(build_dir/'event_pre_registry.csv')
    covariates = pd.read_csv(build_dir/'ea_covariates.csv', parse_dates=['event_date'])
    rng = np.random.default_rng(spec['seed']+1)
    W, diagnostics = counterfactual_v2(controls, spec)
    cf = W[W.phase.eq('PR') & W.root_code.eq('gg') & ~W.is_event]
    draw, sigma, n_pool = noise_sampler(cf, rng)
    E = event_state(controls, registry)
    E = E[E.certified_event_price_eligibility.eq(True)]
    E = E.merge(covariates[covariates.phase.eq('PR')].rename(columns={'event_date': 'trade_date'}),
                on='trade_date', how='inner', validate='one_to_one')
    E = E[np.isfinite(E[['state_z', 'ois1y_z', 'stoxx50e_z', 'lag1', 'history3']]).all(axis=1)].sort_values('trade_date')
    if len(E) < spec['minimum_event_clusters']:
        raise ValueError(f'Too few certified events for calibration: {len(E)}')
    X = surface_design(E.ois1y_z, E.stoxx50e_z, E.state_z)
    years = E.trade_date.dt.year.to_numpy()
    primary = primary_power(X, years, draw, spec, rng)
    history = history_power(E, spec, rng, draw)
    primary.to_csv(out/'primary_power.csv', index=False)
    history.to_csv(out/'history_power.csv', index=False)
    diagnostics.to_csv(out/'control_normal_diagnostics.csv', index=False)
    E[['trade_date', 'state_z', 'ois1y_z', 'stoxx50e_z']].to_csv(out/'calibration_design.csv', index=False)
    dump(out/'specification.json', spec)
    delta_80 = floor_of(primary, 'hypothesis', 'delta', spec)
    r2_80 = floor_of(history, 'direction', 'partial_r2', spec)
    reference = None
    if bridge_dir is not None:
        table = pd.read_csv(Path(bridge_dir)/'bridge_cone_tests.csv')
        reference = {f'{r.source}:{r.hypothesis}': float(r.estimate) for r in table.itertuples()}
    worst_r2 = max(v for v in r2_80.values() if v is not None) if all(v is not None for v in r2_80.values()) else None
    result = dict(status='calibration_complete_outcome_free', created_utc=timestamp(),
        confirmation_outcomes_computed=False, n_events_design=len(E), n_control_residuals=n_pool,
        control_residual_sd=sigma, primary_delta_80=delta_80, history_r2_80_by_direction=r2_80,
        history_calibrated_margin=worst_r2, history_reference_margin=spec['history_reference_margin'],
        generation_reference_estimates=reference,
        design_metric='u=OIS_1Y/10 and z=STOXX50E/100 scaled by confirmation GC_PR event SD; state leave-year-out on Bund PR controls',
        caveat='Detectable sizes refer to the external metric; the frozen primary uses the aligned Schatz coordinate.',
        build_manifest_sha256=digest(build_dir/'status.json'), code_hashes=code_hashes(),
        table_hashes={p.name: digest(p) for p in out.glob('*.csv')},
        specification_sha256=digest(out/'specification.json'))
    dump(out/'status.json', result)
    print(json.dumps({k: v for k, v in result.items() if k not in ['code_hashes', 'table_hashes']}, indent=2), flush=True)
    return result
