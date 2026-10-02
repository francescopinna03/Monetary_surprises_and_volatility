import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[1]
SPEC = REPO/'Raw/Certification/final_analysis_spec_v2.json'


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''):
            h.update(block)
    return h.hexdigest()


def dump(path, obj):
    Path(path).write_text(json.dumps(obj, indent=2, sort_keys=True, allow_nan=False)+'\n')


def specification():
    return json.loads(SPEC.read_text())


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def new_output(path):
    path = Path(path)
    path.mkdir(parents=True, exist_ok=False)
    return path


def code_hashes():
    paths = list((REPO/'confirmation_analysis').glob('*.py'))
    paths += list((REPO/'final_analysis').glob('*.py')) + [SPEC]
    return {str(p.relative_to(REPO)): digest(p) for p in sorted(paths)}


def parse_contract(name, current_year=None):
    current_year = current_year or datetime.now(timezone.utc).year
    m = re.fullmatch(r'(fx|gg|hf|hr)([hmuz])(\d{2})_intraday-(\d+)min_historical-data-(\d{2})-(\d{2})-(\d{4})\.csv', name.lower())
    if not m:
        raise ValueError('unrecognized_contract_filename')
    root, expiry, yy, minutes, month, day, year = m.groups()
    contract_year = 1999 if yy == '99' else 2000 + int(yy)
    if not 1999 <= contract_year <= current_year:
        raise ValueError('contract_year_outside_allowed_range')
    if int(minutes) != 5:
        raise ValueError('not_five_minute_data')
    datetime(int(year), int(month), int(day))
    return dict(root_code=root, expiry_code=expiry.upper(), contract_year=contract_year)


def resolution_gate(draws, hypotheses, alpha=.05):
    if draws < 1 or hypotheses < 1 or not 0 < alpha < 1:
        raise ValueError('Invalid family definition')
    return dict(draws=int(draws), hypotheses=int(hypotheses), p_min=1/(draws+1),
                first_holm_threshold=alpha/hypotheses,
                pass_resolution=bool(1/(draws+1) <= alpha/hypotheses))


def generation_mask(dates):
    d = pd.to_datetime(dates)
    return (d >= pd.Timestamp('2013-01-01')) & (d < pd.Timestamp('2026-01-01'))


def assert_generation_events(dates):
    if not generation_mask(dates).all():
        raise ValueError('BRIDGE_CONFIRMATION_LEAKAGE: event outcomes outside 2013-2025')


def clock_reference():
    rows = []
    for day, expected in [('2004-04-01', 8), ('2004-11-04', 7), ('2007-11-01', 6),
                          ('2006-03-30', 8), ('2007-03-29', 7)]:
        local = pd.Timestamp(day+' 13:45').tz_localize('Europe/Berlin')
        chicago = local.tz_convert('America/Chicago')
        delta = (local.utcoffset()-chicago.utcoffset()).total_seconds()/3600
        if delta != expected:
            raise ValueError('Historical IANA clock self-test failed')
        rows.append(dict(date=day, berlin_wall=str(local), chicago_wall=str(chicago),
                         utc=str(local.tz_convert('UTC')), offset_hours=delta,
                         expected_offset_hours=expected, passed=True))
    return pd.DataFrame(rows)
