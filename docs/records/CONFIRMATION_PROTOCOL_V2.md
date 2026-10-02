# Preparation of the 2000–2012 confirmation sample

*Record written in September 2026 in Italian and translated into English. The original text is preserved in the repository history at commit `0f6daab`.*

Status: preparatory implementation; the specification is not frozen. Base commit `c224fe07dded3599bfb57f8be23e5e4c2032db53` of the `Monetary_surprises_clone` repository only.

Update: `Run_confirmation_quality.sh` now performs the OHLC audit, the audit of exact price pairs and the audit of pre-release contract selection. `Run_confirmation.sh readiness` verifies provenance and reports the remaining blocks. See `CONFIRMATION_NEXT_STEPS.md` for commands, evidence schemas and the discrepancies to be resolved before the estimation is implemented. The canonical press-release support is `(PR, PR+25]`, with five returns, and not `(PR+5, PR+25]`.

The original plan of 12 September is preserved in `docs/Confirmation_plan_2000-2012_original.md`. This note sets out the adaptations it required and the points that remained to be decided. It does not authorize any estimation on the confirmation sample.

**What this update executes.** `Run_confirmation.sh audit` builds the hash inventory of the 2000–2012 contracts, the coverage of the 164 expected cells, the observed sessions, the complete event–root–phase register and the certification templates for the calendar and for the bar labels. It reads only timestamps and volume from the CSV files. It does not load the price columns and computes no realized variance, bipower variation, jump or post-announcement peak. Price quality and the coverage of individual windows are to be certified in the next stage. An interval between the first and the last bar does not prove the absence of internal gaps, nor does it establish the official trading calendar.

`Run_confirmation.sh bridge` accepts a v1 build verified by hash, checks the metadata before reading any outcome column and uses the 2013–2025 sample only. It re-estimates the normal continuation and the state on the control days of the generation sample, leaving out the year being evaluated. It computes H1 and H2 on the abnormal bipower variation of the Bund alone, in the eight-column raw basis declared in the specification. The scales of the futures coordinates come from the press-release control days of the generation sample. STOXX50E, expressed in percent in the EA-EMPD file, is converted into a fractional return before the standard deviations are compared, and its scale comes from the press-release events of the generation sample. No period or price of the new sample enters the bridge.

`Run_confirmation.sh check-protocol` lists the requirements that are still missing. The v2 commands `control-build`, `calibrate`, `freeze` and `estimate` are now implemented and described in `CONFIRMATION_ESTIMATION_V2.md`. `Run_final_analysis.sh freeze` and `Run_pipeline.m` must not be used in their place on the new archive, because the v1 pipeline builds the outcomes and lacks the separation that the plan requires.

**Separation of the samples.** The bridge proposed on 2011H2–2025 is incompatible with the intention of using the whole of 2000–2012 for confirmation if those observations inform the choices. The bridge is therefore restricted to 2013–2025, and no 2026 observation enters its estimates, even where present in the historical build. Covariates and control days of 2000–2012 may be used for ex-ante calibration under a fixed rule, while event outcomes are built only after the freeze.

**Calendar and clock.** `GC_PC` identifies a window of the dataset and does not prove that a press conference took place. The 2001 ECB calendar shows monthly press conferences and meetings held on Wednesdays as well. Presence in the source window, actual occurrence and verified time are kept as separate fields. The meetings of 17 September 2001 and 8 October 2008 require an explicit review of their times and of the validity of their EA-EMPD windows. Missing rows are recorded as such, without inventing events or press conferences.

On 1 April 2004 the offset between Europe/Berlin and America/Chicago is eight hours. On 4 November 2004 it is seven, not six. On 1 November 2007 it is six. These cases are tested in Python and added to the MATLAB self-test. IANA time zones and local Europe/Berlin times are used throughout, and no fixed CET offset is applied across seasons.

**Mathematical object.** The cone formulae are correct for a uniform angular weight in the declared raw metric. H1 and H2 are new functionals and not a renaming of the policy coefficient of the median rotation. The recovered raw matrix and the predicted values do not depend on the representation used to estimate them. Entries and eigenvectors change coordinates under a change of basis, whereas trace and eigenvalues are invariant under orthogonal similarity but not under every transformation that includes whitening or rescaling. A positive rescaling preserves the signs of the quadrants but changes the weighting of directions, and therefore the cone functional.

`Cone_functionals.m` and `confirmation_analysis/cones.py` use the basis `(u², z², 2uz)`. `wild_contrast` imposes the null of the linear combination directly, uses CR1 standard errors and common signs within each meeting, and computes signed one-sided tails, without halving the p-value of a two-sided Wald test. The planned primary family has two tests and 19,999 replications, and the resolution gate passes. The bridge tests are diagnostics on a sample that has already been seen.

**Decisions still open before the freeze.** The bridge records the four criteria of the plan. If criterion 1 or criterion 3 fails, it reports the homogeneous external fallback as a candidate for discussion and does not certify it automatically as equivalent to the aligned pair. The plan specifies no fallback for a failure of criterion 2 or criterion 4 alone. The ratio between the standard deviation on events and on control days may reflect the larger variability of announcements, and the comparison of p-values within a factor of three is also sensitive to Monte Carlo precision. Any revision takes place on the generation sample and is documented before the freeze.

The common metric for a possible hybrid equity source, the exact nuisance vector, the finite list of secondary tests and the joint correction of the sufficiency interval must also be defined. A margin determined by power measures an attainable precision and does not by itself establish that history is economically negligible. The scientific reference threshold and the calibrated margin are reported separately. A failure to reject H1 does not demonstrate heterogeneity across periods without a dedicated contrast.

The US calendar remains unverified until there is evidence for the releases and for the coverage of the calendar. Thursdays at 8:30 ET cannot be converted into verified releases by construction, and matching by day does not guarantee that the dependence between US news and the announcement indicators is removed.

**Running the first pass.** After applying the update, run `bash Run_confirmation_prepare.sh FULL_RUN_PATH NEW_CSV_FOLDER`. The second path is added to `Econometrics_data/Raw/Barchart_futures`, and the search reads only files whose names match the four expected futures. The preparation does not move any data and produces a diagnostic ZIP archive even when it fails. Commits remain with the author.

Sources for the historical checks:

- ECB, 2001 calendar and monthly press conferences: https://www.ecb.europa.eu/press/pr/date/2000/html/pr000608_2.en.html
- ECB, extraordinary decision of 17 September 2001: https://www.ecb.europa.eu/press/pr/date/2001/html/pr010917.en.html
- Federal Reserve, joint statement of 8 October 2008 at 7:00 EDT, FRASER archive: https://fraser.stlouisfed.org/files/docs/historical/FOMC/meetingdocuments/20081008statement.pdf
- NIST, daylight saving time rules and the 2007 change: https://www.nist.gov/pml/time-and-frequency-division/popular-links/daylight-saving-time-dst
- US Department of Transportation, rule before 2007: https://www.transportation.gov/briefing-room/news-digest-18
