import unittest
import numpy as np
import pandas as pd
from confirmation_analysis.measurement_check import noise_floor, tail_test, simulate, iv_elasticity, verdict, profile


def panel(n=300, law=lambda r: 0.6*r, noise=0., seed=0):
    rng = np.random.default_rng(seed)
    su, sz = rng.normal(0, 2, n), rng.normal(0, 2, n)
    s = rng.normal(size=n)
    y = law(np.hypot(su, sz))+0.2*s+rng.normal(0, 0.3, n)
    u, z = su+noise*rng.normal(size=n), sz+noise*rng.normal(size=n)
    return pd.DataFrame(dict(u=u, z=z, crossfit_state_z=s, crossfit_abnormal_log_BV=y)), su


class MeasurementTests(unittest.TestCase):
    def test_noise_floor_is_the_rayleigh_median(self):
        self.assertAlmostEqual(noise_floor(np.eye(2), np.random.default_rng(1)), np.sqrt(2*np.log(2)), delta=0.01)
        self.assertAlmostEqual(noise_floor(np.diag([1., 0.]), np.random.default_rng(2)), 0.6745, delta=0.01)

    def test_simulation_without_noise_recovers_a_linear_law(self):
        T, _ = panel()
        grid, summary = simulate(T, np.eye(2), 9, np.random.default_rng(3))
        self.assertAlmostEqual(grid.set_index('noise_multiple').loc[0., 'median_exponent'], 1., delta=0.2)
        self.assertIn('noise_multiple_needed', summary)

    def test_tail_detects_concavity_and_stays_undecided_when_small(self):
        T, _ = panel(law=lambda r: np.log(r))
        t = tail_test(T, 1.)
        self.assertEqual(t['tail_status'], 'decided'); self.assertLess(t['exponent_tail'], 1.)
        self.assertEqual(tail_test(T.iloc[:20], 1.)['tail_status'], 'undecided_too_few_tail_events')

    def test_instrument_removes_attenuation(self):
        rng = np.random.default_rng(4)
        T, su = panel(law=lambda r: 0.8*np.log(r), noise=1.5, seed=4)
        alt = su+1.5*rng.normal(size=len(su))
        r = iv_elasticity(T, alt)
        self.assertLess(r['elasticity_ols'], r['elasticity_iv'])
        self.assertLess(abs(r['elasticity_iv']-0.8), 0.25)

    def test_verdict_mapping(self):
        self.assertEqual(verdict(True, True), 'excluded'); self.assertEqual(verdict(False, True), 'implausible')
        self.assertEqual(verdict(True, False), 'tail_only'); self.assertEqual(verdict(np.nan, False), 'not_excluded')
