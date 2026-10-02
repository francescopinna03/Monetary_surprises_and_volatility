#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")" && pwd)"
run_root="$(cd "${1:?Pass the existing Monetary_surprises_FULL directory}" && pwd)"
data_root="$run_root/Econometrics_data"
python_bin="$run_root/python_env/bin/python"
[[ -x "$python_bin" ]] || { echo "Existing Python environment missing." >&2; exit 1; }
[[ -d "$data_root/Output/cleaned" ]] || { echo "Existing cleaned data missing." >&2; exit 1; }
matlab_bin="$(command -v matlab || true)"
if [[ -z "$matlab_bin" ]]; then
    matlab_bin="$(ls -d /Applications/MATLAB_*.app/bin/matlab 2>/dev/null | sort | tail -1 || true)"
fi
[[ -n "$matlab_bin" ]] || { echo "MATLAB not found." >&2; exit 1; }

stamp="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="$run_root/logs/resume_$stamp"
mkdir -p "$log_dir"
for name in current_stage.txt exit_code.txt; do
    if [[ -f "$run_root/logs/$name" ]]; then cp "$run_root/logs/$name" "$log_dir/previous_$name"; fi
done
export ECONOMETRICS_DATA_ROOT="$data_root"
export REPLICATION_ROOT="$run_root" REPLICATION_REPO="$repo_dir"
export REPLICATION_ARCHIVE="${run_root}_resume_${stamp}_results.zip"
export REPLICATION_DRIVER="$log_dir/Run_resume_step16.m"
export PYTHON_BIN="$python_bin" PYTHONUNBUFFERED=1 SURPRISE_SOURCE=EA_EMPD
export PATH="$(dirname "$python_bin"):$(dirname "$matlab_bin"):$PATH"
unset FINAL_ANALYSIS_BUILD STEP28_SBB_SPECIFICATION
export STEP21_GIT_SHA="$(git -C "$repo_dir" rev-parse HEAD)"
exec > >(tee -a "$run_root/logs/full_run.log" "$log_dir/console.log") 2>&1

finish() {
    result=$?
    trap - EXIT
    set +e
    printf '%s\n' "$result" > "$run_root/logs/exit_code.txt"
    printf '%s\n' "$result" > "$log_dir/exit_code.txt"
    if "$python_bin" - <<'PACKAGE'
import os
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path(os.environ['REPLICATION_ROOT'])
repo = Path(os.environ['REPLICATION_REPO'])
targets = [root/'logs', root/'Econometrics_data/Output']
if os.environ.get('FINAL_ANALYSIS_BUILD'):
    targets.append(Path(os.environ['FINAL_ANALYSIS_BUILD']))
targets.extend(root/'Econometrics_data/Raw/Certification'/name for name in
               ['window_semantics_inputs.csv', 'step28_sbb_specification.csv', 'us_releases.csv'])
code = ['Archive_analysis_outputs.m', 'BNS_volatility.m', 'Quasi_markov_input_gate.m',
        'Quasi_markov_input_self_test.m', 'Quasi_markov_residual_predictability.m',
        'Run_pipeline.m', 'Run_resume_after_bns.sh', 'FINAL_ANALYSIS_PROTOCOL.md',
        'Raw/Certification/final_analysis_spec_v1.json']
with ZipFile(os.environ['REPLICATION_ARCHIVE'], 'w', ZIP_DEFLATED) as archive:
    for target in targets:
        for path in target.rglob('*') if target.is_dir() else [target]:
            if not path.is_file(): continue
            rel = path.relative_to(root)
            if rel.parts[:3] == ('Econometrics_data', 'Output', 'cleaned'): continue
            archive.write(path, str(rel))
    for name in code:
        archive.write(repo/name, 'executed_code/'+name)
PACKAGE
    then
        printf '\nCodice di uscita: %s\nZIP da caricare: %s\n' "$result" "$REPLICATION_ARCHIVE"
    else
        printf 'Creazione ZIP fallita. Log e risultati sono in %s\n' "$run_root"
        result=1
    fi
    exit "$result"
}
trap finish EXIT
if command -v caffeinate >/dev/null 2>&1; then caffeinate -i -w "$$" & fi
cd "$repo_dir"
git show -s --format=fuller HEAD > "$log_dir/git_commit.txt"
git diff --binary > "$log_dir/git_diff.patch"
git status --short > "$log_dir/git_status.txt"
"$python_bin" -m pip freeze > "$log_dir/python_packages.txt"

"$python_bin" - <<'DRIVER'
import os
from pathlib import Path
source = (Path(os.environ['REPLICATION_REPO'])/'Run_pipeline.m').read_text()
start = "fprintf('\\n[ 1/27] Audit_Barchart"
resume = "fprintf('\\n[16/27] BNS_volatility"
assert source.count(start) == source.count(resume) == 1, 'Unexpected master driver'
assert source.index(start) < source.index(resume)
driver = source[:source.index(start)] + source[source.index(resume):]
Path(os.environ['REPLICATION_DRIVER']).write_text(driver)
DRIVER

stage() {
    printf '\nAvvio: %s\n' "$1"
    printf '%s\n' "$1" > "$run_root/logs/current_stage.txt"
    printf '%s\n' "$1" > "$log_dir/current_stage.txt"
}
stage resume_pipeline_16_27
"$matlab_bin" -batch "addpath(getenv('REPLICATION_REPO')); run(getenv('REPLICATION_DRIVER'));"

stage final_freeze
export FINAL_ANALYSIS_BUILD="$data_root/Raw/Certification/final_resume_$stamp"
bash Run_final_analysis.sh freeze --data-root "$data_root" --build "$FINAL_ANALYSIS_BUILD"
stage final_estimate
bash Run_final_analysis.sh estimate --data-root "$data_root" --build "$FINAL_ANALYSIS_BUILD" \
    --output "$data_root/Output/final_resume_$stamp"
stage final_matlab_checks
"$matlab_bin" -batch "Run_final_matlab_checks"
stage step28_preparation
"$python_bin" step28_prepare_barchart.py "$data_root"
stage step28_gates_and_sbb
"$matlab_bin" -batch "d28=Run_step28(); if String_to_boolean(d28.ready_for_sample_size_gate(1)); Run_step28_gates(); Run_step28_sbb(); else; fprintf('Step 28 fermo al data gate.\n'); end"
stage complete
