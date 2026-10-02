import json
from pathlib import Path
from .decisions import load_decisions
from .protocol import digest, code_hashes, dump, specification, timestamp, new_output


def checked_manifest(directory, expected_status):
    directory = Path(directory)
    manifest = json.loads((directory/'status.json').read_text())
    if manifest.get('status') != expected_status or manifest.get('confirmation_outcomes_computed') is not False:
        raise ValueError('Wrong or incomplete outcome-free audit')
    if not manifest.get('table_hashes') or not manifest.get('source_hashes'):
        raise ValueError('Audit provenance is missing')
    for name, expected in manifest['table_hashes'].items():
        if Path(name).name != name or digest(directory/name) != expected:
            raise ValueError(f'Audit table changed: {name}')
    for path, expected in manifest['source_hashes'].items():
        if digest(path) != expected:
            raise ValueError(f'Audit input changed: {path}')
    if manifest.get('code_hashes') != code_hashes():
        raise ValueError('Audit code/specification changed; rerun quality audit')
    return manifest


def report(quality_dir, output, bridge_dir=None, build_dir=None, calibration_dir=None):
    out = new_output(output)
    checks = []
    def add(name, passed, detail):
        checks.append(dict(gate=name, passed=bool(passed), detail=detail))
    quality = checked_manifest(quality_dir, 'complete_quality_audit_not_frozen')
    add('price_and_window_diagnostics_completed', True, 'Diagnostic audit only, not approval of exclusions or cleaning.')
    add('ecb_calendar_complete', quality['verified_calendar_rows'] == quality['expected_calendar_rows'] > 0,
        'Every source date/phase needs official evidence, including absent conferences.')
    add('deep_bar_labels_verified', quality['all_nonempty_files_label_verified'],
        'Provider evidence per root/period, bound to representative hashes.')
    add('quality_and_session_review', False,
        'Review window exclusions, empty files, duplicate labels, spike flags and historical control sessions.')
    if bridge_dir is None:
        add('generation_bridge_available', False, 'Provide --bridge-dir from a generation-only run.')
    else:
        path = Path(bridge_dir)/'bridge_decision.json'
        bridge = json.loads(path.read_text())
        valid = (bridge.get('scope') == 'generation_2013_2025_only' and
            bridge.get('status') == 'bridge_complete_not_a_freeze' and
            bridge.get('confirmation_outcomes_computed') is False and
            bridge.get('draws') == specification()['bridge_draws'])
        tables = bridge.get('table_hashes', {})
        valid = valid and bool(tables)
        for name, expected in tables.items():
            if Path(name).name != name or digest(Path(bridge_dir)/name) != expected:
                valid = False
        current_hashes = code_hashes()
        for name in ['confirmation_analysis/bridge.py', 'confirmation_analysis/cones.py',
                     'confirmation_analysis/inference.py', 'final_analysis/models.py']:
            if bridge.get('code_hashes', {}).get(name) != current_hashes[name]:
                valid = False
        add('generation_bridge_available', valid,
            'Bridge diagnostic only; production draws and current bound code/tables are required.')
        add('bridge_source_decision_reviewed', bridge.get('selection_finalized') is True and valid,
            bridge.get('proposed_equity_rule', 'No proposed source rule.'))
    try:
        decisions = load_decisions()
    except ValueError as exc:
        decisions = None
        add('reviewed_decisions_file', False, str(exc))
    if decisions is not None:
        add('reviewed_decisions_file', True,
            '; '.join(f"{k}={v['choice']} ({v['reviewer']}, {v['decided_on']})" for k, v in decisions.items()))
        add('pre_pc_support_decision', True, decisions['pc_normal_pre_support']['rationale'])
        add('lagged_daily_rv_blinding', True, decisions['slow_state_rule']['rationale'])
        add('secondary_family_and_joint_interval', True, decisions['secondary_family_rule']['rationale'])
        add('us_release_calendar', decisions['us_calendar_status']['choice'] == 'verified_calendar_provided',
            decisions['us_calendar_status']['rationale'])
    for name, expected, detail in [
        ('protected_control_build', 'control_build_not_frozen',
         'Controls and event pre-quantities only; no event post-window price is read.'),
        ('outcome_free_calibration', 'calibration_complete_outcome_free',
         'Detectable effect sizes and the finite-history floor, simulated on control residuals.')]:
        directory = {'protected_control_build': build_dir, 'outcome_free_calibration': calibration_dir}[name]
        if directory is None:
            add(name, False, f'Not supplied. {detail}')
            continue
        try:
            manifest = json.loads((Path(directory)/'status.json').read_text())
            ok = manifest.get('status') == expected and manifest.get('confirmation_outcomes_computed') is False
            for table, expected_hash in manifest.get('table_hashes', {}).items():
                if digest(Path(directory)/table) != expected_hash:
                    ok = False
            add(name, ok, detail)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            add(name, False, f'{detail} ({exc})')
    add('external_window_timing', False,
        'Bind EA-EMPD baseline/endpoint times to source evidence; invalid extraordinary-event windows cannot be repaired by relabeling.')
    result = dict(status='blocked_before_confirmation_freeze', created_utc=timestamp(),
        confirmation_estimation_enabled=False, confirmation_outcomes_computed=False,
        quality_manifest_sha256=digest(Path(quality_dir)/'status.json'),
        code_hashes=code_hashes(), checks=checks,
        blocking_items=[c['gate'] for c in checks if not c['passed']])
    dump(out/'readiness.json', result)
    print(json.dumps(result, indent=2))
    return result
