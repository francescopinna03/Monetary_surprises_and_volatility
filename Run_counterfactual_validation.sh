#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_counterfactual_validation.sh /path/to/Econometrics_data [draws]" >&2
    exit 2
fi

data_root="$1"
manifest="$data_root/Output/manifests/time_alignment_manifest.csv"
window_file="$data_root/Output/analysis/announcement_counterfactual_windows.csv"

if [ ! -f "$manifest" ] || ! grep -q 'timezone_v1' "$manifest" || ! grep -q 'complete' "$manifest"; then
    echo "Corrected timezone_v1 manifest not found. Rerun Steps 1--18 from raw data." >&2
    exit 2
fi

if [ ! -f "$window_file" ] || ! head -1 "$window_file" | grep -q 'pseudo_pr_datetime_utc'; then
    echo "Corrected Step-18 input not found: $window_file" >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"

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
    echo "Usage: ./Run_counterfactual_validation.sh /path/to/Econometrics_data [draws]" >&2
    exit 1
fi

"$matlab_bin" -batch "cd('$repo_dir'); Announcement_counterfactual_validation" 2>&1 \
    | tee "$repo_dir/counterfactual_validation_run.log"
