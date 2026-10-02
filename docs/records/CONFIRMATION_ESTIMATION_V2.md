# The v2 confirmation chain: protected build, calibration, freeze and estimation

*Record written in September 2026 in Italian and translated into English. The original text is preserved in the repository history at commit `0f6daab`.*

Status: complete implementation of the chain. The specification `final_analysis_spec_v2.json` remains a draft until `Run_confirmation.sh freeze` resolves it into `frozen_v2`. No outcome of the confirmation sample was built during development.

This document describes only the four new stages. The inventory, the quality audit and the generation bridge are described in `CONFIRMATION_PROTOCOL_V2.md` and `CONFIRMATION_NEXT_STEPS.md`.

## Reviewed decisions

The five open questions are not settled by the code. `Run_confirmation.sh decisions-template` writes `Raw/Certification/confirmation_decisions_v2.json` with the admissible alternatives and with empty `reviewer`, `decided_on` and `rationale` fields. `load_decisions` rejects a file with a missing choice, an inadmissible choice, or a missing reviewer, rationale or date. No other module provides a fallback value.

| Key | Admissible alternatives |
|---|---|
| `pc_normal_pre_support` | v1 grid with endpoints −25 to −5, support (−30, −5] |
| `slow_state_rule` | mean over the five preceding **non-event** contract-days |
| `equity_source_rule` | homogeneous external STOXX50E for 2000–2012, or a hybrid with the fx futures where available |
| `secondary_family_rule` | secondary family of the specification, with a single joint history block |
| `us_calendar_status` | candidate screen only, or a supplied verified calendar |

The second entry is substantive. `final_analysis/data.py` computes `slow5_log_rv` from the daily realized variance of the five preceding contract-days, including meeting days, and therefore from post-announcement outcomes of events. On the confirmation sample that rule would read outcomes before the freeze. The v2 rule excludes event days from the computation. The difference between the two rules is measured on the **generation** sample and reported in `slow_state_validation_generation.csv`, never on the confirmation sample.

## Protected build

```bash
bash Run_confirmation_calibration.sh \
  "$HOME/Desktop/Monetary_surprises_FULL_rqjB5J" \
  /path/confirmation_quality_RUN/quality
```

The runner executes `control-build` and then `calibrate`, and ends with a readiness report. It produces a ZIP archive even after a failure.

`control-build` rebuilds the windows from the raw files already certified, in **blind mode**, so that no price after the announcement is read for any meeting. Event rows keep only the pre-release state window, the coverage and the certified admissibility. An explicit guard raises `BLINDING_VIOLATION` if any post-announcement quantity of an event is finite. The tables produced are the complete control days, the pre-release register of events and the EA-EMPD covariates.

The v2 normal-continuation layer differs from v1 in two declared respects, namely the absence of a 2022 regime indicator, which would be identically zero before 2013, and a trend whose origin is 1 January 2000. The v1 module is left untouched, so the bridge continues to verify its hashes.

## Ex-ante calibration

`calibrate` reads no confirmation outcome. The noise comes from the leave-one-year-out residuals of the abnormal bipower variation on Bund **control** root-days, resampled within the calendar year. The design uses the external EA-EMPD coordinates and the pre-release state, because the aligned Schatz coordinate of a meeting is itself a post-announcement quantity and remains unread until the freeze.

The stage produces two power curves, the detectable size of the two primary hypotheses on the grid `delta_grid` and the floor of the historical partial R² on `power_partial_r2_grid`, both with a 95 percent Wilson lower bound and the threshold `power_target`. The calibrated margin enters the frozen specification next to the scientific reference margin, which remains distinct, since an attainable precision is not a threshold of economic negligibility.

The detectable size is expressed in the external metric. The frozen primary test uses the aligned Schatz coordinate, the manifest states this, and the number must not be read as a threshold on the scale of the primary test.

## Freeze

```bash
bash Run_confirmation_final.sh \
  "$HOME/Desktop/Monetary_surprises_FULL_rqjB5J" \
  /path/confirmation_quality_RUN/quality \
  /path/confirmation_calibration_RUN/build \
  /path/confirmation_calibration_RUN/calibration \
  /path/confirmation_preparation_RUN/bridge \
  I_HAVE_REVIEWED_THE_FROZEN_SPECIFICATION
```

The final token is mandatory. The freeze is the only point at which the outcomes of the confirmation sample are built, and it cannot be reversed.

Before building, `freeze` verifies that the calibration belongs to the protected build, that the protected build belongs to the quality audit, that the decisions have not changed after the build, that the bridge is a generation-only diagnostic with intact tables, and that both families carrying a claim pass the resolution gate `1/(B+1) <= alpha/m`. With B = 19,999 and m = 2 the Holm threshold is 0.025 and the smallest attainable p-value is 0.00005, so a first rejection is possible. An existing destination directory is rejected.

The resolved specification records the chosen equity source, the calibrated margin, the outcomes of the four bridge checks and the two resolution gates.

## Estimation

`estimate` accepts only a `frozen_v2` build whose table, specification and code hashes are unchanged. It produces three separate files.

`primary_tests.csv` holds the two primary tests, H1, a positive mean over the MP cone, and H2, a positive difference between the MP and the CBI means, both on the press-release surface of the Bund at zero state, with the aligned Schatz coordinate, one-sided, with Holm over two. `primary_surface.csv` reports the raw matrix, the cone functionals, the eigenvalues and the principal direction, which are invariant under rotation and are not rotated MP and CBI energies.

`secondary_tests.csv` holds the declared secondary family, namely the modulation by the state, two-sided, on the interaction matrix, the same two hypotheses on abnormal realized variance, and the same two hypotheses within each of the two epochs. The eight p-values are corrected by Holm within the family and labelled as secondary.

`sensitivity_tests.csv` holds leave-top-K by total energy, alternative indicators, alternative roots and the US screen on the press-release branch only. There is no simultaneous correction and no claim, and every row carries the label `descriptive_no_simultaneous_claim`.

Inference remains conditional on the measured indicators and on the estimated continuation layer. The bootstrap does not integrate the uncertainty in the construction of the indicators.

## Step 28

`Raw/Certification/step28_sbb_specification_extended_calibration.csv` derives from the frozen specification and changes a single value, extending the sample-size grid to 500 meetings. Its purpose is to record where the extended sample stands relative to criteria that were already frozen.

```bash
STEP28_SBB_SPECIFICATION=Raw/Certification/step28_sbb_specification_extended_calibration.csv \
  ./Run_step28_gates.sh /path/Econometrics_data
```

This is an outcome-free calibration, with no bridge estimation and no event outcome. Its result belongs to the discussion of limits and not to the economic results.

## Remaining blocks of the readiness report

The readiness report remains blocking on `external_window_timing` until the start and end times of the EA-EMPD windows are tied to source evidence, and on `us_release_calendar` as long as only the candidate screen exists. A screen of Thursdays at 8:30 New York time is not a verified release calendar. These entries do not prevent the freeze by construction, but they prevent the result from being described as if those verifications had been made.
