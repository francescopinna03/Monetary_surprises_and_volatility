# Data

## Sources

The analyses combine intraday futures prices with an external database of monetary policy surprises. None of the market data is distributed with this repository, because the licence of the provider does not permit redistribution.

| Source | Content | Use |
|---|---|---|
| Barchart, five-minute bars on expired contracts | Euro-Schatz (`hf`), Euro-Bobl (`hr`), Euro-Bund (`gg`) and EURO STOXX 50 (`fx`) futures, 2000–2026 | Outcomes and aligned coordinates of the ECB samples |
| Barchart, one-minute bars on expired contracts | Euro-Bund futures, 2000–2026, exported in date slices of at most 20,000 rows | One-minute outcomes of the ECB samples |
| Barchart, five-minute bars on expired contracts | Ten-year Treasury note (`zn`), two-year Treasury note (`zt`) and E-mini S&P 500 (`es`) futures, December 2008 to 2026 | Outcome and coordinates of the FOMC sample |
| Euro Area Monetary Policy event-study Database (EA-EMPD) | Changes in OIS rates, sovereign yields and equity indices over the press-release and press-conference windows of every Governing Council meeting since 1999 | External surprise measures, the equity coordinate of the ECB samples and the instrument for the policy coordinate |
| ECB website | Monetary policy decisions and introductory statements | Verification of the ECB calendar |
| Federal Reserve Board website | Meeting calendars, statements and minutes | Construction of the FOMC calendar |
| Eurex circulars and trading calendars | Historical trading hours | Certification of the bar-label convention |

## Directory layout

Every runner receives a facility directory as its first argument and expects the data under `Econometrics_data` inside it.

```text
Econometrics_data/
├── Raw/
│   ├── Barchart_futures/                 five-minute files of the 2013–2026 contracts
│   ├── Barchart_futures_confirmation/    five-minute files of the 2000–2012 contracts
│   ├── Barchart_futures_1min/            one-minute Bund slices, ggXYY_1min_start_end.csv
│   ├── Barchart_futures_fed/             five-minute zn, zt and es files
│   ├── EA-EMPD/                          EA-EMPD.xlsx
│   ├── ECB_calendar/                     ECB event calendar used by the historical pipeline
│   ├── FOMC_calendar/pages/              cache of the Board pages read by the calendar module
│   └── Certification/                    frozen builds, verified calendars and promotion records
└── Output/                               one timestamped directory per run
```

The repository itself holds a second `Raw/Certification` directory with the certified inputs that are small enough to be versioned, among them the verified ECB calendar, the bar-label evidence, the reviewed decisions, the frozen specifications and the signed FOMC protocol. The frozen builds, which contain derived market data, remain in the data directory.

## Conventions

Barchart timestamps are wall-clock times in America/Chicago and are converted to UTC with IANA time-zone rules, never with fixed offsets. ECB event times are wall-clock times in Europe/Berlin and FOMC event times in America/New_York. Bar labels mark the start of each interval, a convention certified for Eurex from session boundaries and for the CME from the reaction at documented release times, as described in `../CONFIRMATION_EVIDENCE_V2.md` and `FOMC_REPLICATION.md`.

The one-minute archive was certified against the five-minute archive by aggregation. Under the interval-start convention the volume of a five-minute bar equals the sum of the five one-minute volumes that start inside it, an identity that holds for 99.99 percent of the bars of all 106 Bund contracts and fails for 91 percent of them under the opposite convention.

No price is filled, interpolated or carried across a missing bar. A window enters an analysis only if every price it requires is available, and the rules for staleness and completeness are stated in the specification or protocol of each stage.
