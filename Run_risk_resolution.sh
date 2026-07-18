#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_risk_resolution.sh /path/to/Econometrics_data [smoke|final] [draws]" >&2
    exit 2
fi

data_root="$1"
mode="${2:-final}"

if [ ! -d "$data_root/Output/analysis" ]; then
    echo "Invalid data root: missing $data_root/Output/analysis" >&2
    exit 2
fi

if [ ! -f "$data_root/Output/analysis/announcement_rotation_date_matrices.csv" ]; then
    echo "Step-20 input not found: $data_root/Output/analysis/announcement_rotation_date_matrices.csv" >&2
    exit 2
fi

case "$mode" in
    smoke)
        draws="${3:-49}"
        case "$draws" in ''|*[!0-9]*) echo "Draws must be a positive integer." >&2; exit 2;; esac
        if [ "$draws" -lt 19 ]; then
            echo "Smoke mode requires at least 19 draws." >&2
            exit 2
        fi
        ;;
    final)
        draws="${3:-999}"
        case "$draws" in ''|*[!0-9]*) echo "Draws must be a positive integer." >&2; exit 2;; esac
        if [ "$draws" -lt 999 ]; then
            echo "Final mode refuses fewer than 999 draws." >&2
            exit 2
        fi
        ;;
    *)
        echo "Mode must be smoke or final." >&2
        exit 2
        ;;
esac

export ECONOMETRICS_DATA_ROOT="$data_root"
export ANNOUNCEMENT_RESOLUTION_MODE="$mode"
export ANNOUNCEMENT_RESOLUTION_DRAWS="$draws"
export STEP21_GIT_SHA="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || printf 'unavailable')"

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    exit 1
fi

"$matlab_bin" -batch "cd('$repo_dir'); Announcement_risk_resolution" 2>&1 \
    | tee "$repo_dir/risk_resolution_${mode}_run.log"
