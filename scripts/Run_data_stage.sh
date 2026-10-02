#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
data_root="${1:?Pass the Econometrics_data directory}"
[[ -d "$data_root/Raw" && -d "$data_root/Output" ]] || { echo "Invalid data root: $data_root" >&2; exit 2; }
export ECONOMETRICS_DATA_ROOT="$(cd "$data_root" && pwd)"
surprise_source="$(printf '%s' "${SURPRISE_SOURCE:-EA_EMPD}" | tr '[:lower:]-' '[:upper:]_')"
case "$surprise_source" in
    EA_EMPD|EA_MPD) ;;
    *) echo "SURPRISE_SOURCE must be EA_EMPD or EA_MPD." >&2; exit 2 ;;
esac
export SURPRISE_SOURCE="$surprise_source"
if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi
[[ -n "${matlab_bin:-}" ]] || { echo "MATLAB not found." >&2; exit 1; }
exec "$matlab_bin" -batch "cd('$repo_dir/matlab'); Run_data_stage"
