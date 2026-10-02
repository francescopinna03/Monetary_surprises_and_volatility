import json
import re
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin
from urllib.request import Request, urlopen
import hashlib
import numpy as np
import pandas as pd
from .audit import CALENDAR_COLUMNS, source_events
from .protocol import digest, dump, timestamp, new_output, code_hashes

BASE = 'https://www.ecb.europa.eu'
DECISIONS_INDEX = BASE + '/press/govcdec/mopo/{year}/html/index_include.en.html'
STATEMENTS_INDEX = BASE + '/press/press_conference/monetary-policy-statement/{year}/html/index_include.en.html'
USER_AGENT = 'Monetary-surprises-confirmation/2.0 (academic replication; contact via repository)'
REGULAR_WALL = {'PR': '13:45', 'PC': '14:30'}
TIMING_EXCEPTIONS = ('2001-09-17', '2008-10-08')
DECISION_TITLE = re.compile(r'monetary\s+policy\s+decisions', re.I)
STATEMENT_TITLE = re.compile(r'(?:introductory|monetary\s+policy)\s+statement', re.I)
PUBLISHED = re.compile(r'<meta\s+property="article:published_time"\s+content="(\d{4}-\d{2}-\d{2})', re.I)
PUB_DATE_DIV = re.compile(r'<div class="ecb-pressContentPubDate">\s*(.*?)\s*</div>', re.I | re.S)
REVIEW_COLUMNS = ['reviewer_decision', 'reviewer_event_datetime_utc', 'reviewer', 'reviewed_on', 'reviewer_note']


class IndexParser(HTMLParser):

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.entries = []
        self.date = None
        self.field = None
        self.depth = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'dt' and 'isodate' in a:
            self.date = a['isodate']
        elif tag == 'div' and a.get('class') in ('title', 'subtitle') and self.date:
            self.field = a['class']
            self.depth = 0
            if self.field == 'title':
                self.entries.append(dict(iso_date=self.date, href='', title='', subtitle=''))
        elif tag == 'div' and self.field:
            self.depth += 1
        elif tag == 'a' and self.field == 'title' and self.entries and not self.entries[-1]['href']:
            self.entries[-1]['href'] = a.get('href', '')

    def handle_endtag(self, tag):
        if tag == 'div' and self.field:
            if self.depth:
                self.depth -= 1
            else:
                self.field = None

    def handle_data(self, data):
        if self.field and self.entries:
            self.entries[-1][self.field] += data.replace('\xa0', ' ')


class PageParser(HTMLParser):

    SKIP = {'script', 'style', 'nav', 'head'}

    def __init__(self, fragment_chars=220):
        super().__init__(convert_charrefs=True)
        self.title = ''
        self.headline = ''
        self.text = []
        self.fragment_chars = fragment_chars
        self.mode = None
        self.skip = 0
        self.seen_headline = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in self.SKIP:
            self.skip += 1
        elif tag == 'title':
            self.mode = 'title'
        elif tag == 'h1' and 'ecb-pressContentTitle' in a.get('class', ''):
            self.mode = 'headline'

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skip:
            self.skip -= 1
        elif tag in ('title', 'h1'):
            if self.mode == 'headline':
                self.seen_headline = True
            self.mode = None

    def handle_data(self, data):
        if self.skip:
            return
        if self.mode == 'title':
            self.title += data.strip()
        elif self.mode == 'headline':
            self.headline += data.strip()
        elif self.seen_headline and sum(len(s) for s in self.text) < self.fragment_chars:
            stripped = ' '.join(data.split())
            if stripped:
                self.text.append(stripped)

    @property
    def fragment(self):
        return ' '.join(self.text)[:self.fragment_chars]


def default_fetch(url, timeout=30):
    request = Request(url, headers={'User-Agent': USER_AGENT, 'Accept': 'text/html'})
    try:
        with urlopen(request, timeout=timeout) as response:
            return dict(url=url, final_url=response.geturl(), status=int(response.status),
                        body=response.read(), error='')
    except HTTPError as exc:
        return dict(url=url, final_url=url, status=int(exc.code), body=exc.read() or b'', error=str(exc))
    except (URLError, TimeoutError, OSError) as exc:
        return dict(url=url, final_url=url, status=0, body=b'', error=str(exc))


def caching_fetch(cache_dir, fetch=default_fetch, delay=0.5):
    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    state = {'last': 0.0}

    def get(url):
        name = hashlib.sha256(url.encode()).hexdigest()[:32] + '.html'
        path = cache_dir/name
        if path.exists():
            body = path.read_bytes()
            return dict(url=url, final_url=url, status=200, body=body, error='', cached=True,
                        sha256=hashlib.sha256(body).hexdigest(), local_path=str(path))
        wait = delay - (time.monotonic()-state['last'])
        if wait > 0:
            time.sleep(wait)
        state['last'] = time.monotonic()
        result = fetch(url)
        if result['status'] == 200 and result['body']:
            path.write_bytes(result['body'])
        return dict(result, cached=False, sha256=hashlib.sha256(result['body']).hexdigest(),
                    local_path=str(path) if result['status'] == 200 else '')
    return get


def read_index(get, url):
    page = get(url)
    if page['status'] != 200:
        raise ValueError(f'ECB index did not resolve: {url} (status {page["status"]})')
    parser = IndexParser()
    parser.feed(page['body'].decode('utf-8', errors='replace'))
    rows = []
    for entry in parser.entries:
        if not entry['href']:
            continue
        rows.append(dict(iso_date=entry['iso_date'], url=urljoin(BASE, entry['href'].strip()),
                         index_title=' '.join(entry['title'].split()),
                         index_subtitle=' '.join(entry['subtitle'].split()), index_url=url))
    return pd.DataFrame(rows).drop_duplicates(['iso_date', 'url'])


def inspect_page(get, url, expected_date):
    page = get(url)
    body = page['body'].decode('utf-8', errors='replace') if page['body'] else ''
    parser = PageParser()
    if body:
        parser.feed(body)
    published = PUBLISHED.search(body)
    pub_div = PUB_DATE_DIV.search(body)
    printed = ' '.join(pub_div.group(1).split()) if pub_div else ''
    page_date = published.group(1) if published else ''
    if page_date:
        agrees = page_date == expected_date
    elif printed:
        parsed = pd.to_datetime(printed, errors='coerce', dayfirst=True)
        agrees = bool(pd.notna(parsed) and parsed.strftime('%Y-%m-%d') == expected_date)
    else:
        agrees = False
    return dict(source_url=url, http_status=page['status'], page_title=parser.title,
                page_headline=parser.headline, page_date=page_date, page_printed_date=printed,
                page_date_agrees=agrees, text_fragment=parser.fragment,
                page_sha256=page['sha256'], cached=page.get('cached', False))


def collect(years, get):
    decisions, statements, pages = [], [], []
    for year in years:
        decisions.append(read_index(get, DECISIONS_INDEX.format(year=year)).assign(archive='decisions'))
        statements.append(read_index(get, STATEMENTS_INDEX.format(year=year)).assign(archive='statements'))
    listed = pd.concat(decisions+statements, ignore_index=True)
    for row in listed.itertuples():
        pages.append(dict(archive=row.archive, iso_date=row.iso_date, index_url=row.index_url,
                          index_title=row.index_title, index_subtitle=row.index_subtitle,
                          **inspect_page(get, row.url, row.iso_date)))
    return pd.DataFrame(pages)


def classify(pages):
    t = pages.copy()
    titles = (t.page_headline.fillna('')+' '+t.index_title.fillna('')).str.strip()
    t['is_decision_release'] = t.archive.eq('decisions') & titles.str.contains(DECISION_TITLE)
    t['is_policy_statement'] = t.archive.eq('statements') & titles.str.contains(STATEMENT_TITLE)
    t['title_recognised'] = np.where(t.archive.eq('decisions'), t.is_decision_release, t.is_policy_statement)
    return t


def regular_instant(date, phase):
    wall = pd.Timestamp(f'{date} {REGULAR_WALL[phase]}').tz_localize('Europe/Berlin')
    return wall.tz_convert('UTC').isoformat()


def candidate_rows(pages):
    p = classify(pages)
    resolved = p[p.http_status.eq(200) & p.page_date_agrees & p.title_recognised]
    decision_dates = sorted(resolved[resolved.archive.eq('decisions')].iso_date.unique())
    statements = resolved[resolved.archive.eq('statements')].set_index('iso_date')
    unresolved = p[p.http_status.ne(200) | ~p.page_date_agrees | ~p.title_recognised]
    rows = []
    for date in decision_dates:
        release = resolved[resolved.archive.eq('decisions') & resolved.iso_date.eq(date)].iloc[0]
        exception = date in TIMING_EXCEPTIONS
        for phase in ('PR', 'PC'):
            if phase == 'PR':
                present, evidence, page = 'true', 'release_resolved_and_date_agrees', release
            elif date in statements.index:
                present, evidence, page = 'true', 'statement_resolved_and_date_agrees', statements.loc[date]
                page = page.iloc[0] if isinstance(page, pd.DataFrame) else page
            else:
                present, evidence, page = 'false', 'statement_absent_from_annual_index', release
            basis = 'requires_specific_evidence' if exception else f'regular_schedule_{REGULAR_WALL[phase]}_Europe_Berlin'
            instant = '' if exception or present != 'true' else regular_instant(date, phase)
            rows.append(dict(event_date=date, phase=phase, verification_status='candidate',
                proposed_actual_phase_present=present, actual_phase_present='',
                event_datetime_utc=instant, timestamp_basis=basis, evidence_status=evidence,
                source_url=page.source_url if present == 'true' else release.source_url,
                evidence_index_url=page.index_url, page_title=page.page_title,
                page_headline=page.page_headline, page_date=page.page_date,
                text_fragment=page.text_fragment, page_sha256=page.page_sha256,
                weekday=pd.Timestamp(date).day_name(),
                notes='timing exception: the source window is known not to be the regular schedule' if exception else ''))
    table = pd.DataFrame(rows)
    for column in CALENDAR_COLUMNS:
        if column not in table:
            table[column] = ''
    return table, unresolved.copy()


def reconcile(candidates, ea):
    source = ea.groupby(['event_date', 'phase']).size().unstack(fill_value=0)
    proposed = candidates.pivot(index='event_date', columns='phase', values='proposed_actual_phase_present')
    dates = sorted(set(source.index) | set(proposed.index))
    rows = []
    for date in dates:
        row = dict(event_date=date, weekday=pd.Timestamp(date).day_name())
        for phase in ('PR', 'PC'):
            row[f'ecb_{phase}'] = str(proposed.get(phase, pd.Series(dtype=str)).get(date, ''))
            row[f'ea_empd_{phase}'] = bool(source.get(phase, pd.Series(dtype=int)).get(date, 0))
        reasons = []
        if date not in proposed.index:
            reasons.append('date_absent_from_ecb_decisions_index')
        if date not in source.index:
            reasons.append('date_absent_from_ea_empd')
        for phase in ('PR', 'PC'):
            if row[f'ecb_{phase}'] == 'true' and not row[f'ea_empd_{phase}']:
                reasons.append(f'{phase}_in_ecb_not_in_ea_empd')
            if row[f'ecb_{phase}'] == 'false' and row[f'ea_empd_{phase}']:
                reasons.append(f'{phase}_window_in_ea_empd_without_an_ecb_statement')
        row['discrepancy'] = '|'.join(reasons)
        rows.append(row)
    return pd.DataFrame(rows)


def review_queue(candidates, reconciliation, unresolved, seed, ordinary_sample=20):
    c = candidates.copy()
    c['event_month'] = c.event_date.str[:7]
    decisions_per_month = c[c.phase.eq('PR')].groupby('event_month').event_date.nunique()
    early = c.event_date.lt('2002-01-01')
    crowded = c.event_month.map(decisions_per_month).gt(1)
    strata = {
        'timing_exception': c.event_date.isin(TIMING_EXCEPTIONS),
        'anomalous_weekday': c.weekday.ne('Thursday'),
        'multiple_meetings_in_month_2000_2001': early & crowded,
        'proposed_absence': c.proposed_actual_phase_present.eq('false'),
        'reconciliation_discrepancy': c.event_date.isin(
            reconciliation.loc[reconciliation.discrepancy.ne(''), 'event_date']),
    }
    reasons = {i: [] for i in c.index}
    for name, mask in strata.items():
        for i in c.index[mask]:
            reasons[i].append(name)
    c['review_reasons'] = ['|'.join(reasons[i]) for i in c.index]
    opened = c[c.review_reasons.ne('')].copy()
    ordinary = c[c.review_reasons.eq('')]
    if len(ordinary):
        drawn = ordinary.sample(min(ordinary_sample, len(ordinary)), random_state=seed % 2**32)
        drawn = drawn.assign(review_reasons='random_ordinary_extractor_validation')
        opened = pd.concat([opened, drawn], ignore_index=True)
    extra = unresolved.assign(event_date=unresolved.iso_date, phase='',
                              proposed_actual_phase_present='', evidence_status='unresolved_evidence',
                              review_reasons='unresolved_evidence', verification_status='candidate',
                              weekday=pd.to_datetime(unresolved.iso_date).dt.day_name())
    orphan = reconciliation[reconciliation.discrepancy.ne('') & ~reconciliation.event_date.isin(c.event_date)]
    orphan = orphan.assign(phase='', proposed_actual_phase_present='',
                           evidence_status='reconciliation_'+orphan.discrepancy,
                           review_reasons='reconciliation_discrepancy', verification_status='candidate')
    columns = ['review_reasons', 'event_date', 'phase', 'weekday', 'proposed_actual_phase_present',
               'evidence_status', 'timestamp_basis', 'source_url', 'page_title', 'page_headline',
               'page_date', 'http_status', 'text_fragment', 'page_sha256']
    queue = pd.concat([opened, extra, orphan], ignore_index=True)
    for column in columns:
        if column not in queue:
            queue[column] = ''
    queue = queue[columns].sort_values(['review_reasons', 'event_date', 'phase'])
    for column in REVIEW_COLUMNS:
        queue[column] = ''
    return queue.reset_index(drop=True)


def build_candidates(data_root, out, years=range(2000, 2013), cache_dir=None, fetch=default_fetch,
                     seed=20260912, ordinary_sample=20):
    data_root = Path(data_root)
    out = new_output(out)
    get = caching_fetch(cache_dir or out/'pages', fetch)
    pages = collect(list(years), get)
    candidates, unresolved = candidate_rows(pages)
    ea = source_events(data_root/'Raw/EA-EMPD/EA-EMPD.xlsx')
    reconciliation = reconcile(candidates, ea)
    queue = review_queue(candidates, reconciliation, unresolved, seed, ordinary_sample)
    tables = {'ecb_pages': classify(pages), 'ecb_calendar_candidates': candidates,
              'ecb_calendar_reconciliation': reconciliation, 'ecb_calendar_review_queue': queue}
    for name, table in tables.items():
        table.to_csv(out/f'{name}.csv', index=False)
    status = dict(status='calendar_candidates_not_verified', created_utc=timestamp(),
        confirmation_outcomes_computed=False, verification_status_written='candidate',
        years=[int(y) for y in years], n_pages=len(pages), n_unresolved_pages=len(unresolved),
        n_decision_dates=int(candidates.phase.eq('PR').sum()),
        n_proposed_conferences=int((candidates.phase.eq('PC') & candidates.proposed_actual_phase_present.eq('true')).sum()),
        n_proposed_absences=int(candidates.proposed_actual_phase_present.eq('false').sum()),
        n_ea_empd_dates=int(ea.event_date.nunique()), n_open_review_rows=len(queue),
        review_strata={k: int(v) for k, v in queue.review_reasons.value_counts().items()},
        n_discrepancies=int(reconciliation.discrepancy.ne('').sum()),
        timestamp_caveat='Dates and occurrence come from the ECB archives; the time of day is the historical regular schedule, not page evidence.',
        table_hashes={p.name: digest(p) for p in out.glob('*.csv')}, code_hashes=code_hashes())
    dump(out/'status.json', status)
    print(json.dumps({k: v for k, v in status.items() if k not in ('code_hashes', 'table_hashes')}, indent=2), flush=True)
    return status


def promote(candidates_dir, reviewed_queue, output, reviewer, rule):
    candidates_dir = Path(candidates_dir)
    if not str(reviewer).strip() or not str(rule).strip():
        raise ValueError('PROMOTION_UNSIGNED: a reviewer name and a written rule are required')
    manifest = json.loads((candidates_dir/'status.json').read_text())
    if manifest.get('status') != 'calendar_candidates_not_verified':
        raise ValueError('Expected a candidate calendar directory')
    for name, expected in manifest['table_hashes'].items():
        if Path(name).name != name or digest(candidates_dir/name) != expected:
            raise ValueError(f'Candidate table changed: {name}')
    c = pd.read_csv(candidates_dir/'ecb_calendar_candidates.csv', dtype=str).fillna('')
    q = pd.read_csv(reviewed_queue, dtype=str).fillna('')
    for column in REVIEW_COLUMNS:
        if column not in q:
            raise ValueError(f'Review queue is missing {column}')
    open_rows = q[q.reviewer_decision.str.strip().eq('')]
    if len(open_rows):
        raise ValueError(f'REVIEW_INCOMPLETE: {len(open_rows)} queue rows carry no reviewer_decision')
    if q.reviewer.str.strip().eq('').any():
        raise ValueError('REVIEW_UNSIGNED: every reviewed row needs a reviewer')
    bad = set(q.reviewer_decision.str.strip()) - {'true', 'false', 'exclude'}
    if bad:
        raise ValueError(f'REVIEW_UNDECIDED: unknown reviewer_decision {sorted(bad)}')
    phaseless = q[q.phase.eq('') & q.reviewer_decision.str.strip().ne('exclude')]
    if len(phaseless):
        raise ValueError('UNUSABLE_DECISION: '+', '.join(sorted(phaseless.event_date.unique()))
                         + ' has no resolved evidence row; resolve the page and rerun, or exclude it')
    decided = q[q.phase.ne('')].set_index(['event_date', 'phase'])
    if decided.index.duplicated().any():
        raise ValueError('Duplicate reviewed queue key')
    known = set(zip(c.event_date, c.phase))
    stray = [key for key in decided.index if key not in known]
    if stray:
        raise ValueError(f'UNMATCHED_DECISION: reviewed rows without a candidate: {sorted(stray)}')
    rows = []
    for row in c.itertuples():
        key = (row.event_date, row.phase)
        if key in decided.index:
            r = decided.loc[key]
            if r.reviewer_decision == 'exclude':
                continue
            present, who, note = r.reviewer_decision, r.reviewer, r.reviewer_note
            instant = r.reviewer_event_datetime_utc.strip() or row.event_datetime_utc
            basis = 'reviewer_supplied_evidence' if r.reviewer_event_datetime_utc.strip() else row.timestamp_basis
        else:
            if row.proposed_actual_phase_present != 'true':
                raise ValueError(f'UNREVIEWED_ABSENCE: {key} proposes an absence and was not individually reviewed')
            if row.evidence_status not in ('release_resolved_and_date_agrees', 'statement_resolved_and_date_agrees'):
                raise ValueError(f'UNREVIEWED_EVIDENCE: {key} carries {row.evidence_status}')
            present, who, note, instant, basis = 'true', reviewer, '', row.event_datetime_utc, row.timestamp_basis
        if present == 'true' and not instant:
            raise ValueError(f'MISSING_TIMESTAMP: {key} is present but has no event_datetime_utc')
        rows.append(dict(event_date=row.event_date, phase=row.phase, actual_phase_present=present,
            event_datetime_utc=instant if present == 'true' else '', source_url=row.source_url,
            verification_status='verified', notes=note, timestamp_basis=basis,
            evidence_status=row.evidence_status, page_title=row.page_title, page_date=row.page_date,
            text_fragment=row.text_fragment, page_sha256=row.page_sha256, reviewer=who,
            promotion_rule=rule))
    verified = pd.DataFrame(rows)[CALENDAR_COLUMNS+['timestamp_basis', 'evidence_status', 'page_title',
                                                    'page_date', 'text_fragment', 'page_sha256',
                                                    'reviewer', 'promotion_rule']]
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    verified.to_csv(output, index=False)
    record = dict(status='calendar_verified_by_named_reviewer', created_utc=timestamp(),
        reviewer=reviewer, rule=rule, candidates_status_sha256=digest(candidates_dir/'status.json'),
        reviewed_queue_sha256=digest(reviewed_queue), output_sha256=digest(output),
        n_rows=len(verified), n_individually_reviewed=int(len(decided)),
        n_present=int(verified.actual_phase_present.eq('true').sum()),
        n_absent=int(verified.actual_phase_present.eq('false').sum()),
        timestamp_caveat=manifest['timestamp_caveat'], code_hashes=code_hashes())
    dump(output.with_name(output.stem+'_promotion.json'), record)
    print(json.dumps({k: v for k, v in record.items() if k != 'code_hashes'}, indent=2), flush=True)
    return record
