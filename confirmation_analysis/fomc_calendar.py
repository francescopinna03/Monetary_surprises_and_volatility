import argparse
import hashlib
import html
import json
import re
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path
import numpy as np
import pandas as pd

BASE = 'https://www.federalreserve.gov'
HISTORICAL = BASE+'/monetarypolicy/fomchistorical{year}.htm'
CURRENT = BASE+'/monetarypolicy/fomccalendars.htm'
PRESS_CONFERENCE = BASE+'/monetarypolicy/fomcpresconf{ymd}.htm'
STATEMENT_LINK = re.compile(r'href="((?:https://www\.federalreserve\.gov)?/newsevents/press(?:releases/monetary|/monetary/)(\d{8})([a-z])\.htm)"', re.I)
RELEASE_AT = re.compile(r'For\s+release\s+at\s+(\d{1,2}):(\d{2})\s*([ap])\.?\s*m\.?\s*(E[SD]T)', re.I)
IMMEDIATE = re.compile(r'For\s+immediate\s+release', re.I)
RELEASED_AT = re.compile(r'Statement:?.{0,200}?\(Released\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})\s+at\s+(\d{1,2}):(\d{2})\s*([ap])\.?\s*m\.?\)', re.I | re.S)
TITLE = re.compile(r'<title>(.*?)</title>', re.I | re.S)
EXCLUDED_TITLES = re.compile(r'longer-run goals|principles|normalization|minutes', re.I)
FED_NAME = re.compile(r'^(zt|es|zn)[hmuz]\d\d_5min_(\d{4}-\d\d-\d\d)_(\d{4}-\d\d-\d\d)\.csv$')
SCHEDULE_SOURCE = BASE+'/newsevents/pressreleases/monetary20130313a.htm'
SCHEDULE_CHANGE = date(2013, 3, 13)
SLOTS = ('12:30', '14:00', '14:15')
MINUTE = np.timedelta64(1, 'm')
REVIEW_COLUMNS = ['reviewer_decision', 'reviewer_event_datetime_utc', 'reviewer', 'reviewed_on', 'reviewer_note']
DECISIONS = {'include_primary', 'include_unscheduled', 'exclude'}


def text_of(page):
    page = re.sub(r'<(script|style)\b.*?</\1>', ' ', page, flags=re.S | re.I)
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', page))).strip()


def title_of(page):
    m = TITLE.search(page)
    return re.sub(r'\s+', ' ', html.unescape(m.group(1))).strip() if m else ''


class Fetcher:
    def __init__(self, cache_dir, pause=0.5, opener=None):
        self.cache = Path(cache_dir); self.cache.mkdir(parents=True, exist_ok=True)
        self.pause = pause; self.opener = opener; self.log = []

    def get(self, url):
        key = hashlib.sha1(url.encode()).hexdigest()
        body, meta = self.cache/f'{key}.html', self.cache/f'{key}.json'
        if meta.exists():
            m = json.loads(meta.read_text())
            page = body.read_text(encoding='utf-8') if body.exists() else ''
            self.log.append(dict(url=url, status=m['status'], sha256=m['sha256'], cached=True))
            return m['status'], page
        status, page = self.download(url)
        body.write_text(page, encoding='utf-8')
        sha = hashlib.sha256(page.encode('utf-8')).hexdigest()
        meta.write_text(json.dumps(dict(url=url, status=status, sha256=sha,
                                        fetched_utc=datetime.now(timezone.utc).isoformat())))
        self.log.append(dict(url=url, status=status, sha256=sha, cached=False))
        return status, page

    def download(self, url):
        if self.opener is not None:
            return self.opener(url)
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 academic research replication'})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    page = r.read().decode('utf-8', errors='replace')
                time.sleep(self.pause)
                return r.status, page
            except urllib.error.HTTPError as e:
                time.sleep(self.pause)
                return e.code, ''
            except urllib.error.URLError:
                time.sleep(2*(attempt+1))
        return 0, ''


def statement_links(page):
    out = {}
    for url, ymd, letter in STATEMENT_LINK.findall(page):
        full = url if url.startswith('http') else BASE+url
        out.setdefault(ymd, set()).add(full)
    return out


def parse_statement(page):
    t = text_of(page); title = title_of(page)
    is_statement = bool(re.search(r'FOMC statement', title+' '+t[:3000], re.I)) and not EXCLUDED_TITLES.search(title)
    m = RELEASE_AT.search(t)
    if m:
        hh, mm, ap, zone = int(m.group(1)), int(m.group(2)), m.group(3).lower(), m.group(4).upper()
        return dict(is_statement=is_statement, title=title, release_local=f'{(hh % 12)+(12 if ap == "p" else 0):02d}:{mm:02d}',
                    zone_on_page=zone, time_fragment=m.group(0), immediate=False)
    return dict(is_statement=is_statement, title=title, release_local='', zone_on_page='',
                time_fragment='For immediate release' if IMMEDIATE.search(t) else '', immediate=bool(IMMEDIATE.search(t)))


def parse_press_conference(page, day):
    t = text_of(page)
    for m in RELEASED_AT.finditer(t):
        if datetime.strptime(re.sub(r'\s+', ' ', m.group(1)), '%B %d, %Y').date() == day:
            hh, mm, ap = int(m.group(2)), int(m.group(3)), m.group(4).lower()
            return f'{(hh % 12)+(12 if ap == "p" else 0):02d}:{mm:02d}', m.group(0)
    return '', ''


def regular_schedule(day, press_conference):
    if day >= SCHEDULE_CHANGE:
        return '14:00'
    return '12:30' if press_conference else '14:15'


def zone_on(day):
    return 'EDT' if pd.Timestamp(f'{day.isoformat()} 12:00').tz_localize('America/New_York').dst() else 'EST'


def to_utc(day, hhmm):
    local = pd.Timestamp(f'{day.isoformat()} {hhmm}').tz_localize('America/New_York')
    return local.tz_convert('UTC')


def load_fed_bars(directory, roots=('zt', 'es')):
    frames = {}
    for path in sorted(Path(directory).glob('*.csv')):
        m = FED_NAME.match(path.name)
        if not m or m.group(1) not in roots:
            continue
        t = pd.read_csv(path, usecols=['Time', 'Latest', 'Volume'])
        t = t[pd.to_numeric(t.Latest, errors='coerce').notna()].copy()
        t['Latest'] = t.Latest.astype(float)
        t['label'] = pd.to_datetime(t.Time, format='mixed').dt.tz_localize(
            'America/Chicago', ambiguous='raise', nonexistent='raise').dt.tz_convert('UTC')
        t['contract'] = path.name[:5]
        frames.setdefault(m.group(1), []).append(t[['label', 'Latest', 'Volume', 'contract']])
    return {root: pd.concat(v, ignore_index=True).sort_values(['contract', 'label']) for root, v in frames.items()}


OFFSETS = (-15, -10, -5, 0, 5, 10)
VISIBLE = 4.
QUIET = 2.


def release_ratios(bars, release_utc):
    ratios = []
    for root, b in bars.items():
        w = b[(b.label >= release_utc-75*MINUTE) & (b.label <= release_utc+15*MINUTE)]
        if w.empty:
            continue
        contract = w.groupby('contract').Volume.sum().idxmax()
        w = w[w.contract.eq(contract)].set_index('label').Latest
        r = np.log(w).diff().abs()
        base = r[(r.index >= release_utc-65*MINUTE) & (r.index < release_utc-15*MINUTE)]
        scale = base[base > 0].median() if (base > 0).any() else np.nan
        if np.isfinite(scale) and scale > 0:
            ratios.append([r.get(release_utc+k*MINUTE, np.nan)/scale for k in OFFSETS])
    if not ratios:
        return None
    return dict(zip(OFFSETS, np.nanmean(np.array(ratios, float), axis=0)))


def market_status(ratios):
    if ratios is None:
        return 'no_market_data', np.nan
    at = ratios[0]; before = max(ratios[k] for k in (-15, -10, -5)); after = max(ratios[k] for k in (5, 10))
    if at >= VISIBLE and at >= before:
        return 'confirmed_at_release_bar', at
    if after >= VISIBLE and at < QUIET and before < QUIET:
        return 'reaction_only_after_release_bar', at
    if before >= VISIBLE and before > at:
        return 'activity_before_release_bar', at
    return 'no_visible_reaction', at


def collect_candidates(fetcher, years, start, end):
    pages = [HISTORICAL.format(year=y) for y in years]+[CURRENT]
    links = {}
    listing = []
    for url in pages:
        status, page = fetcher.get(url)
        listing.append(dict(url=url, status=status))
        for ymd, urls in statement_links(page).items():
            links.setdefault(ymd, set()).update(urls)
    rows, others = [], []
    for ymd in sorted(links):
        day = datetime.strptime(ymd, '%Y%m%d').date()
        if not (start <= day <= end):
            continue
        statements = []
        for url in sorted(links[ymd]):
            status, page = fetcher.get(url)
            p = parse_statement(page) if status == 200 else dict(is_statement=False, title='', release_local='',
                                                                zone_on_page='', time_fragment='', immediate=False)
            statements.append(dict(url=url, status=status, **p))
        stmts = [s for s in statements if s['is_statement']]
        unresolved = [s for s in statements if s['status'] != 200]
        if not stmts and not unresolved:
            others.append(dict(event_date=day.isoformat(), urls='|'.join(s['url'] for s in statements),
                               titles='|'.join(s['title'] for s in statements)))
            continue
        pc_status, pc_page = fetcher.get(PRESS_CONFERENCE.format(ymd=ymd))
        pc_time, pc_fragment = parse_press_conference(pc_page, day) if pc_status == 200 else ('', '')
        chosen = next((s for s in stmts if s['release_local']), stmts[0] if stmts else None)
        if chosen is not None and chosen['release_local']:
            local, source, fragment = chosen['release_local'], 'statement_page', chosen['time_fragment']
        elif pc_time:
            local, source, fragment = pc_time, 'press_conference_page', pc_fragment
        else:
            local, source, fragment = regular_schedule(day, pc_status == 200), 'regular_schedule', ''
        rows.append(dict(event_date=day.isoformat(), weekday=day.strftime('%A'), n_statement_pages=len(stmts),
                         statement_url=chosen['url'] if chosen else '', statement_title=chosen['title'] if chosen else '',
                         statement_http_status=chosen['status'] if chosen else 0,
                         press_conference=pc_status == 200, release_local_et=local, time_source=source,
                         time_fragment=fragment, zone_on_page=chosen['zone_on_page'] if chosen else '',
                         regular_schedule_et=regular_schedule(day, pc_status == 200),
                         zone_expected=zone_on(day)))
    return pd.DataFrame(rows), pd.DataFrame(listing), pd.DataFrame(others)


def verify_with_market(c, bars):
    statuses, ratios = [], []
    for r in c.itertuples():
        if not r.release_local_et:
            statuses.append('no_release_time'); ratios.append(np.nan); continue
        st, at = market_status(release_ratios(bars, to_utc(date.fromisoformat(r.event_date), r.release_local_et)))
        statuses.append(st); ratios.append(at)
    c = c.copy()
    c['release_utc'] = [to_utc(date.fromisoformat(d), t).isoformat() if t else '' for d, t in zip(c.event_date, c.release_local_et)]
    c['market_status'] = statuses
    c['market_ratio_at_release_bar'] = ratios
    best, best_ratio = [], []
    for r in c.itertuples():
        if r.time_source != 'regular_schedule':
            best.append(''); best_ratio.append(np.nan); continue
        d = date.fromisoformat(r.event_date)
        at = {slot: (release_ratios(bars, to_utc(d, slot)) or {0: np.nan})[0] for slot in SLOTS}
        k = max(at, key=lambda x: -np.inf if not np.isfinite(at[x]) else at[x])
        best.append(k); best_ratio.append(at[k])
    c['best_regular_slot'] = best
    c['best_regular_slot_ratio'] = best_ratio
    page = c.time_source.ne('regular_schedule')
    counts = c.loc[page, 'market_status'].value_counts().to_dict()
    confirmed = counts.get('confirmed_at_release_bar', 0); later = counts.get('reaction_only_after_release_bar', 0)
    semantics = 'interval_start' if confirmed >= 3 and confirmed >= 4*later else ('interval_end' if later >= 3 and later >= 4*confirmed else 'undetermined')
    return c, dict(page_evidenced_market_status=counts, implied_bar_label_semantics=semantics,
                   visible_threshold=VISIBLE, quiet_threshold=QUIET)


def review_reasons(r):
    reasons = []
    if r.statement_http_status != 200 or r.n_statement_pages == 0:
        reasons.append('statement_page_unresolved')
    if r.n_statement_pages > 1:
        reasons.append('multiple_statement_pages')
    if r.weekday in ('Saturday', 'Sunday'):
        reasons.append('weekend_announcement')
    if r.release_local_et and r.release_local_et != r.regular_schedule_et:
        reasons.append('nonstandard_time_candidate_unscheduled')
    if r.market_status in ('reaction_only_after_release_bar', 'activity_before_release_bar'):
        reasons.append('market_timing_disagreement')
    if (r.time_source == 'regular_schedule' and r.market_status != 'confirmed_at_release_bar'
            and r.best_regular_slot and r.best_regular_slot != r.release_local_et and r.best_regular_slot_ratio >= VISIBLE):
        reasons.append('market_prefers_other_regular_slot')
    if r.zone_on_page and r.zone_on_page != r.zone_expected:
        reasons.append('time_zone_label_differs_from_calendar')
    return '|'.join(reasons)


def candidates(out, fed_dir, start='2008-12-01', end='2026-03-19', cache_dir=None, fetcher=None):
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    s, e = date.fromisoformat(start), date.fromisoformat(end)
    fetcher = fetcher or Fetcher(cache_dir or out/'pages')
    c, listing, others = collect_candidates(fetcher, range(s.year, min(e.year, date.today().year-5)+1), s, e)
    others.to_csv(out/'fomc_non_statement_releases.csv', index=False)
    if c.empty:
        raise ValueError('FOMC_CANDIDATES_EMPTY: no statement links found on the calendar pages')
    bars = load_fed_bars(fed_dir)
    c, check = verify_with_market(c, bars)
    c['review_reasons'] = [review_reasons(r) for r in c.itertuples()]
    c['proposed_decision'] = np.where(c.review_reasons.eq(''), 'include_primary', '')
    c.to_csv(out/'fomc_calendar_candidates.csv', index=False)
    q = c[c.review_reasons.ne('')].copy()
    for col in REVIEW_COLUMNS:
        q[col] = ''
    q.to_csv(out/'fomc_review_queue.csv', index=False)
    listing.to_csv(out/'fomc_listing_pages.csv', index=False)
    pd.DataFrame(fetcher.log).to_csv(out/'fomc_fetch_log.csv', index=False)
    status = dict(status='fomc_candidates_not_verified', created_utc=datetime.now(timezone.utc).isoformat(),
                  n_candidates=int(len(c)), n_review=int(len(q)), n_page_time=int(c.time_source.ne('regular_schedule').sum()),
                  n_regular_schedule=int(c.time_source.eq('regular_schedule').sum()), market_check=check,
                  regular_schedule_rule='14:15 ET, or 12:30 ET on press-conference days, before 13 March 2013; 14:00 ET for all regularly scheduled meetings afterwards',
                  regular_schedule_source=SCHEDULE_SOURCE,
                  candidates_sha256=hashlib.sha256((out/'fomc_calendar_candidates.csv').read_bytes()).hexdigest())
    (out/'status.json').write_text(json.dumps(status, indent=2))
    print(json.dumps({k: v for k, v in status.items() if k != 'candidates_sha256'}, indent=2), flush=True)
    return status


def promote(candidates_dir, reviewed_queue, output, reviewer, rule):
    cdir = Path(candidates_dir)
    st = json.loads((cdir/'status.json').read_text())
    if hashlib.sha256((cdir/'fomc_calendar_candidates.csv').read_bytes()).hexdigest() != st['candidates_sha256']:
        raise ValueError('CANDIDATES_MODIFIED')
    c = pd.read_csv(cdir/'fomc_calendar_candidates.csv', dtype=str).fillna('')
    q = pd.read_csv(reviewed_queue, dtype=str).fillna('')
    if set(q.event_date) != set(c.loc[c.review_reasons.ne(''), 'event_date']):
        raise ValueError('REVIEW_QUEUE_MISMATCH: the reviewed queue does not cover exactly the flagged dates')
    empty = q[q.reviewer_decision.str.strip().eq('')]
    if len(empty):
        raise ValueError(f'REVIEW_INCOMPLETE: {len(empty)} flagged dates carry no reviewer_decision')
    bad = set(q.reviewer_decision.str.strip())-DECISIONS
    if bad:
        raise ValueError(f'UNUSABLE_DECISION: {sorted(bad)}')
    unsigned = q[q.reviewer.str.strip().eq('') | q.reviewed_on.str.strip().eq('') | q.reviewer_note.str.strip().eq('')]
    if len(unsigned):
        raise ValueError(f'REVIEW_UNSIGNED: {sorted(unsigned.event_date)[:5]}')
    q = q.set_index('event_date')
    rows = []
    for r in c.itertuples():
        if r.review_reasons == '':
            decision, when, note, who, on = 'include_primary', r.release_utc, 'promoted in bulk: time from page evidence, or from the documented regular schedule and not contradicted by the market', reviewer, datetime.now(timezone.utc).date().isoformat()
        else:
            x = q.loc[r.event_date]
            decision = x.reviewer_decision
            when = x.reviewer_event_datetime_utc or r.release_utc
            note, who, on = x.reviewer_note, x.reviewer, x.reviewed_on
            if decision != 'exclude' and not when:
                raise ValueError(f'MISSING_TIMESTAMP: {r.event_date}')
        rows.append(dict(event_date=r.event_date, release_utc=when, decision=decision,
                         primary=decision == 'include_primary', time_source=r.time_source,
                         statement_url=r.statement_url, market_status=r.market_status,
                         review_reasons=r.review_reasons, verification_status='verified', reviewer=who,
                         reviewed_on=on, reviewer_note=note, rule=rule))
    out = pd.DataFrame(rows)
    Path(output).parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(output, index=False)
    print(f'Promoted {len(out)} FOMC dates: {int(out.primary.sum())} primary, '
          f'{int(out.decision.eq("include_unscheduled").sum())} unscheduled, {int(out.decision.eq("exclude").sum())} excluded')
    return out


def main():
    p = argparse.ArgumentParser(prog='python -m confirmation_analysis.fomc_calendar')
    sub = p.add_subparsers(dest='mode', required=True)
    a = sub.add_parser('candidates')
    a.add_argument('--fed-dir', type=Path, required=True)
    a.add_argument('--output', type=Path, required=True)
    a.add_argument('--start', default='2008-12-01')
    a.add_argument('--end', default='2026-03-19')
    a.add_argument('--cache-dir', type=Path)
    b = sub.add_parser('promote')
    b.add_argument('--candidates', type=Path, required=True)
    b.add_argument('--reviewed-queue', type=Path, required=True)
    b.add_argument('--output', type=Path, required=True)
    b.add_argument('--reviewer', required=True)
    b.add_argument('--rule', required=True)
    x = p.parse_args()
    if x.mode == 'candidates':
        candidates(x.output, x.fed_dir, x.start, x.end, x.cache_dir)
    else:
        promote(x.candidates, x.reviewed_queue, x.output, x.reviewer, x.rule)


if __name__ == '__main__':
    main()
