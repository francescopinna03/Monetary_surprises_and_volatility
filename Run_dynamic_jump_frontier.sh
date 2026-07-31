#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_dynamic_jump_frontier.sh /path/to/Econometrics_data [draws]" >&2
    exit 2
fi

data_root="$1"
draws="${2:-999}"
if ! [[ "$draws" =~ ^[0-9]+$ ]] || [ "$draws" -lt 19 ]; then
    echo "Draws must be an integer of at least 19." >&2
    exit 2
fi

decision="$data_root/Output/rank_one_feasibility/step27a_decision.csv"
manifest="$data_root/Output/rank_one_feasibility/step27a_manifest.csv"
if [ ! -f "$decision" ] || \
        ! grep -Eq '^MODULE_A_RANK_GATE,pass,rank_one_is_admissible_not_established' "$decision" || \
        ! grep -Eq '^MODULE_B_JUMP_FRONTIER,eligible_not_run,freeze_module_b_design_before_execution' "$decision"; then
    echo "Final passing Module-A gate not found." >&2
    exit 2
fi
if [ ! -f "$manifest" ] || ! grep -q 'step27a_v1' "$manifest" || \
        ! grep -Eq '^bootstrap_draws,999\r?$' "$manifest"; then
    echo "Final 999-draw step27a_v1 manifest not found." >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"
export DYNAMIC_JUMP_FRONTIER_DRAWS="$draws"
if [ "$draws" -eq 999 ]; then
    log_dir="$data_root/Output/dynamic_jump_frontier"
else
    log_dir="$data_root/Output/dynamic_jump_frontier_smoke"
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

"$matlab_bin" -batch "cd('$repo_dir'); Dynamic_jump_frontier_self_test; Dynamic_jump_frontier" 2>&1 \
    | tee "$log_dir/step27b_run.log"
