import json
import tempfile
import unittest
from pathlib import Path
import pandas as pd
from confirmation_analysis.audit import calendar_review, source_events
from confirmation_analysis.ecb_calendar import (IndexParser, REGULAR_WALL, build_candidates,
                                                promote, regular_instant)
from confirmation_analysis.windows import REGULAR_WALL as WINDOW_WALL

BASE = 'https://www.ecb.europa.eu'
DECISIONS = {2000: ['2000-01-05', '2000-01-20', '2000-06-08', '2000-07-20'],
             2001: ['2001-09-13', '2001-09-17', '2001-12-06']}
STATEMENTS = {2000: ['2000-01-05', '2000-06-08'], 2001: ['2001-12-06']}
BROKEN = '2000-07-20'
OTHER_CONFERENCE = '2001-12-13'


def release_href(date):
    d = pd.Timestamp(date)
    return f'/press/pr/date/{d.year}/html/pr{d.strftime("%y%m%d")}.en.html'


def statement_href(date):
    d = pd.Timestamp(date)
    return (f'/press/press_conference/monetary-policy-statement/{d.year}'
            f'/html/is{d.strftime("%y%m%d")}.en.html')


def index_html(entries):
    parts = []
    for iso, href, title, subtitle in entries:
        parts.append(f'<dt isoDate="{iso}"><div class="date">{iso}</div></dt><dd>'
                     f'<div class="title"><a href="{href}"  >{title}</a></div>'
                     f'<div class="subtitle">{subtitle}</div></dd>')
    return '<dl>'+''.join(parts)+'</dl>'


def page_html(title, headline, iso, body):
    printed = pd.Timestamp(iso).strftime('%-d %B %Y')
    return (f'<html><head><title>{title}</title>'
            f'<meta property="article:published_time"  content="{iso}"></head><body>'
            f'<script>var x = 1;</script>'
            f'<div class="title"><h1 class="ecb-pressContentTitle">{headline}</h1></div>'
            f'<div class="ecb-pressContentPubDate">\n  {printed} \n</div>'
            f'<div class="section"><p>{body}</p></div></body></html>')


def fake_site():
    pages = {}
    for year, dates in DECISIONS.items():
        entries = [(d, release_href(d), 'Monetary policy decisions', '') for d in dates]
        pages[f'{BASE}/press/govcdec/mopo/{year}/html/index_include.en.html'] = index_html(entries)
        for d in dates:
            if d == BROKEN:
                continue
            pages[BASE+release_href(d)] = page_html(
                'Monetary policy decisions', 'Monetary policy decisions', d,
                'At today&#39;s meeting the Governing Council of the ECB took the following decisions.')
    for year, dates in STATEMENTS.items():
        entries = [(d, statement_href(d), 'Introductory statement', 'Willem F. Duisenberg') for d in dates]
        if year == 2001:
            entries.append((OTHER_CONFERENCE, statement_href(OTHER_CONFERENCE),
                            'ECB press conference on the occasion of the Signing of the Agreement with Europol',
                            'Willem F. Duisenberg'))
        pages[f'{BASE}/press/press_conference/monetary-policy-statement/{year}/html/index_include.en.html'] = index_html(entries)
        for d in dates:
            pages[BASE+statement_href(d)] = page_html(
                'Introductory statement', 'Introductory statement', d,
                'Ladies and gentlemen, the Vice-President and I are here to report on the outcome of today&#39;s meeting.')
        if year == 2001:
            pages[BASE+statement_href(OTHER_CONFERENCE)] = page_html(
                'Press conference', 'Signing of the Agreement between the ECB and Europol', OTHER_CONFERENCE,
                'The agreement was signed today in Frankfurt am Main.')

    def fetch(url):
        body = pages.get(url)
        if body is None:
            return dict(url=url, final_url=url, status=404, body=b'Not found', error='404')
        return dict(url=url, final_url=url, status=200, body=body.encode('utf-8'), error='')
    return fetch


def write_ea(path, extra_pr=('2000-03-16',)):
    rows = []
    dates = sorted({d for dates in DECISIONS.values() for d in dates} | set(extra_pr))
    for date in dates:
        for phase, wall in [('GC_PR', '13:45'), ('GC_PC', '14:30')]:
            if phase == 'GC_PC' and date not in {d for x in STATEMENTS.values() for d in x}:
                continue
            rows.append(dict(Date_time=f'{date} {wall}', Event_type=phase, OIS_1M=0.1, OIS_3M=0.1,
                             OIS_6M=0.1, OIS_1Y=0.1, STOXX50E=0.2))
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_excel(path, sheet_name='EA-EMPD', index=False)


def run_extractor(base, ordinary_sample=2):
    data = base/'data'
    write_ea(data/'Raw/EA-EMPD/EA-EMPD.xlsx')
    return build_candidates(data, base/'candidates', years=[2000, 2001], fetch=fake_site(),
                            ordinary_sample=ordinary_sample), data


class ParserTests(unittest.TestCase):
    def test_index_entries_carry_date_url_and_title(self):
        html = index_html([('2001-12-06', '/press/pr/date/2001/html/pr011206.en.html',
                            'Monetary policy decisions', 'Frankfurt am Main')])
        parser = IndexParser()
        parser.feed(html)
        self.assertEqual(len(parser.entries), 1)
        entry = parser.entries[0]
        self.assertEqual(entry['iso_date'], '2001-12-06')
        self.assertEqual(entry['href'], '/press/pr/date/2001/html/pr011206.en.html')
        self.assertIn('Monetary policy decisions', entry['title'])

    def test_regular_schedule_matches_the_window_builder(self):
        self.assertEqual(REGULAR_WALL, WINDOW_WALL)

    def test_instants_use_iana_rules_not_a_fixed_offset(self):
        self.assertTrue(regular_instant('2001-01-04', 'PR').endswith('+00:00'))
        self.assertEqual(pd.Timestamp(regular_instant('2001-01-04', 'PR')).hour, 12)
        self.assertEqual(pd.Timestamp(regular_instant('2001-06-21', 'PR')).hour, 11)


class ExtractorTests(unittest.TestCase):
    def test_candidates_are_never_verified_and_absence_is_not_assumed(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            status, _ = run_extractor(base)
            c = pd.read_csv(base/'candidates/ecb_calendar_candidates.csv', dtype=str).fillna('')
            self.assertEqual(set(c.verification_status), {'candidate'})
            self.assertEqual(status['verification_status_written'], 'candidate')
            self.assertFalse(status['confirmation_outcomes_computed'])
            self.assertNotIn(BROKEN, set(c.event_date))
            queue = pd.read_csv(base/'candidates/ecb_calendar_review_queue.csv', dtype=str).fillna('')
            unresolved = queue[queue.review_reasons.eq('unresolved_evidence')]
            self.assertIn(BROKEN, set(unresolved.event_date))

    def test_second_meeting_of_the_month_is_decided_by_the_statement(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            run_extractor(base)
            c = pd.read_csv(base/'candidates/ecb_calendar_candidates.csv', dtype=str).fillna('')
            pc = c[c.phase.eq('PC')].set_index('event_date')
            self.assertEqual(pc.loc['2000-01-05', 'proposed_actual_phase_present'], 'true')
            self.assertEqual(pc.loc['2000-01-20', 'proposed_actual_phase_present'], 'false')
            self.assertEqual(pc.loc['2000-01-20', 'evidence_status'], 'statement_absent_from_annual_index')
            self.assertEqual(pc.loc['2000-01-20', 'event_datetime_utc'], '')
            queue = pd.read_csv(base/'candidates/ecb_calendar_review_queue.csv', dtype=str).fillna('')
            opened = queue[queue.event_date.eq('2000-01-20') & queue.phase.eq('PC')]
            self.assertIn('multiple_meetings_in_month_2000_2001', opened.iloc[0].review_reasons)
            self.assertIn('proposed_absence', opened.iloc[0].review_reasons)

    def test_non_policy_conference_and_timing_exception_are_not_silently_used(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            run_extractor(base)
            c = pd.read_csv(base/'candidates/ecb_calendar_candidates.csv', dtype=str).fillna('')
            self.assertNotIn(OTHER_CONFERENCE, set(c.event_date))
            pages = pd.read_csv(base/'candidates/ecb_pages.csv')
            europol = pages[pages.iso_date.eq(OTHER_CONFERENCE)].iloc[0]
            self.assertFalse(bool(europol.is_policy_statement))
            exception = c[c.event_date.eq('2001-09-17')]
            self.assertTrue(exception.event_datetime_utc.eq('').all())
            self.assertTrue(exception.timestamp_basis.eq('requires_specific_evidence').all())
            queue = pd.read_csv(base/'candidates/ecb_calendar_review_queue.csv', dtype=str).fillna('')
            self.assertIn('timing_exception', '|'.join(queue[queue.event_date.eq('2001-09-17')].review_reasons))

    def test_reconciliation_reports_dates_only_one_source_knows(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            status, _ = run_extractor(base)
            r = pd.read_csv(base/'candidates/ecb_calendar_reconciliation.csv', dtype=str).fillna('')
            extra = r[r.event_date.eq('2000-03-16')].iloc[0]
            self.assertIn('date_absent_from_ecb_decisions_index', extra.discrepancy)
            missing = r[r.event_date.eq(BROKEN)].iloc[0]
            self.assertIn('date_absent_from_ecb_decisions_index', missing.discrepancy)
            self.assertGreater(status['n_discrepancies'], 0)
            queue = pd.read_csv(base/'candidates/ecb_calendar_review_queue.csv', dtype=str).fillna('')
            self.assertIn('reconciliation_discrepancy', '|'.join(queue.review_reasons))


class PromotionTests(unittest.TestCase):
    def review(self, base, decisions=None, reviewer='Francesco Pinna'):
        queue = pd.read_csv(base/'candidates/ecb_calendar_review_queue.csv', dtype=str).fillna('')
        decisions = decisions or {}
        queue['reviewer_decision'] = [
            decisions.get((row.event_date, row.phase),
                          row.proposed_actual_phase_present or 'exclude')
            for row in queue.itertuples()]
        queue['reviewer'] = reviewer
        queue['reviewed_on'] = '2026-09-12'
        queue['reviewer_note'] = 'reviewed against the ECB archive page'
        exception = queue.event_date.isin(['2001-09-17']) & queue.reviewer_decision.eq('true')
        queue.loc[exception, 'reviewer_event_datetime_utc'] = '2001-09-17T15:15:00+00:00'
        path = base/'reviewed_queue.csv'
        queue.to_csv(path, index=False)
        return path

    def test_promotion_refuses_an_unreviewed_queue(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            run_extractor(base)
            raw = base/'candidates/ecb_calendar_review_queue.csv'
            with self.assertRaisesRegex(ValueError, 'REVIEW_INCOMPLETE'):
                promote(base/'candidates', raw, base/'out.csv', 'Francesco Pinna', 'rule')

    def test_promotion_refuses_without_a_named_reviewer_or_a_rule(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            run_extractor(base)
            queue = self.review(base)
            for reviewer, rule in [('', 'rule'), ('Francesco Pinna', '')]:
                with self.assertRaisesRegex(ValueError, 'PROMOTION_UNSIGNED'):
                    promote(base/'candidates', queue, base/'out.csv', reviewer, rule)

    def test_promoted_calendar_satisfies_the_audit_and_records_its_rule(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            _, data = run_extractor(base)
            queue = self.review(base, {('2001-09-17', 'PR'): 'true', ('2001-09-17', 'PC'): 'false'})
            rule = ('Ordinary rows promoted in bulk: the decision release and, where present, the '
                    'introductory statement resolve on the ECB archive and their published date '
                    'agrees with the annual index. Every open row was reviewed individually.')
            record = promote(base/'candidates', queue, base/'verified.csv', 'Pinna, F.', rule)
            self.assertEqual(record['reviewer'], 'Pinna, F.')
            self.assertEqual(record['rule'], rule)
            verified = pd.read_csv(base/'verified.csv', dtype=str).fillna('')
            self.assertEqual(set(verified.verification_status), {'verified'})
            self.assertEqual(verified[verified.event_date.eq('2001-09-17') & verified.phase.eq('PR')
                                      ].iloc[0].event_datetime_utc, '2001-09-17T15:15:00+00:00')
            ea = source_events(data/'Raw/EA-EMPD/EA-EMPD.xlsx')
            review = calendar_review(ea, base/'verified.csv')
            statuses = set(review[review.calendar_status.ne('unverified_source_window_is_not_proof_of_an_event')
                                  ].calendar_status)
            self.assertTrue(statuses.issubset({'verified_present', 'verified_absent'}))
            self.assertTrue((review[review.event_date.eq('2000-01-05') & review.phase.eq('PC')
                                    ].calendar_status == 'verified_present').all())
            side = json.loads((base/'verified_promotion.json').read_text())
            self.assertIn('regular schedule', side['timestamp_caveat'])

    def test_an_unresolved_page_cannot_be_decided_into_the_calendar(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            run_extractor(base)
            queue = pd.read_csv(self.review(base), dtype=str).fillna('')
            queue.loc[queue.review_reasons.eq('unresolved_evidence'), 'reviewer_decision'] = 'true'
            path = base/'decided_unresolved.csv'
            queue.to_csv(path, index=False)
            with self.assertRaisesRegex(ValueError, 'UNUSABLE_DECISION'):
                promote(base/'candidates', path, base/'out.csv', 'Francesco Pinna', 'rule')

    def test_a_decision_without_a_candidate_row_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            run_extractor(base)
            queue = pd.read_csv(self.review(base), dtype=str).fillna('')
            invented = queue.iloc[[0]].copy()
            invented['event_date'] = '1999-01-07'
            invented['phase'] = 'PR'
            invented['reviewer_decision'] = 'true'
            path = base/'invented.csv'
            pd.concat([queue, invented]).to_csv(path, index=False)
            with self.assertRaisesRegex(ValueError, 'UNMATCHED_DECISION'):
                promote(base/'candidates', path, base/'out.csv', 'Francesco Pinna', 'rule')

    def test_a_proposed_absence_cannot_be_promoted_without_an_individual_review(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            run_extractor(base)
            queue = pd.read_csv(base/'candidates/ecb_calendar_review_queue.csv', dtype=str).fillna('')
            keep = ~(queue.event_date.eq('2000-01-20') & queue.phase.eq('PC'))
            queue = queue[keep].copy()
            queue['reviewer_decision'] = queue.phase.map(lambda p: 'true' if p else 'exclude')
            queue['reviewer'] = 'Francesco Pinna'
            path = base/'partial_queue.csv'
            queue.to_csv(path, index=False)
            with self.assertRaisesRegex(ValueError, 'UNREVIEWED_ABSENCE'):
                promote(base/'candidates', path, base/'out.csv', 'Francesco Pinna', 'rule')


if __name__ == '__main__':
    unittest.main()
