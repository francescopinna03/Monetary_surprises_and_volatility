import json
from pathlib import Path
import pandas as pd
from .protocol import REPO, dump

DECISIONS = REPO/'Raw/Certification/confirmation_decisions_v2.json'

ADMISSIBLE = {
    'pc_normal_pre_support': ['v1_grid_endpoints_minus25_to_minus5_support_minus30_to_minus5'],
    'slow_state_rule': ['event_day_excluded_previous_five_control_days'],
    'equity_source_rule': ['homogeneous_external_stoxx50e_2000_2012',
                           'hybrid_fx_futures_when_available_else_stoxx50e'],
    'secondary_family_rule': ['spec_secondary_family_verbatim_single_joint_history_block'],
    'us_calendar_status': ['candidate_screen_only', 'verified_calendar_provided'],
}

CONTEXT = {
    'pc_normal_pre_support': 'The v1 generation build and the bridge use PC pre endpoints -25..-5, i.e. support (-30,-5]. The plan prose said (-25,-5].',
    'slow_state_rule': 'v1 slow5 averaged full-day RV of the five previous selected contract-days, including event days and hence their post-announcement outcomes.',
    'equity_source_rule': 'fx futures exist from June 2011 only. STOXX50E from EA-EMPD passed bridge checks 1-2 and failed checks 3-4 on generation data.',
    'secondary_family_rule': 'The finite secondary list lives in the specification; the sufficiency interval is one joint history block, reported as an interval and not as a claim.',
    'us_calendar_status': 'A Thursday 08:30 New York candidate screen is not a verified release calendar.',
}


def template():
    return {key: dict(choice='', admissible=values, context=CONTEXT[key], reviewer='',
                      decided_on='', rationale='') for key, values in ADMISSIBLE.items()}


def write_template(path=DECISIONS):
    path = Path(path)
    if path.exists():
        raise FileExistsError(f'Refusing to overwrite decisions: {path}')
    dump(path, template())
    return path


def load_decisions(path=DECISIONS):
    path = Path(path)
    if not path.is_file():
        raise ValueError('DECISIONS_MISSING: write and review Raw/Certification/confirmation_decisions_v2.json')
    raw = json.loads(path.read_text())
    out = {}
    for key, values in ADMISSIBLE.items():
        entry = raw.get(key)
        if not isinstance(entry, dict):
            raise ValueError(f'DECISION_MISSING: {key}')
        choice = str(entry.get('choice', '')).strip()
        if choice not in values:
            raise ValueError(f'DECISION_INADMISSIBLE: {key}={choice!r}; admissible {values}')
        for field in ('reviewer', 'rationale'):
            if not str(entry.get(field, '')).strip():
                raise ValueError(f'DECISION_UNREVIEWED: {key} needs a {field}')
        try:
            decided = pd.Timestamp(entry.get('decided_on', ''))
        except (ValueError, TypeError):
            decided = pd.NaT
        if pd.isna(decided):
            raise ValueError(f'DECISION_UNDATED: {key} needs decided_on (YYYY-MM-DD)')
        out[key] = dict(choice=choice, reviewer=str(entry['reviewer']).strip(),
                        decided_on=decided.strftime('%Y-%m-%d'), rationale=str(entry['rationale']).strip())
    return out
