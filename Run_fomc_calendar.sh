#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")" && pwd)"
run_root="$(cd "${1:?Pass the facility directory}" && pwd)"
python_bin="${PYTHON_BIN:-$run_root/python_env/bin/python}"
data_root="$run_root/Econometrics_data"
fed_dir="$data_root/Raw/Barchart_futures_fed"
cache="$data_root/Raw/FOMC_calendar/pages"
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin" >&2; exit 1; }
[[ -d "$fed_dir" ]] || { echo "Fed directory missing: $fed_dir" >&2; exit 1; }
stamp="$(date +%Y%m%d_%H%M%S)_$$"
out="$data_root/Output/fomc_calendar_$stamp"
archive="${run_root}_fomc_calendar_${stamp}.zip"
mkdir -p "$out" "$cache"
exec > >(tee "$out/console.log") 2>&1
finish() {
    result=$?; trap - EXIT; set +e
    printf '%s\n' "$result" > "$out/exit_code.txt"
    CONFIRMATION_OUT="$out" CONFIRMATION_ZIP="$archive" "$python_bin" - <<'PY'
import os
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(os.environ['CONFIRMATION_OUT'])
with ZipFile(os.environ['CONFIRMATION_ZIP'], 'w', ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        if p.is_file():
            z.write(p, str(p.relative_to(root)))
print('ZIP da caricare:', os.environ['CONFIRMATION_ZIP'])
PY
    packaged=$?; [[ "$packaged" -eq 0 ]] || result=1; exit "$result"
}
trap finish EXIT
cd "$repo_dir"
git rev-parse HEAD > "$out/git_commit.txt"; git status --short > "$out/git_status.txt"
"$python_bin" -m confirmation_analysis.fomc_calendar candidates --fed-dir "$fed_dir" --output "$out/candidates" --cache-dir "$cache"
