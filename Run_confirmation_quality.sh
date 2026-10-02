#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")" && pwd)"
run_root="${1:?Pass the existing Monetary_surprises_FULL directory}"
shift
python_bin="${PYTHON_BIN:-$run_root/python_env/bin/python}"
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin" >&2; exit 1; }
cd "$repo_dir"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export PYTHONUNBUFFERED=1
exec "$python_bin" -m confirmation_analysis.quality_run --run-root "$run_root" "$@"
