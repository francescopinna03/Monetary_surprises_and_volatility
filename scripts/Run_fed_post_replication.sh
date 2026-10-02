#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
run_root="$(cd "${1:?Pass the facility directory}" && pwd)"
python_bin="${PYTHON_BIN:-$run_root/python_env/bin/python}"
data_root="$run_root/Econometrics_data"
run_dir="${2:-$(ls -dt "$data_root/Output/"fed_replication_*/fed 2>/dev/null | head -1)}"
protocol="$repo_dir/Raw/Certification/fed_protocol_v1.json"
calendar="$data_root/Raw/Certification/fomc_calendar_verified.csv"
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin" >&2; exit 1; }
[[ -f "$run_dir/run_manifest.json" ]] || { echo "Replication run missing: $run_dir" >&2; exit 1; }
stamp="$(date +%Y%m%d_%H%M%S)_$$"
out="$data_root/Output/fed_post_replication_$stamp"
archive="${run_root}_fed_post_replication_${stamp}.zip"
mkdir -p "$out"
exec > >(tee "$out/console.log") 2>&1
finish() {
    result=$?; trap - EXIT; set +e
    printf '%s\n' "$result" > "$out/exit_code.txt"
    CONFIRMATION_OUT="$out" CONFIRMATION_ZIP="$archive" "$python_bin" - <<'PY'
import os
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(os.environ['CONFIRMATION_OUT'])
with ZipFile(os.environ['CONFIRMATION_ZIP'], 'w', ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        if p.is_file():
            z.write(p, str(p.relative_to(root)))
print('ZIP da caricare:', os.environ['CONFIRMATION_ZIP'])
PY
    packaged=$?; [[ "$packaged" -eq 0 ]] || result=1; exit "$result"
}
trap finish EXIT
cd "$repo_dir"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}" OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}" PYTHONUNBUFFERED=1
git rev-parse HEAD > "$out/git_commit.txt"; git status --short > "$out/git_status.txt"
echo "Replication run: $run_dir"
"$python_bin" -m confirmation_analysis.fed_replication post-replication --fed-dir "$data_root/Raw/Barchart_futures_fed" --calendar "$calendar" --protocol "$protocol" --run "$run_dir" --output "$out/post"
