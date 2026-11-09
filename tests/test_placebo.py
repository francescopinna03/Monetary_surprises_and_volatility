import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import numpy as np
import pandas as pd
from confirmation_analysis import placebo as pl
from confirmation_analysis.decisions import load_decisions
from confirmation_analysis.freeze import freeze
from confirmation_analysis.protocol import digest, dump
from tests import test_confirmation_v2 as chain_fixture
from tests.test_fed_replication import write_synthetic


def synthetic_frame(event_slope, control_slope, n_events=150, n_controls=1500, seed=0):
    rng = np.random.default_rng(seed)
    rows = []
    for k in range(n_events+n_controls):
        ev = k < n_events
        u = rng.normal(0, 3 if ev else 1); z = rng.normal(0, 3 if ev else 1); s = rng.normal()
        y = (event_slope if ev else control_slope)*(abs(u)+abs(z))+0.2*s+rng.normal(0, .5)
        rows.append(dict(trade_date=pd.Timestamp('2010-01-01')+pd.Timedelta(days=k), cluster=f'c{k}', is_event=ev,
                         u=u, z=z, s=s, y=y))
    return pd.DataFrame(rows)


class PlaceboUnitTests(unittest.TestCase):
    def test_detects_an_excess_slope_on_announcements(self):
        rows = pl.estimate(synthetic_frame(.5, .1), 'u_z', 'mean', 'all', 199, np.random.default_rng(1))
        r = {x['term']: x for x in rows}
        self.assertAlmostEqual(r['abs_u']['difference'], .4, delta=.1)
        self.assertAlmostEqual(r['abs_u']['control_estimate'], .1, delta=.05)
        self.assertLess(r['abs_u']['p_wild_difference'], .01)

    def test_equal_slopes_are_not_rejected(self):
        rows = pl.estimate(synthetic_frame(.3, .3, seed=2), 'u_z', 'mean', 'all', 199, np.random.default_rng(3))
        r = {x['term']: x for x in rows}
        self.assertGreater(r['abs_u']['p_wild_difference'], .05)

    def test_log_specification_reports_slope_and_level(self):
        rows = pl.estimate(synthetic_frame(.5, .1), 'u', 'log', 'common', 99, np.random.default_rng(4))
        self.assertEqual([x['term'] for x in rows], ['log_r', 'level'])
        self.assertTrue(all(x['n_events'] > 0 for x in rows))

    def test_bins_cover_every_event(self):
        f = synthetic_frame(.5, .1)
        b = pd.DataFrame(pl.amplitude_bins(f, 'u_z'))
        self.assertEqual(b.n_events.sum(), int(f.is_event.sum()))

    def test_event_reproduction_raises_on_a_mismatch(self):
        f = synthetic_frame(.5, .1)
        ref = f[f.is_event][['trade_date', 'u', 's', 'y']].copy()
        pl.check_events(f, ref, ['u', 's', 'y'], 'ok')
        ref.loc[ref.index[0], 'y'] += 1e-6
        with self.assertRaisesRegex(ValueError, 'PLACEBO_EVENTS_NOT_REPRODUCED'):
            pl.check_events(f, ref, ['u', 's', 'y'], 'bad')


class GenerationFrameTests(unittest.TestCase):
    def test_controls_and_events_share_one_scale(self):
        days = pd.bdate_range('2014-01-01', periods=300)
        ev = set(days[::30])
        rows = []
        for d in days:
            for root, net in [('hf', 1e-4*np.sin(d.day)), ('fx', 2e-3*np.cos(d.day)), ('gg', 0.)]:
                rows.append(dict(trade_date=d, phase='PR', root_code=root, net_post=net, is_event=d in ev))
        w = pd.DataFrame(rows)

        class Design:
            def __init__(self, g, b):
                self.windows = w; self.spec = {}
                self.schatz_sd = float(w[w.root_code.eq('hf') & ~w.is_event].net_post.std())

            def panel(self):
                e = w[w.root_code.eq('hf') & w.is_event]
                return pd.DataFrame(dict(trade_date=e.trade_date.to_numpy(), u=(-e.net_post/self.schatz_sd).to_numpy(),
                                         z=0., crossfit_state_z=1., crossfit_abnormal_log_BV=2.))

        def fake_counterfactual(v, spec):
            r = v.copy(); r['window_eligible'] = True; r['crossfit_state_z'] = 1.; r['crossfit_abnormal_log_BV'] = 2.
            return r, []

        with patch.object(pl, 'GenerationDesign', Design), patch.object(pl, 'counterfactual', fake_counterfactual):
            frames, checks, prov = pl.generation_frames('g', 'b')
        f = frames[('G_2013_2025', 'BV5_frozen')]
        self.assertEqual(int(f.is_event.sum()), len(ev))
        self.assertAlmostEqual(f[~f.is_event].u.std(), 1., places=10)
        self.assertAlmostEqual(f[~f.is_event].z.std(), 1., places=10)
        self.assertEqual(checks[0]['max_abs_difference'], 0.)


class PlaceboEndToEndTests(unittest.TestCase):
    def test_fomc_run_reproduces_the_events_and_writes_its_tables(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fed, cal = write_synthetic(base)
            result = pl.placebo(base/'out', fed_dir=fed, fed_calendar=cal, smoke=True)
            self.assertEqual(result['status'], 'complete_smoke_not_for_inference')
            t = pd.read_csv(base/'out/placebo_tests.csv')
            self.assertEqual(set(t['sample']), {'FED_2008_2026'})
            self.assertEqual(set(t.coordinates), {'u', 'u_z'})
            rep = pd.read_csv(base/'out/placebo_event_reproduction.csv')
            self.assertTrue((rep.max_abs_difference <= pl.TOLERANCE).all())
            row = t[t.coordinates.eq('u_z') & t.spec.eq('mean') & t.support.eq('all') & t.term.eq('abs_u') & t.measure.eq('BV')].iloc[0]
            self.assertGreater(row.difference, 0)

    def test_historical_run_on_the_frozen_build(self):
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
            pl.placebo(base/'out', build=base/'frozen', smoke=True)
            t = pd.read_csv(base/'out/placebo_tests.csv')
            self.assertEqual(set(t['sample']), {'H_2000_2012'})
            self.assertEqual(set(t.coordinates), {'u'})
            self.assertTrue((t.n_controls > t.n_events).all())
