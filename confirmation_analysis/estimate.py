import json
import platform
import subprocess
from pathlib import Path
import numpy as np
import pandas as pd
import scipy
from final_analysis.models import holm, clustered, DesignGate
from .cones import surface_design, surface_contrasts, cone_functionals
from .inference import wild_contrast
from .nuisance import counterfactual_v2
from .protocol import REPO, digest, dump, timestamp, new_output, code_hashes

HYPOTHESES = [('H1_MP_cone_mean', 0), ('H2_MP_minus_CBI', 2)]


def verify_build(build, spec_seen=None):
    build = Path(build)
    manifest = json.loads((build/'status.json').read_text())
    if manifest.get('status') not in ('frozen_v2', 'frozen_after_opening'):
        raise ValueError('Estimation requires a frozen v2 build')
    for name, expected in manifest['table_hashes'].items():
        if Path(name).name != name or digest(build/name) != expected:
            raise ValueError(f'Frozen table modified: {name}')
    if digest(build/'specification.json') != manifest['specification_sha256']:
        raise ValueError('Frozen specification modified')
    if manifest['code_hashes'] != code_hashes():
        raise ValueError('Code or specification changed after the freeze; create a new build')
    return manifest, json.loads((build/'specification.json').read_text())


def panel(W, indicators, spec, root, phase, u, z, outcome, state='crossfit_state_z'):
    T = W[W.root_code.eq(root) & W.phase.eq(phase) & W.is_event & W.window_eligible].copy()
    T = T.merge(indicators, on=['trade_date', 'phase'], how='left', validate='one_to_one')
    T = T[np.isfinite(T[[outcome, state, u, z]]).all(axis=1)].sort_values('trade_date')
    return T


def cone_tests(T, spec, outcome, u, z, draws, seed, meta, state='crossfit_state_z', slope=False):
    X = surface_design(T[u], T[z], T[state])
    contrasts = surface_contrasts(slope=slope)
    rows = []
    for offset, (name, idx) in enumerate(HYPOTHESES):
        try:
            r = wild_contrast(T[outcome].to_numpy(float), X, T.trade_date.astype(str), contrasts[idx],
                              draws, np.random.default_rng(seed+offset), alternative='greater' if not slope else 'two-sided',
                              min_clusters=spec['minimum_event_clusters'])
            rows.append(dict(**meta, hypothesis=name+('_slope' if slope else ''), status='estimated', **r))
        except (DesignGate, ValueError) as exc:
            rows.append(dict(**meta, hypothesis=name+('_slope' if slope else ''), status=str(exc),
                             estimate=np.nan, p_wild=np.nan, n_rows=len(T), n_clusters=T.trade_date.nunique()))
    return rows, X


def surface_matrix(T, spec, outcome, u, z, state='crossfit_state_z'):
    X = surface_design(T[u], T[z], T[state])
    fit = clustered(T[outcome].to_numpy(float), X, T.trade_date.astype(str), spec['minimum_event_clusters'])
    b = fit['beta']
    level = np.array([[b[1], b[3]], [b[3], b[2]]])
    slope = np.array([[b[5], b[7]], [b[7], b[6]]])
    rows = []
    for name, A in [('level_state_zero', level), ('slope_per_state_sd', slope)]:
        f = cone_functionals(A)
        values = np.linalg.eigvalsh(A)
        rows.append(dict(component=name, a11=A[0, 0], a22=A[1, 1], a12=A[0, 1], **f,
                         eigenvalue_min=values[0], eigenvalue_max=values[1],
                         principal_direction_angle=float(np.arctan2(*np.linalg.eigh(A)[1][::-1, -1])),
                         n_rows=len(T), n_clusters=fit['G'],
                         note='raw-basis rotation-invariant summary; entries are not rotated MP/CBI energies'))
    return pd.DataFrame(rows)


def influence_order(T, u, z):
    energy = T[u].to_numpy()**2 + T[z].to_numpy()**2
    return T.trade_date.to_numpy()[np.argsort(-energy)]


def estimate(build, out, smoke=False):
    build = Path(build)
    manifest, spec = verify_build(build)
    out = new_output(out)
    dump(out/'run_manifest.json', dict(status='running', mode='smoke' if smoke else 'frozen_full_v2'))
    w = pd.read_csv(build/'windows.csv', parse_dates=['trade_date'])
    indicators = pd.read_csv(build/'indicators.csv', parse_dates=['trade_date'])
    if smoke:
        spec = dict(spec, primary_family=dict(spec['primary_family'], draws=19),
                    secondary_family=dict(spec['secondary_family'], draws=19),
                    sensitivity_family=dict(spec['sensitivity_family'], draws=19))
    W, diagnostics = counterfactual_v2(w, spec)
    W.to_csv(out/'counterfactual_windows.csv', index=False)
    diagnostics.to_csv(out/'normal_diagnostics.csv', index=False)
    outcome = 'crossfit_abnormal_log_' + spec['outcome_primary']
    u, z = spec['primary_coordinates']['u'], spec['primary_coordinates']['z']
    root, phase = spec['primary_root'], 'PR'
    T = panel(W, indicators, spec, root, phase, u, z, outcome)
    family = spec['primary_family']
    opened = bool(manifest.get('confirmation_outcomes_read_before_freeze'))
    meta = dict(family='primary_reestimated_after_opening' if opened else 'primary_confirmation',
                root_code=root, phase=phase, outcome=outcome,
                indicator=u, equity=z, sample='confirmation_2000_2012', trimming='none')
    rows, X = cone_tests(T, spec, outcome, u, z, family['draws'], spec['seed'], meta)
    primary = pd.DataFrame(rows)
    from .exploratory import holm_declared
    primary['p_holm'] = holm_declared(primary.p_wild.to_numpy(), family['size'])
    primary['alpha'] = family['alpha']
    primary['rejected_at_alpha'] = primary.p_holm.le(family['alpha'])
    primary.to_csv(out/'primary_tests.csv', index=False)
    surface_matrix(T, spec, outcome, u, z).to_csv(out/'primary_surface.csv', index=False)
    T[['trade_date', 'input_path', u, z, 'crossfit_state_z', outcome]].to_csv(out/'primary_sample_registry.csv', index=False)
    secondary = []
    sec = spec['secondary_family']
    for j, test in enumerate(sec['tests']):
        kind = test['kind']
        if kind == 'slope':
            rows_s, _ = cone_tests(T, spec, outcome, u, z, sec['draws'], spec['seed']+100+j,
                                   dict(meta, family='secondary_declared', test_id=test['id']), slope=True)
            secondary.extend(rows_s)
        elif kind == 'outcome_rv':
            alt = 'crossfit_abnormal_log_RV'
            Ta = panel(W, indicators, spec, root, phase, u, z, alt)
            rows_s, _ = cone_tests(Ta, spec, alt, u, z, sec['draws'], spec['seed']+100+j,
                                   dict(meta, family='secondary_declared', test_id=test['id'], outcome=alt))
            secondary.extend(rows_s)
        elif kind == 'era':
            for era, (lo, hi) in spec['eras'].items():
                Te = T[(T.trade_date >= lo) & (T.trade_date <= hi)]
                rows_s, _ = cone_tests(Te, spec, outcome, u, z, sec['draws'], spec['seed']+100+j,
                                       dict(meta, family='secondary_declared', test_id=f"{test['id']}_{era}", sample=era))
                secondary.extend(rows_s)
    secondary = pd.DataFrame(secondary)
    if len(secondary):
        from .exploratory import holm_declared
        secondary['p_holm'] = holm_declared(secondary.p_wild.to_numpy(), sec['size'])
        secondary['claim_scope'] = 'declared_secondary_not_a_primary_claim'
    secondary.to_csv(out/'secondary_tests.csv', index=False)
    sens, sf = [], spec['sensitivity_family']
    order = influence_order(T, u, z)
    for k in sf['leave_top_k']:
        Tk = T[~T.trade_date.isin(order[:k])] if k else T
        rows_k, _ = cone_tests(Tk, spec, outcome, u, z, sf['draws'], spec['seed']+200+k,
                               dict(meta, family='sensitivity_descriptive', trimming=f'leave_top_{k}'))
        sens.extend(rows_k)
    for name in sf['alternative_indicators']:
        Ta = panel(W, indicators, spec, root, phase, name['u'], name['z'], outcome)
        rows_a, _ = cone_tests(Ta, spec, outcome, name['u'], name['z'], sf['draws'], spec['seed']+300,
                               dict(meta, family='sensitivity_descriptive', indicator=name['u'], equity=name['z'],
                                    trimming='none'))
        sens.extend(rows_a)
    for other in sf['alternative_roots']:
        To = panel(W, indicators, spec, other, phase, u, z, outcome)
        rows_o, _ = cone_tests(To, spec, outcome, u, z, sf['draws'], spec['seed']+400,
                               dict(meta, family='sensitivity_descriptive', root_code=other, trimming='none'))
        sens.extend(rows_o)
    if sf.get('us_screen'):
        Ws, _ = counterfactual_v2(w, spec, screen='pr')
        Ts = panel(Ws, indicators, spec, root, phase, u, z, outcome)
        rows_u, _ = cone_tests(Ts, spec, outcome, u, z, sf['draws'], spec['seed']+500,
                               dict(meta, family='sensitivity_descriptive', sample='us_pr_screen', trimming='none'))
        sens.extend(rows_u)
    sens = pd.DataFrame(sens)
    if len(sens):
        sens['claim_scope'] = 'descriptive_no_simultaneous_claim'
    sens.to_csv(out/'sensitivity_tests.csv', index=False)
    flow = W[W.is_event].groupby(['phase', 'root_code']).agg(
        n_calendar_with_contract=('trade_date', 'nunique'), n_complete_windows=('window_eligible', 'sum'),
        n_candidate_overlaps=('us_0830_candidate', 'sum'), n_verified_overlaps=('verified_us_release', 'sum'))
    flow.to_csv(out/'event_flow.csv')
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, capture_output=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=REPO, text=True, capture_output=True).stdout)
    result = dict(status='complete_smoke_not_for_inference' if smoke else
                  ('complete_reestimation_after_opening' if opened else 'complete_conditional_inference_v2'),
        prior_results_seen={'generation_2013_2025': True, 'confirmation_2000_2012': opened},
        opened_from=manifest.get('opened_from'),
        mode='smoke' if smoke else 'frozen_full_v2', created_utc=timestamp(), git_sha=sha, git_dirty=dirty,
        build_manifest_sha256=digest(build/'status.json'), code_hashes=code_hashes(),
        primary_draws=family['draws'], seed=spec['seed'], n_primary_events=len(T),
        us_calendar_status=spec['us_calendar_status'],
        bootstrap_scope=spec['bootstrap_scope'], claim_gate='conditional_inference_only',
        python=platform.python_version(), numpy=np.__version__, pandas=pd.__version__, scipy=scipy.__version__)
    dump(out/'run_manifest.json', result)
    if not smoke:
        print(primary[['hypothesis', 'estimate', 'p_wild', 'p_holm', 'n_clusters']].to_string(index=False), flush=True)
    print(json.dumps({k: v for k, v in result.items() if k != 'code_hashes'}, indent=2), flush=True)
    return result
