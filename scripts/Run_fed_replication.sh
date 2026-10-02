#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
run_root="$(cd "${1:?Pass the facility directory}" && pwd)"
protocol="${2:-$repo_dir/Raw/Certification/fed_protocol_v1.json}"
python_bin="${PYTHON_BIN:-$run_root/python_env/bin/python}"
data_root="$run_root/Econometrics_data"
fed_dir="$data_root/Raw/Barchart_futures_fed"
calendar="$data_root/Raw/Certification/fomc_calendar_verified.csv"
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin" >&2; exit 1; }
[[ -f "$protocol" ]] || { echo "Protocol missing: $protocol" >&2; exit 1; }
[[ -f "$calendar" ]] || { echo "Calendar missing: $calendar" >&2; exit 1; }
stamp="$(date +%Y%m%d_%H%M%S)_$$"
out="$data_root/Output/fed_replication_$stamp"
archive="${run_root}_fed_replication_${stamp}.zip"
mkdir -p "$out"
exec > >(tee "$out/console.log") 2>&1
finish() {
    result=$?; trap - EXIT; set +e
    printf '%s\n' "$result" > "$out/exit_code.txt"
    CONFIRMATION_OUT="$out" CONFIRMATION_ZIP="$archive" CONFIRMATION_REPO="$repo_dir" "$python_bin" - <<'PY'
import os
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(os.environ['CONFIRMATION_OUT']); repo = Path(os.environ['CONFIRMATION_REPO'])
with ZipFile(os.environ['CONFIRMATION_ZIP'], 'w', ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        if p.is_file():
            z.write(p, str(p.relative_to(root)))
    for p in sorted((repo/'confirmation_analysis').glob('*.py')):
        z.write(p, 'executed_code/'+str(p.relative_to(repo)))
print('ZIP da caricare:', os.environ['CONFIRMATION_ZIP'])
PY
    packaged=$?; [[ "$packaged" -eq 0 ]] || result=1; exit "$result"
}
trap finish EXIT
cd "$repo_dir"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}" OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}" PYTHONUNBUFFERED=1
git rev-parse HEAD > "$out/git_commit.txt"; git status --short > "$out/git_status.txt"
cp "$protocol" "$out/protocol.json"; cp "$calendar" "$out/fomc_calendar_verified.csv"
"$python_bin" -m confirmation_analysis.fed_replication run --fed-dir "$fed_dir" --calendar "$calendar" --protocol "$protocol" --output "$out/fed"
