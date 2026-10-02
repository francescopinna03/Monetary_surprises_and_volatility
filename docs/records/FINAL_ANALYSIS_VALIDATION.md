# Verification of the implementation

*Record written between 10 and 11 September 2026 in Italian and translated into English. The original text is preserved in the repository history at commit `0a10406`.*

Verification performed on 10 September 2026 on base commit `af799bae170d1ecfc3be6aefcc74a8111c06b816`, with uncommitted local changes in the clone only. The validation run was executed before the commit of the pull request, and the hashes of the executed code remain in the manifest.

- Fifteen Python tests pass. They cover endpoints, missing and duplicated bars, zero bipower variation, asymmetric daylight saving time, changes in ECB release times, releases at the boundaries, CR1 covariance, unit invariance of the wild bootstrap, the rank and sample-size gates, the JK reconstruction, Holm, partial R², the paired sample and the rejection of invalid builds or certifications.
- The build from real data completed: 219 files actually needed for the period, 3,273,396 bars, 13,575 selected root-days and 27,150 phase rows. The fingerprint covers all 222 available cleaned files, including those outside the loaded subset.
- Register of 114 meetings, 4 roots and 2 phases, for 912 rows. Every root–phase has 114 complete windows and 111 observations with OIS1Y available. Further exclusions for shocks, logarithms, history and model remain in the sample registers.
- Comparison with the pre-existing certified outputs: more than 6,500 windows per phase on the same contract, with a maximum absolute discrepancy of about `1.0e-16` for pre- and post-window realized variance and bipower variation. Details are in `Raw/Certification/final_analysis_window_reconstruction_check.csv`.
- The complete runner finished with 999 wild replications and 499 replications for the history and power diagnostics. It produced 992 rows of phase tests and 16 mean tests, with audits of rotations and of leave-top-K. The press-release sensitivity to possible US news produced 16 further tests, with 80 to 85 clusters depending on K.
- The paired press-release–press-conference sensitivity to US news stops, because 4 to 5 meetings remain, below the gate of 30. The filter considers every potential coincidence at 08:30 and not a verified calendar, so this outcome does not demonstrate absorption of US news.
- MATLAB and Octave were not available in the verification environment. The MATLAB files were reviewed and the driver and self-test are provided, but **the MATLAB rerun of the shrinkage step was not executed**. A successful Python run is not equivalent to a certification of the MATLAB execution.

Environment of the complete run: Python 3.12.14, NumPy 2.3.5, pandas 2.2.3, SciPy 1.17.0, seed 20260910, status `complete_conditional_inference`. The wild bootstrap conditions on the indicators and on the estimated normal layer and does not integrate first-stage uncertainty. The numbers reported here certify execution and data support, not new structural conclusions.

The complete manifests, the registers of each model and the tables are regenerated with `freeze` and `estimate` as described in `FINAL_ANALYSIS_PROTOCOL.md`. The public snapshot contains availability, times and source names, without prices or surprise intensities.

## MATLAB rerun of 11 September 2026

The external runs `Monetary_surprises_FULL_4IvvOA` and `Monetary_surprises_FULL_rqjB5J`, on commit `9b54c1c`, complete Steps 1 to 15 in MATLAB R2025b Update 3. The nine coefficient files are identical byte for byte. The 228 fx and gg windows have five returns each, and the maximum discrepancy between the window realized variance and its reconstruction from the bars is `3.524e-19`. The shrinkage step selects index 1, that is, the strongest penalty within the one-standard-error band, for all three outcomes. This verifies the historical Step 14, not yet the rerun with the frozen pre-release selection.

Both runs stop at Step 17, because Step 16 records `median_bar_count_too_small` and does not produce the BNS panel. The correction keeps the threshold of six bars, records the bipower variation as blocked and routes only realized variance to the state panel, checking the hashes of the inputs. It includes `Quasi_markov_input_self_test` for residual files, blocked and passed gates, missing panels and changed hashes. The shell and Python syntax and the boundaries of the resumption are verified, while the new MATLAB self-test must be run on the user's machine. `Run_resume_after_bns.sh` runs it before resuming from Step 16 and keeps the logs and code of the resumption in the ZIP archive.

## Resumption completed on 11 September 2026

The archive `Monetary_surprises_FULL_rqjB5J_finish_20260911_182722_5429_results.zip` ends with `current_stage=complete` and `exit_code=0`. The Quasi-Markov self-test, Steps 16 to 27, the Python battery and the auxiliary MATLAB rebuild are complete.

The 23 files of the Python battery are identical before and after the rebuild (999 wild replications, 499 for power). The 228 MATLAB press-release windows use the same contracts as the Python build, with a maximum realized-variance discrepancy of `1.247e-17`. The shrinkage step selects index 1 for the three outcomes. The BNS step remains blocked with five returns per window.

Step 28 passes the data gate (165 of 165 contracts), but no point of the 20–120 grid passes calibration. 100 meetings per phase remain, with 300 press-release and 700 press-conference transitions. Decision `blocked_before_sbb`, so the subsequent gates that were not executed are planned stops.

Conditional inference, the unverified US calendar and the insufficient resolution of the 896 Holm tests with 999 replications remain declared. This note supersedes the earlier pending verifications and does not modify the statistical specification. Historical and final outputs have separate provenance, and archives containing market data remain separate from the repository.
