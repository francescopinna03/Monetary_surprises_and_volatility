#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")" && pwd)"
run_root="$(cd "${1:?Pass the facility directory}" && pwd)"
frozen="${2:?Pass the frozen build directory}"
python_bin="${PYTHON_BIN:-$run_root/python_env/bin/python}"
data_root="$run_root/Econometrics_data"
minute_dir="${3:-$data_root/Raw/Barchart_futures_1min}"
generation="$data_root/Raw/Certification/final_resume_20260911_174739_4124"
bridge="$data_root/Output/confirmation_preparation_20260912_132851_8951/bridge"
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin" >&2; exit 1; }
[[ -f "$frozen/status.json" ]] || { echo "Frozen build missing: $frozen" >&2; exit 1; }
[[ -d "$minute_dir" ]] || { echo "Minute directory missing: $minute_dir" >&2; exit 1; }
stamp="$(date +%Y%m%d_%H%M%S)_$$"
out="$data_root/Output/confirmation_minute_$stamp"
archive="${run_root}_confirmation_minute_${stamp}.zip"
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
        if p.is_file() and p.name != 'minute_measures_panel.csv':
            z.write(p, str(p.relative_to(root)))
    panel = root/'minute/minute_measures_panel.csv'
    if panel.exists():
        z.write(panel, 'minute/minute_measures_panel.csv')
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
args=(--build "$frozen" --minute-dir "$minute_dir" --output "$out/minute"
      --five-minute-dir "$data_root/Raw/Barchart_futures_confirmation" --five-minute-dir "$data_root/Raw/Barchart_futures")
[[ -f "$generation/status.json" ]] && args+=(--generation-dir "$generation")
[[ -f "$bridge/bridge_decision.json" ]] && args+=(--bridge-dir "$bridge")
"$python_bin" -m confirmation_analysis.minute "${args[@]}"
