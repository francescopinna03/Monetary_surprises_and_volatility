#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_shock_components.sh /path/to/Econometrics_data" >&2
    exit 2
fi

data_root="$1"
manifest="$data_root/Output/manifests/time_alignment_manifest.csv"
semantics_manifest="$data_root/Output/manifests/window_semantics_manifest.csv"

if [ ! -d "$data_root/Raw/EA_MPD" ]; then
    echo "EA-MPD directory not found: $data_root/Raw/EA_MPD" >&2
    exit 2
fi

if [ ! -f "$manifest" ] || ! grep -q 'timezone_v1' "$manifest" || ! grep -q 'complete' "$manifest"; then
    echo "Corrected timezone_v1 manifest not found. Run the corrected pipeline first." >&2
    exit 2
fi

if [ ! -f "$semantics_manifest" ] || ! grep -q 'window_semantics_v1' "$semantics_manifest" || ! grep -q 'certified' "$semantics_manifest"; then
    echo "Certified window_semantics_v1 manifest not found. Run Window_semantics_certification first." >&2
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

"$matlab_bin" -batch "cd('$repo_dir'); Shock_component_self_test; Shock_component_construction" 2>&1 \
    | tee "$repo_dir/shock_components_run.log"
