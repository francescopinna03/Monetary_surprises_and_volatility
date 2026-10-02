import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import numpy as np
import pandas as pd
from confirmation_analysis.design_information import (quadratic_angles, absolute_angles, exponent_profile,
                                                      contrast_information, odd_block, design_information)
from confirmation_analysis.functional_form import degree2_basis, degree1_basis
from confirmation_analysis.minute import minute_run
from confirmation_analysis.protocol import dump, digest
from confirmation_analysis.freeze import freeze
from confirmation_analysis.decisions import load_decisions
from tests import test_confirmation_v2 as chain_fixture
from tests.test_minute import write_minute_slices

SPEC = dict(minimum_event_clusters=10)


def synthetic(n=260, seed=0, law='linear', correlated=False, odd=0.):
    rng = np.random.default_rng(seed)
    u = rng.normal(size=n); z = rng.normal(size=n)
    if correlated:
        big = np.hypot(u, z) > 1.2
        z = np.where(big, np.sign(u)*np.abs(z), -np.sign(u)*np.abs(z))
    r = np.hypot(u, z); s = rng.normal(size=n)
    y = {'linear': 0.6*r, 'quadratic': 0.3*r**2, 'log': 0.8*np.log(r)}[law]+odd*z+rng.normal(scale=0.4, size=n)
    return pd.DataFrame(dict(trade_date=pd.date_range('2000-01-06', periods=n, freq='7D'), u=u, z=z,
                             crossfit_state_z=s, crossfit_abnormal_log_BV=y))


class DesignPrimitiveTests(unittest.TestCase):
    def test_bases_nest_the_published_ones(self):
        rng = np.random.default_rng(1); u, z = rng.normal(size=50), rng.normal(size=50)
        self.assertTrue(np.allclose(quadratic_angles(2.)(u, z), degree2_basis(u, z)))
        self.assertTrue(np.allclose(absolute_angles(1.)(u, z), degree1_basis(u, z)))

    def test_exponent_is_recovered(self):
        rows, curve = exponent_profile(synthetic(law='linear'), SPEC, 19, np.random.default_rng(2))
        q = [r for r in rows if r['angular_basis'] == 'quadratic_angles'][0]
        self.assertLess(abs(q['exponent_hat']-1.), 0.3)
        self.assertGreater(q['lr_at_exponent_2'], 3.84)
        rows, _ = exponent_profile(synthetic(law='quadratic'), SPEC, 9, np.random.default_rng(3))
        self.assertLess(abs(rows[0]['exponent_hat']-2.), 0.3)
        rows, _ = exponent_profile(synthetic(law='log'), SPEC, 9, np.random.default_rng(4))
        self.assertLess(rows[0]['lr_log_radius_vs_best_power'], rows[0]['lr_at_exponent_2'])
        self.assertLess(rows[0]['cv_mse_log_radius'], rows[0]['cv_mse_exponent_2'])
        self.assertLess(abs(rows[0]['mean_elasticity_log_radius']-0.8), 0.25)

    def test_retention_detects_sector_magnitude_confounding(self):
        free = contrast_information(synthetic(), SPEC, 1., 99, np.random.default_rng(5))[0]
        tied = contrast_information(synthetic(correlated=True), SPEC, 1., 99, np.random.default_rng(6))[0]
        self.assertGreater(free['information_retention_vs_independent_signs'], 0.8)
        self.assertLess(tied['information_retention_vs_independent_signs'], free['information_retention_vs_independent_signs'])
        self.assertGreater(free['meetings_for_80pct_power_observed_design'], 0)

    def test_odd_block_flags_signed_response(self):
        even = odd_block(synthetic(), SPEC, 99, np.random.default_rng(7))
        signed = odd_block(synthetic(odd=0.5), SPEC, 99, np.random.default_rng(8))
        self.assertLess(signed['p_wild_joint_odd_block'], 0.05)
        self.assertGreater(signed['partial_r2_odd_block'], even['partial_r2_odd_block'])


class DesignEndToEndTests(unittest.TestCase):
    def test_runs_on_the_opened_build_after_the_minute_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            data, spec, decisions, build, calibration = chain_fixture.ChainTests().run_to_calibration(base)
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
            raw = data/'Raw/Barchart_futures'
            write_minute_slices(raw, base/'minute')
            minute_run(base/'frozen', base/'minute', [raw], base/'m', smoke=True)
            result = design_information(base/'frozen', base/'m', base/'d', smoke=True)
            self.assertTrue(result['prior_results_seen']['confirmation_2000_2012'])
            for name in ['radial_exponent_profile', 'radial_exponent_curves', 'sector_contrast_information',
                         'central_symmetry_odd_block']:
                t = pd.read_csv(base/f'd/{name}.csv')
                self.assertGreater(len(t), 0, name)
            prof = pd.read_csv(base/'d/radial_exponent_profile.csv')
            self.assertEqual(set(prof.measure), {'BV5_frozen', 'BV', 'BV_excl5', 'VOL'})
