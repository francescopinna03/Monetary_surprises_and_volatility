#!/usr/bin/env python3
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import traceback
import zipfile
import numpy as np
import pandas as pd
from confirmation_analysis.functional_form import functional_form, DIAGNOSTIC_VERSION
from confirmation_analysis.protocol import digest, timestamp

REPO = Path(__file__).resolve().parent
REVIEWED_BUILD = 'f3880de1a82a841373ffee1ac4c7383b56879061e6ea8a9bbdc4c9d6b3f81527'


def bundle_bytes(source, relative):
    source = Path(source)
    if source.is_dir():
        return (source/relative).read_bytes()
    with zipfile.ZipFile(source) as z:
        matches = [n for n in z.namelist() if n == relative or n.endswith('/'+relative)]
        if len(matches) != 1:
            raise ValueError(f'Expected exactly one {relative} in {source.name}')
        return z.read(matches[0])


def load_opened_results(source):
    read = lambda name: bundle_bytes(source, name)
    manifest = json.loads(read('estimated/run_manifest.json'))
    if manifest.get('status') != 'complete_reestimation_after_opening':
        raise ValueError('Requires an already completed re-estimation after opening')
    if manifest.get('prior_results_seen', {}).get('confirmation_2000_2012') is not True:
        raise ValueError('Input does not document that confirmation outcomes have already been opened')
    frozen_bytes = read('frozen_manifest/status.json')
    frozen = json.loads(frozen_bytes)
    if hashlib.sha256(frozen_bytes).hexdigest() != manifest['build_manifest_sha256']:
        raise ValueError('Frozen manifest does not match the input estimation')
    spec_bytes = read('frozen_manifest/specification.json')
    if hashlib.sha256(spec_bytes).hexdigest() != frozen['specification_sha256']:
        raise ValueError('Archived specification checksum mismatch')
    registry_bytes = read('estimated/primary_sample_registry.csv')
    T = pd.read_csv(io.BytesIO(registry_bytes), parse_dates=['trade_date'])
    if len(T) != manifest['n_primary_events'] or T.trade_date.duplicated().any():
        raise ValueError('Unexpected primary sample size or duplicate event dates')
    if not T.trade_date.between('2000-01-01', '2012-12-31').all():
        raise ValueError('This diagnostic runner expects the opened 2000-2012 sample')
    return T, json.loads(spec_bytes), manifest, {
        'primary_sample_registry.csv': hashlib.sha256(registry_bytes).hexdigest(),
        'specification.json': hashlib.sha256(spec_bytes).hexdigest(),
        'frozen_status.json': hashlib.sha256(frozen_bytes).hexdigest()}


def discover_results(facility):
    stem = 'Monetary_surprises_testing_facility_confirmation_final_20260915_112120_2190'
    candidates = sorted((Path.home()/'Downloads').glob(stem+'*.zip'))
    candidates += sorted(facility.rglob(stem+'*.zip'))
    candidates += sorted(p.parent.parent for p in (facility/'runs').rglob('primary_sample_registry.csv')
                         if p.parent.name == 'estimated')
    seen = set()
    for p in candidates:
        if p.resolve() in seen:
            continue
        seen.add(p.resolve())
        try:
            _, _, manifest, _ = load_opened_results(p)
        except (OSError, ValueError, KeyError, zipfile.BadZipFile):
            continue
        if manifest['build_manifest_sha256'] == REVIEWED_BUILD:
            return p
    raise FileNotFoundError('Bundle non trovato. Conserva in Downloads lo ZIP confirmation_final_20260915_112120_2190 '
                            'oppure indica --source-results /percorso/al/bundle.zip')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--facility', type=Path, required=True)
    parser.add_argument('--source-results', type=Path)
    args = parser.parse_args(argv)
    facility = args.facility.expanduser().resolve()
    if facility.name != 'Monetary_surprises_testing_facility' or REPO.parent.resolve() != facility:
        raise ValueError('Eseguire dalla copia in Monetary_surprises_testing_facility/Monetary_surprises_clone')
    source = args.source_results.expanduser().resolve() if args.source_results else discover_results(facility)
    T, spec, old_manifest, inputs = load_opened_results(source)
    print(f'Campione gia aperto: {source}\nEventi: {len(T)}. Nessun dato grezzo richiesto.', flush=True)
    from datetime import datetime, timezone
    out = facility/'runs'/('functional_form_corrected_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')+f'_{os.getpid()}')
    out.mkdir(parents=True, exist_ok=False)
    paths = ['confirmation_analysis/functional_form.py', 'confirmation_analysis/inference.py',
             'confirmation_analysis/cones.py', 'final_analysis/models.py', 'Run_functional_form_checks.py',
             'tests/test_functional_form.py']
    manifest = dict(status='running', mode='functional_form_only_after_opening', diagnostic_version=DIAGNOSTIC_VERSION,
        source_results=str(source), source_run=old_manifest, input_hashes=inputs, created_utc=timestamp(),
        n_primary_events=len(T), draws=19999, seed=spec['seed']+7000,
        code_hashes={p:digest(REPO/p) for p in paths}, python=platform.python_version(),
        numpy=np.__version__, pandas=pd.__version__, prior_results_seen=True,
        confirmation_verdict_unchanged=True, raw_data_accessed=False,
        cv_scope='Conditional on the previously computed indicators, crossfit state and outcome; not real-time forecasting')
    for path in paths:
        dest = out/'executed_code'/path
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(REPO/path, dest)
    (out/'inputs').mkdir()
    (out/'inputs/primary_sample_registry.csv').write_bytes(bundle_bytes(source, 'estimated/primary_sample_registry.csv'))
    (out/'inputs/specification.json').write_bytes(bundle_bytes(source, 'frozen_manifest/specification.json'))
    try:
        print('Stima delle diagnostiche e validazione annidata della spline', flush=True)
        tables = functional_form(T, spec, spec['primary_coordinates']['u'], spec['primary_coordinates']['z'],
                                 draws=19999, seed=spec['seed']+7000)
        for name, table in tables.items():
            table.to_csv(out/f'functional_form_{name}.csv', index=False)
        manifest['status'] = 'complete_post_opening_functional_diagnostics'
        print(tables['basis_summary'].to_string(index=False), flush=True)
    except Exception:
        manifest['status'] = 'failed'
        (out/'error.txt').write_text(traceback.format_exc())
        raise
    finally:
        manifest['finished_utc'] = timestamp()
        (out/'run_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        archive = out.with_suffix('.zip')
        with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as z:
            for f in sorted(out.rglob('*')):
                if f.is_file():
                    z.write(f, str(f.relative_to(out)))
        print(f'Output: {out}\nZIP: {archive}', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
