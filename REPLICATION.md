# Replication

## Requirements

The Python code requires Python 3.10 or later and the packages listed in `requirements-final-analysis.txt`, and the figures of the paper additionally require matplotlib. The data stage requires MATLAB, and the recorded runs used R2025b Update 3. The FOMC calendar module needs network access to the Federal Reserve Board website on its first run and caches every page it reads.

```bash
python3 -m pip install -r requirements-final-analysis.txt
python3 -m pytest -q tests
```

## Data

The market data are not distributed with this repository, because the licence of the provider does not permit redistribution.

| Source | Content | Use |
|---|---|---|
| Barchart, five-minute bars on expired contracts | Euro-Schatz (`hf`), Euro-Bobl (`hr`), Euro-Bund (`gg`) and EURO STOXX 50 (`fx`) futures, 2000–2026 | Outcomes and aligned coordinates of the ECB samples |
| Barchart, one-minute bars on expired contracts | Euro-Bund futures, 2000–2026, in slices of at most 20,000 rows | One-minute outcomes of the ECB samples |
| Barchart, five-minute bars on expired contracts | Ten-year Treasury note (`zn`), two-year Treasury note (`zt`) and E-mini S&P 500 (`es`) futures, December 2008 to 2026 | Outcome and coordinates of the FOMC sample |
| Euro Area Monetary Policy event-study Database (EA-EMPD) | Changes in OIS rates, sovereign yields and equity indices over the press-release and press-conference windows of every Governing Council meeting | Equity coordinate of the ECB samples and the instrument for the policy coordinate |

Every runner receives a facility directory as its first argument and expects the data under `Econometrics_data` inside it, together with a Python environment in `python_env`.

```text
Econometrics_data/
├── Raw/
│   ├── Barchart_futures/                 five-minute files of the 2013–2026 contracts
│   ├── Barchart_futures_confirmation/    five-minute files of the 2000–2012 contracts
│   ├── Barchart_futures_1min/            one-minute Bund slices
│   ├── Barchart_futures_fed/             five-minute zn, zt and es files
│   ├── EA-EMPD/                          EA-EMPD.xlsx
│   ├── ECB_calendar/                     ECB event calendar
│   ├── FOMC_calendar/pages/              cache of the Board pages
│   └── Certification/                    frozen builds and verified calendars
└── Output/                               one timestamped directory per run
```

Barchart timestamps are wall-clock times in America/Chicago and are converted to UTC with IANA rules, never with fixed offsets. Bar labels mark the start of each interval, which was certified for Eurex from session boundaries, for the one-minute archive by aggregation against the five-minute archive, and for the CME from the reaction at documented release times. No price is filled, interpolated or carried across a missing bar.

## Single command

The whole sequence below runs with one command, which records the paths produced by each stage, stops at the first failure and resumes from the stage that failed when it is launched again. The second argument is the review token required by the confirmation freeze.

```bash
bash scripts/Run_replication.sh FACILITY I_HAVE_REVIEWED_THE_FROZEN_SPECIFICATION
```

Its progress is written to `Output/replication.log` and its state to `Output/replication_state.env`, and `DRY_RUN=1` prints the commands without executing them.

## Stages

The stages run in the order below. Each runner writes into a new timestamped directory, records the commit, the state of the working tree and the hashes of the code and of the inputs, and packages its outputs into a ZIP archive. The steps that originally required a human decision, namely the review of the ECB calendar, the bar-label promotion, the five design decisions and the signature of the FOMC protocol, enter the replication through the certified files in `Raw/Certification`.

| Stage | Command | Output used by the paper |
|---|---|---|
| 1. Data stage | `bash scripts/Run_data_stage.sh DATA_ROOT` | Cleaned files and the time-alignment and window-semantics manifests |
| 2. Build of the 2013–2025 sample | `bash scripts/Run_final_analysis.sh freeze --data-root DATA_ROOT --build BUILD` | Frozen generation build |
| 3. Preparation, inventory and quality audit of 2000–2012 | `scripts/Run_confirmation_prepare.sh`, `scripts/Run_confirmation_inventory.sh`, `scripts/Run_confirmation_quality.sh` | Quality directory |
| 4. Protected build and calibration | `scripts/Run_confirmation_calibration.sh` | Calibration |
| 5. Freeze and estimation of 2000–2012 | `scripts/Run_confirmation_final.sh` with the review token | Frozen tests, Table 13 |
| 6. Mean branch and functional form | `scripts/Run_confirmation_exploratory.sh`, `scripts/Run_functional_form_checks.py` | Ridge and history tables |
| 7. Cross-period comparison | `scripts/Prepare_cross_epoch_inputs.py`, `scripts/Run_cross_epoch_checks.py` | Tables 2, 3 and 20 |
| 8. Jump-robust measures | `scripts/Run_confirmation_jump.sh` | Five-minute robustness |
| 9. One-minute outcomes | `scripts/Run_confirmation_minute.sh` | Tables 4 and 18 |
| 10. Radial exponent and sector information | `scripts/Run_design_information.sh` | Tables 5, 6, 11 and 19, Figure 2 |
| 11. FOMC calendar | `scripts/Run_fomc_calendar.sh` | Verified FOMC calendar |
| 12. FOMC replication | `scripts/Run_fed_replication.sh` | Tables 8 and 9 |
| 13. FOMC post-replication decomposition | `scripts/Run_fed_post_replication.sh` | Table 10 |
| 14. Measurement-error check | `scripts/Run_measurement_check.sh` | Tables 6 and 7, Figure 3 |
| 15. Tables and figures | `python3 scripts/Make_paper_tables.py --output tables` | All tables and figures |

Stages 6 to 14 take the facility directory as their first argument and, where relevant, the frozen 2000–2012 build or an earlier run, which they otherwise locate as the most recent one in `Output`. The runners of stages 3, 4, 9, 10 and 14 also require two environment variables, `GENERATION_BUILD`, the build produced by stage 2, and `BRIDGE_DIR`, the `bridge` directory produced by stage 3, and they stop if either is missing. After the last stage, `python3 scripts/Compare_with_archive.py --data-root DATA_ROOT --cross-epoch CROSS_EPOCH_OUTPUT` compares every table produced by the replication with the archived one and reports the largest absolute difference. Stage 15 reads the archived outputs in `reference_outputs`. The central figure additionally requires the FOMC event panel, which is passed with `--event-panels` because event-level data are not distributed.

## Stages of the FOMC replication

The FOMC calendar is built from the meeting pages of the Board of Governors, which link to 142 statement pages between December 2008 and March 2026. The release time comes from the statement page when stated there, from the press-conference page otherwise, and from the regular schedule in the remaining cases, namely 14:15 Eastern Time before 13 March 2013, with 12:30 on press-conference days, and 14:00 afterwards. No anchor is set from the market reaction, and the minutes of a meeting prevail over a press-conference page. Every time is checked against the reaction of the two coordinates at the release bar, and the eighteen flagged dates were reviewed individually before the calendar was promoted.

The module `confirmation_analysis/fed_replication.py` enforces the order of operations. `protocol-template` writes the protocol with an empty signature, the author fills in reviewer and date, `coverage` counts the bars of every window without reading any post-window price of the outcome contract, the signed protocol is committed, and `run` refuses to execute without it and records its SHA-256 hash. The post-replication decomposition refuses to run if the protocol hash differs from that of the replication run, and labels its outputs as descriptive.
