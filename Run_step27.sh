#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_step27.sh /path/to/Econometrics_data" >&2
    exit 2
fi

data_root="$1"
if [ ! -d "$data_root/Raw" ] || [ ! -d "$data_root/Output" ]; then
    echo "Invalid data root: expected Raw and Output under $data_root" >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"
export RANK_ONE_FEASIBILITY_DRAWS=999
export DYNAMIC_JUMP_FRONTIER_DRAWS=999

log_dir="$data_root/Output/step27"
mkdir -p "$log_dir"

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    exit 1
fi

"$matlab_bin" -batch "cd('$repo_dir'); Run_step27" 2>&1 \
    | tee "$log_dir/step27_run.log"
