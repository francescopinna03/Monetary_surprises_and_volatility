import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import numpy as np
import pandas as pd
from confirmation_analysis.jump_robustness import measures, jump_robustness
from confirmation_analysis.protocol import dump, digest
from confirmation_analysis.freeze import freeze
from confirmation_analysis.decisions import load_decisions
from tests import test_confirmation_v2 as chain_fixture


class MeasureTests(unittest.TestCase):
    def test_single_jump_in_first_return(self):
        rng = np.random.default_rng(0)
        base = rng.normal(scale=1e-4, size=5)
        m0 = measures(base, 1e-8)
        withjump = {}
        for J in [1e-3, 2e-3, 4e-3]:
            r = base.copy(); r[0] = J
            m = measures(r, 1e-8)
            withjump[J] = m
            self.assertAlmostEqual(m['BV25'], m0['BV25'], places=12)
            self.assertLess(m['TBV'], m['BV5'])
        for k in ['MedRV', 'MinRV', 'TBV']:
            self.assertAlmostEqual(withjump[1e-3][k], withjump[2e-3][k], places=12)
            self.assertAlmostEqual(withjump[2e-3][k], withjump[4e-3][k], places=12)
        zero = np.r_[0., base[1:]]
        z0 = measures(zero, 1e-8)
        j1, j2 = [measures(np.r_[J, base[1:]], 1e-8) for J in (1e-3, 2e-3)]
        self.assertAlmostEqual((j2['BV5']-z0['BV5'])/(j1['BV5']-z0['BV5']), 2., places=9)
        self.assertGreater((j2['RV']-z0['RV'])/(j1['RV']-z0['RV']), 3.9)

    def test_missing_return_gives_nan(self):
        m = measures([1e-4, np.nan, 1e-4, 1e-4, 1e-4], 1e-8)
        self.assertTrue(all(np.isnan(v) for v in m.values()))


class JumpRobustnessTests(unittest.TestCase):
    def test_runs_on_an_opened_build_and_reproduces_the_frozen_outcome(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            chain = chain_fixture.ChainTests()
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
            result = jump_robustness(base/'frozen', base/'quality', base/'jump', smoke=True)
            self.assertTrue(result['prior_results_seen']['confirmation_2000_2012'])
            self.assertLess(result['reproduction_check']['max_abs_diff_BV5_vs_frozen'], 1e-12)
            t = pd.read_csv(base/'jump/jump_robustness_measures.csv')
            self.assertEqual(set(t.measure), {'BV5', 'BV25', 'RV', 'MedRV', 'MinRV', 'TBV', 'VOL'})
            self.assertTrue((base/'jump/post_returns_panel.csv').exists())
