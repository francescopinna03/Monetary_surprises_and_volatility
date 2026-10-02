#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
run_root="$(cd "${1:?Pass the existing Monetary_surprises_FULL directory}" && pwd)"
quality_dir="${2:?Pass the confirmation_quality_*/quality directory}"
build_dir="${3:?Pass the confirmation_calibration_*/build directory}"
calibration_dir="${4:?Pass the confirmation_calibration_*/calibration directory}"
bridge_dir="${5:?Pass the confirmation_preparation_*/bridge directory}"
confirm="${6:-}"
already_opened="${7:-}"
if [[ "$confirm" != "I_HAVE_REVIEWED_THE_FROZEN_SPECIFICATION" ]]; then
    echo "Ultimo argomento mancante: I_HAVE_REVIEWED_THE_FROZEN_SPECIFICATION" >&2
    echo "Il freeze costruisce gli outcome del campione di conferma e non e' reversibile." >&2
    exit 2
fi
python_bin="${PYTHON_BIN:-$run_root/python_env/bin/python}"
data_root="$run_root/Econometrics_data"
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin" >&2; exit 1; }
stamp="$(date +%Y%m%d_%H%M%S)_$$"
out="$data_root/Output/confirmation_final_$stamp"
frozen="$data_root/Raw/Certification/final_confirmation_v2_$stamp"
archive="${run_root}_confirmation_final_${stamp}.zip"
mkdir -p "$out"
exec > >(tee "$out/console.log") 2>&1
finish() {
    result=$?
    trap - EXIT
    set +e
    printf '%s\n' "$result" > "$out/exit_code.txt"
    CONFIRMATION_OUT="$out" CONFIRMATION_ZIP="$archive" CONFIRMATION_REPO="$repo_dir" \
    CONFIRMATION_FROZEN="$frozen" "$python_bin" - <<'PY'
import os
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(os.environ['CONFIRMATION_OUT'])
repo = Path(os.environ['CONFIRMATION_REPO'])
frozen = Path(os.environ['CONFIRMATION_FROZEN'])
with ZipFile(os.environ['CONFIRMATION_ZIP'], 'w', ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        if p.is_file(): z.write(p, str(p.relative_to(root)))
    for name in ['status.json', 'specification.json', 'decisions.json']:
        if (frozen/name).is_file(): z.write(frozen/name, 'frozen_manifest/'+name)
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
opened_args=()
[[ -n "$already_opened" ]] && opened_args+=(--already-opened "$already_opened")
bash scripts/Run_confirmation.sh freeze --quality-dir "$quality_dir" --data-root "$data_root" \
    --build "$build_dir" --calibration "$calibration_dir" --bridge-dir "$bridge_dir" \
    --destination "$frozen" "${opened_args[@]}"
bash scripts/Run_confirmation.sh estimate --build "$frozen" --output "$out/estimated"
printf '\nStima v2 completata. Build congelata: %s\n' "$frozen"
