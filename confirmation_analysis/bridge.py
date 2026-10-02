import json
from pathlib import Path
import numpy as np
import pandas as pd
from final_analysis.models import counterfactual, holm
from .cones import surface_design, surface_contrasts
from .inference import wild_contrast
from .protocol import (REPO, specification, new_output, dump, digest, code_hashes,
                       timestamp, generation_mask, assert_generation_events)


def jk_interval(m):
    m = np.asarray(m, float)
    if len(m) < 8 or not np.isfinite(m).all() or np.linalg.matrix_rank(m) != 2:
        raise ValueError('Invalid JK diagnostic sample')
    _, r = np.linalg.qr(m, mode='reduced')
    sign = np.sign(np.diag(r)); sign[sign == 0] = 1
    r = sign[:, None] * r
    lo = float(np.arctan(r[0, 1]/r[1, 1])) if r[0, 1] > 0 else 0.
    hi = np.pi/2 if r[0, 1] >= 0 else float(np.arctan(-r[1, 1]/r[0, 1]))
    return dict(lower=lo, median=(lo+hi)/2, upper=float(hi))


def read_generation_build(build):
    build = Path(build)
    manifest = json.loads((build/'status.json').read_text())
    if manifest['status'] != 'frozen':
        raise ValueError('Bridge needs a completed generation build')
    for name in ['windows.csv', 'ea_source.csv', 'specification.json']:
        expected = manifest['specification_sha256'] if name == 'specification.json' else manifest['table_hashes'][name]
        if digest(build/name) != expected:
            raise ValueError(f'Generation build hash mismatch: {name}')
    for name, expected in manifest['code_hashes'].items():
        if digest(REPO/name) != expected:
            raise ValueError(f'Generation code changed: {name}')
    meta = pd.read_csv(build/'windows.csv', usecols=['trade_date', 'is_event'], parse_dates=['trade_date'])
    if not meta.is_event.isin([True, False]).all():
        raise ValueError('Invalid event flags')
    if (meta.is_event & meta.trade_date.lt('2013-01-01')).any():
        raise ValueError('BRIDGE_CONFIRMATION_LEAKAGE: build contains pre-2013 event outcomes')
    w = pd.read_csv(build/'windows.csv', parse_dates=['trade_date'])
    w = w[generation_mask(w.trade_date)].copy()
    assert_generation_events(w.loc[w.is_event, 'trade_date'])
    ea = pd.read_csv(build/'ea_source.csv', parse_dates=['event_date'])
    ea = ea[generation_mask(ea.event_date) & ea.phase.eq('PR')].copy()
    spec = json.loads((build/'specification.json').read_text())
    return w, ea, spec, manifest


def bridge(build, out, draws=None):
    v2 = specification()
    draws = v2['bridge_draws'] if draws is None else int(draws)
    w, ea, v1, original = read_generation_build(build)
    out = new_output(out)
    dump(out/'bridge_decision.json', {'status': 'running_generation_only', 'confirmation_outcomes_read': False})
    pr = w[w.phase.eq('PR')]
    nets = pr.pivot(index='trade_date', columns='root_code', values='net_post')
    event = pr.groupby('trade_date').is_event.first()
    sd = nets.loc[~event, ['hf', 'fx']].std()
    if not np.isfinite(sd).all() or not sd.gt(0).all():
        raise ValueError('Invalid generation PR control scales')
    ea_sd = float((ea.STOXX50E/100).std())
    if not np.isfinite(ea_sd) or ea_sd <= 0:
        raise ValueError('Invalid generation external equity scale')
    coordinates = nets.loc[event, ['hf', 'fx']].reset_index().merge(
        ea[['event_date', 'STOXX50E']], left_on='trade_date', right_on='event_date', validate='one_to_one')
    coordinates['u'] = -coordinates.hf/sd.hf
    coordinates['z_fx'] = coordinates.fx/sd.fx
    coordinates['z_ea'] = (coordinates.STOXX50E/100)/ea_sd
    c = coordinates[np.isfinite(coordinates[['u', 'z_fx', 'z_ea']]).all(axis=1)].copy()
    assert_generation_events(c.trade_date)
    correlation = float(c.z_fx.corr(c.z_ea))
    angle_fx = jk_interval(c[['u', 'z_fx']])
    angle_ea = jk_interval(c[['u', 'z_ea']])
    normal, diagnostics = counterfactual(w, v1)
    bund = normal[normal.is_event & normal.phase.eq('PR') & normal.root_code.eq('gg')]
    fields = ['trade_date', 'crossfit_abnormal_log_BV', 'crossfit_state_z', 'window_eligible']
    panel = c.merge(bund[fields], on='trade_date', validate='one_to_one')
    panel['included'] = panel.window_eligible & np.isfinite(panel[['crossfit_abnormal_log_BV', 'crossfit_state_z']]).all(axis=1)
    panel[['trade_date', 'included']].to_csv(out/'bridge_sample_registry.csv', index=False)
    t = panel[panel.included].copy()
    assert_generation_events(t.trade_date)
    results = []
    contrasts = surface_contrasts()
    for source, column in [('fx_futures', 'z_fx'), ('ea_empd_stoxx50e', 'z_ea')]:
        x = surface_design(t.u, t[column], t.crossfit_state_z)
        for idx, hypothesis in [(0, 'H1_MP_cone_mean'), (2, 'H2_MP_minus_CBI')]:
            r = wild_contrast(t.crossfit_abnormal_log_BV.to_numpy(), x,
                t.trade_date.astype(str), contrasts[idx], draws,
                np.random.default_rng(v2['seed']+idx), min_clusters=v2['minimum_event_clusters'])
            results.append(dict(source=source, hypothesis=hypothesis, **r,
                                scope='generation_only_not_confirmation'))
    table = pd.DataFrame(results)
    table['p_holm_descriptive'] = table.groupby('source').p_wild.transform(lambda p: holm(p.to_numpy()))
    table.to_csv(out/'bridge_cone_tests.csv', index=False)
    estimates = table.pivot(index='hypothesis', columns='source', values='estimate')
    pvalues = table.pivot(index='hypothesis', columns='source', values='p_wild')
    ratios = pvalues.ea_empd_stoxx50e / pvalues.fx_futures
    same_sign = bool((np.sign(estimates.fx_futures) == np.sign(estimates.ea_empd_stoxx50e)).all()
                     and estimates.ne(0).all().all())
    limits = v2['bridge_thresholds']
    checks = dict(correlation=bool(correlation >= limits['correlation']),
        jk_median_in_generation_fx_interval=bool(angle_fx['lower'] <= angle_ea['median'] <= angle_fx['upper']),
        cone_sign_and_p_ratio=bool(same_sign and ratios.between(1/limits['p_ratio'], limits['p_ratio']).all()),
        event_control_scale_ratio=bool(limits['sd_ratio_lower'] <= ea_sd/sd.fx <= limits['sd_ratio_upper']))
    if all(checks.values()):
        proposed = 'hybrid_candidate_requires_metric_and_timing_review'
    elif not checks['correlation'] or not checks['cone_sign_and_p_ratio']:
        proposed = 'homogeneous_external_candidate_requires_review_not_validation_of_equivalence'
    else:
        proposed = 'blocked_no_fallback_defined_for_checks_2_or_4'
    c.to_csv(out/'generation_bridge_coordinates.csv', index=False)
    diagnostics.to_csv(out/'generation_normal_diagnostics.csv', index=False)
    decision = dict(status='bridge_complete_not_a_freeze', scope='generation_2013_2025_only',
        created_utc=timestamp(), draws=draws, confirmation_outcomes_read=False,
        confirmation_outcomes_computed=False, n_coordinate_meetings=len(c), n_model_meetings=len(t),
        correlation=correlation, jk_fx=angle_fx, jk_external=angle_ea,
        external_event_sd_over_fx_control_sd=float(ea_sd/sd.fx),
        scales={'hf_pr_control_sd': float(sd.hf), 'fx_pr_control_sd': float(sd.fx),
                'external_pr_generation_event_sd_fractional_return': ea_sd},
        checks=checks, all_four_checks_pass=all(checks.values()),
        proposed_equity_rule=proposed, selection_finalized=False,
        positive_H1_H2_point_estimates_with_fx=bool(estimates.fx_futures.gt(0).all()),
        p_ratios_external_over_fx={str(k): float(v) for k, v in ratios.items()},
        generation_build_manifest_sha256=digest(Path(build)/'status.json'), code_hashes=code_hashes(),
        table_hashes={p.name: digest(p) for p in out.glob('*.csv')},
        generation_build_path=str(Path(build).resolve()),
        caveat='Cone functionals are new estimands; old rotated MP-energy p-values do not calibrate their power.')
    dump(out/'bridge_decision.json', decision)
    print(table[['source', 'hypothesis', 'estimate', 'p_wild']].to_string(index=False), flush=True)
    print('Bridge completed on generation data only. No confirmation freeze or estimate.', flush=True)
    return decision
