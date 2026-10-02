import argparse
import json
import os
from pathlib import Path
import subprocess
from datetime import datetime
from zipfile import ZipFile, ZIP_DEFLATED
from .protocol import REPO, dump
from .quality import quality_audit
from .readiness import report


def inventory_path(data_root, explicit=None):
    if explicit is not None:
        path = Path(explicit).expanduser().resolve()
        if (path/'audit/status.json').is_file():
            path = path/'audit'
        if not (path/'status.json').is_file():
            raise ValueError('Inventory status.json missing')
        return path
    candidates = []
    for path in (data_root/'Output').glob('confirmation_inventory_*/audit/status.json'):
        manifest = json.loads(path.read_text())
        if manifest.get('status') == 'complete_metadata_audit_not_frozen':
            candidates.append(path)
    if not candidates:
        raise ValueError('No successful inventory found; run Run_confirmation_inventory.sh first')
    return max(candidates, key=lambda p: p.parent.parent.name).parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-root', type=Path, required=True)
    parser.add_argument('--audit-dir', type=Path)
    parser.add_argument('--canonical-raw-dir', type=Path)
    parser.add_argument('--bridge-dir', type=Path)
    parser.add_argument('--build-dir', type=Path)
    parser.add_argument('--calibration-dir', type=Path)
    args = parser.parse_args()
    run = args.run_root.expanduser().resolve()
    data = run/'Econometrics_data'
    if not (data/'Raw/EA-EMPD/EA-EMPD.xlsx').is_file():
        raise ValueError('EA-EMPD source missing in the existing run')
    inventory = inventory_path(data, args.audit_dir)
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + str(os.getpid())
    out = data/'Output'/('confirmation_quality_'+stamp)
    out.mkdir(parents=True, exist_ok=False)
    archive = run.parent/(run.name+'_confirmation_quality_'+stamp+'.zip')
    code = 1
    try:
        dump(out/'run_inputs.json', dict(inventory=str(inventory), data_root=str(data),
            canonical_raw_dir=str(args.canonical_raw_dir) if args.canonical_raw_dir else None))
        for name, command in [('git_commit.txt', ['rev-parse', 'HEAD']), ('git_status.txt', ['status', '--short'])]:
            (out/name).write_text(subprocess.check_output(['git', '-C', str(REPO), *command], text=True))
        print('Inventory:', inventory, flush=True)
        quality_audit(inventory, data, out/'quality', args.canonical_raw_dir)
        readiness = report(out/'quality', out/'readiness', args.bridge_dir, args.build_dir, args.calibration_dir)
        code = 0
        print('Audit riuscito. Stima NON autorizzata. Blocchi:', ', '.join(readiness['blocking_items']), flush=True)
    except Exception as exc:
        dump(out/'error.json', dict(error_type=type(exc).__name__, message=str(exc)))
        raise
    finally:
        (out/'exit_code.txt').write_text(str(code)+'\n')
        with ZipFile(archive, 'w', ZIP_DEFLATED) as z:
            for path in sorted(out.rglob('*')):
                if path.is_file(): z.write(path, str(path.relative_to(out)))
            code_files = list((REPO/'confirmation_analysis').glob('*.py'))
            code_files += [REPO/'Raw/Certification/final_analysis_spec_v2.json', REPO/'scripts'/'Run_confirmation_quality.sh']
            for path in sorted(code_files):
                z.write(path, 'executed_code/'+str(path.relative_to(REPO)))
        print('ZIP da caricare:', archive, flush=True)


if __name__ == '__main__':
    main()
