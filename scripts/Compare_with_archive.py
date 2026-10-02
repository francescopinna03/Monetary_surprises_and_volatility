import argparse
from pathlib import Path
import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[1]
ARCHIVE = REPO/'reference_outputs'
RUNS = [('paper/ecb_confirmation_20260915', 'confirmation_final_', 'estimated'),
        ('paper/ecb_minute_20260928', 'confirmation_minute_', 'minute'),
        ('paper/ecb_design_information_20260928', 'design_information_', 'design'),
        ('paper/fomc_replication_20260929', 'fed_replication_', 'fed'),
        ('paper/fomc_post_replication_20260930', 'fed_post_replication_', 'post'),
        ('paper/measurement_check_20260930', 'measurement_check_', 'check')]


def latest(output, prefix, sub):
    found = sorted((p/sub for p in output.glob(prefix+'*') if (p/sub).is_dir()), key=lambda p: p.stat().st_mtime)
    return found[-1] if found else None


def compare_csv(a, b, tol):
    x, y = pd.read_csv(a), pd.read_csv(b)
    if x.shape != y.shape or list(x.columns) != list(y.columns):
        return False, f'shape {x.shape} against {y.shape}'
    worst = 0.
    for c in x.columns:
        if pd.api.types.is_numeric_dtype(x[c]) and pd.api.types.is_numeric_dtype(y[c]):
            u, v = x[c].to_numpy(float), y[c].to_numpy(float)
            if not np.array_equal(np.isnan(u), np.isnan(v)):
                return False, f'missing values differ in {c}'
            d = np.abs(u-v)[~np.isnan(u)]
            worst = max(worst, float(d.max()) if d.size else 0.)
        elif not x[c].astype(str).equals(y[c].astype(str)):
            return False, f'text differs in {c}'
    return worst <= tol, f'max abs difference {worst:.3g}'


def compare_dir(archived, produced, tol):
    rows = []
    for a in sorted(archived.rglob('*.csv')):
        b = produced/a.relative_to(archived)
        if not b.exists():
            rows.append((str(a.relative_to(ARCHIVE)), False, 'missing in the replication'))
            continue
        ok, note = compare_csv(a, b, tol)
        rows.append((str(a.relative_to(ARCHIVE)), ok, note))
    return rows


def main():
    p = argparse.ArgumentParser(prog='python scripts/Compare_with_archive.py')
    p.add_argument('--data-root', type=Path, required=True)
    p.add_argument('--cross-epoch', type=Path)
    p.add_argument('--tolerance', type=float, default=1e-8)
    a = p.parse_args()
    rows = []
    for archived, prefix, sub in RUNS:
        produced = latest(a.data_root/'Output', prefix, sub)
        if produced is None:
            rows.append((archived, False, 'no replication run found'))
            continue
        rows += compare_dir(ARCHIVE/archived, produced, a.tolerance)
    if a.cross_epoch is not None:
        rows += compare_dir(ARCHIVE/'cross_epoch_20260916', a.cross_epoch, a.tolerance)
    table = pd.DataFrame(rows, columns=['archived_file', 'identical', 'note'])
    pd.set_option('display.width', 200); pd.set_option('display.max_colwidth', 90)
    print(table.to_string(index=False))
    print(f'{int(table.identical.sum())} of {len(table)} archived tables reproduced within {a.tolerance:g}')


if __name__ == '__main__':
    main()
