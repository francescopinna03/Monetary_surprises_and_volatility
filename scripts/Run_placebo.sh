#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
run_root="$(cd "${1:?Pass the facility directory}" && pwd)"
frozen="${2:?Pass the frozen build directory}"
python_bin="${PYTHON_BIN:-$run_root/python_env/bin/python}"
data_root="$run_root/Econometrics_data"
calendar="$repo_dir/Raw/Certification/fomc_calendar_verified.csv"
generation="${GENERATION_BUILD:?Set GENERATION_BUILD to the frozen 2013-2025 build}"
[[ -f "$generation/status.json" ]] || { echo "Generation build missing: $generation" >&2; exit 1; }
bridge="${BRIDGE_DIR:?Set BRIDGE_DIR to the bridge directory of the preparation run}"
[[ -f "$bridge/bridge_decision.json" ]] || { echo "Bridge missing: $bridge" >&2; exit 1; }
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin" >&2; exit 1; }
[[ -f "$frozen/status.json" ]] || { echo "Frozen build missing: $frozen" >&2; exit 1; }
[[ -d "$data_root/Raw/Barchart_futures_fed" ]] || { echo "FOMC data missing: $data_root/Raw/Barchart_futures_fed" >&2; exit 1; }
[[ -f "$calendar" ]] || { echo "Calendar missing: $calendar" >&2; exit 1; }
stamp="$(date +%Y%m%d_%H%M%S)_$$"
out="$data_root/Output/placebo_$stamp"
archive="${run_root}_placebo_${stamp}.zip"
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
"$python_bin" -m confirmation_analysis.placebo --build "$frozen" --generation-dir "$generation" --bridge-dir "$bridge" \
    --fed-dir "$data_root/Raw/Barchart_futures_fed" --fed-calendar "$calendar" --output "$out/placebo"
