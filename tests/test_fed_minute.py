import tempfile
import unittest
from datetime import date
from pathlib import Path
import numpy as np
import pandas as pd
from confirmation_analysis.fed_minute import (load_minute_dir, certify_against_five_minutes, minute_panel, merged_panel,
                                              MINUTE_NAME, REGRESSION_MEASURES)
from confirmation_analysis.fed_replication import to_minutes as five_minute_labels


def bars_from(labels, prices, volumes=None):
    labels = np.asarray(labels, np.int64); prices = np.asarray(prices, float)
    vol = np.ones(len(labels)) if volumes is None else np.asarray(volumes, float)
    return dict(label=labels, latest=prices, volume=vol, cumvol=np.concatenate([[0.], np.cumsum(vol)]))


def minute_frame(start, n, seed=0):
    rng = np.random.default_rng(seed)
    labels = np.arange(start, start+n, dtype=np.int64)
    prices = 120+np.cumsum(rng.normal(0, .01, n))
    volumes = rng.integers(1, 50, n).astype(float)
    return labels, prices, volumes


def aggregate_five(labels, prices, volumes):
    base = labels-labels % 5
    keys = np.unique(base)
    vol = np.array([volumes[base == k].sum() for k in keys])
    last = np.array([prices[base == k][-1] for k in keys])
    return bars_from(keys, last, vol)


def write_slice(folder, contract, labels, prices, volumes):
    local = (pd.Timestamp('1970-01-01', tz='UTC')+pd.to_timedelta(labels, unit='min')).tz_convert('America/Chicago')
    t = pd.DataFrame(dict(Time=local.strftime('%Y-%m-%d %H:%M'), Open=prices, High=prices, Low=prices, Latest=prices,
                          Change=0., Volume=volumes))
    t['%Change'] = '0.00%'
    name = f'{contract}_1min_{local[0].date()}_{local[-1].date()}.csv'
    body = t[['Time', 'Open', 'High', 'Low', 'Latest', 'Change', '%Change', 'Volume']].iloc[::-1].to_csv(index=False)
    (folder/name).write_text(body+'"Downloaded from Barchart.com as of test"\n')
    return name


class FedMinuteLoadingTests(unittest.TestCase):
    def test_pattern_accepts_only_treasury_contracts(self):
        self.assertIsNotNone(MINUTE_NAME.match('znh09_1min_2008-12-01_2008-12-26.csv'))
        self.assertIsNone(MINUTE_NAME.match('ggh09_1min_2008-12-01_2008-12-26.csv'))
        self.assertIsNone(MINUTE_NAME.match('znh09_intraday-1min_historical-data-11-09-2026.csv'))

    def test_slices_merge_and_conflicts_raise(self):
        labels, prices, volumes = minute_frame(20_500_000, 600)
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            write_slice(folder, 'znh09', labels[:400], prices[:400], volumes[:400])
            write_slice(folder, 'znh09', labels[300:], prices[300:], volumes[300:])
            bars, manifest = load_minute_dir(folder)
            self.assertEqual(len(manifest), 2)
            self.assertEqual(len(bars['znh09']['label']), 600)
            self.assertTrue(np.allclose(bars['znh09']['volume'], volumes))
            write_slice(folder, 'znm09', labels[300:], prices[300:]+1., volumes[300:])
            write_slice(folder, 'znm09', labels[:400], prices[:400], volumes[:400])
            with self.assertRaises(ValueError):
                load_minute_dir(folder)


class FedMinuteCertificationTests(unittest.TestCase):
    def setUp(self):
        labels, prices, volumes = minute_frame(20_500_000, 1500, seed=1)
        self.bars = {'znh09': bars_from(labels, prices, volumes)}
        self.manifest = pd.DataFrame([dict(contract='znh09', first_label=labels[0], last_label=labels[-1])])
        self.windows = pd.DataFrame([dict(root='zn', contract='znh09', start=date(2008, 12, 1), end=date(2009, 2, 27),
                                          file='znh09_5min_2008-12-01_2009-02-27.csv', sha256='abc')])
        self.five = aggregate_five(labels, prices, volumes)

    def test_interval_start_is_certified(self):
        table, verdict = certify_against_five_minutes(self.bars, self.manifest, {'znh09': self.five}, self.windows, min_bars=50)
        self.assertEqual(verdict, 'interval_start')
        self.assertEqual(table.volume_match_interval_start.iloc[0], 1.)
        self.assertLess(table.volume_match_interval_end.iloc[0], .5)

    def test_shifted_labels_are_not_certified(self):
        shifted = dict(self.five); shifted['label'] = self.five['label']+1
        table, verdict = certify_against_five_minutes(self.bars, self.manifest, {'znh09': shifted}, self.windows, min_bars=50)
        self.assertNotEqual(verdict, 'interval_start')

    def test_missing_five_minute_file_blocks_certification(self):
        table, verdict = certify_against_five_minutes(self.bars, self.manifest, {}, self.windows, min_bars=50)
        self.assertEqual(verdict, 'not_certified')
        self.assertEqual(table.status.iloc[0], 'five_minute_file_missing')


class FedMinutePanelTests(unittest.TestCase):
    def setUp(self):
        self.anchor = 20_500_600
        labels, prices, volumes = minute_frame(self.anchor-120, 300, seed=2)
        self.labels, self.prices, self.volumes = labels, prices, volumes
        self.windows = pd.DataFrame([dict(root='zn', contract='znh09', start=date(2008, 12, 1), end=date(2009, 2, 27),
                                          file='f', sha256='s')])
        self.reg = pd.DataFrame([dict(day=date(2008, 12, 16), clock='14:15', anchor=self.anchor, is_event=True)])

    def test_complete_window_is_strict_and_reproduces_five_minute_bipower(self):
        pm = minute_panel(self.reg, {'znh09': bars_from(self.labels, self.prices, self.volumes)}, self.windows, 5)
        row = pm.iloc[0]
        self.assertTrue(row.post_complete and row.post_complete_strict)
        self.assertEqual(row.n_post_bars, 25)
        five = aggregate_five(self.labels, self.prices, self.volumes)
        idx = np.searchsorted(five['label'], self.anchor+np.arange(0, 26, 5)-5)
        r5 = np.diff(np.log(five['latest'][idx]))
        self.assertAlmostEqual(row.BV5_from_1min, np.pi/2*float(np.sum(np.abs(r5[1:])*np.abs(r5[:-1]))), places=12)
        self.assertAlmostEqual(row.VOL, float(self.volumes[120:145].sum()), places=9)
        self.assertAlmostEqual(row.VOL_minute1+row.VOL_minutes2_5+row.VOL_minutes6_25, row.VOL, places=9)

    def test_missing_minutes_fail_the_strict_rule_but_carry_forward(self):
        keep = ~np.isin(self.labels, [self.anchor+2, self.anchor+3])
        pm = minute_panel(self.reg, {'znh09': bars_from(self.labels[keep], self.prices[keep], self.volumes[keep])}, self.windows, 5)
        row = pm.iloc[0]
        self.assertTrue(row.post_complete)
        self.assertFalse(row.post_complete_strict)
        self.assertEqual(row.filled_post_endpoints, 2)
        self.assertEqual(row.n_post_bars, 23)

    def test_merged_panel_masks_incomplete_rows(self):
        pm = minute_panel(self.reg, {'znh09': bars_from(self.labels, self.prices, self.volumes)}, self.windows, 5)
        pm.loc[0, 'post_complete_strict'] = False
        panel5 = pd.DataFrame([dict(day=date(2008, 12, 16), clock='14:15', is_event=True, anchor=self.anchor, BV=1., BV25=1., RV=1.,
                                    MedRV=1., MinRV=1., VOL=1., VOL1=1., VOL25=1., RV25=1., pre_BV=1., pre_VOL=1., zt_net=0., es_net=0.)])
        m = merged_panel(panel5, pm)
        self.assertTrue(m[REGRESSION_MEASURES].isna().all().all())
        self.assertEqual(m.BV_5min.iloc[0], 1.)


if __name__ == '__main__':
    unittest.main()
