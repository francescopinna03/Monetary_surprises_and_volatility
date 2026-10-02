#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 1 ] || [ -z "${1:-}" ]; then
    echo "Usage: ./Run_step28_gates.sh /path/to/Econometrics_data [specification.csv]" >&2
    exit 2
fi

data_root="$1"
if [ ! -d "$data_root/Raw" ] || [ ! -d "$data_root/Output" ]; then
    echo "Invalid data root: expected Raw and Output under $data_root" >&2
    exit 2
fi

export ECONOMETRICS_DATA_ROOT="$data_root"
surprise_source="${SURPRISE_SOURCE:-EA_EMPD}"
surprise_source="$(printf '%s' "$surprise_source" | tr '[:lower:]-' '[:upper:]_')"
case "$surprise_source" in
    EA_EMPD|EA_MPD) ;;
    *) echo "SURPRISE_SOURCE must be EA_EMPD or EA_MPD." >&2; exit 2 ;;
esac
export SURPRISE_SOURCE="$surprise_source"

if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then
    if [ ! -f "$2" ]; then
        echo "Frozen specification not found: $2" >&2
        exit 2
    fi
    export STEP28_SBB_SPECIFICATION="$2"
fi

if command -v matlab >/dev/null 2>&1; then
    matlab_bin="matlab"
else
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${matlab_bin:-}" ]; then
    echo "MATLAB not found. Add matlab to PATH or install it in /Applications." >&2
    exit 1
fi

log_dir="$data_root/Output/step28_sbbts"
mkdir -p "$log_dir"
echo "Step 28 surprise source: $SURPRISE_SOURCE"
"$matlab_bin" -batch "cd('$repo_dir'); Run_step28_gates" 2>&1 \
    | tee "$log_dir/step28_gates_run.log"
