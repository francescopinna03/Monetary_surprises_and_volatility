import copy
import unittest
from unittest.mock import patch
import numpy as np
import pandas as pd
from confirmation_analysis import functional_form as ff


def sample():
    rng = np.random.default_rng(410)
    n = 80
    return pd.DataFrame(dict(trade_date=pd.to_datetime([f'{2000+i//20}-02-{1+i%20:02d}' for i in range(n)]),
        u=rng.normal(size=n), z=rng.normal(size=n), crossfit_state_z=rng.normal(size=n),
        crossfit_abnormal_log_BV=rng.normal(size=n)))


class FunctionalCorrectionsTests(unittest.TestCase):
    def test_axes_belong_to_neither_open_sector(self):
        mp, cbi, axis = ff.sector_masks([0, 1, -1, 0, 1, -1], [1, 0, 0, 0, -1, -1])
        np.testing.assert_array_equal(mp, [0, 0, 0, 0, 1, 0])
        np.testing.assert_array_equal(cbi, [0, 0, 0, 0, 0, 1])
        np.testing.assert_array_equal(axis, [1, 1, 1, 1, 0, 0])

    def test_axes_are_excluded_from_bin_regression_and_reported(self):
        t = sample()
        t.loc[:14, 'u'] = 0.
        seen = []
        def fake(y, X, g, c, *args, **kwargs):
            seen.extend(g)
            return dict(estimate=.1, p_wild=.04)
        with patch.object(ff, 'wild_contrast', side_effect=fake):
            rows = ff.sector_means_by_radius(t, {'minimum_event_clusters': 8}, 'u', 'z', 9, 0, min_per_cell=2)
        self.assertEqual(rows.n_axis.sum(), 15)
        self.assertEqual((rows.n_mp+rows.n_cbi+rows.n_axis).sum(), len(t))
        self.assertFalse(set(t.trade_date[:15].astype(str)) & set(seen))
        np.testing.assert_allclose(rows.p_holm_exploratory_bins, .12)

    def test_unestimable_bins_do_not_shrink_the_holm_family(self):
        t = sample(); t['u'] = 0.
        rows = ff.sector_means_by_radius(t, {'minimum_event_clusters': 8}, 'u', 'z', 9, 0)
        self.assertFalse(rows.supported.any())
        self.assertTrue(rows.p_wild_two_sided.isna().all())
        np.testing.assert_allclose(rows.p_holm_exploratory_bins, 1.)

    def test_equity_model_nests_all_original_scalar_columns(self):
        t = sample(); u, z, s = t.u.to_numpy(), t.z.to_numpy(), t.crossfit_state_z.to_numpy()
        X, names = ff.equity_design(u, z, s)
        expected = np.column_stack([np.ones(len(t)), u, abs(u), s, u*s, abs(u)*s])
        take = [names.index(k) for k in ['const', 'u', 'abs_u', 'state', 'u_x_state', 'abs_u_x_state']]
        np.testing.assert_array_equal(X[:, take], expected)
        self.assertIn('z_x_state', names)

    def test_radial_basis_changes_only_radial_degree_and_handles_origin(self):
        u, z = np.array([0., .2, -3.]), np.array([0., -.5, 2.])
        b = ff.quadratic_angles_radial1(u, z)
        self.assertTrue(np.isfinite(b).all())
        np.testing.assert_allclose(ff.quadratic_angles_radial1(3*u, 3*z), 3*b)
        phi = np.linspace(.1, 6.1, 21)
        np.testing.assert_allclose(ff.quadratic_angles_radial1(np.cos(phi), np.sin(phi)),
                                   ff.degree2_basis(np.cos(phi), np.sin(phi)), atol=1e-14)

    def test_natural_spline_has_linear_tails(self):
        knots = np.array([-1., -.3, .4, 1.])
        for x in [np.array([-8., -7., -6.]), np.array([6., 7., 8.])]:
            np.testing.assert_allclose(np.diff(ff._natural_basis(x, knots), n=2, axis=0), 0., atol=1e-12)

    def test_held_out_transform_does_not_change_training_metadata(self):
        t = sample(); tr = t.iloc[:60]
        X, pen, meta = ff.spline_transform_fit(tr.u, tr.z, tr.crossfit_state_z)
        old = copy.deepcopy(meta)
        test = ff.spline_transform_apply([100.], [-80.], [3.], meta)
        self.assertTrue(np.isfinite(test).all())
        for key in ['u', 'z']:
            np.testing.assert_array_equal(meta[key]['knots'], old[key]['knots'])
            self.assertEqual(meta[key]['centre'], old[key]['centre'])
        self.assertEqual(int((pen == 0).sum()), 6)
        self.assertEqual(X.shape[1], 32)

    def test_every_nested_transform_excludes_its_validation_years(self):
        t = sample(); seen = []
        original = ff.spline_transform_fit
        def wrapped(u, z, s, *a, **kw):
            dates = t.loc[t.u.isin(np.asarray(u)), 'trade_date']
            seen.append(set(dates.dt.year))
            return original(u, z, s, *a, **kw)
        with patch.object(ff, 'spline_transform_fit', side_effect=wrapped):
            result = ff.tensor_spline_reference(t, {'minimum_event_clusters': 10}, 'u', 'z', lambdas=(.1, 1.))
        self.assertEqual(len(result), 4)
        for outer, year in enumerate(sorted(t.trade_date.dt.year.unique())):
            batch = seen[outer*4:(outer+1)*4]
            self.assertEqual([len(v) for v in batch], [2, 2, 2, 3])
            self.assertTrue(all(year not in v for v in batch))

    def test_spline_prediction_and_selection_are_invariant_to_positive_units(self):
        t = sample(); spec = {'minimum_event_clusters': 10}
        first = ff.tensor_spline_reference(t, spec, 'u', 'z', lambdas=(.01, .1, 1.))
        changed = t.copy(); changed.u *= 1000.; changed.z *= .01
        second = ff.tensor_spline_reference(changed, spec, 'u', 'z', lambdas=(.01, .1, 1.))
        np.testing.assert_array_equal(first.lambda_inner, second.lambda_inner)
        np.testing.assert_allclose(first.mse, second.mse, rtol=1e-9, atol=1e-9)

    def test_existing_pair_remains_same_and_factorial_pair_is_reported(self):
        t = sample(); _, paired, summary = ff.basis_comparison(t, {'minimum_event_clusters': 10}, 'u', 'z')
        self.assertIn('quadratic_angles_radial1', paired)
        self.assertIn('absolute_angles_radial2', paired)
        self.assertEqual(summary['n_folds'], 4)
        for year in paired.year:
            tr = t.trade_date.dt.year.ne(year); te = ~tr
            X = ff.design_with_state(ff.degree2_basis, t.u, t.z, t.crossfit_state_z)
            b = np.linalg.lstsq(X[tr], t.crossfit_abnormal_log_BV[tr], rcond=None)[0]
            mse = np.mean((t.crossfit_abnormal_log_BV[te]-X[te]@b)**2)
            self.assertAlmostEqual(mse, paired.loc[paired.year.eq(year), 'degree2_quadratic'].iloc[0])


if __name__ == '__main__':
    unittest.main()
