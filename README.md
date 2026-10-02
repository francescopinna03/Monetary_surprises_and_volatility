# The Amplitude of Monetary Surprises and the Intraday Volatility of Government Bond Futures

This repository reproduces the empirical results of the working paper of the same title (Francesco Pinna, October 2026). The paper studies how abnormal bond-market variation in the twenty-five minutes after a monetary policy announcement scales with the joint amplitude of the interest-rate and equity surprises. The relation is found on ECB press releases and tested out of sample on FOMC statements under a protocol signed before any outcome of the FOMC sample was computed.

## Results

| Result | Sample | Status |
|---|---|---|
| Abnormal bipower variation rises with the magnitude of the two-year and of the equity surprise, and no effect of their signs is detected | ECB, 2000–2012 and 2013–2025 | Found after the samples were opened |
| A surface growing with the amplitude predicts held-out years better than the quadratic surface, and an exponent of two is excluded | ECB and FOMC | Found after opening |
| Once the amplitude is instrumented with an independent measurement, the elasticity of variance lies near one and that of volume near one half | ECB | Found after opening |
| F1, positive coefficient on the magnitude of the two-year surprise | FOMC, 2008–2026 | Pre-registered, confirmed, Holm-adjusted p = 0.001 |
| F2, positive coefficient on the magnitude of the equity surprise | FOMC, 2008–2026 | Pre-registered, confirmed, Holm-adjusted p = 0.009 |
| F3, elasticity strictly between zero and one | FOMC, 2008–2026 | Pre-registered, not confirmed, p = 0.079 |
| Ordering of pure-policy and information surprises at comparable amplitude | ECB and FOMC | Not identified; the FOMC contrast is a tight null |

## Repository layout

| Location | Content |
|---|---|
| `confirmation_analysis/`, `final_analysis/` | Python code for the ECB samples, the FOMC calendar and the FOMC replication |
| `matlab/` | MATLAB data stage: audit, cleaning, contract selection and certification of time alignment and bar labels |
| `scripts/` | One runner per stage, and `Make_paper_tables.py`, which rebuilds the tables and figures of the paper |
| `Raw/Certification/` | Certified inputs: verified ECB and FOMC calendars, bar-label evidence, reviewed decisions, frozen specifications and the signed FOMC protocol |
| `reference_outputs/` | Archived outputs and manifests of every run behind the paper |
| `tests/` | Test suite, 135 tests |
| `docs/` | Provenance, chronology and the dated records of the project |

## Reproduction

The tables and figures of the paper can be rebuilt from the archived outputs, without market data. The figures additionally require matplotlib.

```bash
python3 -m pip install -r requirements-final-analysis.txt matplotlib
python3 scripts/Make_paper_tables.py --output tables
```

Rerunning the analyses from market data, stage by stage, is described in `REPLICATION.md`. The market data are not distributed with this repository, because their licence does not permit redistribution.

## Provenance

The order in which the analyses were designed and run determines the status of each result, and it is documented in `docs/provenance.md` and `docs/chronology.md`. The complete research history, including the earlier designs that the paper does not use, is preserved at the tag `research-history-2026-10-02`.

## Citation

Pinna, F. (2026). *The Amplitude of Monetary Surprises and the Intraday Volatility of Government Bond Futures.* Working paper, LUISS Guido Carli.

## Licence

The code is released under the MIT licence. The licence does not extend to the market data, which remain subject to the terms of their providers.
