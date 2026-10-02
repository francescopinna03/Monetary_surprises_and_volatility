import tempfile
import unittest
from pathlib import Path
import numpy as np
import pandas as pd
from confirmation_analysis.bar_label import (material_support, cell_decisions, load_schedule, promote, session_evidence,
                                            write_schedule_template)
from confirmation_analysis.protocol import digest

OPEN_WALL, CLOSE_WALL = '08:00', '22:00'
SOURCE = 'https://www.eurex.com/ex-en/trade/trading-calendar-and-hours'


def schedule_rows(reviewer='Francesco Pinna', **overrides):
    row = dict(root_code='all', period_start_date='2000-01-01', period_end_date='2012-12-31',
               session_open_wall=OPEN_WALL, session_close_wall=CLOSE_WALL, timezone='Europe/Berlin',
               source_url=SOURCE, reviewer=reviewer, notes='published Eurex session for the epoch')
    row.update(overrides)
    return pd.DataFrame([row])


def write_schedule(path, table=None):
    table = schedule_rows() if table is None else table
    path.parent.mkdir(parents=True, exist_ok=True)
    table.to_csv(path, index=False)
    return path


def write_contract(path, dates, semantics, seed, drop_announcement=False):
    rng = np.random.default_rng(seed)
    frames = []
    for date in dates:
        opened = pd.Timestamp(f'{date} {OPEN_WALL}', tz='Europe/Berlin')
        closed = pd.Timestamp(f'{date} {CLOSE_WALL}', tz='Europe/Berlin')
        first = opened if semantics == 'interval_start' else opened+pd.Timedelta(minutes=5)
        last = closed-pd.Timedelta(minutes=5) if semantics == 'interval_start' else closed
        labels = pd.date_range(first, last, freq='5min')
        if drop_announcement:
            wall = labels.tz_convert('Europe/Berlin').strftime('%H:%M')
            labels = labels[(wall < '13:00') | (wall > '15:00')]
        price = 100*np.exp(np.cumsum(rng.normal(0, 2e-4, len(labels))))
        chicago = labels.tz_convert('America/Chicago').tz_localize(None)
        frames.append(pd.DataFrame(dict(Time=chicago.strftime('%m/%d/%Y %H:%M'), Open=price,
                                        High=price*1.001, Low=price*0.999, Latest=price, Volume=100)))
    pd.concat(frames).to_csv(path, index=False)
    return path


def primary_table(paths, root='gg', year=2001, expiry='H'):
    rows = []
    for path in paths:
        rows.append(dict(input_path=str(path), file_name=path.name, root_code=root,
                         contract_year=year, expiry_code=expiry, sha256=digest(path),
                         n_rows=sum(1 for _ in path.open())-1))
        expiry = 'HMUZ'['HMUZ'.index(expiry)+1]
    return pd.DataFrame(rows)


def make_contract(base, semantics, name='ggh01_intraday-5min_historical-data-09-12-2026.csv',
                  seed=1, drop_announcement=False, n_days=25):
    days = pd.bdate_range('2001-02-01', periods=n_days).strftime('%Y-%m-%d')
    return write_contract(base/name, days, semantics, seed, drop_announcement)


class ScheduleTests(unittest.TestCase):
    def test_template_is_empty_and_refuses_to_be_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'eurex_trading_hours.csv'
            write_schedule_template(path)
            with self.assertRaises(FileExistsError):
                write_schedule_template(path)
            with self.assertRaisesRegex(ValueError, 'EUREX_SCHEDULE_EMPTY'):
                load_schedule(path)

    def test_missing_unsourced_and_overlapping_schedules_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            with self.assertRaisesRegex(ValueError, 'EUREX_SCHEDULE_MISSING'):
                load_schedule(base/'absent.csv')
            for overrides, pattern in [(dict(reviewer=''), 'EUREX_SCHEDULE_UNSOURCED'),
                                       (dict(source_url='ftp://example.test'), 'EUREX_SCHEDULE_UNSOURCED'),
                                       (dict(session_close_wall='25:99'), 'EUREX_SCHEDULE_TIME'),
                                       (dict(period_end_date='1999-01-01'), 'EUREX_SCHEDULE_RANGE')]:
                path = write_schedule(base/'s.csv', schedule_rows(**overrides))
                with self.assertRaisesRegex(ValueError, pattern):
                    load_schedule(path)
                path.unlink()
            overlapping = pd.concat([schedule_rows(), schedule_rows(period_start_date='2005-01-01',
                                                                    period_end_date='2015-12-31')])
            path = write_schedule(base/'s.csv', overlapping)
            with self.assertRaisesRegex(ValueError, 'EUREX_SCHEDULE_OVERLAP'):
                load_schedule(path)

    def test_one_timezone_per_schedule_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            mixed = pd.concat([schedule_rows(), schedule_rows(root_code='hf', timezone='America/Chicago')])
            path = write_schedule(Path(tmp)/'s.csv', mixed)
            with self.assertRaisesRegex(ValueError, 'EUREX_SCHEDULE_TIMEZONE'):
                load_schedule(path)


class BoundaryTests(unittest.TestCase):
    def evidence(self, base, semantics, **kwargs):
        path = make_contract(base, semantics, **kwargs)
        schedule = write_schedule(base/'hours.csv')
        out = base/f'evidence_{semantics}_{kwargs.get("name", "default")}'
        session_evidence(primary_table([path]), schedule, out)
        return pd.read_csv(out/'bar_label_cells.csv'), pd.read_csv(out/'bar_label_files.csv'), out

    def test_both_conventions_are_recovered_from_the_session_boundary(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            cases = [('interval_start', '08:00', '21:55', 'ggh01'), ('interval_end', '08:05', '22:00', 'ggm01')]
            for semantics, first, last, stem in cases:
                cells, files, _ = self.evidence(base, semantics,
                                                name=f'{stem}_intraday-5min_historical-data-09-12-2026.csv')
                self.assertEqual(cells.iloc[0].bar_label_semantics, semantics)
                self.assertEqual(cells.iloc[0].period_start, 2000)
                self.assertFalse(bool(cells.iloc[0].conflict))
                self.assertEqual(files.iloc[0].modal_first_wall, first)
                self.assertEqual(files.iloc[0].modal_last_wall, last)

    def test_the_decision_does_not_use_the_announcement_window(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            full, _, _ = self.evidence(base, 'interval_start',
                                       name='ggh01_intraday-5min_historical-data-09-12-2026.csv')
            pruned, _, _ = self.evidence(base, 'interval_start', drop_announcement=True,
                                         name='ggm01_intraday-5min_historical-data-09-12-2026.csv')
            self.assertEqual(full.iloc[0].bar_label_semantics, 'interval_start')
            self.assertEqual(pruned.iloc[0].bar_label_semantics, 'interval_start')
            self.assertEqual(full.iloc[0].n_days_interval_start, pruned.iloc[0].n_days_interval_start)

    def test_boundaries_matching_neither_convention_stay_inconclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            path = make_contract(base, 'interval_start')
            schedule = write_schedule(base/'hours.csv', schedule_rows(session_close_wall='17:30'))
            session_evidence(primary_table([path]), schedule, base/'evidence')
            cells = pd.read_csv(base/'evidence/bar_label_cells.csv')
            self.assertEqual(cells.iloc[0].bar_label_semantics, 'inconclusive')
            self.assertGreater(cells.iloc[0].n_days_inconclusive, 0)

    def test_too_few_days_leave_the_cell_open(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            path = make_contract(base, 'interval_start', n_days=5)
            schedule = write_schedule(base/'hours.csv')
            session_evidence(primary_table([path]), schedule, base/'evidence')
            cells = pd.read_csv(base/'evidence/bar_label_cells.csv')
            self.assertEqual(cells.iloc[0].bar_label_semantics, 'inconclusive')
            self.assertEqual(cells.iloc[0].n_days_interval_start, 5)


class PromotionTests(unittest.TestCase):
    def test_promotion_writes_the_evidence_the_quality_audit_reads(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            path = make_contract(base, 'interval_start')
            primary = primary_table([path])
            schedule = write_schedule(base/'hours.csv')
            session_evidence(primary, schedule, base/'evidence')
            rule = ('Cells whose conclusive session boundaries all agree with one convention, on at '
                    'least twenty days of the published Eurex schedule for the epoch.')
            record = promote(base/'evidence', base/'bar_label_evidence_v2.csv', 'Francesco Pinna', rule)
            self.assertEqual(record['n_cells_promoted'], 1)
            self.assertEqual(record['method'], 'session_boundary_only_no_announcement_window')
            t = pd.read_csv(base/'bar_label_evidence_v2.csv', dtype={'representative_sha256': str})
            required = {'root_code', 'period_start', 'verified', 'bar_label_semantics',
                        'evidence_source', 'reviewer', 'representative_sha256'}
            self.assertTrue(required.issubset(t.columns))
            row = t.iloc[0]
            self.assertTrue(bool(row.verified))
            self.assertEqual(row.bar_label_semantics, 'interval_start')
            self.assertEqual(row.reviewer, 'Francesco Pinna')
            self.assertEqual(len(row.representative_sha256), 64)
            self.assertEqual(row.evidence_source, SOURCE)
            match = primary[primary.sha256.eq(row.representative_sha256)
                            & primary.root_code.eq(row.root_code)
                            & primary.contract_year.between(row.period_start, row.period_start+2)
                            & primary.n_rows.gt(0)]
            self.assertEqual(len(match), 1)

    def test_promotion_refuses_without_a_named_reviewer_or_a_rule(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            path = make_contract(base, 'interval_start')
            schedule = write_schedule(base/'hours.csv')
            session_evidence(primary_table([path]), schedule, base/'evidence')
            for reviewer, rule in [('', 'rule'), ('Francesco Pinna', '')]:
                with self.assertRaisesRegex(ValueError, 'PROMOTION_UNSIGNED'):
                    promote(base/'evidence', base/'out.csv', reviewer, rule)

    def test_an_inconclusive_cell_is_never_promoted(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            path = make_contract(base, 'interval_start', n_days=5)
            schedule = write_schedule(base/'hours.csv')
            session_evidence(primary_table([path]), schedule, base/'evidence')
            record = promote(base/'evidence', base/'out.csv', 'Francesco Pinna', 'rule')
            self.assertEqual(record['n_cells_promoted'], 0)
            self.assertEqual(record['n_cells_left_open'], 1)


if __name__ == '__main__':
    unittest.main()


class MinorityThresholdTests(unittest.TestCase):

    def test_two_days_against_five_thousand_is_noise(self):
        kept, dropped = material_support({'interval_start': 5578, 'interval_end': 2}, .01, 3)
        self.assertEqual(kept['interval_end'], 0)
        self.assertEqual(dropped, {'interval_end': 2})

    def test_a_real_split_is_kept(self):
        kept, dropped = material_support({'interval_start': 100, 'interval_end': 50}, .01, 3)
        self.assertEqual(kept['interval_end'], 50)
        self.assertEqual(dropped, {})

    def test_both_thresholds_must_be_cleared(self):
        kept, _ = material_support({'interval_start': 100, 'interval_end': 4}, .01, 3)
        self.assertEqual(kept['interval_end'], 4)
        kept, _ = material_support({'interval_start': 10, 'interval_end': 2}, .01, 3)
        self.assertEqual(kept['interval_end'], 0)

    def test_unanimous_cell_is_untouched(self):
        kept, dropped = material_support({'interval_start': 200, 'interval_end': 0}, .01, 3)
        self.assertEqual(kept['interval_start'], 200)
        self.assertEqual(dropped, {})

    def test_discarded_count_is_reported(self):
        files = pd.DataFrame([dict(root_code='gg', period_start=2006, file_decision='interval_start',
            n_days_interval_start=189, n_days_interval_end=0, n_days_inconclusive=10,
            n_days_without_schedule=0, schedule_source_url='https://example.test', sha256='a'*64,
            file_name='a.csv', input_path='/a.csv', n_rows=100),
            dict(root_code='gg', period_start=2006, file_decision='interval_end',
            n_days_interval_start=0, n_days_interval_end=1, n_days_inconclusive=5,
            n_days_without_schedule=0, schedule_source_url='https://example.test', sha256='b'*64,
            file_name='b.csv', input_path='/b.csv', n_rows=100)])
        cells = cell_decisions(files, minimum_days=20)
        row = cells.iloc[0]
        self.assertEqual(row.bar_label_semantics, 'interval_start')
        self.assertFalse(row.conflict)
        self.assertEqual(row.n_days_interval_end, 1)
        self.assertEqual(row.n_days_discarded_minority, 1)
        self.assertEqual(row.discarded_minority_verdicts, 'interval_end:1')
