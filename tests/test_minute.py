import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest.mock import patch
import numpy as np
import pandas as pd
from confirmation_analysis.minute import (prices_at, minute_measures, last_trading_day, next_contract, select_contract,
                                          load_minute_dir, minute_run, read_provider_csv)
from confirmation_analysis.protocol import dump, digest
from confirmation_analysis.freeze import freeze
from confirmation_analysis.decisions import load_decisions
from tests import test_confirmation_v2 as chain_fixture


def bars_from(labels, prices, volumes=None):
    labels = np.asarray(labels, np.int64); prices = np.asarray(prices, float)
    vol = np.ones(len(labels)) if volumes is None else np.asarray(volumes, float)
    return dict(label=labels, latest=prices, volume=vol, cumvol=np.concatenate([[0.], np.cumsum(vol)]))


def write_minute_slices(raw, minute_dir, seed=0):
    rng = np.random.default_rng(seed)
    minute_dir.mkdir(parents=True, exist_ok=True)
    for path in sorted(raw.glob('gg*_intraday-5min_*.csv')):
        contract = path.name[:5]
        f = read_provider_csv(path)
        rows = []
        prev = f.Latest.iloc[0]
        for L, P, V in zip(f.label, f.Latest, f.Volume):
            cuts = np.sort(rng.choice(np.arange(1, int(V)), 4, replace=False))
            parts = np.diff(np.concatenate([[0], cuts, [int(V)]]))
            path_prices = np.linspace(prev, P, 6)[1:]
            for k in range(5):
                rows.append((L+k, path_prices[k], parts[k]))
            prev = P
        t = pd.DataFrame(rows, columns=['label', 'Latest', 'Volume'])
        local = (pd.Timestamp('1970-01-01', tz='UTC')+pd.to_timedelta(t.label, unit='min')).dt.tz_convert('America/Chicago')
        t['Time'] = local.dt.strftime('%Y-%m-%d %H:%M')
        t['Open'] = t.Latest; t['High'] = t.Latest; t['Low'] = t.Latest; t['Change'] = 0.; t['%Change'] = '0.00%'
        days = sorted(local.dt.date.unique()); half = len(days)//2
        for part in [days[:half+1], days[half:]]:
            s = t[local.dt.date.isin(part)].sort_values('label', ascending=False)
            name = f'{contract}_1min_{part[0]}_{part[-1]}.csv'
            body = s[['Time', 'Open', 'High', 'Low', 'Latest', 'Change', '%Change', 'Volume']].to_csv(index=False)
            (minute_dir/name).write_text(body+'"Downloaded from Barchart.com as of test"\n')


class MinutePrimitiveTests(unittest.TestCase):
    def test_minutes_are_unit_free(self):
        from confirmation_analysis.minute import to_minutes, minute_string
        for unit in ['s', 'ms', 'us', 'ns']:
            ts = pd.Series(pd.to_datetime(['2012-12-06 12:45'], utc=True)).dt.as_unit(unit)
            self.assertEqual(minute_string(to_minutes(ts).iloc[0]), '2012-12-06 12:45:00+00:00')

    def test_carry_forward_and_staleness(self):
        b = bars_from([100, 101, 105], [1., 2., 3.])
        p, filled = prices_at(b, np.array([101, 102, 104, 106, 112]), stale=5)
        self.assertEqual(p[0], 1.); self.assertEqual(p[1], 2.); self.assertEqual(p[2], 2.)
        self.assertEqual(p[3], 3.); self.assertTrue(np.isnan(p[4]))
        self.assertEqual(filled, 1)

    def test_jump_in_the_first_minute(self):
        rng = np.random.default_rng(0)
        base = rng.normal(scale=1e-4, size=25); pre = rng.normal(scale=1e-4, size=55)
        m0 = minute_measures(base, pre)
        big = base.copy(); big[0] = 5e-3
        m1 = minute_measures(big, pre)
        self.assertAlmostEqual(m1['BV_excl1'], m0['BV_excl1'], places=14)
        self.assertAlmostEqual(m1['BV_excl5'], m0['BV_excl5'], places=14)
        self.assertGreater(m1['RV'], 100*m0['RV'])
        self.assertLess(m1['MedRV'], 2*m0['MedRV']+1e-12)
        self.assertLess(m1['TBV_prewindow'], m1['BV'])
        self.assertLess(m1['TBV_postwindow'], m1['BV'])
        self.assertAlmostEqual(m0['TBV_postwindow'], m0['BV'], delta=0.2*m0['BV'])
        self.assertGreater(m1['bns_z'], 2.326)
        self.assertLess(m0['bns_z'], 2.326)
        self.assertTrue(np.isnan(minute_measures(np.r_[base[:10], np.nan, base[11:]], pre)['BV']))

    def test_expiry_rule(self):
        self.assertEqual(last_trading_day('ggz12'), date(2012, 12, 6))
        self.assertEqual(last_trading_day('ggh00'), date(2000, 3, 8))
        self.assertEqual(last_trading_day('ggm00'), date(2000, 6, 8))
        self.assertEqual(next_contract('ggz12'), 'ggh13')
        self.assertEqual(next_contract('ggz99'), 'ggh00')
        self.assertEqual(select_contract('2012-12-06', 'ggz12'), ('ggh13', True))
        self.assertEqual(select_contract('2012-12-05', 'ggz12'), ('ggz12', False))

    def test_loader_deduplicates_identical_overlaps_and_refuses_conflicts(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            head = 'Time,Open,High,Low,Latest,Change,%Change,Volume\n'
            a = '"2010-02-01 06:02",1,1,1,1.02,0,0.00%,3\n"2010-02-01 06:01",1,1,1,1.01,0,0.00%,2\n'
            b = '"2010-02-01 06:03",1,1,1,1.03,0,0.00%,4\n"2010-02-01 06:02",1,1,1,1.02,0,0.00%,3\n'
            foot = '"Downloaded from Barchart.com as of test"\n'
            (d/'ggh10_1min_2010-02-01_2010-02-01.csv').write_text(head+a+foot)
            (d/'ggh10_1min_2010-02-01_2010-02-02.csv').write_text(head+b+foot)
            bars, files = load_minute_dir(d)
            self.assertEqual(len(bars['ggh10']['label']), 3)
            self.assertTrue(np.all(np.diff(bars['ggh10']['label']) > 0))
            self.assertEqual(files.rows.sum(), 4)
            (d/'ggh10_1min_2010-02-01_2010-02-02.csv').write_text(head+b.replace('1.02,0', '1.09,0')+foot)
            with self.assertRaisesRegex(ValueError, 'MINUTE_CONFLICT'):
                load_minute_dir(d)


class MinuteEndToEndTests(unittest.TestCase):
    def test_certifies_reproduces_and_runs_on_the_opened_build(self):
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
            raw = data/'Raw/Barchart_futures'
            write_minute_slices(raw, base/'minute')
            result = minute_run(base/'frozen', base/'minute', [raw], base/'out', smoke=True)
            out = base/'out'
            self.assertEqual(result['minute_bar_label_verdict'], 'interval_start')
            self.assertGreater(result['bv5_reproduction']['n_compared'], 20)
            self.assertLess(result['bv5_reproduction']['max_relative_difference'], 1e-9)
            self.assertTrue(result['prior_results_seen']['confirmation_2000_2012'])
            cert = pd.read_csv(out/'minute_bar_label_certification.csv')
            self.assertTrue(cert.status.eq('interval_start').all())
            self.assertTrue((cert.volume_match_interval_end < .5).all())
            table = pd.read_csv(out/'minute_robustness_measures.csv')
            self.assertEqual(set(table.measure), {'BV', 'BV_excl1', 'BV_excl2', 'BV_excl5', 'RV', 'MedRV', 'MinRV',
                                                  'TBV_prewindow', 'TBV_postwindow', 'VOL', 'BV5_from_1min'})
            self.assertTrue(table['sample'].eq('H_2000_2012').all())
            for name in ['minute_measures_panel', 'minute_coverage_summary', 'minute_jump_descriptives', 'minute_file_manifest']:
                self.assertTrue((out/f'{name}.csv').exists(), name)

    def test_refuses_uncertified_labels(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            raw = base/'raw'; raw.mkdir()
            times = pd.date_range('2010-02-01 01:00', periods=600, freq='5min')
            rng = np.random.default_rng(1)
            price = 120*np.exp(np.cumsum(rng.normal(0, 1e-4, len(times))))
            pd.DataFrame(dict(Time=times.strftime('%m/%d/%Y %H:%M'), Latest=price, Volume=100)).to_csv(
                raw/'ggh10_intraday-5min_historical-data-09-12-2026.csv', index=False)
            write_minute_slices(raw, base/'minute')
            for f in (base/'minute').glob('*.csv'):
                lines = f.read_text().splitlines(); head, body, foot = lines[0], lines[1:-1], lines[-1]
                shifted = []
                for line in body:
                    t = pd.Timestamp(line.split(',')[0].strip('"'))+pd.Timedelta(minutes=1)
                    shifted.append(f'{t.strftime("%Y-%m-%d %H:%M")},'+','.join(line.split(',')[1:]))
                f.write_text('\n'.join([head]+shifted+[foot])+'\n')
            from confirmation_analysis.minute import certify_against_five_minutes
            bars, files = load_minute_dir(base/'minute')
            table, verdict = certify_against_five_minutes(bars, files, [raw])
            self.assertEqual(table.status.iloc[0], 'interval_end')
            self.assertEqual(verdict, 'not_certified')
