#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")" && pwd)"
run_root="${1:?Pass the existing Monetary_surprises_FULL directory}"
shift
python_bin="${PYTHON_BIN:-$run_root/python_env/bin/python}"
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin"; exit 1; }
cd "$repo_dir"
exec "$python_bin" -m confirmation_analysis.inventory --run-root "$run_root" "$@"
