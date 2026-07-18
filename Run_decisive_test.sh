#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_decisive_test.sh /path/to/Econometrics_data [smoke|final] [draws]" >&2
    exit 2
fi

data_root="$1"
mode="${2:-final}"

if [ ! -d "$data_root/Output/cleaned" ]; then
    echo "Invalid data root: missing $data_root/Output/cleaned" >&2
    exit 2
fi

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

case "$mode" in
    smoke)
        draws="${3:-49}"
        case "$draws" in ''|*[!0-9]*) echo "Draws must be a positive integer." >&2; exit 2;; esac
        "$repo_dir/Run_risk_rotation.sh" "$data_root" "$draws"
        "$repo_dir/Run_risk_resolution.sh" "$data_root" smoke "$draws"
        ;;
    final)
        draws="${3:-999}"
        case "$draws" in ''|*[!0-9]*) echo "Draws must be a positive integer." >&2; exit 2;; esac
        if [ "$draws" -lt 999 ]; then
            echo "Final mode refuses fewer than 999 draws." >&2
            exit 2
        fi
        "$repo_dir/Run_risk_rotation.sh" "$data_root" "$draws"
        "$repo_dir/Run_risk_resolution.sh" "$data_root" final "$draws"
        ;;
    *)
        echo "Mode must be smoke or final." >&2
        exit 2
        ;;
esac
