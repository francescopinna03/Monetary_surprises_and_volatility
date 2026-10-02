# The pre-registered FOMC replication

## Purpose

The amplitude law documented on ECB press releases was found on data that had already been opened, so its existence on data that had not shaped it could not be established from the ECB samples alone. The FOMC replication tests it on a different central bank, market, set of contracts and period, under a protocol written and signed before any outcome of the FOMC sample was computed.

## Calendar

`Run_fomc_calendar.sh` builds the calendar of FOMC statements from the historical meeting pages and the current calendar page of the Board of Governors, which link to 142 statement pages between December 2008 and March 2026. Every page read is cached in `Raw/FOMC_calendar/pages` with its hash, so that later runs do not depend on the website.

The release time of each statement is taken from the statement page when the page states it, from the press-conference page otherwise, and from the regular schedule in the remaining cases. The regular schedule is 14:15 Eastern Time before 13 March 2013, with 12:30 on press-conference days, and 14:00 afterwards, as documented in the Board's announcement of 13 March 2013. Of the 142 times, 86 come from statement pages, 20 from press-conference pages and 36 from the schedule.

Four rules govern the anchors. An anchor is never set from the market reaction. When a page and the schedule disagree, the discrepancy is reviewed and documented. The minutes of a meeting prevail over a press-conference page, which applies to four press-conference days of 2012 whose pages state 12:20 or 12:35 while the minutes state 12:30. The perimeter of events comprises decisions on the policy rate, forward guidance and asset purchases, and excludes statements concerning swap lines only.

Every time is then checked against the reaction of the two-year note and the E-mini future at the release bar relative to the preceding hour. The check confirms 65 of the 68 page-documented times at the release bar and finds the reaction in the following bar for the other three, which establishes the interval-start convention of the CME bars. Eighteen dates were flagged and reviewed individually. Fourteen are included in the primary sample, the unscheduled actions of 3 and 23 March 2020 are kept in the calendar but excluded from estimation because no control day shares their clock, and two are excluded, the swap-line statement of Sunday 9 May 2010 and the statement of Sunday 15 March 2020, released before the CME reopened. The reviewed calendar was promoted to `Raw/Certification/fomc_calendar_verified.csv` on 29 September 2026.

## Data and design

The outcome is the bipower variation of the ten-year Treasury note future over the five five-minute returns in the twenty-five minutes after the release, relative to a continuation fitted on control days at the same clock, leaving out one calendar year at a time. The continuation uses the log pre-window bipower over (−60, −5] minutes and its square, a slow state given by the mean log daily realized variance over the five preceding control days, a linear trend and weekday and month indicators. Control days are weekdays inside the contract windows that are not FOMC dates, anchored at 14:15 and 12:30 before 13 March 2013 and at 14:00 afterwards.

The policy coordinate is minus the log return of the two-year note future over the same window, and the equity coordinate is the log return of the E-mini S&P 500 future, each divided by its standard deviation over control days. The contract of each date is the file whose non-overlapping front-month window contains it, with windows bounded by first notice days and roll dates.

## Protocol and workflow

The module `confirmation_analysis/fed_replication.py` enforces the order of operations.

1. `protocol-template` writes the protocol with the reviewer and the review date left empty.
2. The author fills in both fields, which constitutes the signature.
3. `coverage` counts the bars of every window of the two coordinates and of the pre-window of the outcome, without reading any post-window price of the ten-year contract.
4. The signed protocol is committed to the repository.
5. `run` refuses to execute without a signed protocol, records its SHA-256 hash in the manifest and runs the declared family once.

The protocol, `Raw/Certification/fed_protocol_v1.json`, declares a family of three one-sided tests corrected by Holm at the five percent level:

| Test | Statement | Inference |
|---|---|---|
| F1 | The coefficient on the magnitude of the two-year surprise is positive | Restricted wild cluster bootstrap, 19,999 draws |
| F2 | The coefficient on the magnitude of the equity surprise is positive | Restricted wild cluster bootstrap, 19,999 draws |
| F3 | The mean elasticity under the logarithmic law lies strictly between zero and one | Intersection–union of two one-sided CR1 tests |

It also declares the list of descriptive analyses, the completeness rule under which an event enters only if every endpoint price of the three contracts is available within five minutes and the continuation is defined, and a statement of what had been seen before signature, namely the release times checked against the reaction of the two coordinates and the bar counts of every window, and nothing of the outcome.

The protocol was amended once, after its first signature and before it was committed or any run took place. The amendment rewrote F3, which had stated only that the elasticity is below one and would therefore have been satisfied by a null effect, as an intersection–union test of a positive elasticity below one, added the completeness rule, and set the review date in ISO format. The committed and hashed protocol is the amended one.

## Results

The replication was run once, on commit `bb061b1` of the working repository, with the protocol hash `296e6acb9bedc40e4f3f9254a66d39d44f3559e853f31f0a7d173ef4759a25a9`. Of the 138 scheduled statements, 137 have complete windows and 131 a positive bipower variation.

| Test | Estimate | One-sided p | Holm p | Verdict |
|---|---:|---:|---:|---|
| F1 | 0.092 | 0.0004 | 0.0012 | Rejected, hypothesis confirmed |
| F2 | 0.203 | 0.0046 | 0.0092 | Rejected, hypothesis confirmed |
| F3 | 0.748 | 0.0794 | 0.0794 | Not rejected, hypothesis not confirmed |

The verdict on F3 is final under the protocol. The later measurement-error check, which shows that the uncorrected elasticity is attenuated on the ECB samples, offers a possible explanation of the failure but does not alter it.

## Post-replication decomposition

`Run_fed_post_replication.sh` splits the post-window volume of the ten-year contract into its first bar and the four that follow, and computes realized variance over returns two to five. The command reads the manifest of a completed replication run, refuses to execute if the protocol hash differs from the one recorded there, verifies that it reproduces the confirmatory coefficients on the bipower and on volume, and labels every output as descriptive and outside the declared family.
