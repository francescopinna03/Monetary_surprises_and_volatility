#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")" && pwd)"
facility="$(cd "$repo_dir/.." && pwd)"
python_bin="${PYTHON_BIN:-$facility/python_env/bin/python}"
[[ -x "$python_bin" ]] || { echo "Python mancante: $python_bin" >&2; exit 1; }
cd "$repo_dir"
if command -v caffeinate >/dev/null 2>&1; then
    exec caffeinate -i "$python_bin" -u facility_run.py --facility "$facility" "$@"
fi
exec "$python_bin" -u facility_run.py --facility "$facility" "$@"
