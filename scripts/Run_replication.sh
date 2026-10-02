#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
facility="$(cd "${1:?Pass the facility directory}" && pwd)"
token="${2:?Pass the review token required by the confirmation freeze}"
data_root="$facility/Econometrics_data"
python_bin="${PYTHON_BIN:-$facility/python_env/bin/python}"
dry_run="${DRY_RUN:-0}"
state="$data_root/Output/replication_state.env"
log="$data_root/Output/replication.log"
[[ -x "$python_bin" ]] || { echo "Python environment missing: $python_bin" >&2; exit 1; }
[[ -d "$data_root/Raw" ]] || { echo "Data directory missing: $data_root" >&2; exit 1; }
mkdir -p "$data_root/Output"
touch "$state"
source "$state"
export PYTHON_BIN="$python_bin"
cd "$repo_dir"

missing=""
need_dir() { [[ -d "$1" ]] || missing="$missing    $2"$'\n'; }
need_file() { [[ -f "$1" ]] || missing="$missing    $2"$'\n'; }
for d in Barchart_futures Barchart_futures_confirmation Barchart_futures_1min Barchart_futures_fed ECB_calendar; do
    need_dir "$data_root/Raw/$d" "Raw/$d"
done
for f in EA-EMPD/EA-EMPD.xlsx Certification/window_semantics_inputs.csv Certification/ecb_calendar_verified_v2.csv Certification/bar_label_evidence_v2.csv Certification/fomc_calendar_verified.csv; do
    need_file "$data_root/Raw/$f" "Raw/$f"
done
if [[ -f "$data_root/Raw/Certification/window_semantics_inputs.csv" ]]; then
    while IFS=, read -r role relative rest || [[ -n "$role" ]]; do
        [[ "$role" == "role" || -z "$relative" ]] && continue
        need_file "$data_root/$relative" "$relative"
    done < "$data_root/Raw/Certification/window_semantics_inputs.csv"
fi
for f in Raw/Certification/fed_protocol_v1.json Raw/Certification/confirmation_decisions_v2.json Raw/Certification/final_analysis_spec_v1.json Raw/Certification/final_analysis_spec_v2.json reference_outputs/cross_epoch_20260916/inputs/analysis_protocol.json reference_outputs/cross_epoch_20260916/inputs/generation_harmonized_native_state.csv; do
    need_file "$repo_dir/$f" "repository: $f"
done
if [[ -n "$missing" ]]; then
    printf 'Missing inputs, nothing was run:\n%s' "$missing" >&2
    exit 1
fi
echo "Preflight: every required input is present" | tee -a "$log"

latest() {
    ls -dt $1 2>/dev/null | head -1
}

record() {
    printf 'export %s=%q\n' "$1" "$2" >> "$state"
    export "$1=$2"
}

skipped=0

stage() {
    local name="$1"; shift
    local flag="DONE_$name"
    skipped=0
    if [[ "${!flag:-0}" == "1" ]]; then
        skipped=1
        echo "[$(date +%H:%M:%S)] $name: already completed, skipped" | tee -a "$log"
        return
    fi
    echo "[$(date +%H:%M:%S)] $name: start" | tee -a "$log"
    if [[ "$dry_run" == "1" ]]; then
        echo "    $*" | tee -a "$log"
    else
        "$@"
    fi
    echo "[$(date +%H:%M:%S)] $name: done" | tee -a "$log"
}

keep() {
    [[ "$dry_run" == "1" || "$skipped" == "1" ]] || record "$1" "$2"
}

finish_stage() {
    [[ "$dry_run" == "1" || "$skipped" == "1" ]] || record "DONE_$1" 1
}

cross_epoch_inputs() {
    rm -rf "$data_root/Output/cross_epoch_inputs_replication"
    "$python_bin" scripts/Prepare_cross_epoch_inputs.py --generation "$GENERATION_BUILD" --historical "$HISTORICAL_RUN" --bridge "$BRIDGE_DIR" --out "$data_root/Output/cross_epoch_inputs_replication"
    cp "$repo_dir/reference_outputs/cross_epoch_20260916/inputs/analysis_protocol.json" "$data_root/Output/cross_epoch_inputs_replication/"
}

cross_epoch_checks() {
    rm -rf "$data_root/Output/cross_epoch_replication"
    "$python_bin" scripts/Run_cross_epoch_checks.py --inputs "$data_root/Output/cross_epoch_inputs_replication" --out "$data_root/Output/cross_epoch_replication"
}

stage data_stage bash scripts/Run_data_stage.sh "$data_root"
finish_stage data_stage

stage generation_build bash scripts/Run_final_analysis.sh freeze --data-root "$data_root" --build "$data_root/Raw/Certification/generation_build_replication"
keep GENERATION_BUILD "$data_root/Raw/Certification/generation_build_replication"
finish_stage generation_build

stage preparation bash scripts/Run_confirmation_prepare.sh "$facility"
keep BRIDGE_DIR "$(latest "$data_root/Output/confirmation_preparation_*/bridge")"
finish_stage preparation

stage inventory bash scripts/Run_confirmation_inventory.sh "$facility"
finish_stage inventory

stage quality bash scripts/Run_confirmation_quality.sh "$facility" --canonical-raw-dir "$data_root/Raw/Barchart_futures_confirmation" --bridge-dir "${BRIDGE_DIR:-BRIDGE_DIR}"
keep QUALITY_DIR "$(latest "$data_root/Output/confirmation_quality_*/quality")"
finish_stage quality

stage calibration bash scripts/Run_confirmation_calibration.sh "$facility" "${QUALITY_DIR:-QUALITY_DIR}"
keep CALIBRATION_RUN "$(latest "$data_root/Output/confirmation_calibration_*")"
finish_stage calibration

stage first_freeze bash scripts/Run_confirmation_final.sh "$facility" "${QUALITY_DIR:-QUALITY_DIR}" "${CALIBRATION_RUN:-CALIBRATION_RUN}/build" "${CALIBRATION_RUN:-CALIBRATION_RUN}/calibration" "${BRIDGE_DIR:-BRIDGE_DIR}" "$token"
keep FIRST_FROZEN "$(latest "$data_root/Raw/Certification/final_confirmation_v2_*")"
finish_stage first_freeze

stage second_estimation bash scripts/Run_confirmation_final.sh "$facility" "${QUALITY_DIR:-QUALITY_DIR}" "${CALIBRATION_RUN:-CALIBRATION_RUN}/build" "${CALIBRATION_RUN:-CALIBRATION_RUN}/calibration" "${BRIDGE_DIR:-BRIDGE_DIR}" "$token" "${FIRST_FROZEN:-FIRST_FROZEN}"
keep FROZEN "$(latest "$data_root/Raw/Certification/final_confirmation_v2_*")"
keep HISTORICAL_RUN "$(latest "$data_root/Output/confirmation_final_*")"
finish_stage second_estimation

stage exploratory bash scripts/Run_confirmation_exploratory.sh "$facility" "${FROZEN:-FROZEN}" "${CALIBRATION_RUN:-CALIBRATION_RUN}/calibration"
finish_stage exploratory

stage jump bash scripts/Run_confirmation_jump.sh "$facility" "${FROZEN:-FROZEN}" "${QUALITY_DIR:-QUALITY_DIR}"
finish_stage jump

stage minute bash scripts/Run_confirmation_minute.sh "$facility" "${FROZEN:-FROZEN}"
finish_stage minute

stage design_information bash scripts/Run_design_information.sh "$facility" "${FROZEN:-FROZEN}"
finish_stage design_information

stage cross_epoch_inputs cross_epoch_inputs
finish_stage cross_epoch_inputs

stage cross_epoch cross_epoch_checks
finish_stage cross_epoch

stage fed_replication bash scripts/Run_fed_replication.sh "$facility"
finish_stage fed_replication

stage fed_post_replication bash scripts/Run_fed_post_replication.sh "$facility"
finish_stage fed_post_replication

stage measurement_check bash scripts/Run_measurement_check.sh "$facility" "${FROZEN:-FROZEN}"
finish_stage measurement_check

stage comparison "$python_bin" scripts/Compare_with_archive.py --data-root "$data_root" --cross-epoch "$data_root/Output/cross_epoch_replication"
finish_stage comparison

echo "Replication complete. Log: $log"
