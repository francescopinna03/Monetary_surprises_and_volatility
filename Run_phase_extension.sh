#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_phase_extension.sh /path/to/Econometrics_data [certify|build|all]" >&2
    exit 2
fi

data_root="$1"
mode="${2:-all}"
case "$mode" in
    certify|build|all) ;;
    *)
        echo "Mode must be certify, build or all." >&2
        exit 2
        ;;
esac

time_manifest="$data_root/Output/manifests/time_alignment_manifest.csv"
if [ ! -f "$time_manifest" ] || ! grep -q 'timezone_v1' "$time_manifest" || ! grep -q 'complete' "$time_manifest"; then
    echo "Corrected timezone_v1 manifest not found. Run the corrected pipeline first." >&2
    exit 2
fi

if [ "$mode" = "build" ]; then
    semantics_manifest="$data_root/Output/manifests/window_semantics_manifest.csv"
    if [ ! -f "$semantics_manifest" ] || ! grep -q 'window_semantics_v1' "$semantics_manifest" || ! grep -q 'certified' "$semantics_manifest"; then
        echo "Certified window_semantics_v1 manifest not found. Run certify mode first." >&2
        exit 2
    fi
fi

export ECONOMETRICS_DATA_ROOT="$data_root"
export PHASE_EXTENSION_MODE="$mode"

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    exit 1
fi

"$matlab_bin" -batch "cd('$repo_dir'); Run_phase_extension" 2>&1 \
    | tee "$repo_dir/phase_extension_${mode}_run.log"
