#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_phase_component_contrasts.sh /path/to/Econometrics_data [draws]" >&2
    exit 2
fi

data_root="$1"
draws="${2:-999}"
if ! [[ "$draws" =~ ^[0-9]+$ ]] || [ "$draws" -lt 19 ]; then
    echo "Draws must be an integer of at least 19." >&2
    exit 2
fi

step23_manifest="$data_root/Output/component_sufficiency/step23_manifest.csv"
step23_decision="$data_root/Output/component_sufficiency/step23_decision.csv"
if [ ! -f "$step23_manifest" ] || ! grep -q 'step23_v1' "$step23_manifest" || ! grep -q ',999' "$step23_manifest"; then
    echo "Final 999-draw step23_v1 manifest not found." >&2
    exit 2
fi
if [ ! -f "$step23_decision" ] || ! grep -q 'retain_mp_cbi_primary_pc2_diagnostic' "$step23_decision"; then
    echo "Step-23 MP-CBI retention decision not found." >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"
export PHASE_COMPONENT_CONTRAST_DRAWS="$draws"

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi
if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    exit 1
fi

"$matlab_bin" -batch "cd('$repo_dir'); Phase_component_contrast_self_test; Phase_component_contrasts" 2>&1 \
    | tee "$repo_dir/phase_component_contrasts_run.log"
