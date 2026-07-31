#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_invariant_phase_attribution.sh /path/to/Econometrics_data [draws]" >&2
    exit 2
fi

data_root="$1"
draws="${2:-999}"
if ! [[ "$draws" =~ ^[0-9]+$ ]] || [ "$draws" -lt 19 ]; then
    echo "Draws must be an integer of at least 19." >&2
    exit 2
fi

step24_manifest="$data_root/Output/phase_component_contrasts/step24_manifest.csv"
step24_decision="$data_root/Output/phase_component_contrasts/step24_decision.csv"
if [ ! -f "$step24_manifest" ] || ! grep -q 'step24_v1' "$step24_manifest" || \
        ! grep -q ',999' "$step24_manifest"; then
    echo "Final 999-draw step24_v1 manifest not found." >&2
    exit 2
fi
if [ ! -f "$step24_decision" ] || \
        ! grep -q 'phase_response_surfaces_differ' "$step24_decision" || \
        ! grep -q 'component_attribution_partial' "$step24_decision"; then
    echo "Final Step-24 phase-gap/partial-attribution decision not found." >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"
export INVARIANT_ATTRIBUTION_DRAWS="$draws"

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi
if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    exit 1
fi

"$matlab_bin" -batch "cd('$repo_dir'); Invariant_phase_attribution_self_test; Invariant_phase_attribution" 2>&1 \
    | tee "$repo_dir/invariant_phase_attribution_run.log"
