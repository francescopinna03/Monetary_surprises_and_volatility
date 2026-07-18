# Monetary Surprises and Volatility

> **Research-reset status.** Steps 1--17 reproduce the original state-dependent-volatility project. Steps 18--19 show that the monetary-surprise slope and its state gradient are not robustly identified. Step 20 tests whether ECB announcements reallocate high-frequency risk between equity and sovereign-bond futures. Step 21 subjects the identified negative risk direction to common-support trimming and cross-fitted bias correction. The legacy results are retained for auditability; they are not treated as the headline evidence of the revised project.

This repository contains the MATLAB code used to construct the empirical dataset and to estimate the econometric specifications in the project *State-Dependent Transmission of ECB Monetary Surprises to Intraday Volatility*. The computational workflow is designed as a transparent event-study pipeline. Starting from raw intraday futures files and ECB monetary policy dates, the code builds cleaned five-minute futures panels, selects the most reliable contracts around each announcement, extracts press-release windows, merges monetary surprise measures, constructs event-level state variables and estimates a sequence of state-dependent volatility models.

The repository should be read as the computational counterpart of the paper. Its purpose is not only to reproduce tables, but also to document the logic through which raw market data are transformed into the final econometric objects. The central empirical question is whether the intraday volatility response to ECB monetary policy surprises can be represented by a constant average coefficient, or whether it is better understood as a response function whose slope depends on the pre-announcement state of the market.

## Computational design

The pipeline follows the logic of a high-frequency event study. The unit of analysis is an ECB monetary policy event, observed through the intraday response of futures prices in the press-release window. The raw market data are Barchart five-minute futures files. The code first audits and cleans these files, then builds contract-day quality diagnostics, links ECB event dates to available futures contracts, selects the preferred contract for each event and asset family, extracts event windows, and constructs the final panel used for econometric analysis.

The project distinguishes between three computational layers.

First, the data-engineering layer transforms raw intraday futures files into cleaned contract-day and event-window panels. This part of the pipeline is deliberately conservative. Invalid rows, malformed timestamps, non-positive prices, negative volumes, OHLC inconsistencies, duplicated timestamps and isolated one-bar spikes are removed. Low-volume bars are flagged but not mechanically removed, because in an intraday volatility study the distinction between deletion and diagnostic flagging affects the realized-measure construction.

Second, the event-study layer links the cleaned intraday data to ECB monetary policy events. For each event and each futures family, the code ranks candidate contracts using volume, number of bars, low-volume share and gap regularity. It then extracts press-release, press-conference and combined announcement windows. The main empirical panel is constructed from the press-release window.

Third, the econometric layer estimates the response of intraday volatility to monetary policy surprises. The baseline shock is the press-release target surprise, typically measured by a high-frequency OIS change and scaled in units of 10 basis points. The main specifications allow the slope of the volatility response to depend on pre-announcement market states, including the hiking regime, pre-announcement realized volatility, downside volatility and monetary-policy memory.

## Notes on reproducibility

The code is written in MATLAB and uses standard table, datetime and matrix operations. 

All scripts resolve the location of the data package through the shared helper `Get_project_root.m`, so no source file needs to be edited before replication. The helper looks for the data folder in the following order: the environment variable `ECONOMETRICS_DATA_ROOT` (if set), a folder named `Econometrics_data` next to the MATLAB scripts, and finally a folder named `Econometrics_data` in the current working directory. If none of these resolves to a folder containing the expected `Raw/` subfolder, the scripts stop with an explicit error message.

Common utilities are shared function files in the repository root: `Parse_date_flexible.m`, `Parse_datetime_flexible.m`, `String_to_boolean.m`, `Locate_first_existing.m` and `Find_column.m`. They are found automatically when MATLAB runs from the repository folder or when the folder is on the MATLAB path.

The stochastic steps are seeded for exact reproducibility. `Hierarchical_shrinkage.m`, `Quasi_markov_residual_predictability.m` and Steps 18--21 each declare their seeds in the corresponding script. Changing a seed changes bootstrap or placebo results within simulation noise; keeping the defaults reproduces the reported draws.

The pipeline deliberately includes a large number of diagnostic checks, intermediate summaries and debugging tables. The authors agree that a similar design choice reflects the size and fragility of the underlying intraday dataset. Since the empirical analysis depends on high-frequency futures prices, event-time matching, contract selection and short-window realized measures, each step produces auxiliary outputs that make the data-management process inspectable.

These diagnostics are part of the computational strategy used to preserve data integrity throughout the pipeline. File-level manifests, cleaning logs, contract-day quality summaries, event-coverage reports, window-level eligibility checks and model-summary tables allow the user to verify whether each transformation is coherent before moving to the next stage of the analysis. In this sense, the repository is structured also to document the path by which the final estimation sample is obtained from a large and heterogeneous set of raw intraday files.

The raw input files are provided separately together with the paper draft, as a single archive that unzips to a folder named `Econometrics_data`. To replicate the full empirical workflow, unzip the archive and either place the resulting `Econometrics_data` folder next to the MATLAB scripts or point the environment variable `ECONOMETRICS_DATA_ROOT` to it, for example with `setenv('ECONOMETRICS_DATA_ROOT', '/path/to/Econometrics_data')` inside MATLAB before running the pipeline.

## Repository structure

The repository is organized as a flat MATLAB codebase. The files are intended to be run sequentially, with some later files serving as robustness checks or extensions rather than mandatory baseline steps. The master script `Run_pipeline.m` executes all twenty-one steps in order and writes a full console log to `pipeline_run.log`.

A full replication therefore reduces to one command. From MATLAB:

```matlab
cd /path/to/this/repository
setenv('ECONOMETRICS_DATA_ROOT', '/path/to/Econometrics_data')
Run_pipeline
```

From the terminal, without opening the MATLAB desktop:

```bash
./Run_pipeline.sh /path/to/Econometrics_data
```

The shell wrapper requires and validates the data-root argument, uses `matlab` from the PATH or the newest installation found in `/Applications`, exports `ECONOMETRICS_DATA_ROOT`, and runs the pipeline headless with `matlab -batch`. Direct MATLAB execution may instead use `setenv` or place `Econometrics_data` next to the scripts.

| Step | File | Role |
| --- | --- | --- |
| 1 | `Audit_Barchart.m` | Audits the raw Barchart intraday futures files. It checks filename structure, contract metadata, headers, footers, timestamps, duplicates, missing fields and OHLC consistency. |
| 2 | `Clean_raw_files.m` | Driver script that applies the cleaning helper to all raw Barchart CSV files in `Raw/Barchart_futures`. It writes cleaned files and cleaning logs. |
| 2 helper | `clean_single_barchart_file.m` | Helper function for cleaning one raw Barchart file. It is called repeatedly by `Clean_raw_files.m` and is not meant to be run as a standalone script. |
| 3 | `Contract_event_day.m` | Builds the contract-day quality panel from cleaned files. It computes liquidity, coverage, gap and realized-measure diagnostics. |
| 4 | `Event_panel_construction.m` | Constructs the ECB event panel and links monetary policy dates to available futures contract-days. |
| 5 | `Event_windows.m` | Extracts intraday PR, PC and announcement windows from the preferred futures contracts. |
| 6 | `Press_release_panel.m` | Builds the baseline press-release panel and merges it with EA-MPD-style monetary surprise data. |
| 7 | `Regression_fractional.m` | Estimates fractional-response QMLE models for the negative semivariance share. |
| 8 | `PR_signal_model.m` | Constructs PR-only signal variables and estimates first-pass linear signal regressions. |
| 9 | `State_vector_panel.m` | Constructs the event-level state vector and merges it into the long press-release panel. |
| 10 | `State_dependent_models.m` | Estimates the main state-dependent press-release models with event-clustered standard errors. |
| 11 | `Shock_purification_models.m` | Residualizes the monetary surprise with respect to pre-announcement states and re-estimates the state-dependent models. |
| 12 | `Functional_state_models.m` | Estimates threshold and spline functional-coefficient extensions. |
| 13 | `Volatility_components.m` | Decomposes press-release realized variance into directional and dispersion components. |
| 14 | `Hierarchical_shrinkage.m` | Runs a sparse-group lasso selection exercise with event-level grouped cross-validation and post-selection OLS. |
| 15 | `PR_bar_panel.m` | Reconstructs the bar-level press-release panel needed for the BNS-style volatility decomposition. |
| 16 | `BNS_volatility.m` | Computes realized variance, bipower variation and jump variation, then estimates state-dependent models on the continuous and jump components. |
| 17 | `Quasi_markov_residual_predictability.m` | Implements the hierarchical falsification of the sufficient-state interpretation using cross-fitted residuals, history tests, forecast comparisons and long-memory diagnostics. |
| 18 | `Announcement_counterfactual.m` | Uses non-ECB trading days to estimate normal pre/post volatility propagation, constructs abnormal ECB-window volatility, and tests whether squared target or target-path surprise magnitude affects the bipower component and its state gradient. Contract selection is based only on pre-window information. |
| 19 | `Announcement_counterfactual_validation.m` | Stress-tests the counterfactual with a one-stage stacked model, a stratified two-stage date bootstrap, matched non-event controls and placebos, shock-support diagnostics, leave-top-k sensitivity, and separate FX/GG estimates. |
| 20 | `Announcement_risk_rotation.m` | Reconstructs paired Euro Stoxx/Euro Bund returns, estimates the abnormal post-minus-pre second-moment matrix against paired non-event controls, and tests whether ECB announcements create a positive news direction while resolving risk in a distinct negative direction. |
| 21 | `Announcement_risk_resolution.m` | Re-estimates the Step-20 abnormal matrix after common-support trimming and leave-year-out correction of normal continuation; the binding result is the negative eigenvalue in the full and non-2020 samples. |

### Decisive non-event counterfactual

`Announcement_counterfactual.m` is deliberately separate from the legacy PR-window and BNS stages. It reconstructs both ECB and control observations on common, non-overlapping windows: the pre-announcement base uses five-minute returns ending from 55 to 5 minutes before the scheduled release, while the outcome uses returns ending from the release through 45 minutes after it. Non-event dates use the ECB release clock applicable in the corresponding calendar regime. The preferred contract is selected from pre-window coverage and volume alone, so neither the post-window outcome nor full-day event volume enters selection.

The normal continuation model is estimated only on non-ECB dates and validated by leave-one-year-out prediction. Its event-date prediction is subtracted from observed log bipower variation, log realized variance and jump share. The event regression then uses squared surprise magnitude, its interaction with the standardized pre-window state, hiking-regime and asset-family controls. Inference includes event-date clustered standard errors, null-imposed wild-cluster bootstrap p-values and a two-one-sided equivalence test for a 25 percent change in the response per state standard deviation for a ten-basis-point target surprise.

The decisive outputs are:

| Output | Interpretation |
| --- | --- |
| `announcement_counterfactual_normal_summary.csv` | Whether the non-event model predicts ordinary pre/post volatility propagation out of sample. |
| `announcement_counterfactual_event_coefficients.csv` | Whether surprise magnitude explains volatility above that normal propagation. |
| `announcement_counterfactual_equivalence.csv` | Whether economically meaningful state dependence can be excluded, rather than merely failing to reject a zero interaction. |
| `announcement_counterfactual_effects.csv` | Implied response to one unit of surprise energy at low, average and high pre-announcement states. |
| `announcement_counterfactual_event_rows.csv` | Event-level observations and generated abnormal outcomes used in the final regressions. |

### Counterfactual validation and weak-support diagnostics

`Announcement_counterfactual_validation.m` treats the Step-18 window panel as immutable input. The stacked specification estimates root-specific normal continuation functions and event deviations jointly, so uncertainty in the normal mapping enters the same regression. A stratified date bootstrap then resamples event dates and non-event dates separately and re-estimates both counterfactual stages on every draw; its inference is conditional on the selected root-day windows, but not on the fitted Step-18 coefficients.

The matching design compares every event/root observation with ten non-event observations having the same asset family, scheduled-clock regime and weekday, selected by pre-window state, slow volatility and calendar proximity. Matched placebos replace event outcomes with ordinary matched-control outcomes while retaining the realized surprise sequence. Finally, support tables disclose the concentration of squared surprise variation, and leave-top-k tables show directly whether the monetary slope or its state gradient changes when the largest surprises are removed.

The validation outputs all use the prefix `announcement_validation_`. The principal files are the stacked coefficients, the two-stage bootstrap, the matched-placebo results, the event-level support table, the support summary, the leave-top-k sensitivity table and the combined equivalence tests. Random seeds and all match, bootstrap and equivalence settings are fixed at the top of the script.

For a quick syntax and data smoke test, set the environment variable `ANNOUNCEMENT_VALIDATION_DRAWS` to an integer of at least 19 before running Step 19. The published run should leave the variable unset and therefore uses 999 wild-bootstrap, two-stage-bootstrap and placebo draws.

The validation can be run without repeating Steps 1--18. `./Run_counterfactual_validation.sh /path/to/Econometrics_data 19` performs a 19-draw smoke test; omitting the final argument runs the pre-declared 999-draw analysis.

### Spectral risk-rotation experiment

`Announcement_risk_rotation.m` treats the Step-18 selected root-day windows as immutable input and uses only dates on which Euro Stoxx (`fx`) and Euro Bund (`gg`) returns are both available on the same exact five-minute grid. Returns are scaled by non-event volatility, after which the script forms pre- and post-release realized second-moment matrices. Every ECB date is compared with ten paired non-event dates sharing the release-clock regime and weekday and matched on the pre-window covariance matrix, slow volatility and calendar proximity.

The additive one-shock null implies that the average abnormal matrix is positive semidefinite and has rank at most one. The experiment therefore reports both eigenvalues and eigenvectors. A positive largest eigenvalue and a negative smallest eigenvalue, supported by event-date bootstrap intervals and matched placebos, is the pre-declared signature of risk creation in one cross-asset direction and uncertainty resolution in another. The squared target surprise is not used to construct the matrix or select controls; it is retained only for secondary mechanism checks.

Step 20 can be run without repeating the preceding stages once `announcement_counterfactual_windows.csv` exists. Its explicit data-root argument may point to an incremental project directory containing `Output/analysis` and `Output/cleaned`; Step 20 does not require `Raw/`. `./Run_risk_rotation.sh /project/root 19` performs a 19-draw smoke test; omitting the final argument runs the 999-draw experiment. Its six outputs use the prefix `announcement_rotation_`: the date matrices, matched rows, summary, event bootstrap, matched-placebo distribution and leave-one-event-out spectrum.

### Bias-adjusted risk-resolution test

`Announcement_risk_resolution.m` treats `announcement_rotation_date_matrices.csv` as immutable input. It estimates normal pre/post matrix continuation exclusively on non-event dates with leave-year-out cross-fitting. A control-only predictive guard contracts each nuisance prediction toward its fold mean whenever the linear model does not improve OOS loss; event outcomes never enter that choice. Events are retained only on common support and are compared with ten exact-clock, exact-weekday controls within two years. The nuisance model, predictive guard, support rule and matches are re-estimated in every stratified date-bootstrap draw.

The protocol and binding decision rule are recorded in `STEP21_PROTOCOL.md`. The negative eigenvalue must have a bootstrap upper endpoint below zero both in the full sample and after excluding 2020; retention and usable-bootstrap gates must also pass. The positive eigenvalue and the relative Bund-equity rotation are secondary and cannot rescue a failed decision.

Step 21 writes separate directories so a smoke test cannot overwrite the final results. `./Run_risk_resolution.sh /path/to/Econometrics_data smoke 49` writes to `Output/analysis/step21_smoke`. `./Run_risk_resolution.sh /path/to/Econometrics_data final 999` writes to `Output/analysis/step21_final`. `Run_decisive_test.sh` reruns Steps 20 and 21 only. A complete `Run_pipeline.sh /path/to/Econometrics_data` replication executes all 21 steps and defaults to the final 999-draw specification.

The distinction between `Clean_raw_files.m` and `clean_single_barchart_file.m` is important. The former is the script that should be executed by the user. The latter is a single-file cleaning function. In a full run, the driver calls the helper once for each raw Barchart CSV file. The shared helper `Get_project_root.m` must also be available on the MATLAB path or in the same folder as the scripts, which is automatic when the repository is used as the working directory.

## Data availability and required inputs

The raw and intermediate input files required to reproduce the empirical workflow are not stored directly in this repository. They are provided separately together with the draft of the paper, in order to keep the code repository lightweight and to separate the computational routines from the data package.

The replication package is expected to contain the files required by the MATLAB pipeline, including all 104 raw Barchart intraday futures CSV files at five-minute frequency, the ECB monetary policy meeting calendar, including event dates, press-release times and press-conference time, EA-MPD monetary surprise data (Altavilla et al. (2019)), OIS changes used to construct target and path surprise measures and the auxiliary input files needed to reproduce the intermediate panels used in the paper

Once the data package has been placed locally, the scripts locate it automatically through `Get_project_root.m` as described in the reproducibility notes above. No path needs to be edited in the source files.

The expected directory structure of the data package is:

```text
Econometrics_data/
├── Raw/
│   ├── Barchart_futures/
│   ├── ECB_calendar/
│   └── EA_MPD/
└── Output/
    ├── manifests/
    ├── cleaned/
    ├── diagnostics/
    ├── event_windows/
    ├── analysis/
    └── paper_tables/
```
Enjoy exploring this MATLAB workflow!
