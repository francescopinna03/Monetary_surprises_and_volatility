import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
from datetime import datetime, timezone


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def dump(path, value):
    Path(path).write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')


def contract(name):
    match = re.fullmatch(r'(fx|gg|hf|hr)([hmuz])(\d{2})_intraday-5min_historical-data-(\d{2}-\d{2}-\d{4})\.csv', name.lower())
    if not match:
        raise ValueError(f'Unrecognized raw CSV; resolve before MATLAB: {name}')
    root, expiry, yy, downloaded = match.groups()
    datetime.strptime(downloaded, '%m-%d-%Y')
    year = 2000 + int(yy)
    if not 2000 <= year <= datetime.now(timezone.utc).year:
        raise ValueError(f'Contract outside supported archive years: {name}')
    return dict(root_code=root, expiry_code=expiry.upper(), contract_year=year)


def scan(directory):
    if directory.is_symlink():
        raise ValueError(f'Archive must be a physical directory: {directory}')
    rows = []
    for path in sorted(directory.iterdir()) if directory.exists() else []:
        if path.is_dir():
            raise ValueError(f'Nested archive directory requires review: {path}')
        if path.suffix.lower() != '.csv':
            continue
        if path.is_symlink() or not path.is_file() or path.stat().st_nlink != 1:
            raise ValueError(f'CSV must be a regular, unaliased file: {path}')
        rows.append(dict(file_name=path.name, **contract(path.name), path=path))
    return rows


def split_archive(data_root, out, apply=False):
    data_root, out = Path(data_root).resolve(), Path(out)
    source = data_root/'Raw/Barchart_futures'
    target = data_root/'Raw/Barchart_futures_confirmation'
    if not source.is_dir():
        raise FileNotFoundError(source)
    left, right = scan(source), scan(target)
    if any(r['contract_year'] >= 2013 for r in right):
        raise ValueError('Generation contract already in confirmation folder; no files moved')
    moving = [r for r in left if r['contract_year'] <= 2012]
    if any((target/r['file_name']).exists() for r in moving):
        raise ValueError('Destination collision; no files overwritten or moved')
    if not any(r['contract_year'] >= 2013 for r in left):
        raise ValueError('No generation contracts found')
    out.mkdir(parents=True, exist_ok=False)
    fields = ['file_name', 'root_code', 'expiry_code', 'contract_year', 'source', 'destination', 'sha256', 'action']
    plan = []
    for row in left + right:
        path = row['path']
        destination = target/path.name if row in moving else path
        plan.append({k: row[k] for k in fields[:4]} | dict(source=str(path),
            destination=str(destination), sha256=digest(path), action='move' if row in moving else 'keep'))
    with (out/'archive_plan.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader(); writer.writerows(plan)
    result = dict(status='dry_run', moves_planned=len(moving), moved=0,
        generation_files=sum(r['contract_year'] >= 2013 for r in left),
        confirmation_files=len(moving)+len(right), confirmation_outcomes_computed=False)
    dump(out/'status.json', result)
    if apply:
        lock = data_root/'Raw/confirmation_split.lock'
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(descriptor)
        try:
            target.mkdir(exist_ok=True)
            if source.stat().st_dev != target.stat().st_dev:
                raise ValueError('Split requires same-filesystem atomic renames')
            for row in plan:
                if row['action'] != 'move':
                    continue
                src, dst = Path(row['source']), Path(row['destination'])
                if dst.exists() or digest(src) != row['sha256']:
                    raise ValueError('Archive changed after preflight; stopped with journal')
                src.rename(dst)
                if digest(dst) != row['sha256']:
                    raise ValueError('Post-move digest mismatch')
                result['moved'] += 1
                result['status'] = 'applying'
                dump(out/'status.json', result)
            if any(r['contract_year'] < 2013 for r in scan(source)):
                raise ValueError('Confirmation contract remains in generation archive')
            result['status'] = 'separated'
            dump(out/'status.json', result)
        except Exception:
            result['status'] = 'interrupted_review_journal_and_lock'
            dump(out/'status.json', result)
            raise
        else:
            lock.unlink()
    for row in plan:
        if row['contract_year'] >= 2013:
            print(f"MATLAB archive: {row['contract_year']} {row['file_name']}", flush=True)
    print(json.dumps(result), flush=True)
    return result


def safe_relative(name):
    p = Path(name)
    if p.is_absolute() or '..' in p.parts:
        raise ValueError(f'Unsafe manifest path: {name}')
    return p


def frozen_copy(data_root, build, destination, repo, recovery_root=None):
    build, destination, repo = Path(build), Path(destination), Path(repo)
    meta = json.loads((build/'status.json').read_text())
    if meta.get('status') != 'frozen' or meta.get('schema_version') != 'final_analysis_v1':
        raise ValueError('Expected the frozen generation v1 build')
    for name, expected in meta['table_hashes'].items():
        if digest(build/safe_relative(name)) != expected:
            raise ValueError(f'Frozen table hash mismatch: {name}')
    if digest(build/'specification.json') != meta['specification_sha256']:
        raise ValueError('Frozen specification changed')
    with (build/'preferred_contracts.csv').open(newline='') as stream:
        preferred = list(csv.DictReader(stream))
    dates = [r['event_date'][:10] for r in preferred]
    if not dates or any(d < '2013-01-01' for d in dates):
        raise ValueError('GENERATION_LEAKAGE: frozen preferred selection includes pre-2013 dates')
    selected = [d for d in dates if d < '2026-01-01']
    if not selected:
        raise ValueError('Empty 2013-2025 generation subset')
    with (build/'input_hashes.csv').open(newline='') as stream:
        inputs = list(csv.DictReader(stream))
    if {r['relative_path']: r['sha256'] for r in inputs} != meta['source_hashes']:
        raise ValueError('input_hashes.csv differs from frozen status.json')
    roots = [Path(data_root)] + ([Path(recovery_root)] if recovery_root else [])
    bundled_recovery = repo/'Raw/Certification/generation_recovery_20260911'
    if bundled_recovery.is_dir():
        roots.append(bundled_recovery)
    copies, problems = [], []
    for row in inputs:
        name, expected = row['relative_path'], row['sha256']
        if name == 'specification':
            if digest(repo/'Raw/Certification/final_analysis_spec_v1.json') != expected:
                problems.append('Current v1 specification differs from frozen build')
            continue
        rel = safe_relative(name)
        matches = [r/rel for r in roots if (r/rel).is_file() and digest(r/rel) == expected]
        if not matches:
            problems.append(f'Missing or changed frozen input: {name}')
        else:
            copies.append((matches[0], rel, expected))
    if problems:
        raise ValueError('\n'.join(problems))
    destination.mkdir(parents=True, exist_ok=False)
    for source, rel, expected in copies:
        target = destination/rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if digest(target) != expected:
            raise ValueError(f'Copy verification failed: {target}')
    local_build = destination/'Raw/Certification'/build.name
    shutil.copytree(build, local_build)
    report = dict(status='generation_inputs_verified', source_build=str(build.resolve()),
        input_files=len(copies), event_dates_2013_2025=len(set(selected)),
        excluded_later_event_dates=sorted(set(dates)-set(selected)),
        raw_confirmation_copied=False, frozen_selection_modified=False)
    dump(destination.parent/'generation_inputs.json', report)
    print(json.dumps(report, indent=2), flush=True)
    return local_build


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    split_archive(args.data_root, args.output, args.apply)
