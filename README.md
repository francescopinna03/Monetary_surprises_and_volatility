# Monetary Surprises and Volatility

This repository contains a MATLAB pipeline for studying how high-frequency monetary policy surprises affect intraday realized volatility around ECB monetary policy announcements. The empirical design combines ECB event dates, high-frequency futures prices, Barchart intraday contract data and monetary policy surprises from EA-MPD-style OIS changes.

The project focuses on press-release windows and asks whether the volatility response to monetary policy surprises is state-dependent. The code builds cleaned intraday futures panels, selects the most reliable contract around each ECB event, extracts event windows, merges monetary surprises and estimates several layers of econometric models.

## Research motivation

Monetary policy announcements can move asset prices through target-rate surprises, forward-guidance signals and information effects. This project studies the realized-volatility side of that transmission mechanism. The main empirical object is the response of press-release realized volatility, semivariance and jump-like price movement to monetary policy surprises.

The pipeline is designed to answer three related questions.

1. Do ECB monetary policy surprises generate measurable intraday volatility responses around the press release?
2. Are those responses different across asset families, especially equity-index futures and Bund futures?
3. Does the response depend on pre-announcement uncertainty, recent monetary-policy memory or the hiking-regime state?

## Repository contents

The repository is organized as a flat MATLAB codebase. The main files are listed below in their intended execution order.

| Step | File | Purpose |
| --- | --- | --- |
| 1 | `Audit_Barchart.m` | Audits raw Barchart intraday futures files and creates file-level manifest and coverage diagnostics. |
| 2 | `Cleaning_Barchart.m` | Helper function for conservative cleaning of a single raw Barchart file. It removes invalid rows, duplicates and isolated one-bar spikes, while flagging low-volume bars. |
| 3 | `Contract_event_day.m` | Builds the contract-day quality panel from cleaned intraday files. It computes liquidity, coverage, gap and realized-measure diagnostics. |
| 4 | `Event_panel_construction.m` | Constructs the ECB event panel and links monetary policy dates to available futures contract-days. |
| 5 | `Event_windows.m` | Extracts intraday PR, PC and announcement windows from the preferred futures contracts. |
| 6 | `Press_release_panel.m` | Builds the baseline PR panel and merges it with EA-MPD monetary surprise data. |
| 7 | `Regression_fractional.m` | Estimates fractional-response QMLE models for the negative semivariance share. |
| 8 | `PR_signal_model.m` | Builds PR-only signal variables and estimates baseline linear signal regressions. |
| 9 | `State_vector_panel.m` | Constructs the event-level state vector and merges it into the PR long panel. |
| 10 | `State_dependent_models.m` | Estimates the main state-dependent PR models with event-clustered standard errors. |
| 11 | `Shock_purification_models.m` | Residualizes the monetary surprise with respect to pre-announcement states and re-estimates the state-dependent models. |
| 12 | `Functional_state_models.m` | Estimates threshold and spline functional-coefficient extensions. |
| 13 | `Volatility_components.m` | Decomposes PR realized variance into directional and dispersion components and estimates state-dependent models. |
| 14 | `Hierarchical_shrinkage.m` | Runs a sparse-group lasso exercise with event-level grouped cross-validation and post-selection OLS. |
| 15 | `PR_bar_panel.m` | Reconstructs a PR bar-level panel needed for BNS-type volatility decomposition. |
| 16 | `BNS_volatility.m` | Computes BNS-style realized variance, bipower variation and jump variation, then estimates state-dependent models when feasible. |

The numbering above describes the analytical order. Some files are robustness or extension modules rather than mandatory steps for the baseline results.

## Data requirements

The repository does not include proprietary or large raw datasets. To run the full pipeline, the user must provide the relevant input files locally.

Expected raw inputs include:

- Barchart intraday futures CSV files at 5-minute frequency
- An ECB monetary policy meeting calendar with event dates, press-release times and press-conference times
- EA-MPD or EA-MPD-style monetary surprise data
- OIS changes used to construct target and path surprise measures

The scripts expect the following directory structure under `projectRoot`:

```text
projectRoot/
├── Raw/
│   ├── Barchart_futures/
│   ├── ECB_calendar/
│   └── EA_MPD/
└── Output/
    ├── manifests/
    ├── cleaned/
    ├── diagnostics/
    ├── event_windows/
    └── analysis/
```

Before running the code, set the `projectRoot` variable at the top of each script to the local project directory.

## Main outputs

The pipeline produces several intermediate and final CSV files. The most important outputs are:

| Output | Description |
| --- | --- |
| `Output/manifests/raw_manifest_barchart.csv` | File-level audit of raw Barchart files. |
| `Output/manifests/coverage_barchart.csv` | Contract-grid coverage by root, expiry and year. |
| `Output/diagnostics/contract_day_quality.csv` | Contract-day quality and liquidity panel. |
| `Output/diagnostics/preferred_contract_by_event.csv` | Selected contract for each ECB event and asset family. |
| `Output/event_windows/event_window_panel.csv` | Wide event-window panel with PR, PC and announcement-window realized measures. |
| `Output/analysis/pr_baseline_panel.csv` | Baseline press-release panel merged with monetary surprise data. |
| `Output/analysis/pr_signal_panel.csv` | PR-only signal panel with signed jump, absolute jump and volatility outcomes. |
| `Output/analysis/event_state_panel.csv` | Event-level monetary policy state vector. |
| `Output/analysis/pr_state_dependent_panel.csv` | Long PR panel with state variables and interactions. |
| `Output/analysis/pr_state_model_coefficients.csv` | Main state-dependent regression coefficients. |
| `Output/analysis/pr_state_purified_model_coefficients.csv` | State-dependent coefficients based on purified monetary surprises. |
| `Output/analysis/functional_threshold_summary.csv` | Threshold-model summaries. |
| `Output/analysis/shrinkage_selected_features.csv` | Sparse-group lasso selected features. |
| `Output/analysis/pr_bns_component_panel.csv` | BNS-style volatility components when the bar-level decomposition is feasible. |

## Econometric structure

The baseline monetary surprise is the press-release target surprise, usually proxied by the one-month OIS change and expressed in units of 10 basis points. When enough OIS maturities are available, the code also constructs target and path factors using a PCA-style rotation and orthogonalization.

The main PR outcomes are:

- signed PR jump
- absolute PR jump
- press-release realized variance
- positive and negative realized semivariance
- negative semivariance share
- directional and dispersion components of realized variance
- BNS-style bipower and jump variation components when bar-level data are sufficient

The state-dependent specifications are built around interactions of the monetary surprise with:

- the hiking-regime indicator
- standardized pre-announcement realized volatility
- standardized pre-announcement downside volatility
- recent monetary-policy memory based on lagged target surprises
- optional curve-state measures

Most linear specifications are estimated by OLS with event-date clustered standard errors. Fractional-response models use logit QMLE. The shrinkage extension uses sparse-group lasso with event-level grouped cross-validation.

## Suggested execution order

A typical full run is:

```matlab
run('Audit_Barchart.m')
```

Then clean the raw Barchart files using `Cleaning_Barchart.m` through the cleaning driver or loop used in the local project setup.

After cleaned files are available, run:

```matlab
run('Contract_event_day.m')
run('Event_panel_construction.m')
run('Event_windows.m')
run('Press_release_panel.m')
run('Regression_fractional.m')
run('PR_signal_model.m')
run('State_vector_panel.m')
run('State_dependent_models.m')
run('Shock_purification_models.m')
run('Functional_state_models.m')
run('Volatility_components.m')
run('Hierarchical_shrinkage.m')
run('PR_bar_panel.m')
run('BNS_volatility.m')
```

The baseline empirical results require the pipeline up to `State_dependent_models.m`. The subsequent files are robustness checks or extensions.

## Notes on reproducibility

The code is written in MATLAB and uses standard table, datetime and matrix operations. Several scripts use functions such as `tcdf`, `tinv`, `fcdf`, `chi2cdf` and grouped summaries, so the Statistics and Machine Learning Toolbox may be required.

Local paths are intentionally explicit. This makes the workflow transparent but requires updating `projectRoot` before replication.

Raw data are not distributed with this repository. Replication therefore requires access to the original intraday Barchart data, the ECB event calendar and the monetary surprise dataset.

## License

This repository is released under the MIT License. See `LICENSE` for details.

## Citation

If you use this code, please cite the repository as:

```text
Pinna, F. Monetary Surprises and Volatility. GitHub repository.
https://github.com/francescopinna03/Monetary_surprises_and_volatility
```
