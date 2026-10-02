import json
import tempfile
import unittest
from datetime import date
from pathlib import Path
import numpy as np
import pandas as pd
from confirmation_analysis.fed_replication import (PROTOCOL_TEMPLATE, prices_at, measures, control_clocks, check_protocol,
                                                   replication, blinded_coverage, load_files, contract_for, post_replication)

MONTHS = {'h': 3, 'm': 6, 'u': 9, 'z': 12}


def quarter_windows(years):
    out = []
    for y in years:
        for m, mo in MONTHS.items():
            start = date(y, mo, 1) - pd.offsets.MonthBegin(3)
            end = date(y, mo, 1) - pd.Timedelta(days=1)
            out.append((f'{m}{y % 100:02d}', pd.Timestamp(start).date(), pd.Timestamp(end).date()))
    return out


def write_synthetic(base, years=range(2010, 2016), seed=0):
    rng = np.random.default_rng(seed)
    fed = base/'fed'; fed.mkdir(parents=True)
    events = []
    for y in years:
        for mo in (1, 3, 4, 6, 7, 9, 10, 12):
            d = pd.Timestamp(date(y, mo, 15))
            while d.weekday() != 2:
                d += pd.Timedelta(days=1)
            clock = '14:00' if d.date() >= date(2013, 3, 13) else '14:15'
            events.append((d.date(), clock))
    ev_utc = {d: pd.Timestamp(f'{d} {c}').tz_localize('America/New_York').tz_convert('UTC') for d, c in events}
    shocks = {d: (rng.normal(), rng.normal()) for d, _ in events}
    for code, start, end in quarter_windows(years)+quarter_windows([max(years)+1])[:1]:
        days = pd.bdate_range(start, end)
        frames = {'zn': [], 'zt': [], 'es': []}
        for d in days:
            local = pd.date_range(f'{d.date()} 07:00', f'{d.date()} 16:25', freq='5min').tz_localize('America/Chicago')
            utc = local.tz_convert('UTC')
            n = len(local)
            r = {k: rng.normal(0, s, n) for k, s in [('zn', 3e-4), ('zt', 1e-4), ('es', 6e-4)]}
            if d.date() in shocks:
                u, z = shocks[d.date()]; a = ev_utc[d.date()]
                hit = (utc >= a) & (utc < a+pd.Timedelta(minutes=25))
                r['zt'][np.argmax(utc >= a)] += -u*6e-4
                r['es'][np.argmax(utc >= a)] += z*3e-3
                r['zn'][hit] *= 1+0.8*np.abs(u)+0.8*np.abs(z)
            for k in frames:
                p = 100*np.exp(np.cumsum(r[k]))
                frames[k].append(pd.DataFrame(dict(Time=local.tz_localize(None).strftime('%Y-%m-%d %H:%M'), Open=p, High=p,
                                                   Low=p, Latest=p, Change=0., **{'%Change': '0%'}, Volume=rng.integers(50, 150, n))))
        for k, parts in frames.items():
            t = pd.concat(parts)
            (fed/f'{k}{code}_5min_{start}_{end}.csv').write_text(t.iloc[::-1].to_csv(index=False)+'"Downloaded from Barchart.com as of test"\n')
    cal = pd.DataFrame([dict(event_date=str(d), release_utc=ev_utc[d].isoformat(), decision='include_primary') for d, _ in events])
    cal.to_csv(base/'calendar.csv', index=False)
    return fed, base/'calendar.csv'


class FedPrimitiveTests(unittest.TestCase):
    def test_prices_and_measures(self):
        b = dict(label=np.array([95, 100, 105], np.int64), latest=np.array([1., 2., 3.]))
        self.assertEqual(list(prices_at(b, np.array([100, 105, 110]))), [1., 2., 3.])
        self.assertTrue(np.isnan(prices_at(b, np.array([125]))[0]))
        m = measures(np.array([1e-3, 1e-4, -1e-4, 1e-4, -1e-4]), 50.)
        self.assertLess(m['BV25'], m['BV']); self.assertEqual(m['VOL'], 50.)
        self.assertTrue(np.isnan(measures(np.array([1e-4, np.nan, 1e-4, 1e-4, 1e-4]), 1.)['BV']))

    def test_clocks(self):
        self.assertEqual(control_clocks(date(2012, 6, 1)), ['14:15', '12:30'])
        self.assertEqual(control_clocks(date(2013, 3, 13)), ['14:00'])

    def test_protocol_must_be_signed(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)/'protocol.json'; p.write_text(json.dumps(PROTOCOL_TEMPLATE))
            with self.assertRaisesRegex(ValueError, 'PROTOCOL_UNSIGNED'):
                check_protocol(p)


class FedPipelineTests(unittest.TestCase):
    def test_coverage_then_signed_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            fed, cal = write_synthetic(base)
            bars, windows = load_files(fed)
            self.assertEqual(contract_for(windows, 'zn', date(2012, 2, 1)), 'znh12')
            cov = blinded_coverage(fed, cal, base/'cov')
            self.assertEqual(cov['n_events_complete'], cov['n_events'])
            proto = dict(PROTOCOL_TEMPLATE, reviewer='Tester', reviewed_on='2026-09-29')
            (base/'protocol.json').write_text(json.dumps(proto))
            result = replication(fed, cal, base/'protocol.json', base/'out', smoke=True)
            self.assertEqual(result['n_primary_events'], 48)
            fam = pd.read_csv(base/'out/fed_primary_family.csv')
            self.assertEqual(list(fam.id), ['F1', 'F2', 'F3'])
            self.assertGreater(fam.set_index('id').loc['F1', 'estimate'], 0)
            for name in ['fed_mean_branch', 'fed_radial_exponent_profile', 'fed_basis_summary',
                         'fed_sector_contrast_information', 'fed_central_symmetry_odd_block']:
                self.assertTrue((base/f'out/{name}.csv').exists(), name)
            post = post_replication(fed, cal, base/'protocol.json', base/'out', base/'post', smoke=True)
            self.assertLess(max(post['reproduction_abs_u_difference'].values()), 1e-10)
            split = pd.read_csv(base/'post/fed_post_replication_split.csv')
            self.assertEqual(list(split.measure), ['BV', 'BV25', 'RV25', 'VOL', 'VOL1', 'VOL25'])
            other = dict(PROTOCOL_TEMPLATE, reviewer='Someone else', reviewed_on='2026-09-30')
            (base/'other.json').write_text(json.dumps(other))
            with self.assertRaisesRegex(ValueError, 'PROTOCOL_DIFFERS_FROM_REPLICATION'):
                post_replication(fed, cal, base/'other.json', base/'out', base/'post2', smoke=True)
