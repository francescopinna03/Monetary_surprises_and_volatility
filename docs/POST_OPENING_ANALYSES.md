# Post-opening analyses on the ECB samples

## Status

The analyses described here were designed and run after the outcomes of both ECB samples had been seen, the 2013–2025 sample from the start and the 2000–2012 sample after its freeze of 14 September 2026 and its declared second opening of 15 September 2026. Their outputs are labelled as post-opening in every manifest, and none of them overwrites a confirmatory output. The amplitude law that they document was subsequently tested on FOMC statements under a signed protocol, as described in `FOMC_REPLICATION.md`.

## Mean branch and functional form

The command `Run_confirmation.sh exploratory`, executed through `Run_confirmation_exploratory.sh`, estimates on the opened 2000–2012 build the mean branch with the signed and absolute coordinates and their interactions with the state, the ridge regression on the state block with annual folds, the Poisson pseudo-maximum-likelihood regression in levels and the declared interval for announcement history. `Run_functional_form_checks.py` compares four radial bases, the quadratic and absolute angular profiles combined with linear and quadratic radial growth, by leave-one-year-out prediction error. The corrections adopted after an external review of these diagnostics are recorded in `Functional_form_corrections_20260916.md`.

## Cross-period comparison

`Prepare_cross_epoch_inputs.py` rebuilds the event inputs of both periods from the opened archives, verifying the hashes of the frozen generation build, and `Run_cross_epoch_checks.py` estimates the native and common-metric comparisons, the common support of the sectors and the decomposition of the cross-period gap into composition and response. The inputs and outputs of the run of 16 September 2026 are archived in `../reference_outputs/cross_epoch_20260916`, the findings are recorded in `Cross_epoch_findings_20260916.md` and the instructions for reproducing them in `REPRODUCTION_20260916.md`.

## Jump-robust measures

`Run_confirmation_jump.sh` recomputes the five-minute outcome as the bipower variation without its first return, the median and minimum realized measures of Andersen, Dobrev and Schaumburg, two threshold bipower measures and post-window volume, each with the same continuation, and re-estimates the mean branch and the radial comparison on each of them. The purpose of the stage is to separate the response of trading from the mechanical entry of an announcement jump into a bipower measure computed on five returns.

## One-minute outcomes

`Run_confirmation_minute.sh` rebuilds the post-release window of both ECB samples from one-minute bars, with twenty-five returns per announcement, after certifying the bar-label convention of the one-minute archive against the five-minute archive. It reports the bipower variation with the first one, two and five minutes removed, realized variance, the median and minimum measures, a threshold bipower calibrated inside the window and volume, together with one-minute descriptives of jump shares and of the distribution of variation over the window. The contract of each announcement follows the selection of the frozen build, and an expiry rule recovers the one meeting whose selected contract had expired.

## Radial exponent, elasticity and sector information

`Run_design_information.sh` estimates the radial exponent of the response surface on a grid from 0.05 to 3 under two angular profiles, with likelihood-ratio intervals and leave-one-year-out prediction errors at every exponent, and the mean elasticity of the logarithmic law with CR1 standard errors. It also computes the information that the observed design carries about the contrast between pure-policy and information surprises at fixed amplitude, its retention relative to designs with independently drawn equity signs, the number of meetings required to detect the observed contrast with power 0.8, and the explanatory power of the odd block of the response, which measures the departure from central symmetry.

## Measurement error in the coordinates

`Run_measurement_check.sh` asks whether the concavity of the response in the amplitude could be an artefact of noise in the coordinates. It applies three checks to both ECB periods and to the FOMC sample. The first estimates the exponent on the announcements whose amplitude exceeds twice the median radius of Gaussian noise with the control-day covariance. The second simulates the estimator under a linear law in the true amplitude, measured with noise equal to a multiple of the control-day covariance, and reports the multiple at which the median simulated exponent reaches the observed one. The third instruments the log amplitude with the amplitude built from the change in the two-year German yield recorded in EA-EMPD, an independent measurement of the policy surprise available for the ECB samples only.

The criteria were fixed before the checks were run and are recorded in the manifest of the run. The artefact is excluded when the tail exponent lies below one with a likelihood ratio against one above the ten percent critical value and the required noise multiple is at least 1.5, and it is implausible when only the simulation criterion holds. The instrumented elasticity is reported and does not enter the verdict, because the two measurements share the background news of the same minutes.
