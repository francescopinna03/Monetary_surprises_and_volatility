#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ $# -ge 1 ]; then
    export ECONOMETRICS_DATA_ROOT="$1"
fi

if [ $# -ge 2 ]; then
    export ANNOUNCEMENT_VALIDATION_DRAWS="$2"
else
    unset ANNOUNCEMENT_VALIDATION_DRAWS || true
fi

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    echo "Usage: ./Run_counterfactual_validation.sh [/path/to/Econometrics_data] [draws]" >&2
    exit 1
fi

"$matlab_bin" -batch "cd('$repo_dir'); Announcement_counterfactual_validation" 2>&1 \
    | tee "$repo_dir/counterfactual_validation_run.log"
