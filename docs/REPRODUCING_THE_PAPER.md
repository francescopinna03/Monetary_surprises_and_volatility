# Correspondence between the paper and the runs

Every table and figure of the October 2026 version of the paper is generated from the archived output of one of the runs listed below. The tables are assembled by a script that reads the output files directly, so that no number is transcribed by hand. Commits refer to the working repository in which the runs were executed.

## Runs

| Run | Date | Commit | Runner | Status |
|---|---|---|---|---|
| Confirmation freeze v2 | 14 September 2026 | `4045b48` | `Run_confirmation_final.sh` | Frozen |
| Confirmation re-estimation v3 | 15 September 2026 | `4045b48` | `Run_confirmation_final.sh` | Declared second opening |
| Cross-period comparison | 16 September 2026 | `9d00951` | `Run_cross_epoch_checks.py` | Post-opening, outputs in `reference_outputs/cross_epoch_20260916` |
| One-minute outcomes | 28 September 2026 | `ff9e97b` | `Run_confirmation_minute.sh` | Post-opening |
| Radial exponent and sector information | 28 September 2026 | `ff9e97b` | `Run_design_information.sh` | Post-opening |
| FOMC calendar | 29 September 2026 | `65e5212` | `Run_fomc_calendar.sh` | Reviewed and promoted |
| FOMC replication | 29 September 2026 | `bb061b1` | `Run_fed_replication.sh` | Pre-registered |
| FOMC post-replication decomposition | 30 September 2026 | `92f37d3` | `Run_fed_post_replication.sh` | Descriptive |
| Measurement-error check | 30 September 2026 | `65e5212` | `Run_measurement_check.sh` | Post-opening |

## Tables and figures

| Item in the paper | Content | Output file |
|---|---|---|
| Table 1 | Samples, calendars and estimation counts | Verified calendars and run manifests |
| Table 2 | Mean branch with both coordinates | `mean_branch_with_equity.csv` of the cross-period run; `fed_mean_branch.csv` |
| Table 3 | Prediction error of three radial bases | `basis_summary.csv` of the cross-period run; `fed_basis_summary.csv` |
| Figure 1 | Abnormal variation against log amplitude | Event panels of the cross-period run; `fed_primary_event_panel.csv` |
| Table 4 | One-minute outcomes | `minute_robustness_measures.csv` |
| Table 5 and Figure 2 | Radial exponent | `radial_exponent_profile.csv`, `radial_exponent_curves.csv`; `fed_radial_exponent_profile.csv`, `fed_radial_exponent_curves.csv` |
| Table 6 | Elasticity, least squares and instrumented | `radial_exponent_profile.csv`; `measurement_check.csv` |
| Table 7 and Figure 3 | Measurement-error check | `measurement_check.csv`, `measurement_simulation_grid.csv` |
| Table 8 | Pre-registered FOMC family | `fed_primary_family.csv` |
| Table 9 | FOMC descriptive mean branch | `fed_mean_branch.csv` |
| Table 10 | FOMC post-replication decomposition | `fed_post_replication_split.csv` |
| Table 11 | Sector contrast and information required | `sector_contrast_information.csv`; `fed_sector_contrast_information.csv` |
| Table 12 | Runs behind the results | Run manifests |
| Tables 13 to 17 | Frozen tests, sub-periods, native cones, common support and power | `primary_tests.csv` and the reference outputs of the confirmation runs |
| Table 18 | One-minute descriptives | `minute_jump_descriptives.csv` |
| Table 19 | Central symmetry | `central_symmetry_odd_block.csv`; `fed_central_symmetry_odd_block.csv` |
| Table 20 | Sector contrast at a common target | `common_metric_cone_tests.csv` of the cross-period run |
| Tables 21 and 22 | Ridge folds and history interval | Outputs of the exploratory run on the 2000–2012 build |

## Reproducing a run

Each runner takes the facility directory as its first argument and, where relevant, the frozen build or the earlier run on which it depends. For example:

```bash
bash Run_design_information.sh /path/to/facility /path/to/Econometrics_data/Raw/Certification/final_confirmation_v2_20260915_112120_2190
bash Run_fed_replication.sh /path/to/facility
bash Run_measurement_check.sh /path/to/facility /path/to/Econometrics_data/Raw/Certification/final_confirmation_v2_20260915_112120_2190
```

Two stages compare the hashes of the executed code with those recorded in a frozen build and therefore reproduce exactly only with the code of the working repository at the commit listed above, namely the estimation on the 2000–2012 build and the preparation of the cross-period inputs. The other stages run from this repository, whose code differs from that of the working repository only by the removal of comments from newly added files.
