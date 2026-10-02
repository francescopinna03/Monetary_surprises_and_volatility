import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import numpy as np
import pandas as pd
from confirmation_analysis.audit import audit
from confirmation_analysis.build import control_build
from confirmation_analysis.calibrate import calibrate, wilson_lower
from confirmation_analysis.decisions import DECISIONS, load_decisions, template, write_template
from confirmation_analysis.estimate import estimate, verify_build
from confirmation_analysis.freeze import freeze
from confirmation_analysis.protocol import digest, dump, specification
from confirmation_analysis.quality import quality_audit
from confirmation_analysis.windows import slow_state

EVENT_DATES = pd.date_range('2000-01-06', '2001-12-27', freq='W-THU')[::3]


def spec_for_tests():
    s = specification()
    s['samples'] = dict(s['samples'], confirmation=['2000-01-01', '2001-12-31'])
    s['minimum_controls'] = 20
    s['minimum_event_clusters'] = 10
    s['calibration'] = dict(s['calibration'], replications=6, draws=39,
                            delta_grid=[0.0, 0.5], power_partial_r2_grid=[0, 0.3])
    s['primary_family'] = dict(s['primary_family'], draws=199)
    s['secondary_family'] = dict(s['secondary_family'], draws=199)
    s['sensitivity_family'] = dict(s['sensitivity_family'], draws=99, leave_top_k=[0, 1],
                                   alternative_indicators=[], alternative_roots=[], us_screen=False)
    s['eras'] = {'early': ['2000-01-01', '2000-12-31'], 'late': ['2001-01-01', '2001-12-31']}
    return s


def write_contract(path, root, dates, seed):
    rng = np.random.default_rng(seed)
    frames = []
    for date in dates:
        start = pd.Timestamp(f'{date} 12:00', tz='Europe/Berlin').tz_convert('America/Chicago')
        times = pd.date_range(start, periods=48, freq='5min')
        steps = rng.normal(0, 2e-4, len(times))
        price = 100*np.exp(np.cumsum(steps))
        frames.append(pd.DataFrame(dict(Time=times.tz_localize(None).strftime('%m/%d/%Y %H:%M'),
            Open=price, High=price*1.001, Low=price*0.999, Latest=price, Volume=100)))
    pd.concat(frames).to_csv(path, index=False)


def make_source(base):
    data = base/'data'
    raw = data/'Raw/Barchart_futures'
    raw.mkdir(parents=True)
    cert = data/'Raw/Certification'
    cert.mkdir()
    days = pd.bdate_range('2000-01-03', '2001-12-31')
    days = days[days.weekday == 3]
    dates = [d.strftime('%Y-%m-%d') for d in days]
    seed = 0
    for rootcode in ['gg', 'hf', 'hr']:
        for year in (0, 1):
            for expiry in 'hmuz':
                seed += 1
                name = f'{rootcode}{expiry}0{year}_intraday-5min_historical-data-09-12-2026.csv'
                write_contract(raw/name, rootcode, dates, seed)
    events = [d.strftime('%Y-%m-%d') for d in EVENT_DATES]
    rng = np.random.default_rng(3)
    rows = []
    for date in events:
        for phase, wall in [('GC_PR', '13:45'), ('GC_PC', '14:30')]:
            rows.append(dict(Date_time=f'{date} {wall}', Event_type=phase,
                OIS_1M=rng.normal(0, 2), OIS_3M=rng.normal(0, 2), OIS_6M=rng.normal(0, 2),
                OIS_1Y=rng.normal(0, 2), STOXX50E=rng.normal(0, .5)))
    ea = data/'Raw/EA-EMPD'
    ea.mkdir()
    pd.DataFrame(rows).to_excel(ea/'EA-EMPD.xlsx', sheet_name='EA-EMPD', index=False)
    calendar = []
    for date in events:
        for phase, wall in [('PR', '12:45'), ('PC', '13:30')]:
            calendar.append(dict(event_date=date, phase=phase, actual_phase_present='true',
                event_datetime_utc=f'{date}T{wall}:00Z', source_url='https://www.ecb.europa.eu/press/test',
                verification_status='verified', notes='synthetic'))
    pd.DataFrame(calendar).to_csv(cert/'ecb_calendar_verified_v2.csv', index=False)
    return data, raw, cert


def label_evidence(cert, raw, primary):
    rows = []
    for row in primary.itertuples():
        lo = 2000+3*((int(row.contract_year)-2000)//3)
        rows.append(dict(root_code=row.root_code, period_start=lo, verified=True,
            bar_label_semantics='interval_start', evidence_source='https://example.test/provider',
            reviewer='synthetic test', representative_sha256=row.sha256))
    t = pd.DataFrame(rows).drop_duplicates(['root_code', 'period_start'])
    t.to_csv(cert/'bar_label_evidence_v2.csv', index=False)


def reviewed(path, equity='homogeneous_external_stoxx50e_2000_2012'):
    t = template()
    choices = {'pc_normal_pre_support': 'v1_grid_endpoints_minus25_to_minus5_support_minus30_to_minus5',
               'slow_state_rule': 'event_day_excluded_previous_five_control_days',
               'equity_source_rule': equity,
               'secondary_family_rule': 'spec_secondary_family_verbatim_single_joint_history_block',
               'us_calendar_status': 'candidate_screen_only'}
    for key, choice in choices.items():
        t[key].update(choice=choice, reviewer='synthetic test', decided_on='2026-09-12', rationale='test fixture')
    dump(path, t)


class DecisionTests(unittest.TestCase):
    def test_template_is_refused_until_reviewed(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'decisions.json'
            write_template(path)
            with self.assertRaisesRegex(ValueError, 'DECISION_INADMISSIBLE'):
                load_decisions(path)
            with self.assertRaises(FileExistsError):
                write_template(path)
            t = template()
            for key in t:
                t[key].update(choice=t[key]['admissible'][0], reviewer='', decided_on='2026-09-12', rationale='x')
            dump(path, t)
            with self.assertRaisesRegex(ValueError, 'DECISION_UNREVIEWED'):
                load_decisions(path)
            reviewed(path)
            self.assertEqual(load_decisions(path)['slow_state_rule']['reviewer'], 'synthetic test')

    def test_missing_file_blocks(self):
        with self.assertRaisesRegex(ValueError, 'DECISIONS_MISSING'):
            load_decisions(Path('/nonexistent/decisions.json'))


class SlowStateTests(unittest.TestCase):
    def test_event_days_never_enter_the_slow_state(self):
        dates = pd.bdate_range('2000-01-03', periods=12, freq='W-THU')
        w = pd.DataFrame(dict(trade_date=dates, root_code='gg', phase='PR',
            is_event=[False]*6+[True]+[False]*5, log_day_rv=np.arange(12, dtype=float)))
        w.loc[w.is_event, 'log_day_rv'] = 1e6
        out = slow_state(w, {'slow_state_rule': {'choice': 'event_day_excluded_previous_five_control_days'}})
        self.assertTrue(out.slow_state.dropna().lt(1e5).all())
        self.assertTrue(np.isfinite(out.slow_state.iloc[-1]))


class ChainTests(unittest.TestCase):
    def run_to_calibration(self, base, equity='homogeneous_external_stoxx50e_2000_2012'):
        data, raw, cert = make_source(base)
        spec = spec_for_tests()
        with patch('confirmation_analysis.audit.specification', return_value=spec), \
             patch('confirmation_analysis.quality.specification', return_value=spec):
            audit(data, [raw], base/'audit')
            primary = pd.read_csv(base/'audit/primary_files_v2.csv')
            label_evidence(cert, raw, primary)
            quality_audit(base/'audit', data, base/'quality')
        decisions = cert/'confirmation_decisions_v2.json'
        reviewed(decisions, equity)
        with patch('confirmation_analysis.decisions.DECISIONS', decisions), \
             patch('confirmation_analysis.build.load_decisions', lambda: load_decisions(decisions)), \
             patch('confirmation_analysis.windows.checked_manifest') as guard:
            from confirmation_analysis.readiness import checked_manifest as real
            guard.side_effect = real
            build = control_build(base/'quality', data, base/'build', spec)
            calibration = calibrate(base/'build', base/'calibration', spec)
        return data, spec, decisions, build, calibration

    def test_protected_build_reads_no_event_outcome(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            data, spec, decisions, build, calibration = self.run_to_calibration(base)
            self.assertFalse(build['confirmation_outcomes_computed'])
            self.assertFalse(build['event_post_windows_read'])
            registry = pd.read_csv(base/'build/event_pre_registry.csv')
            self.assertTrue(registry.event_post_blinded.all())
            forbidden = {'BV_post', 'RV_post', 'net_post', 'rv_minus_bv', 'log_BV_post', 'log_RV_post'}
            self.assertFalse(forbidden & set(registry))
            controls = pd.read_csv(base/'build/control_windows.csv')
            self.assertFalse(controls.is_event.any())
            self.assertFalse(calibration['confirmation_outcomes_computed'])
            self.assertGreater(calibration['n_control_residuals'], 0)
            power = pd.read_csv(base/'calibration/primary_power.csv')
            self.assertEqual(set(power.hypothesis), {'H1_MP_cone_mean', 'H2_MP_minus_CBI'})
            self.assertTrue(power.power_lower_95.between(0, 1).all())

    def test_freeze_and_estimate_with_full_provenance(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            data, spec, decisions, build, calibration = self.run_to_calibration(base)
            bridge = base/'bridge'
            bridge.mkdir()
            pd.DataFrame([dict(source='ea_empd_stoxx50e', hypothesis='H1_MP_cone_mean', estimate=.1, p_wild=.01)]
                         ).to_csv(bridge/'bridge_cone_tests.csv', index=False)
            dump(bridge/'bridge_decision.json', dict(scope='generation_2013_2025_only',
                status='bridge_complete_not_a_freeze', confirmation_outcomes_computed=False,
                checks=dict(correlation=True), correlation=.95,
                proposed_equity_rule='homogeneous_external_candidate_requires_review_not_validation_of_equivalence',
                table_hashes={'bridge_cone_tests.csv': digest(bridge/'bridge_cone_tests.csv')}))
            patches = [patch('confirmation_analysis.decisions.DECISIONS', decisions),
                       patch('confirmation_analysis.freeze.load_decisions', lambda: load_decisions(decisions))]
            for p in patches:
                p.start()
            try:
                stamp = freeze(base/'quality', data, base/'build', base/'calibration', bridge, base/'frozen', spec)
                self.assertEqual(stamp['status'], 'frozen_v2')
                self.assertFalse(stamp['confirmation_outcomes_read_before_freeze'])
                self.assertFalse(stamp['prior_results_seen']['confirmation_2000_2012'])
                with self.assertRaises(FileExistsError):
                    freeze(base/'quality', data, base/'build', base/'calibration', bridge, base/'frozen', spec)
                frozen = json.loads((base/'frozen/specification.json').read_text())
                self.assertEqual(frozen['status'], 'frozen_v2')
                self.assertTrue(frozen['primary_resolution']['pass_resolution'])
                result = estimate(base/'frozen', base/'estimated', smoke=False)
                self.assertEqual(result['status'], 'complete_conditional_inference_v2')
                primary = pd.read_csv(base/'estimated/primary_tests.csv')
                self.assertEqual(len(primary), 2)
                self.assertTrue(primary.p_wild.between(0, 1).all())
                self.assertTrue((primary.p_holm >= primary.p_wild).all())
                surface = pd.read_csv(base/'estimated/primary_surface.csv')
                level = surface[surface.component.eq('level_state_zero')].iloc[0]
                self.assertAlmostEqual(level.difference, -4/np.pi*level.a12, places=10)
                path = base/'frozen/windows.csv'
                path.write_text(path.read_text()+'\n')
                with self.assertRaisesRegex(ValueError, 'Frozen table modified'):
                    verify_build(base/'frozen')
            finally:
                for p in patches:
                    p.stop()

    def test_estimate_refuses_unfrozen_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            base.joinpath('build').mkdir()
            dump(base/'build/status.json', dict(status='control_build_not_frozen'))
            with self.assertRaisesRegex(ValueError, 'requires a frozen v2 build'):
                verify_build(base/'build')


class HelperTests(unittest.TestCase):
    def test_wilson_lower_is_conservative(self):
        self.assertLess(wilson_lower(.8, 100), .8)
        self.assertGreater(wilson_lower(.8, 10000), wilson_lower(.8, 100))
        self.assertAlmostEqual(wilson_lower(1., 1000), 1-3.84/(1000+3.84), places=2)


if __name__ == '__main__':
    unittest.main()


class ExploratoryTests(unittest.TestCase):
    def test_holm_declared_keeps_family_size(self):
        from confirmation_analysis.exploratory import holm_declared
        from final_analysis.models import holm
        p = np.array([0.01, np.nan, 0.04])
        self.assertLess(holm(p[[0, 2]])[0], holm_declared(p, 3)[0] + 1e-12)
        self.assertAlmostEqual(holm_declared(p, 3)[0], 0.03)
        self.assertTrue(np.isnan(holm_declared(p, 3)[1]) or holm_declared(p, 3)[1] == 1.0)
        with self.assertRaises(ValueError):
            holm_declared(p, 2)

    def test_ppml_recovers_a_log_linear_mean(self):
        from confirmation_analysis.exploratory import ppml
        rng = np.random.default_rng(0)
        X = np.column_stack([np.ones(2000), rng.normal(size=2000)])
        y = np.exp(0.5 + 0.8*X[:, 1]) * rng.gamma(4, 1/4, size=2000)
        beta, _ = ppml(y, X)
        self.assertAlmostEqual(beta[0], 0.5, delta=0.1)
        self.assertAlmostEqual(beta[1], 0.8, delta=0.1)

    def test_exploratory_runs_only_after_opening_and_labels_it(self):
        from confirmation_analysis.exploratory import exploratory
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            chain = ChainTests()
            data, spec, decisions, build, calibration = chain.run_to_calibration(base)
            bridge = base/'bridge'; bridge.mkdir()
            pd.DataFrame([dict(source='ea_empd_stoxx50e', hypothesis='H1_MP_cone_mean', estimate=.1, p_wild=.01)]
                         ).to_csv(bridge/'bridge_cone_tests.csv', index=False)
            dump(bridge/'bridge_decision.json', dict(scope='generation_2013_2025_only',
                status='bridge_complete_not_a_freeze', confirmation_outcomes_computed=False,
                checks=dict(correlation=True), correlation=.95,
                proposed_equity_rule='homogeneous_external_candidate_requires_review_not_validation_of_equivalence',
                table_hashes={'bridge_cone_tests.csv': digest(bridge/'bridge_cone_tests.csv')}))
            with patch('confirmation_analysis.decisions.DECISIONS', decisions), \
                 patch('confirmation_analysis.freeze.load_decisions', lambda: load_decisions(decisions)):
                freeze(base/'quality', data, base/'build', base/'calibration', bridge, base/'frozen', spec)
            result = exploratory(base/'frozen', base/'explored', base/'calibration', smoke=True)
            self.assertTrue(result['prior_results_seen']['confirmation_2000_2012'])
            for name in ['level1_mean_branch', 'level1_history_interval', 'bv_zero_by_year',
                         'common_sample_bv_rv', 'ppml_bv_levels', 'ridge_state_block_path', 'design_recalibration_power']:
                self.assertTrue((base/f'explored/{name}.csv').exists(), name)
            l1 = pd.read_csv(base/'explored/level1_mean_branch.csv')
            self.assertTrue(l1.status.eq('observed_after_opening').all())
            path = pd.read_csv(base/'explored/ridge_state_block_path.csv')
            self.assertEqual(int(path.chosen_1se_largest_lambda.sum()), 1)
            reg = pd.read_csv(base/'build/event_pre_registry.csv')
            self.assertFalse({'BV_pre', 'RV_pre'} & set(reg))
            scales = pd.read_csv(base/'frozen/indicator_scales.csv')
            self.assertIn('pr_control_sd', scales)
            self.assertTrue(scales.rule.str.contains('PR_control').all())


class SecondOpeningTests(unittest.TestCase):
    def test_a_build_after_opening_cannot_claim_confirmation(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            chain = ChainTests()
            data, spec, decisions, build, calibration = chain.run_to_calibration(base)
            bridge = base/'bridge'; bridge.mkdir()
            pd.DataFrame([dict(source='ea_empd_stoxx50e', hypothesis='H1_MP_cone_mean', estimate=.1, p_wild=.01)]
                         ).to_csv(bridge/'bridge_cone_tests.csv', index=False)
            dump(bridge/'bridge_decision.json', dict(scope='generation_2013_2025_only',
                status='bridge_complete_not_a_freeze', confirmation_outcomes_computed=False,
                checks=dict(correlation=True), correlation=.95,
                proposed_equity_rule='homogeneous_external_candidate_requires_review_not_validation_of_equivalence',
                table_hashes={'bridge_cone_tests.csv': digest(bridge/'bridge_cone_tests.csv')}))
            with patch('confirmation_analysis.decisions.DECISIONS', decisions), \
                 patch('confirmation_analysis.freeze.load_decisions', lambda: load_decisions(decisions)):
                first = freeze(base/'quality', data, base/'build', base/'calibration', bridge, base/'frozen_v2', spec)
                self.assertFalse(first['prior_results_seen']['confirmation_2000_2012'])
                second = freeze(base/'quality', data, base/'build', base/'calibration', bridge, base/'frozen_v3', spec,
                                already_opened=base/'frozen_v2')
            self.assertEqual(second['status'], 'frozen_after_opening')
            self.assertTrue(second['confirmation_outcomes_read_before_freeze'])
            self.assertTrue(second['prior_results_seen']['confirmation_2000_2012'])
            self.assertEqual(second['opened_from']['status_sha256'], digest(base/'frozen_v2/status.json'))
            result = estimate(base/'frozen_v3', base/'estimated_v3', smoke=True)
            self.assertEqual(result['status'], 'complete_smoke_not_for_inference')
            primary = pd.read_csv(base/'estimated_v3/primary_tests.csv')
            self.assertTrue(primary.family.eq('primary_reestimated_after_opening').all())
            with self.assertRaisesRegex(ValueError, 'already_opened'):
                freeze(base/'quality', data, base/'build', base/'calibration', bridge, base/'frozen_v4', spec,
                       already_opened=base/'build')


class ExploratoryCorrectionTests(unittest.TestCase):
    def test_frobenius_weights_count_the_off_diagonal_twice(self):
        import inspect
        from confirmation_analysis import exploratory
        src = inspect.getsource(exploratory.ridge_state_block)
        self.assertIn('pen[7] = 2.', src)

    def test_ppml_wild_is_centred_at_the_qmle(self):
        from confirmation_analysis.exploratory import ppml, ppml_wild
        rng = np.random.default_rng(1)
        X = np.column_stack([np.ones(600), rng.normal(size=600)])
        y = np.exp(0.3 + 0.5*X[:, 1]) * rng.gamma(3, 1/3, size=600)
        clusters = np.repeat(np.arange(60).astype(str), 10)
        beta, _ = ppml(y, X)
        boot = ppml_wild(y, X, np.zeros(600), clusters, 399, rng)
        self.assertEqual(boot.shape, (399, 2))
        self.assertLess(abs(boot[:, 1].mean()), 0.05)

    def test_convexity_bootstrap_reports_a_band(self):
        from confirmation_analysis.exploratory import convexity_bootstrap
        rng = np.random.default_rng(2)
        n = 120
        T = pd.DataFrame(dict(trade_date=pd.date_range('2000-01-01', periods=n, freq='7D'),
                              u=rng.normal(size=n), z=rng.normal(size=n), crossfit_state_z=rng.normal(size=n)))
        T['crossfit_abnormal_log_BV'] = 0.3*T.u**2 + 0.3*T.z**2 + rng.normal(scale=0.5, size=n)
        spec = dict(minimum_event_clusters=10)
        r = convexity_bootstrap(T, spec, 'u', 'z', 199, 0)
        self.assertGreater(r['lambda_min'], 0)
        self.assertLessEqual(r['lambda_min_boot_q05'], r['lambda_min_boot_q50'])
        self.assertTrue(0 <= r['share_boot_negative'] <= 1)

    def test_opened_build_records_code_drift_instead_of_refusing(self):
        from confirmation_analysis.exploratory import verify_opened_build
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            dump(base/'status.json', dict(status='frozen_v2', table_hashes={}, specification_sha256='x',
                                          code_hashes={'a': 'stale'}))
            dump(base/'specification.json', dict(primary_root='gg'))
            with self.assertRaisesRegex(ValueError, 'specification modified'):
                verify_opened_build(base)
            from confirmation_analysis.protocol import digest
            dump(base/'status.json', dict(status='frozen_v2', table_hashes={},
                                          specification_sha256=digest(base/'specification.json'),
                                          code_hashes={'a': 'stale'}))
            _, _, changed = verify_opened_build(base)
            self.assertTrue(changed)


class FunctionalFormTests(unittest.TestCase):
    def test_numeric_cone_means_match_the_closed_form_for_the_quadratic(self):
        from confirmation_analysis.functional_form import cone_means_numeric, degree2_basis
        from confirmation_analysis.cones import cone_functionals
        A = np.array([[0.039, 0.053], [0.053, 0.225]])
        closed = cone_functionals(A)
        numeric = cone_means_numeric(degree2_basis, np.array([A[0, 0], A[1, 1], A[0, 1]]))
        self.assertAlmostEqual(numeric['mp'], closed['mp'], places=4)
        self.assertAlmostEqual(numeric['cbi'], closed['cbi'], places=4)
        self.assertAlmostEqual(numeric['difference'], -4/np.pi*A[0, 1], places=4)

    def test_degree1_basis_is_homogeneous_of_degree_one(self):
        from confirmation_analysis.functional_form import cone_means_numeric, degree1_basis
        coef = np.array([0.4, 0.1, -0.2])
        c1 = cone_means_numeric(degree1_basis, coef, r=1.); c2 = cone_means_numeric(degree1_basis, coef, r=2.)
        self.assertAlmostEqual(c2['mp'], 2*c1['mp'], places=8)
        c3 = cone_means_numeric(degree1_basis, np.array([0, 0, -0.2]), r=1.)
        self.assertGreater(c3['difference'], 0)

    def test_functional_form_tables_on_synthetic_data(self):
        from confirmation_analysis.functional_form import functional_form
        rng = np.random.default_rng(5); n = 156
        T = pd.DataFrame(dict(trade_date=pd.date_range('2000-01-06', periods=n, freq='4W-THU'),
                              u=rng.normal(size=n), z=rng.normal(size=n), crossfit_state_z=rng.normal(size=n)))
        T['crossfit_abnormal_log_BV'] = 0.5*np.abs(T.u) + 0.2*np.abs(T.z) + rng.normal(scale=0.6, size=n)
        spec = dict(minimum_event_clusters=10)
        out = functional_form(T, spec, 'u', 'z', draws=99, seed=0)
        self.assertEqual(set(out), {'mean_branch_with_equity', 'basis_fits', 'basis_paired_annual_errors',
                                    'basis_summary', 'sector_means_by_radius'})
        summary = out['basis_summary'].iloc[0]
        self.assertLessEqual(summary.mean_mse_degree1, summary.mean_mse_degree2 + 0.05)
        self.assertTrue(np.isfinite(summary.mean_mse_tensor_spline))
        sm = out['sector_means_by_radius']
        self.assertEqual(len(sm), 3)
        self.assertTrue(set(['n_mp', 'n_cbi', 'supported']).issubset(sm))
