#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_long_horizon_attribution.sh /path/to/Econometrics_data [draws]" >&2
    exit 2
fi

data_root="$1"
draws="${2:-999}"
if ! [[ "$draws" =~ ^[0-9]+$ ]] || [ "$draws" -lt 19 ]; then
    echo "Draws must be an integer of at least 19." >&2
    exit 2
fi

step25_manifest="$data_root/Output/invariant_phase_attribution/step25_manifest.csv"
step25_decision="$data_root/Output/invariant_phase_attribution/step25_decision.csv"
if [ ! -f "$step25_manifest" ] || ! grep -q 'step25_v1' "$step25_manifest" || \
        ! grep -q ',999' "$step25_manifest"; then
    echo "Final 999-draw step25_v1 manifest not found." >&2
    exit 2
fi
if [ ! -f "$step25_decision" ] || \
        ! grep -q 'both_bv_blocks_survive_holm_and_wild_cluster' "$step25_decision" || \
        ! grep -q 'mp_like_direction_set_identified' "$step25_decision" || \
        ! grep -q 'extend_ea_mpd_beyond_1y_before_excluding_omitted_components' "$step25_decision"; then
    echo "Final Step-25 invariant/long-horizon decision state not found." >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"
export LONG_HORIZON_ATTRIBUTION_DRAWS="$draws"
log_dir="$data_root/Output/long_horizon_attribution"
mkdir -p "$log_dir"

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi
if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    exit 1
fi

"$matlab_bin" -batch "cd('$repo_dir'); Long_horizon_phase_attribution_self_test; Long_horizon_phase_attribution" 2>&1 \
    | tee "$log_dir/step26_run.log"
