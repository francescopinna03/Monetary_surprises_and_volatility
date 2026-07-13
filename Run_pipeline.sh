#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ $# -ge 1 ]; then
    export ECONOMETRICS_DATA_ROOT="$1"
fi

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    echo "Usage: ./Run_pipeline.sh [/path/to/Econometrics_data]" >&2
    exit 1
fi

exec "$matlab_bin" -batch "cd('$repo_dir'); Run_pipeline"
