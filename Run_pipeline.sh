#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_pipeline.sh /path/to/Econometrics_data" >&2
    exit 2
fi

data_root="$1"

if [ ! -d "$data_root/Raw" ]; then
    echo "Invalid data root: missing $data_root/Raw" >&2
    exit 2
fi

if [ ! -d "$data_root/Output" ]; then
    echo "Invalid data root: missing $data_root/Output" >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"
export STEP21_GIT_SHA="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || printf 'unavailable')"

# Run_pipeline.m repeats this lock inside MATLAB so that both supported entry
# points (shell and direct MATLAB invocation) produce the same final run.
export ANNOUNCEMENT_VALIDATION_DRAWS=999
export ANNOUNCEMENT_ROTATION_DRAWS=999
export ANNOUNCEMENT_RESOLUTION_MODE=final
export ANNOUNCEMENT_RESOLUTION_DRAWS=999

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    echo "Usage: ./Run_pipeline.sh /path/to/Econometrics_data" >&2
    exit 1
fi

exec "$matlab_bin" -batch "cd('$repo_dir'); Run_pipeline"
