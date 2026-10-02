# Frozen specification for the new estimation

*Record written in September 2026 in Italian and translated into English. The original text is preserved in the repository history at commit `0a10406`. The file name is unchanged because the resumption scripts include it in their hashed inputs.*

This implementation keeps the three levels of the research question. The final branch starts from the phase counterfactual, does not reopen the gates of Steps 26 to 28 and does not recover the April tables. The specification is `Raw/Certification/final_analysis_spec_v1.json`. It is a freeze subsequent to the exploratory audit and not a retroactive pre-registration, so `prior_results_seen=true` remains in the manifest.

## Conventions and sample

| Object | Executable definition |
|---|---|
| PR | Returns with endpoints at +5, +10, +15, +20 and +25 minutes, with effective support `(PR, PR+25]` |
| PC | Endpoints at +5 to +45, with support `(PC, PC+45]` |
| State and contract selection | Endpoints at −55 to −5 relative to PR, with support `(PR−60, PR−5]` |
| Prediction of the normal continuation | Pre-PR window for PR; endpoints PC−25 to PC−5 for PC, as in the existing phase counterfactual |
| Clock | UTC, end-of-interval timestamps; `interval_start` requires a shift of five minutes |
| Missing data | No filling, no interpolation and no return between non-consecutive bars; every required pair must be present |
| Outcome | Bipower variation as primary, realized variance as sensitivity; zeros are excluded from the logarithm and are not replaced by a constant |
| Assets | fx and gg as primary; fx, gg, hf and hr only in the declared sensitivity |
| Contract | Completeness and pre-PR coverage, then pre-PR volume, and finally the file name to break ties; no post-PR variable enters the ranking |

Realized variance and bipower variation are functions of the same vector of returns. The bipower variation is `(pi/2) sum(abs(r_j*r_{j-1}))`, without a correction for M. With five press-release returns the admissible language is *bipower proxy* and *RV−BV residual*, and the code does not attribute variation structurally to a continuous component and to jumps.

The pre-PC window of the continuation model may contain press-release news. This conditioning is kept so that the new battery can be compared with the existing layer, and it is distinct from the state that modulates the effect, which is always pre-PR. The normalization of the state uses control days only and does not depend on the chosen outcome. The requirement of complete pairs and of five available days for the slow state is stricter than the historical coverage of 80 percent and the mean over up to five available days, and the resulting changes in N are recorded.

`event_registry.csv` includes every meeting of the calendar, every root and every phase, even when the contract or the surprise is missing. It distinguishes price coverage, positivity of bipower variation and realized variance for the logarithm, the availability of each indicator and macro status. The sample registers produced by the estimation add the effective exclusions by model, outcome, indicator and leave-top-K. Modules with different requirements are not forced to have the same N.

## Indicators and phase comparisons

The primary aligned proxy is the Schatz log return with its sign reversed, and the equity coordinate is the net fx return in the same phase. Both coordinates must close with the outcome. The units are standard deviations over the pooled PR and PC control days, common to both phases and without centring. They are not basis points of interest rates and not an exogenous structural shock.

The Schatz–Bobl sensitivity is the equally weighted mean of the two price returns with their signs reversed, each divided by its standard deviation over control days. OIS1Y and the EA-EMPD first principal component remain two separate branches, each with the equity coordinate of its source. For PC they are explicitly **ex post**, since changing the OIS maturity does not correct the temporal misalignment. Each branch is estimated on its own paired PR–PC sample and then on the sample common to all branches.

The battery replicates the quadratic-surface contrast of Step 24 and the invariant geometry of Step 25 within the final runner. It does not call the old functions of Steps 24 and 25 automatically, because they depend on historical manifests and gates. The geometric metric is the pooled covariance of the coordinates, counting a single observation per meeting-phase, and the bootstrap intervals are conditional on this metric. The rotations at 0.1, 0.25, 0.5, 0.75 and 0.9 are a finite audit, not the whole identified set and not a proof of an MP/CBI attribution.

Leave-top-K uses K = 0, 1, 3 and 5 and rankings by total, MP and CBI energy at the meeting level. Removing a meeting removes both phases and all its assets. The rotation uses the paired meetings of the declared sample and is re-estimated on the reduced sample, a choice distinct from the historical rotation estimated on the full calendar of the source. The counterfactual, estimated on non-ECB days, remains unchanged when only ECB meetings are removed. Every declared contrast has a wild p-value, and no classical p-value is promoted in its place.

## Level 1 and inference

The mean branch uses the press-release OIS1M surprise divided by ten, signed and absolute in separate specifications, the pre-PR state, the interaction between surprise and state, the regime and an asset indicator. The response is the abnormal log bipower variation, with realized variance as sensitivity. The interaction is tested with a wild cluster bootstrap by meeting and a Holm correction over the primary family. Out-of-sample predictions exclude an entire year from the training meetings **and from the control days used by the first stage**. All centring and scaling of the state are re-estimated on the training control days only. This is not a real-time forecast, since leave-one-year-out can use years after the test fold.

The sufficiency branch uses the equally weighted mean of fx and gg and requires both assets. It compares the partial R² of the state block with the increment from two historical variables only, the first lag and the mean of the three preceding press-release OIS1M surprises. The lags are built on the full calendar of the source before exclusions, and a missing value is not skipped. The result concerns this observed history and this aggregated response, not the whole theoretical state nor the general quasi-Markov property. T_e and P_e remain explicitly unavailable, and no proxy is invented for them.

The power floor is a design-conditional calibration at the meeting level along each of the two residualized historical coordinates. It also reports the size at R² = 0 and uses the Wilson lower bound to declare that power 0.80 has been reached. A failure to reach it on the grid produces NaN, and no universal sample size is extrapolated. The percentile upper bound of the partial R² is a bootstrap diagnostic and not an exact interval. The finite rule requires both a bound below 0.02 and adequate power at that scale, and a failure to reject does not certify sufficiency.

The main wild bootstrap imposes the restricted null, uses Rademacher signs common to all assets and phases of a meeting, CR1 studentization and p-values with the plus-one correction, with 999 replications. The p-values are **conditional on the measured indicators and on the estimated counterfactual**. This version does not integrate the uncertainty of the generated regressors and of the first stage in a joint bootstrap and must not be described as doing so. The outputs keep this limitation in the manifest and in the tables. Holm distinguishes primary families from sensitivities, and the sensitivity grid does not select the primary model.

## US releases

The 08:30 `America/New_York` flag considers every weekday, handles daylight saving time and conservatively includes coincidences at the boundaries. It marks a possible exposure and not a verified calendar of publications. The sensitivity removes the paired meeting if one of its phases is exposed and re-estimates the normal layer after applying the same filter to the control days. The scalar press-release branch instead applies the filter to press-release coincidences only, with the same exclusion among its own control days. The mere presence of day-of-week effects does not show that the macro surprise has been absorbed.

`Raw/Certification/us_releases.csv` may be supplied in the data root, with the columns `release_id`, `timestamp_utc` and `source_url` and explicit UTC timestamps. The build records its hash and the release flags. Without the file, the status is `candidate_screen_only`. The conservative sensitivity remains computable, although it may fail the gate of 30 meetings, and such a failure must be reported, not circumvented by choosing exclusions after the estimation.

## Execution and retention

The Python runner allows the design to be checked on the available data without a MATLAB licence, while the corrections to the extractors and to the shrinkage step also remain in the MATLAB code. Requirements are Python 3.10 or later and `requirements-final-analysis.txt`, with the actual versions saved in the manifest.

```bash
python3 -m pip install -r requirements-final-analysis.txt
./Run_final_analysis.sh freeze --data-root /path/to/Econometrics_data \
  --build /path/to/Econometrics_data/Raw/Certification/final_analysis_v1
./Run_final_analysis.sh estimate --data-root /path/to/Econometrics_data \
  --build /path/to/Econometrics_data/Raw/Certification/final_analysis_v1 \
  --output /path/to/Econometrics_data/Output/final_analysis_v1
```

An existing path is rejected, and a revision requires a new directory. The estimation verifies the hashes of the executable code, of the specification, of the source data and of the frozen tables, so that changing the code after the freeze requires a new build. `--smoke` on `estimate` uses 19 replications and a reduced grid, and every output is marked `complete_smoke_not_for_inference` and supports no econometric conclusion.

The new outputs do not overwrite the historical ones. `Run_pipeline` remains the historical pipeline for the earlier exercises and is not the entry point of the final estimation. The April `Output/paper_tables` are to be treated as **superseded** with respect to the canonical windows, and the runner imports none of their tables and does not delete their archive.

With five press-release returns, Step 16 stops at the historical BNS gate, which requires a median of at least six. This threshold is unchanged. Step 17 records the bipower branch as `blocked_bns_gate` and estimates only the realized-variance diagnostic from the state panel, without using any residual BNS files. The new feasibility report binds bars, state and, when produced, the BNS panel by hash. The old BNS and quasi-Markov outputs are archived before a new execution. This stop does not prevent the computation of the bipower proxy in the final Python battery.

For the auxiliary MATLAB rerun:

```matlab
setenv('ECONOMETRICS_DATA_ROOT', '/path/to/Econometrics_data');
setenv('FINAL_ANALYSIS_BUILD', '/path/to/Econometrics_data/Raw/Certification/final_analysis_v1');
Run_final_matlab_checks
```

The driver verifies the frozen inputs, uses `preferred_contracts.csv` with pre-release selection, archives the historical `analysis` and `event_windows` directories, rebuilds the windows and re-estimates the shrinkage step as well. The one-standard-error rule selects the strongest penalty within the band, and interactions from raw variables, scaling, centring and the maximum lambda of the fold prevent the test fold from entering training. Post-selection statistics are labelled descriptive. The existing sparse-group penalty does not impose strong heredity.

Reproducible tests:

```bash
python3 -m unittest discover -s tests -v
```

In MATLAB, run `Final_window_self_test`. The availability and results of the checks performed for this change are reported in `FINAL_ANALYSIS_VALIDATION.md`.
