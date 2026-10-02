import tempfile
import unittest
from datetime import date
from pathlib import Path
import numpy as np
import pandas as pd
from confirmation_analysis.fomc_calendar import (statement_links, parse_statement, parse_press_conference, regular_schedule,
                                                 to_utc, zone_on, market_status, candidates, promote, Fetcher)

STATEMENT = '<html><head><title>Federal Reserve Board - Federal Reserve issues FOMC statement</title></head><body><p>{d}</p><h3>Federal Reserve issues FOMC statement</h3><p>{when}</p><p>Information received since</p></body></html>'
MINUTES = '<html><head><title>Minutes of the Federal Open Market Committee</title></head><body>For release at 2:00 p.m. EST</body></html>'
PRESS = '<html><body><h4>Related Information</h4>FOMC Meeting Statement: <a>PDF</a> | <a>HTML</a> (Released\n {long} at {t})</body></html>'
MEETINGS = [('20150128', 'January 28, 2015', 'For immediate release', None),
            ('20151216', 'December 16, 2015', 'For immediate release', '2:00 p.m.'),
            ('20161214', 'December 14, 2016', 'For release at 2:00 p.m. EST', None),
            ('20120913', 'September 13, 2012', 'For release at 12:30 p.m. EDT', '12:30 p.m.'),
            ('20200315', 'March 15, 2020', 'For release at 5:00 p.m. EDT', None)]


def site():
    pages = {}
    links = ''.join(f'<a href="/newsevents/pressreleases/monetary{ymd}a.htm">HTML</a>' for ymd, *_ in MEETINGS)
    links += '<a href="/newsevents/press/monetary/20160106a.htm">Minutes</a>'
    for y in range(2015, 2021):
        pages[f'https://www.federalreserve.gov/monetarypolicy/fomchistorical{y}.htm'] = links
    pages['https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm'] = ''
    for ymd, long, when, pc in MEETINGS:
        pages[f'https://www.federalreserve.gov/newsevents/pressreleases/monetary{ymd}a.htm'] = STATEMENT.format(d=long, when=when)
        if pc:
            pages[f'https://www.federalreserve.gov/monetarypolicy/fomcpresconf{ymd}.htm'] = PRESS.format(long=long, t=pc)
    pages['https://www.federalreserve.gov/newsevents/press/monetary/20160106a.htm'] = MINUTES
    return lambda url: (200, pages[url]) if url in pages else (404, '')


def write_bars(directory, jumps, seed=0):
    rng = np.random.default_rng(seed)
    directory.mkdir(parents=True, exist_ok=True)
    for root, scale in [('zt', 2e-4), ('es', 5e-4)]:
        for day in sorted({j.date() for j in jumps} | {date(2015, 1, 27)}):
            local = pd.date_range(f'{day} 08:00', f'{day} 15:55', freq='5min').tz_localize('America/Chicago')
            r = rng.normal(0, scale, len(local))
            for j in jumps:
                hit = local.tz_convert('UTC') == j
                r[hit] += 25*scale
            price = 100*np.exp(np.cumsum(r))
            t = pd.DataFrame(dict(Time=local.tz_localize(None).strftime('%Y-%m-%d %H:%M'), Open=price, High=price, Low=price,
                                  Latest=price, Change=0., **{'%Change': '0%'}, Volume=100))
            name = f'{root}h{day.year % 100:02d}_5min_{day}_{day}.csv'
            (directory/name).write_text(t.to_csv(index=False)+'"Downloaded from Barchart.com as of test"\n')


class FomcParsingTests(unittest.TestCase):
    def test_links_in_both_url_schemes(self):
        page = '<a href="/newsevents/pressreleases/monetary20151216a.htm">x</a><a href="https://www.federalreserve.gov/newsevents/press/monetary/20081216b.htm">y</a>'
        links = statement_links(page)
        self.assertEqual(set(links), {'20151216', '20081216'})

    def test_statement_times(self):
        p = parse_statement(STATEMENT.format(d='x', when='For release at 2:15 p.m. EST'))
        self.assertTrue(p['is_statement']); self.assertEqual(p['release_local'], '14:15'); self.assertEqual(p['zone_on_page'], 'EST')
        p = parse_statement(STATEMENT.format(d='x', when='For immediate release'))
        self.assertTrue(p['immediate']); self.assertEqual(p['release_local'], '')
        self.assertFalse(parse_statement(MINUTES)['is_statement'])
        t, frag = parse_press_conference(PRESS.format(long='December 16, 2015', t='2:00 p.m.'), date(2015, 12, 16))
        self.assertEqual(t, '14:00')
        older = '<html><body>FOMC Meeting Statement (Released March 20, 2013 at 2:00 p.m.) | HTML (Released March 20, 2013 at 2:00 p.m.)</body></html>'
        self.assertEqual(parse_press_conference(older, date(2013, 3, 20))[0], '14:00')

    def test_schedule_and_zones(self):
        self.assertEqual(regular_schedule(date(2012, 1, 25), True), '12:30')
        self.assertEqual(regular_schedule(date(2012, 3, 13), False), '14:15')
        self.assertEqual(regular_schedule(date(2013, 1, 30), False), '14:15')
        self.assertEqual(regular_schedule(date(2013, 3, 20), True), '14:00')
        self.assertEqual(zone_on(date(2015, 12, 16)), 'EST'); self.assertEqual(zone_on(date(2016, 7, 27)), 'EDT')
        self.assertEqual(str(to_utc(date(2015, 12, 16), '14:00')), '2015-12-16 19:00:00+00:00')

    def test_market_status_rules(self):
        self.assertEqual(market_status({-15: 1, -10: 1, -5: 1, 0: 9, 5: 3, 10: 2})[0], 'confirmed_at_release_bar')
        self.assertEqual(market_status({-15: 1, -10: 1, -5: 1, 0: 1, 5: 9, 10: 2})[0], 'reaction_only_after_release_bar')
        self.assertEqual(market_status({-15: 9, -10: 1, -5: 1, 0: 2, 5: 1, 10: 1})[0], 'activity_before_release_bar')
        self.assertEqual(market_status({-15: 1, -10: 1, -5: 1, 0: 2, 5: 2, 10: 2})[0], 'no_visible_reaction')


class FomcPipelineTests(unittest.TestCase):
    def test_candidates_queue_and_promotion(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            jumps = [to_utc(date(2015, 1, 28), '14:00'), to_utc(date(2015, 12, 16), '14:00'),
                     to_utc(date(2016, 12, 14), '14:00'), to_utc(date(2012, 9, 13), '12:30')]
            write_bars(base/'fed', jumps)
            fetcher = Fetcher(base/'cache', pause=0, opener=site())
            status = candidates(base/'out', base/'fed', start='2012-01-01', end='2020-12-31', fetcher=fetcher)
            c = pd.read_csv(base/'out/fomc_calendar_candidates.csv', dtype=str).fillna('')
            self.assertEqual(sorted(c.event_date), ['2012-09-13', '2015-01-28', '2015-12-16', '2016-12-14', '2020-03-15'])
            src = c.set_index('event_date').time_source
            self.assertEqual(src['2016-12-14'], 'statement_page'); self.assertEqual(src['2015-12-16'], 'press_conference_page')
            self.assertEqual(src['2015-01-28'], 'regular_schedule')
            self.assertEqual(status['market_check']['implied_bar_label_semantics'], 'interval_start')
            q = pd.read_csv(base/'out/fomc_review_queue.csv', dtype=str).fillna('')
            self.assertIn('2020-03-15', set(q.event_date))
            self.assertIn('weekend_announcement', q.set_index('event_date').loc['2020-03-15', 'review_reasons'])
            self.assertNotIn('2015-01-28', set(q.event_date))
            self.assertTrue((base/'out/fomc_non_statement_releases.csv').exists())
            with self.assertRaisesRegex(ValueError, 'REVIEW_INCOMPLETE'):
                promote(base/'out', base/'out/fomc_review_queue.csv', base/'v.csv', 'Tester', 'test rule')
            q['reviewer_decision'] = 'exclude'; q['reviewer'] = 'Tester'; q['reviewed_on'] = '2026-09-29'
            q['reviewer_note'] = 'synthetic'
            q.to_csv(base/'reviewed.csv', index=False)
            v = promote(base/'out', base/'reviewed.csv', base/'v.csv', 'Tester', 'test rule')
            self.assertEqual(int(v.primary.sum()), len(c)-len(q))
            self.assertTrue(v.verification_status.eq('verified').all())
