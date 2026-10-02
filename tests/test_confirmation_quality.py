import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import numpy as np
import pandas as pd
from confirmation_analysis.quality import (read_prices, window_check, select_candidate,
    primary_files, isolated_spikes, quality_audit)
from confirmation_analysis.audit import audit
from confirmation_analysis.protocol import digest
from confirmation_analysis.readiness import checked_manifest, report
from confirmation_analysis.quality_run import inventory_path


def frame(start='2004-04-01 11:40', count=30):
    times = pd.date_range(start, periods=count, freq='5min', tz='UTC')
    return pd.DataFrame(dict(end_utc=times, Latest=np.full(count, 100.),
        Volume=np.full(count, 10.), valid_core=True))


class QualityTests(unittest.TestCase):
    def test_support_and_internal_gap(self):
        anchor = pd.Timestamp('2004-04-01 11:45', tz='UTC')
        t = frame()
        r = window_check(t, anchor, [5, 10, 15, 20, 25])
        self.assertEqual(pd.Timestamp(r['support_start_utc']), anchor)
        self.assertEqual(r['n_required_prices'], 6)
        self.assertEqual(r['n_valid_pairs'], 5)
        g = window_check(t.drop(index=3), anchor, [5, 10, 15, 20, 25])
        self.assertTrue(g['inside_observed_session'])
        self.assertFalse(g['complete_price_grid'])
        self.assertEqual(g['n_valid_pairs'], 3)

    def test_no_later_price_can_change_window(self):
        anchor = pd.Timestamp('2004-04-01 11:45', tz='UTC')
        t = frame()
        first = window_check(t, anchor, [5, 10, 15, 20, 25])
        t.loc[t.end_utc.gt(anchor+pd.Timedelta(minutes=25)), 'Latest'] = 1e8
        second = window_check(t, anchor, [5, 10, 15, 20, 25])
        self.assertEqual(first, second)

    def test_pre_selection_and_spike_cutoff(self):
        t = frame(count=3)
        t.loc[1, 'Latest'] = 1000
        self.assertFalse(isolated_spikes(t, t.end_utc.iloc[1]).any())
        self.assertTrue(isolated_spikes(t, t.end_utc.iloc[2]).iloc[1])
        a = dict(input_path='a', file_name='a', post_volume=1e10,
                 pre=dict(complete_price_grid=True, coverage=1., endpoint_volume=10.))
        b = dict(input_path='b', file_name='b', post_volume=0.,
                 pre=dict(complete_price_grid=True, coverage=1., endpoint_volume=20.))
        self.assertIs(select_candidate([a, b]), b)
        a['post_volume'] = -1e15
        self.assertIs(select_candidate([a, b]), b)

    def test_empty_and_low_volume(self):
        t = frame(count=2)
        t['Volume'] = 0.
        r = window_check(t, t.end_utc.iloc[0], [5])
        self.assertTrue(r['complete_price_grid'])
        self.assertEqual(r['n_low_volume_prices'], 2)
        r = window_check(t.iloc[:0], t.end_utc.iloc[0], [5])
        self.assertFalse(r['complete_price_grid'])

    def test_ohlc_duplicates_and_dst(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'raw.csv'
            p.write_text('Time,Open,High,Low,Latest,Volume\n'
                '04/01/2004 05:40,100,101,99,100,0\n'
                '04/01/2004 05:45,100,90,99,100,10\n'
                '04/01/2004 05:50,100,101,99,100,10\n'
                '04/01/2004 05:50,100,101,99,100,20\n'
                'Downloaded from Barchart.com,,,,,\n')
            t, flags = read_prices(p)
            self.assertEqual(flags['n_rows'], 4)
            self.assertEqual(flags['n_duplicate_rows'], 2)
            self.assertEqual(flags['n_valid_core'], 1)
            self.assertEqual(t.label_utc.iloc[0], pd.Timestamp('2004-04-01 11:40', tz='UTC'))
            self.assertEqual(t.valid_core.tolist(), [True, False, False])

    def test_empty_and_nonfinite_csvs_are_recorded_without_ufunc_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            header = 'Time,Open,High,Low,Latest,Volume\n'
            empty = base/'empty.csv'
            empty.write_text(header)
            t, flags = read_prices(empty)
            self.assertEqual(len(t), 0)
            self.assertEqual(flags['n_rows'], 0)
            self.assertEqual(flags['n_valid_core'], 0)
            self.assertEqual(str(t.Open.dtype), 'float64')

            zero = base/'zero-byte.csv'
            zero.touch()
            t, flags = read_prices(zero)
            self.assertEqual(len(t), 0)
            self.assertEqual(flags['n_rows'], 0)

            malformed = base/'malformed.csv'
            malformed.write_text(header + '04/01/2004 05:40,Inf,101,99,100,10\n')
            t, flags = read_prices(malformed)
            self.assertEqual(len(t), 1)
            self.assertEqual(flags['n_nonfinite_core'], 1)
            self.assertFalse(bool(t.valid_core.iloc[0]))

    def test_timestamp_representation_is_nanosecond_utc(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'raw.csv'
            p.write_text('Time,Open,High,Low,Latest,Volume\n'
                '04/01/2004 05:40,100,101,99,100,10\n')
            t, _ = read_prices(p)
            self.assertEqual(t.label_utc.iloc[0].value,
                pd.Timestamp('2004-04-01 11:40', tz='UTC').value)

    def test_canonical_source_priority_not_file_size(self):
        t = pd.DataFrame([dict(root_code='gg', contract_year=2000, expiry_code='H',
            input_path='/x/Downloads/ggh00.csv', n_rows=100000),
            dict(root_code='gg', contract_year=2000, expiry_code='H',
            input_path='/x/Raw/Barchart_futures/ggh00.csv', n_rows=10)])
        self.assertEqual(primary_files(t).iloc[0].n_rows, 10)

    def create_audit(self, base):
        data = base/'data'; raw = data/'Raw/Barchart_futures'; raw.mkdir(parents=True)
        ea_path = data/'Raw/EA-EMPD/EA-EMPD.xlsx'; ea_path.parent.mkdir()
        p = raw/'ggh00_intraday-5min_historical-data-09-12-2026.csv'
        times = pd.date_range('2000-01-05 05:35', periods=40, freq='5min')
        t = pd.DataFrame(dict(Time=times.strftime('%m/%d/%Y %H:%M'), Open=100, High=101, Low=99, Latest=100, Volume=10))
        t.to_csv(p, index=False)
        ea = pd.DataFrame(dict(Date_time=['2000-01-05 13:45', '2000-01-05 14:30'],
            Event_type=['GC_PR', 'GC_PC'], OIS_1M=1., OIS_3M=1., OIS_6M=1., OIS_1Y=1., STOXX50E=1.))
        ea.to_excel(ea_path, sheet_name='EA-EMPD', index=False)
        output = base/'audit'
        audit(data, [raw], output)
        return data, raw, output

    def test_end_to_end_no_outcomes_no_fake_certification(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); data, raw, inventory = self.create_audit(base)
            quality = base/'quality'
            with patch('final_analysis.data.variation', side_effect=AssertionError('NO OUTCOMES')):
                result = quality_audit(inventory, data, quality)
            self.assertFalse(result['confirmation_outcomes_computed'])
            self.assertFalse(result['all_nonempty_files_label_verified'])
            w = pd.read_csv(quality/'window_quality.csv')
            self.assertFalse(w.confirmation_outcome_computed.any())
            self.assertFalse(w.actual_phase_eligible.eq(True).any())
            self.assertFalse(set(w) & {'BV', 'RV', 'BV_post', 'RV_post', 'net_post', 'Latest'})
            with patch('builtins.print'):
                with patch('confirmation_analysis.readiness.load_decisions',
                           side_effect=ValueError('DECISIONS_MISSING: isolated test')):
                    r = report(quality, base/'readiness')
            self.assertFalse(r['confirmation_estimation_enabled'])
            for gate in ['reviewed_decisions_file', 'protected_control_build', 'outcome_free_calibration']:
                self.assertIn(gate, r['blocking_items'])
            p = next(raw.glob('*.csv'))
            p.write_text(p.read_text()+'\n')
            with self.assertRaisesRegex(ValueError, 'input changed'):
                checked_manifest(quality, 'complete_quality_audit_not_frozen')

    def test_changed_raw_and_changed_table_block(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); data, raw, inventory = self.create_audit(base)
            path = inventory/'raw_inventory_v2.csv'
            path.write_text(path.read_text()+'\n')
            with self.assertRaisesRegex(ValueError, 'table hash mismatch'):
                quality_audit(inventory, data, base/'quality')

    def test_verified_absent_pc_never_eligible(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); data, raw, inventory = self.create_audit(base)
            cert = data/'Raw/Certification'; cert.mkdir()
            pd.DataFrame([
                dict(event_date='2000-01-05', phase='PR', actual_phase_present='true', event_datetime_utc='2000-01-05T12:45:00Z',
                    source_url='https://www.ecb.europa.eu/press/example', verification_status='verified', notes='synthetic test'),
                dict(event_date='2000-01-05', phase='PC', actual_phase_present='false', event_datetime_utc='',
                    source_url='https://www.ecb.europa.eu/press/example', verification_status='verified', notes='synthetic test')
            ]).to_csv(cert/'ecb_calendar_verified_v2.csv', index=False)
            pd.DataFrame([dict(root_code='gg', period_start=2000, verified=True, bar_label_semantics='interval_start',
                evidence_source='https://example.test/provider', reviewer='synthetic test',
                representative_sha256=digest(next(raw.glob('*.csv'))))]).to_csv(cert/'bar_label_evidence_v2.csv', index=False)
            result = quality_audit(inventory, data, base/'quality')
            self.assertTrue(result['all_nonempty_files_label_verified'])
            w = pd.read_csv(base/'quality/window_quality.csv')
            pc = w[w.phase.eq('PC') & w.root_code.eq('gg')]
            self.assertFalse(pc.actual_phase_eligible.any())
            pr = w[w.phase.eq('PR') & w.root_code.eq('gg')]
            self.assertTrue(pr.actual_phase_eligible.all())

    def test_explicit_inventory_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root/'audit').mkdir()
            (root/'audit/status.json').write_text('{}')
            self.assertEqual(inventory_path(root, root), (root/'audit').resolve())


if __name__ == '__main__':
    unittest.main()
