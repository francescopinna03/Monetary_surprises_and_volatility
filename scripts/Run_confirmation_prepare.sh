#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
run_root="$(cd "${1:?Pass the existing Monetary_surprises_FULL directory}" && pwd)"
python_bin="${PYTHON_BIN:-$run_root/python_env/bin/python}"
data_root="$run_root/Econometrics_data"
build="${GENERATION_BUILD:?Set GENERATION_BUILD to the frozen 2013-2025 build}"
[[ -f "$build/status.json" ]] || { echo "Generation build missing: $build" >&2; exit 1; }
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin"; exit 1; }
[[ -f "$build/status.json" ]] || { echo "Generation build missing: $build"; exit 1; }
stamp="$(date +%Y%m%d_%H%M%S)_$$"
export CONFIRMATION_PREPARATION_OUTPUT="$data_root/Output/confirmation_preparation_$stamp"
export CONFIRMATION_PREPARATION_ZIP="${run_root}_confirmation_preparation_${stamp}.zip"
mkdir -p "$CONFIRMATION_PREPARATION_OUTPUT"
exec > >(tee "$CONFIRMATION_PREPARATION_OUTPUT/console.log") 2>&1
finish() {
    result=$?
    trap - EXIT
    set +e
    printf '%s\n' "$result" > "$CONFIRMATION_PREPARATION_OUTPUT/exit_code.txt"
    "$python_bin" - <<'PY'
import os
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root=Path(os.environ['CONFIRMATION_PREPARATION_OUTPUT'])
with ZipFile(os.environ['CONFIRMATION_PREPARATION_ZIP'], 'w', ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        if p.is_file(): z.write(p, str(p.relative_to(root)))
print('ZIP da caricare:', os.environ['CONFIRMATION_PREPARATION_ZIP'])
PY
    packaged=$?
    [[ "$packaged" -eq 0 ]] || result=1
    exit "$result"
}
trap finish EXIT
if command -v caffeinate >/dev/null 2>&1; then caffeinate -i -w "$$" & fi
cd "$repo_dir"
git rev-parse HEAD > "$CONFIRMATION_PREPARATION_OUTPUT/git_commit.txt"
git status --short > "$CONFIRMATION_PREPARATION_OUTPUT/git_status.txt"
args=(--raw-dir "$data_root/Raw/Barchart_futures")
if [[ -n "${2:-}" ]]; then args+=(--raw-dir "$2"); fi
export PYTHON_BIN="$python_bin"
matlab_bin="$(command -v matlab || true)"
if [[ -z "$matlab_bin" ]]; then
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi
if [[ -n "$matlab_bin" ]]; then
    "$matlab_bin" -batch "cd('$repo_dir/matlab'); Time_alignment_self_test();"
else
    printf 'MATLAB non disponibile: self-test MATLAB da eseguire separatamente.\n'
fi
bash scripts/Run_confirmation.sh audit --data-root "$data_root" "${args[@]}" \
    --output "$CONFIRMATION_PREPARATION_OUTPUT/audit"
bash scripts/Run_confirmation.sh bridge --generation-build "$build" \
    --output "$CONFIRMATION_PREPARATION_OUTPUT/bridge"
bash scripts/Run_confirmation.sh check-protocol > "$CONFIRMATION_PREPARATION_OUTPUT/protocol_readiness.json"
printf '\nPreparazione completata. Campione di conferma non stimato; specifica v2 ancora in bozza.\n'
