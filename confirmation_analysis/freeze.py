import json
import platform
import subprocess
from pathlib import Path
import numpy as np
import pandas as pd
import scipy
from .calibrate import checked_build
from .decisions import load_decisions
from .protocol import REPO, digest, dump, timestamp, new_output, code_hashes, resolution_gate
from .windows import build_windows, load_ea_v2, indicators_v2


def git_state():
    sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True, capture_output=True).stdout.strip()
    dirty = bool(subprocess.run(['git', 'status', '--porcelain'], cwd=REPO, text=True, capture_output=True).stdout)
    return sha, dirty


def read_bridge(bridge_dir):
    path = Path(bridge_dir)/'bridge_decision.json'
    b = json.loads(path.read_text())
    if b.get('scope') != 'generation_2013_2025_only' or b.get('confirmation_outcomes_computed') is not False:
        raise ValueError('Bridge decision is not a generation-only diagnostic')
    for name, expected in b.get('table_hashes', {}).items():
        if digest(Path(bridge_dir)/name) != expected:
            raise ValueError(f'Bridge table changed: {name}')
    return b, digest(path)


def resolve_specification(spec, decisions, calibration, bridge):
    family = spec['primary_family']; secondary = spec['secondary_family']
    for fam in (family, secondary):
        gate = resolution_gate(fam['draws'], fam['size'], fam['alpha'])
        if not gate['pass_resolution']:
            raise ValueError(f'RESOLUTION_GATE: {fam["name"]} cannot reject at its Holm threshold')
    expected = 2*sum(len(spec['eras']) if test['kind'] == 'era' else 1 for test in secondary['tests'])
    if expected != secondary['size']:
        raise ValueError(f'Secondary family size {secondary["size"]} does not match its {expected} declared tests')
    resolved = dict(spec)
    resolved.update(status='frozen_v2', confirmation_outcomes_may_be_read=True,
        decisions={k: v for k, v in decisions.items()},
        confirmation_equity_source=decisions['equity_source_rule']['choice'],
        history_calibrated_margin=calibration['history_calibrated_margin'],
        primary_delta_80=calibration['primary_delta_80'],
        calibration_status=calibration['status'], calibration_caveat=calibration['caveat'],
        bridge_checks=bridge['checks'], bridge_correlation=bridge['correlation'],
        bridge_proposed_equity_rule=bridge['proposed_equity_rule'],
        us_calendar_status=decisions['us_calendar_status']['choice'],
        primary_resolution=resolution_gate(family['draws'], family['size'], family['alpha']),
        secondary_resolution=resolution_gate(secondary['draws'], secondary['size'], secondary['alpha']))
    return resolved


def freeze(quality_dir, data_root, build_dir, calibration_dir, bridge_dir, destination, spec, already_opened=None):
    destination = Path(destination)
    if destination.exists():
        raise FileExistsError(f'Refusing to replace a frozen build: {destination}')
    decisions = load_decisions()
    build_manifest = checked_build(build_dir, 'control_build_not_frozen')
    calibration = checked_build(calibration_dir, 'calibration_complete_outcome_free')
    if calibration['build_manifest_sha256'] != digest(Path(build_dir)/'status.json'):
        raise ValueError('Calibration does not belong to this protected build')
    if build_manifest['quality_manifest_sha256'] != digest(Path(quality_dir)/'status.json'):
        raise ValueError('Protected build does not belong to this quality audit')
    if build_manifest['decisions'] != {k: v['choice'] for k, v in decisions.items()}:
        raise ValueError('Decisions changed after the protected build; rebuild')
    bridge, bridge_sha = read_bridge(bridge_dir)
    opened = None
    if already_opened is not None:
        prior = json.loads((Path(already_opened)/'status.json').read_text())
        if prior.get('status') not in ('frozen_v2', 'frozen_after_opening'):
            raise ValueError('already_opened must point to a frozen build whose outcomes were estimated')
        opened = dict(path=str(Path(already_opened).resolve()), status_sha256=digest(Path(already_opened)/'status.json'),
                      note='Confirmation outcomes for 2000-2012 were read once from this build; the present build is a '
                           're-estimation after opening and cannot carry confirmatory weight.')
    resolved = resolve_specification(spec, decisions, calibration, bridge)
    resolved['opened_from'] = opened
    if opened:
        resolved['status'] = 'frozen_after_opening'
    destination.mkdir(parents=True)
    dump(destination/'status.json', dict(status='freezing', confirmation_outcomes_computed=False))
    w, quality_manifest = build_windows(quality_dir, data_root, spec, decisions, blinded=False)
    ea = load_ea_v2(data_root, spec)
    indicators, scales, external = indicators_v2(w, ea, spec, decisions['equity_source_rule']['choice'])
    dates = sorted(ea.event_date.unique())
    registry = pd.MultiIndex.from_product([dates, spec['roots'], ['PR', 'PC']],
                                          names=['trade_date', 'root_code', 'phase']).to_frame(index=False)
    registry = registry.merge(w[w.is_event], on=['trade_date', 'root_code', 'phase'], how='left', validate='one_to_one')
    registry = registry.merge(indicators, on=['trade_date', 'phase'], how='left', validate='many_to_one')
    registry['price_status'] = np.select(
        [registry.input_path.isna(), ~registry.certified_event_price_eligibility.astype('boolean').fillna(False).to_numpy(bool),
         registry.post_coverage.lt(1)],
        ['no_candidate_contract', 'not_certified', 'missing_post_pair'], default='eligible')
    registry['primary_asset'] = registry.root_code.eq(spec['primary_root'])
    registry['era'] = np.where(registry.trade_date <= spec['eras']['early'][1], 'early', 'late')
    tables = {'windows': w, 'indicators': indicators, 'indicator_scales': scales, 'event_registry': registry,
              'ea_source': ea, 'preferred_contracts': w[w.phase.eq('PR')][['trade_date', 'root_code', 'input_path', 'is_event']]}
    for name, t in tables.items():
        t.to_csv(destination/f'{name}.csv', index=False)
    resolved['external_scales'] = external
    dump(destination/'specification.json', resolved)
    dump(destination/'decisions.json', decisions)
    sha, dirty = git_state()
    stamp = dict(schema_version='final_analysis_v2',
        status='frozen_after_opening' if opened else 'frozen_v2', created_utc=timestamp(),
        confirmation_outcomes_computed=True, confirmation_outcomes_read_before_freeze=bool(opened),
        prior_results_seen={'generation_2013_2025': True, 'confirmation_2000_2012': bool(opened)},
        opened_from=opened,
        git_sha=sha, git_dirty=dirty, code_hashes=code_hashes(),
        source_hashes=quality_manifest['source_hashes'],
        quality_manifest_sha256=digest(Path(quality_dir)/'status.json'),
        build_manifest_sha256=digest(Path(build_dir)/'status.json'),
        calibration_manifest_sha256=digest(Path(calibration_dir)/'status.json'),
        bridge_decision_sha256=bridge_sha, decisions_sha256=digest(destination/'decisions.json'),
        table_hashes={f'{n}.csv': digest(destination/f'{n}.csv') for n in tables},
        specification_sha256=digest(destination/'specification.json'),
        n_calendar_events=int(registry.trade_date.nunique()),
        n_primary_pr_eligible=int((registry.primary_asset & registry.phase.eq('PR') & registry.price_status.eq('eligible')).sum()),
        python=platform.python_version(), numpy=np.__version__, pandas=pd.__version__, scipy=scipy.__version__)
    dump(destination/'status.json', stamp)
    print(json.dumps({k: v for k, v in stamp.items() if k not in ['code_hashes', 'source_hashes', 'table_hashes']}, indent=2), flush=True)
    return stamp
