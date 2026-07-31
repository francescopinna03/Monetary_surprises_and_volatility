#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_component_sufficiency.sh /path/to/Econometrics_data [draws]" >&2
    exit 2
fi

data_root="$1"
draws="${2:-999}"

if ! [[ "$draws" =~ ^[0-9]+$ ]] || [ "$draws" -lt 19 ]; then
    echo "Draws must be an integer of at least 19." >&2
    exit 2
fi

time_manifest="$data_root/Output/manifests/time_alignment_manifest.csv"
semantics_manifest="$data_root/Output/manifests/window_semantics_manifest.csv"
if [ ! -f "$time_manifest" ] || ! grep -q 'timezone_v1' "$time_manifest"; then
    echo "Complete timezone_v1 manifest not found." >&2
    exit 2
fi
if [ ! -f "$semantics_manifest" ] || ! grep -q 'window_semantics_v1' "$semantics_manifest" || ! grep -q 'certified' "$semantics_manifest"; then
    echo "Certified window_semantics_v1 manifest not found." >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"
export COMPONENT_SUFFICIENCY_DRAWS="$draws"

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    exit 1
fi

"$matlab_bin" -batch "cd('$repo_dir'); Component_sufficiency_self_test; Component_sufficiency_analysis" 2>&1 \
    | tee "$repo_dir/component_sufficiency_run.log"
