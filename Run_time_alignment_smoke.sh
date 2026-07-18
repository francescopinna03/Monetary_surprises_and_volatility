#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_time_alignment_smoke.sh /path/to/Econometrics_data" >&2
    exit 2
fi

data_root="$1"

if [ ! -d "$data_root/Raw/Barchart_futures" ]; then
    echo "Invalid data root: missing $data_root/Raw/Barchart_futures" >&2
    exit 2
fi

if [ ! -d "$data_root/Output" ]; then
    echo "Invalid data root: missing $data_root/Output" >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    exit 1
fi

exec "$matlab_bin" -batch "cd('$repo_dir'); Run_time_alignment_smoke"
