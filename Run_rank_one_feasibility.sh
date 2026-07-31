#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_rank_one_feasibility.sh /path/to/Econometrics_data [draws]" >&2
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
step26_manifest="$data_root/Output/long_horizon_attribution/step26_manifest.csv"
step26_decision="$data_root/Output/long_horizon_attribution/step26_decision.csv"

if [ ! -f "$step25_manifest" ] || ! grep -q 'step25_v1' "$step25_manifest" || \
        ! grep -Eq '^bootstrap_draws,"?999"?\r?$' "$step25_manifest"; then
    echo "Final 999-draw step25_v1 manifest not found." >&2
    exit 2
fi
if [ ! -f "$step25_decision" ] || \
        ! grep -q 'mp_like_direction_set_identified' "$step25_decision" || \
        ! grep -q 'mp_like_dominant_but_rank_one_not_established' "$step25_decision"; then
    echo "Required Step-25 MP-like/unresolved-rank decision not found." >&2
    exit 2
fi
if [ ! -f "$step26_manifest" ] || ! grep -q 'step26_v1' "$step26_manifest" || \
        ! grep -Eq '^bootstrap_draws,"?999"?\r?$' "$step26_manifest"; then
    echo "Final 999-draw step26_v1 manifest not found." >&2
    exit 2
fi
if [ ! -f "$step26_decision" ] || \
        ! grep -q 'abgmr_restrictions_and_generated_factor_stability_certified' "$step26_decision" || \
        ! grep -q 'no_robust_incremental_long_curve_evidence' "$step26_decision"; then
    echo "Required final Step-26 factor/attribution decision not found." >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"
export RANK_ONE_FEASIBILITY_DRAWS="$draws"
if [ "$draws" -eq 999 ]; then
    log_dir="$data_root/Output/rank_one_feasibility"
else
    log_dir="$data_root/Output/rank_one_feasibility_smoke"
fi
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

"$matlab_bin" -batch "cd('$repo_dir'); Rank_one_feasibility_self_test; Rank_one_feasibility" 2>&1 \
    | tee "$log_dir/step27a_run.log"
