# Monetary Surprises and Volatility

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

Local paths are intentionally explicit. This makes the workflow transparent but requires updating `projectRoot` before replication.

The pipeline deliberately includes a large number of diagnostic checks, intermediate summaries and debugging tables. The authors agree that a similar design choice reflects the size and fragility of the underlying intraday dataset. Since the empirical analysis depends on high-frequency futures prices, event-time matching, contract selection and short-window realized measures, each step produces auxiliary outputs that make the data-management process inspectable.

These diagnostics are part of the computational strategy used to preserve data integrity throughout the pipeline. File-level manifests, cleaning logs, contract-day quality summaries, event-coverage reports, window-level eligibility checks and model-summary tables allow the user to verify whether each transformation is coherent before moving to the next stage of the analysis. In this sense, the repository is structured also to document the path by which the final estimation sample is obtained from a large and heterogeneous set of raw intraday files.

The raw input files are provided separately together with the paper draft. To replicate the full empirical workflow, place the input files in the directory structure described above and update `projectRoot` accordingly.

## Repository structure

The repository is organized as a flat MATLAB codebase. The files are intended to be run sequentially, with some later files serving as robustness checks or extensions rather than mandatory baseline steps.

| Step | File | Role |
| --- | --- | --- |
| 1 | `Audit_Barchart.m` | Audits the raw Barchart intraday futures files. It checks filename structure, contract metadata, headers, footers, timestamps, duplicates, missing fields and OHLC consistency. |
| 2 | `clean_raw_files_02.m` | Driver script that applies the cleaning helper to all raw Barchart CSV files in `Raw/Barchart_futures`. It writes cleaned files and cleaning logs. |
| 2 helper | `Cleaning_Barchart.m` | Helper function for cleaning one raw Barchart file. It is called repeatedly by `clean_raw_files_02.m` and is not meant to be run as a standalone script. |
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

The distinction between `clean_raw_files_02.m` and `Cleaning_Barchart.m` is important. The former is the script that should be executed by the user. The latter is a single-file cleaning function. In a full run, the driver calls the helper once for each raw Barchart CSV file.

## Data availability and required inputs

The raw and intermediate input files required to reproduce the empirical workflow are not stored directly in this repository. They are provided separately together with the draft of the paper, in order to keep the code repository lightweight and to separate the computational routines from the data package.

The replication package is expected to contain the files required by the MATLAB pipeline, including all 104 raw Barchart intraday futures CSV files at five-minute frequency, the ECB monetary policy meeting calendar, including event dates, press-release times and press-conference time, EA-MPD monetary surprise data (Altavilla et al. (2019)), OIS changes used to construct target and path surprise measures and the auxiliary input files needed to reproduce the intermediate panels used in the paper

Once the data package has been placed locally, the user should arrange the files according to the directory structure expected by the scripts and set the `projectRoot` variable at the top of each MATLAB file.

The expected directory structure is:

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
    ├── analysis/
    └── paper_tables/
```
Enjoy exploring this MATLAB workflow!
