# Correction of the FOMC calendar, 5 October 2026

## Origin

The certified calendar `Raw/Certification/fomc_calendar_verified.csv` was cross-checked against the U.S. Monetary Policy Event-Study Database of the Federal Reserve Bank of San Francisco (USMPD, sheet `Statements`, vintages of 19 March 2026 and 17 September 2026) and against the FOMC dates of Bauer and Swanson (sheet `High_Freq`). All 142 rows of the calendar appear in USMPD, and the release times agree on 140 of them. The two vintages of USMPD give the same results.

## Release times

| Date | Calendar | USMPD | Bauer and Swanson | Decision |
|---|---|---|---|---|
| 16 December 2008 | 14:15 ET | 14:11 ET | 14:15 ET | Retained |
| 24 October 2012 | 12:30 ET | 14:15 ET | 14:15 ET | Corrected to 14:15 ET |

The anchor of 16 December 2008 is stated in the minutes, and the market check at 14:15 found the reaction only after the release bar, which is not consistent with a release at 14:11.

The anchor of 24 October 2012 came from the Board page `monetarypolicy/fomcpresconf20121024.htm`. The page carries the title of the meeting of 23–24 October 2012, is headed as a press conference, and states that the statement was released at 12:30 p.m. No press conference was held at that meeting, and USMPD lists none. The minutes state that the vote "encompassed approval of the statement below to be released at 2:15 p.m." and record that the meeting adjourned at 12:50 p.m., so a release at 12:30 p.m. was not possible. The date was not flagged for review: the press-conference page made 12:30 the regular slot for that day, and the market check found no visible reaction. The minutes were consulted only for flagged dates. The anchor is set to 14:15 ET, 18:15 UTC, with the regular schedule as time source. The market check at the new anchor finds no visible reaction and prefers no other regular slot.

Of the 21 rows whose time came from a press-conference page, this is the only one without a press conference in USMPD.

## Releases absent from the calendar

USMPD lists four unscheduled events in the period of the calendar that the calendar did not contain. The calendar module had read the releases of 11 October 2019, 19 March 2020, 31 March 2020 and 27 August 2020 and had set them aside as non-statement releases, without a row.

| Date | Release | Content | Decision | Market check |
|---|---|---|---|---|
| 4 October 2019 | none | Conference call; USMPD measures a window on this date in which nothing was released | Not added | |
| 11 October 2019 | 11:00 a.m. EDT | Treasury bill purchases and repurchase operations for reserve management, described by the statement as technical measures that do not change the stance of policy | Excluded | Confirmed at release bar |
| 19 March 2020 | 9:00 a.m. EDT | Temporary dollar liquidity swap lines with nine central banks | Excluded | No visible reaction |
| 31 March 2020 | 8:30 a.m. EDT | Temporary FIMA Repo Facility | Excluded | No visible reaction |
| 27 August 2020 | 9:10 a.m. EDT | Updates to the Statement on Longer-Run Goals and Monetary Policy Strategy | Excluded | Confirmed at release bar |

The release that USMPD dates 4 October 2019 is the statement of 11 October 2019, which Bauer and Swanson date correctly. The four releases are added as excluded rows with their reasons, in the form of the excluded row of 9 May 2010. Before the correction their days entered the control sample, because the control sample consists of the weekdays that are not calendar dates. The exclusion of 27 August 2020 is a decision on the event perimeter with an observable market reaction.

## Calendar versions

| Version | Rows | Primary | SHA-256 |
|---|---|---|---|
| Certified on 29 September 2026 | 142 | 138 | `e5bf1ebf88d011682b4a8fb519d56a411aa00102f568cde85911b7eb159ac978` |
| Corrected on 5 October 2026 | 146 | 138 | `16d4b3c50ca56cfabed4a63f74ffee7d1444d73cfdc6bd6bb43c138c077c66cb` |

The corrected version differs by one changed row, 24 October 2012, and four added rows.

## Primary sample

Of the 138 primary events, 131 enter the primary specification. The losses are the same under both versions of the calendar.

| Step | Events | Lost |
|---|---|---|
| Complete bars of ZN, ZT and ES | 137 | 29 April 2015: ZN and ZT lack the bars of 14:05 to 14:20 ET, while ES is complete |
| Positive pre-window bipower variation | 133 | 29 January 2014, 27 April 2016, 17 March 2021, 18 June 2025 |
| Positive post-window bipower variation | 131 | 30 January 2019, 19 March 2025 |

The two events lost to a zero post-window bipower variation have positive realized variance. Their zero comes from unchanged closes of ZN in alternate bars. The realized-variance row of the mean branch, on 133 events, includes them.

## Effect on the pre-registered family

| Run | Calendar | F1 | F2 | F3 |
|---|---|---|---|---|
| 29 September 2026, archived | Certified | 0.09157 (Holm 0.0012) | 0.20349 (Holm 0.0092) | 0.7478 (p 0.0794) |
| 5 October 2026, diagnostic | 24 October 2012 corrected only | 0.09048 (Holm 0.00105) | 0.20202 (Holm 0.0097) | 0.7416 (p 0.0737) |
| 5 October 2026 | Corrected | 0.09059 (Holm 0.00105) | 0.20179 (Holm 0.0097) | 0.7413 (p 0.0733) |

F1 and F2 remain confirmed and F3 remains not confirmed. Nearly all of the change comes from the anchor of 24 October 2012. At 14:15 the event has a policy coordinate of exactly zero, an equity coordinate of −0.76 control standard deviations and an abnormal log bipower variation of 1.72, against 0.65 at the earlier anchor. The exclusions remove four control rows, from 5,517 to 5,513. The exponent interval, the comparison of the radial bases and the sector contrast keep the conclusions stated in the paper.

The protocol and the code are unchanged. The calendar is an input certified before the protocol was signed, and its correction does not alter the hypotheses, the specification or the tests.

## Runs

| Run | Output | Commit |
|---|---|---|
| Reproduction of the archived replication in a new environment | `fed_replication_20261005_223701_4098` | `1b36045` |
| Diagnostic, 24 October 2012 corrected only | `fed_replication_20261005_225134_4661` | `1b36045` |
| Diagnostic, corrected calendar | `fed_replication_20261005_225634_4700` | `1b36045` |
| FOMC replication | `fed_replication_20261005_230052_4750` | `147a791` |
| FOMC post-replication decomposition | `fed_post_replication_20261005_230144_4776` | `147a791` |
| Measurement-error check | `measurement_check_20261005_235839_4980` | `147a791` |

The reproduction matched the archived family of 29 September 2026 to the last digit. The two diagnostic runs read a corrected copy of the calendar in the data folder, with the repository clean. The last three runs were executed on the commit that contains the corrected calendar, and their outputs are archived in `reference_outputs/paper` as `fomc_replication_20261005`, `fomc_post_replication_20261005` and `measurement_check_20261005`, with the event-level panel excluded. The measurement-error check reproduces the ECB rows of the archive of 30 September 2026 exactly and leaves every verdict unchanged.
