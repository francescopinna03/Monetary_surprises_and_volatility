# Monetary Surprises and Volatility

This repository contains the code, the certified inputs, the signed protocols and the reference outputs behind the working paper *The Amplitude of Monetary Surprises and the Intraday Volatility of Government Bond Futures* (Francesco Pinna, October 2026). The paper studies how the variation of ten-year government bond futures in the twenty-five minutes after a monetary policy announcement depends on the joint amplitude of the interest-rate and equity surprises. It establishes the relation on ECB press releases from 2000 to 2025 and replicates it on FOMC statements from 2008 to 2026 under a protocol signed before any outcome of that sample was computed.

The state of the code that produced the results reported in the October 2026 version of the paper is identified by the tag `v2-preprint`.

## Summary of the evidence

The results that the code supports, together with their status, are the following.

| Result | Sample | Status |
|---|---|---|
| Abnormal bipower variation rises with the magnitude of the two-year and of the equity surprise, while the signed surprises carry no detectable effect | ECB, 2000–2012 and 2013–2025 | Observed after opening |
| A surface growing with the amplitude predicts held-out years better than the quadratic surface, and the exponent of two is excluded | ECB and FOMC | Observed after opening |
| Once the amplitude is instrumented with an independent measurement, the elasticity of variance lies near one and that of volume near one half | ECB | Observed after opening |
| The coefficients on the magnitude of the two-year and of the equity surprise are positive | FOMC, 2008–2026 | Pre-registered, confirmed at Holm-adjusted p of 0.001 and 0.009 |
| The elasticity lies strictly between zero and one | FOMC, 2008–2026 | Pre-registered, not confirmed (p = 0.079) |
| The mean over the pure-policy cone is positive and exceeds that over the information cone | ECB, 2000–2012 | Frozen, not confirmed |

The distinction between frozen, pre-registered and post-opening results is maintained in every manifest and output of the repository and is documented in the chronology below.

## Repository structure

| Location | Content |
|---|---|
| `*.m`, `Run_pipeline.m` | The historical MATLAB pipeline of twenty-eight steps, which certifies time alignment and bar semantics, builds the event windows and implements the earlier sign-based and dynamic designs |
| `final_analysis/` | The Python estimation battery for the 2013–2025 generation sample |
| `confirmation_analysis/` | The Python modules for the 2000–2012 confirmation sample, the post-opening analyses, the FOMC calendar and the FOMC replication |
| `tests/` | The Python test suite, 146 tests at the tag `v2-preprint` |
| `Raw/Certification/` | Certified inputs, namely the verified ECB and FOMC calendars, the bar-label evidence, the reviewed decisions, the frozen specifications and the signed FOMC protocol |
| `config/` | Exchange trading hours with their documentary sources |
| `reference_outputs/` | Archived outputs of the cross-period comparison of 16 September 2026, with their manifests |
| `docs/` | Documentation of the analyses and the dated records of the project, indexed in `docs/README.md` |
| `*_PROTOCOL.md`, `STEP*.md` | Frozen protocols and records of the historical pipeline |
| `Run_*.sh` | Shell runners that execute each stage, write a manifest and package the outputs into a ZIP archive |

## Data

The market data are not distributed with this repository, because their licence does not permit redistribution. The analyses use five-minute and one-minute bars on expired futures contracts obtained from Barchart, namely the Euro-Schatz, Euro-Bobl, Euro-Bund and EURO STOXX 50 futures on Eurex and the two-year and ten-year Treasury note and E-mini S&P 500 futures on the CME, together with the Euro Area Monetary Policy event-study Database of Altavilla, Gürkaynak, Kind and Laeven. The expected layout of the data directory is described in `docs/DATA.md`. Every runner locates the data through the facility directory passed as its first argument, and no path needs to be edited in the source files.

## Requirements

The Python code requires Python 3.10 or later and the packages listed in `requirements-final-analysis.txt`. The historical pipeline requires MATLAB, and the recorded runs used R2025b Update 3. The FOMC calendar module requires network access to the Federal Reserve Board website on its first run and caches every page it reads.

```bash
python3 -m pip install -r requirements-final-analysis.txt
python3 -m pytest -q tests
```

## Running the analyses

Each stage is executed by a shell runner whose first argument is the facility directory containing `Econometrics_data` and the Python environment. Every runner writes its outputs into a new timestamped directory, records the commit, the state of the working tree, the hashes of the code and of the inputs, and packages the outputs into a ZIP archive, so that no run overwrites another.

| Stage | Runner | Documentation |
|---|---|---|
| Historical pipeline, Steps 1 to 28 | `Run_pipeline.sh` | `docs/HISTORICAL_PIPELINE.md` |
| Estimation battery, 2013–2025 | `Run_final_analysis.sh` | `FINAL_ANALYSIS_PROTOCOL.md` |
| Confirmation sample, inventory to freeze | `Run_confirmation.sh` and the `Run_confirmation_*.sh` runners | `CONFIRMATION_PROTOCOL_V2.md`, `CONFIRMATION_ESTIMATION_V2.md` |
| Post-opening analyses on the ECB samples | `Run_confirmation_exploratory.sh`, `Run_confirmation_jump.sh`, `Run_confirmation_minute.sh`, `Run_design_information.sh`, `Run_measurement_check.sh` | `docs/POST_OPENING_ANALYSES.md` |
| FOMC calendar and replication | `Run_fomc_calendar.sh`, `Run_fed_replication.sh`, `Run_fed_post_replication.sh` | `docs/FOMC_REPLICATION.md` |
| Correspondence with the tables and figures of the paper | | `docs/REPRODUCING_THE_PAPER.md` |

## Provenance and integrity guards

Three mechanisms protect the integrity of the results. Confirmatory stages refuse to run on a build whose code hashes differ from those recorded when the build was frozen, so that a frozen result cannot be recomputed with different code. The FOMC replication refuses to run without a signed protocol and records the hash of the protocol in its manifest. Post-opening analyses label their outputs as such and never overwrite confirmatory outputs.

The code in this repository was developed in a separate working repository and published here in thematic commits on 2 October 2026, with comments removed from newly added code. Because the integrity guards compare byte-level hashes, the two confirmatory stages that depend on frozen builds, the estimation on the 2000–2012 build and the preparation of the cross-period inputs, can be re-executed exactly only with the code of the working repository at the commits recorded in the run manifests. Every other stage runs from this repository.

## Chronology

The order in which the analyses were designed and run determines the status of each result.

| Date | Event |
|---|---|
| July–August 2026 | Historical pipeline, time-alignment correction and dynamic extension (Steps 1 to 28) |
| 10–11 September 2026 | Frozen specification and estimation battery for 2013–2025 |
| 12–13 September 2026 | Confirmation plan, quality audit and certification of the ECB calendar and bar labels for 2000–2012 |
| 14 September 2026 | Freeze and single estimation of the confirmation tests on 2000–2012 |
| 15 September 2026 | Declared second opening of the 2000–2012 sample after a correction of scale |
| 16–19 September 2026 | Functional-form diagnostics, cross-period comparison and jump-robust measures, all after opening |
| 28 September 2026 | One-minute outcomes and radial-exponent diagnostics, after opening |
| 29 September 2026 | Certified FOMC calendar, signed FOMC protocol and single run of the pre-registered replication |
| 30 September 2026 | Post-replication decomposition and measurement-error check |

## Citation

Pinna, F. (2026). *The Amplitude of Monetary Surprises and the Intraday Volatility of Government Bond Futures.* Working paper, LUISS Guido Carli.

## Licence

The code is released under the MIT licence, as stated in `LICENSE`. The licence does not extend to the market data, which remain subject to the terms of their providers.
