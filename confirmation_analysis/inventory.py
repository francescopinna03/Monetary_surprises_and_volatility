import argparse
import csv
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, BadZipFile
from .audit import audit
from .protocol import REPO, parse_contract, dump


def candidate(name):
    match = re.match(r'^(fx|gg|hf|hr)[hmuz](\d{2})_intraday-', name.lower())
    return bool(match and 0 <= int(match.group(2)) <= 12)


def discover(roots, out):
    csv_paths, archives, skipped = set(), [], []
    seen_archives = set()
    def onerror(error):
        skipped.append(dict(path=str(error.filename), reason=str(error)))
    for root in roots:
        print('Ricerca:', root, flush=True)
        for directory, dirs, names in os.walk(root, onerror=onerror, followlinks=False):
            dirs[:] = [d for d in dirs if d not in {'.git', '.venv', 'python_env', '__pycache__', 'Output'}]
            for name in names:
                path = Path(directory)/name
                if name.lower().endswith('.csv') and candidate(name):
                    csv_paths.add(path.resolve())
                elif name.lower().endswith('.zip') and path.resolve() not in seen_archives:
                    seen_archives.add(path.resolve())
                    try:
                        with ZipFile(path) as z:
                            members = [i for i in z.infolist() if not i.is_dir()
                                       and i.filename.lower().endswith('.csv')
                                       and candidate(Path(i.filename).name)]
                        if members:
                            archives.append(dict(archive_path=str(path.resolve()), n_candidate_members=len(members),
                                uncompressed_bytes=sum(i.file_size for i in members),
                                status='member_names_only_payload_not_read_or_extracted'))
                    except (OSError, BadZipFile, NotImplementedError) as exc:
                        skipped.append(dict(path=str(path), reason=str(exc)))
    rows = []
    for path in sorted(csv_paths):
        try:
            meta = parse_contract(path.name)
            status = 'recognized_raw_filename'
        except ValueError as exc:
            meta = {}
            status = str(exc)
        rows.append(dict(input_path=str(path), folder=str(path.parent), file_name=path.name,
                         **meta, status=status))
    def write(name, fields, rows):
        with (out/name).open('w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader(); writer.writerows(rows)
    write('discovered_csv_paths.csv', ['input_path','folder','file_name','root_code','expiry_code','contract_year','status'], rows)
    write('archives_with_confirmation_names.csv', ['archive_path','n_candidate_members','uncompressed_bytes','status'], archives)
    write('discovery_errors.csv', ['path','reason'], skipped)
    print(f'Ricerca: {len(rows)} CSV candidati, {len(archives)} ZIP con nomi del nuovo periodo.', flush=True)
    return sorted({p.parent for p in csv_paths}), dict(
        searched_roots=[str(p) for p in roots], n_candidate_csv_paths=len(rows),
        n_archives_with_candidate_names=len(archives), n_discovery_errors=len(skipped),
        archived_csv_payloads_read=False)


def search_roots(data, raw_root=None, extra=None, discover_home=False):
    if raw_root is not None and (extra or discover_home):
        raise ValueError('--raw-root is exclusive; remove discovery options')
    roots = [Path(raw_root) if raw_root is not None else Path(data)/'Raw/Barchart_futures_confirmation']
    roots += list(extra or [])
    if discover_home:
        roots += [p for p in [Path.home()/'Downloads', Path.home()/'Desktop'] if p.is_dir()]
    for path in roots:
        if not path.expanduser().is_dir():
            raise FileNotFoundError(f'Confirmation archive missing: {path}; separate the archives first')
    return list(dict.fromkeys(p.expanduser().resolve() for p in roots))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-root', type=Path, required=True)
    parser.add_argument('--search-dir', type=Path, action='append')
    parser.add_argument('--raw-root', type=Path, help='Exclusive canonical confirmation archive')
    parser.add_argument('--discover', action='store_true', help='Explicitly include Desktop and Downloads discovery')
    args = parser.parse_args()
    run = args.run_root.expanduser().resolve()
    data = run/'Econometrics_data'
    if not (data/'Raw/EA-EMPD/EA-EMPD.xlsx').is_file():
        raise FileNotFoundError('EA-EMPD assente nella run indicata')
    roots = search_roots(data, args.raw_root, args.search_dir, args.discover)
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + str(os.getpid())
    out = data/'Output'/('confirmation_inventory_'+stamp)
    out.mkdir(parents=True, exist_ok=False)
    archive = run.parent/(run.name+'_confirmation_inventory_'+stamp+'.zip')
    code = 1
    try:
        for filename, command in [('git_commit.txt', ['rev-parse','HEAD']), ('git_status.txt', ['status','--short'])]:
            (out/filename).write_text(subprocess.check_output(['git','-C',str(REPO),*command], text=True))
        folders, discovery = discover(roots, out)
        dump(out/'discovery_status.json', discovery)
        preferred = roots
        folders = list(dict.fromkeys([p.resolve() for p in preferred if p.is_dir()] + folders))
        result = audit(data, folders, out/'audit')
        print('Celle con barre:', result['n_expected_contracts_with_bars'], '/', result['expected_contract_cells'], flush=True)
        print('File vuoti o senza timestamp utilizzabili:', result['n_raw_files_without_bars'], flush=True)
        if discovery['n_archives_with_candidate_names']:
            print('Sono presenti anche ZIP da esaminare: vedi archives_with_confirmation_names.csv.', flush=True)
        print('Ponte non ripetuto. Certificazione e freeze restano da completare.', flush=True)
        code = 0
    except Exception as exc:
        dump(out/'error.json', dict(error_type=type(exc).__name__, message=str(exc)))
        raise
    finally:
        (out/'exit_code.txt').write_text(str(code)+'\n')
        with ZipFile(archive, 'w', ZIP_DEFLATED) as z:
            for p in sorted(out.rglob('*')):
                if p.is_file(): z.write(p, str(p.relative_to(out)))
        print('ZIP da caricare:', archive, flush=True)


if __name__ == '__main__':
    main()
