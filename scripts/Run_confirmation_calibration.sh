#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
run_root="$(cd "${1:?Pass the existing Monetary_surprises_FULL directory}" && pwd)"
shift
quality_dir="${1:?Pass the confirmation_quality_*/quality directory}"
shift
python_bin="${PYTHON_BIN:-$run_root/python_env/bin/python}"
data_root="$run_root/Econometrics_data"
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin" >&2; exit 1; }
[[ -f "$quality_dir/status.json" ]] || { echo "Quality audit missing: $quality_dir" >&2; exit 1; }
stamp="$(date +%Y%m%d_%H%M%S)_$$"
out="$data_root/Output/confirmation_calibration_$stamp"
archive="${run_root}_confirmation_calibration_${stamp}.zip"
mkdir -p "$out"
exec > >(tee "$out/console.log") 2>&1
finish() {
    result=$?
    trap - EXIT
    set +e
    printf '%s\n' "$result" > "$out/exit_code.txt"
    CONFIRMATION_OUT="$out" CONFIRMATION_ZIP="$archive" CONFIRMATION_REPO="$repo_dir" "$python_bin" - <<'PY'
import os
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(os.environ['CONFIRMATION_OUT'])
repo = Path(os.environ['CONFIRMATION_REPO'])
with ZipFile(os.environ['CONFIRMATION_ZIP'], 'w', ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        if p.is_file(): z.write(p, str(p.relative_to(root)))
    code = list((repo/'confirmation_analysis').glob('*.py'))
    code += [repo/'Raw/Certification/final_analysis_spec_v2.json']
    for p in sorted(code):
        z.write(p, 'executed_code/'+str(p.relative_to(repo)))
print('ZIP da caricare:', os.environ['CONFIRMATION_ZIP'])
PY
    packaged=$?
    [[ "$packaged" -eq 0 ]] || result=1
    exit "$result"
}
trap finish EXIT
if command -v caffeinate >/dev/null 2>&1; then caffeinate -i -w "$$" & fi
cd "$repo_dir"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export PYTHONUNBUFFERED=1
export PYTHON_BIN="$python_bin"
git rev-parse HEAD > "$out/git_commit.txt"
git status --short > "$out/git_status.txt"
generation_build="${GENERATION_BUILD:?Set GENERATION_BUILD to the frozen 2013-2025 build}"
[[ -f "$generation_build/status.json" ]] || { echo "Generation build missing: $generation_build" >&2; exit 1; }
args=()
args+=(--generation-build "$generation_build")
bash scripts/Run_confirmation.sh control-build --quality-dir "$quality_dir" --data-root "$data_root" \
    --output "$out/build" "${args[@]}" "$@"
bash scripts/Run_confirmation.sh calibrate --build "$out/build" --output "$out/calibration"
bash scripts/Run_confirmation.sh readiness --quality-dir "$quality_dir" --build-dir "$out/build" \
    --calibration-dir "$out/calibration" --output "$out/readiness" || true
printf '\nCostruzione protetta e calibrazione completate. Nessun outcome di conferma calcolato.\n'
