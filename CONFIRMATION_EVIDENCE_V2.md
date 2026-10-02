# Automated evidence: ECB calendar and bar-label semantics

*Record written in September 2026 in Italian and translated into English. The original text is preserved in the repository history at commit `0f6daab`.*

Two items remained open row by row, namely which meetings of 2000–2012 were followed by a press conference, and whether the label of a five-minute bar marks the start or the end of its interval. Both can be automated almost entirely, neither can be closed without a human signature, and this document states exactly where the boundary lies.

## ECB calendar

The ECB publishes two indices that provide the required discrimination. The index of monetary policy decisions lists every decision of the Governing Council by year, and the archive of introductory statements states, date by date, whether a press conference took place.

This matters for the second meetings of the month in 2000 and 2001, when the Governing Council met twice a month but the press conference followed only the monetary policy meeting. No calendar rule resolves the question. In 2000 the index lists 25 decision dates and only 13 introductory statements, and in 2001 the monetary policy meeting of August is that of the 30th and not that of the 2nd. The presence or absence of the statement for a given date is the evidence.

```bash
bash Run_confirmation.sh calendar-candidates \
  --data-root "$HOME/Desktop/Monetary_surprises_FULL_rqjB5J/Econometrics_data" \
  --output /path/output/ecb_calendar
```

The script downloads the annual indices for 2000–2012 from `/press/govcdec/mopo/<year>/html/index_include.en.html` and `/press/press_conference/monetary-policy-statement/<year>/html/index_include.en.html`, resolves every listed release, checks that the date published on the page (`article:published_time`, with the printed date as a cross-check) matches that of the index, and archives every page read together with its SHA-256 hash. It computes `event_datetime_utc` from 13:45 and 14:30 Europe/Berlin with the IANA time zone, never with a fixed offset. Finally, it reconciles the ECB list with the EA-EMPD dates.

### Limits of the automated extraction

It writes `verification_status=candidate`, never `verified`.

**The absence of a page is not evidence that the event did not occur.** Over twenty-five years the ECB website has changed structure several times, and the URLs of 2000–2001 do not follow today's scheme. If a release cannot be resolved, the script produces no row for that date and sends it to the review queue as `unresolved_evidence`. Marking `actual_phase_present=false` on a 404 response would have removed a valid observation from the confirmation sample silently, without any test detecting it, and the opposite error, including a press conference that never took place, is worse.

A date absent from the annual index of statements is instead an absence declared by the source and not a broken URL. The script proposes it as `statement_absent_from_annual_index`, and the proposal can only be promoted row by row. A bulk promotion that encounters an unreviewed proposed absence stops with `UNREVIEWED_ABSENCE`.

The script infers nothing from volume peaks, for the same reason that the rest of the chain does not, since the only thing that makes a confirmation sample credible is the ability to state how each claim is known.

### Assumptions on release times

The ECB pages carry the **date** of an event and not its **time**. The times 13:45 and 14:30 are the historical regular schedule and not page evidence, the column `timestamp_basis` declares this row by row, and the readiness report keeps `external_window_timing` blocking precisely for this reason. The two known exceptions, 17 September 2001 and 8 October 2008, receive no timestamp, so the reviewer must supply one in `reviewer_event_datetime_utc`, otherwise the promotion stops with `MISSING_TIMESTAMP`.

### Outputs

| File | Content |
|---|---|
| `ecb_calendar_candidates.csv` | One row per date and phase, with URL, HTTP status, title, extracted date and the text fragment on which the script decided |
| `ecb_pages.csv` | Every resolved page, with its hash and the classification of its title |
| `ecb_calendar_reconciliation.csv` | The ECB list against EA-EMPD, with the type of discrepancy |
| `ecb_calendar_review_queue.csv` | Only the rows where a human decision changes the sample |
| `pages/` | Archive of the pages read, which does not enter the repository |

### Review

The queue opens five layers and nothing else:

- `timing_exception`, for 17 September 2001 and 8 October 2008;
- `anomalous_weekday`, for every date that does not fall on a Thursday, one by one;
- `multiple_meetings_in_month_2000_2001`, for the months of those two years with more than one meeting, where the decision on presence or absence changes the sample;
- `proposed_absence`, for every press conference proposed as absent;
- `reconciliation_discrepancy` and `unresolved_evidence`, for the disagreements between the two lists and the pages that could not be resolved;

together with a random sample of twenty ordinary rows, drawn with a fixed seed, to validate the extractor. If that sample is clean, the remaining rows are promoted in bulk under a written rule:

```bash
bash Run_confirmation.sh calendar-promote \
  --candidates /path/output/ecb_calendar \
  --reviewed-queue /path/reviewed_queue.csv \
  --output .../Raw/Certification/ecb_calendar_verified_v2.csv \
  --reviewer "Francesco Pinna" \
  --rule "Ordinary rows promoted in bulk: release and statement resolve on the ECB archive and the published date matches the annual index. Every open row was reviewed individually."
```

The promotion rejects a queue with even one row lacking a `reviewer_decision`, a row without a reviewer, a decision other than `true`, `false` or `exclude`, a promotion without a name or a rule, and any absence or unresolved evidence that was not reviewed individually. The rule, the reviewer and the hash of the queue are recorded in `ecb_calendar_verified_v2_promotion.json`.

Some fifty rows are genuinely opened for review, out of three hundred and sixty-two, and a documented rule covers the rest.

## Bar-label semantics

The obvious empirical test, which bar contains the movement of the announcement, is circular, because it uses the announcement to establish the label and then the label to measure the announcement.

The alternative is the session boundary, which has nothing to do with announcements. The first and last observed bars are compared with the Eurex trading hours published for the relevant period. If the session closes at 22:00 and the last bar is labelled 21:55, the label marks the start of the interval, and if the last bar is labelled 22:00 and the first one bar after the opening, it marks the end. A day that matches neither pattern is inconclusive and does not vote.

The only human task is to obtain the historical schedule, once per period and not once per file.

```bash
bash Run_confirmation.sh trading-hours-template --output config/eurex_trading_hours.csv
bash Run_confirmation.sh bar-label-evidence \
  --primary-files /path/confirmation_quality_RUN/quality/primary_files.csv \
  --schedule config/eurex_trading_hours.csv \
  --output /path/output/bar_label
```

The template is completed by hand with the fields `root_code`, `period_start_date`, `period_end_date`, `session_open_wall`, `session_close_wall`, `timezone`, `source_url`, `reviewer` and `notes`.

There is no fallback schedule. The loader rejects a missing file (`EUREX_SCHEDULE_MISSING`), the empty template (`EUREX_SCHEDULE_EMPTY`), a period without a source URL or without a reviewer (`EUREX_SCHEDULE_UNSOURCED`), overlapping periods (`EUREX_SCHEDULE_OVERLAP`) and more than one time zone in the same file, since a guessed session boundary would silently select a bar convention.

Dates in the schedule are written in ISO format `YYYY-MM-DD`, and `root_code` accepts `all` for a period valid for every root.

The decision is aggregated over the cell (root, three-year period) that the quality audit already uses. A cell is closed only if all conclusive days agree and number at least `--minimum-days`, twenty by default, and if both patterns receive votes within the same cell the conflict is recorded and the cell remains open.

```bash
bash Run_confirmation.sh bar-label-promote \
  --evidence /path/output/bar_label \
  --output .../Raw/Certification/bar_label_evidence_v2.csv \
  --reviewer "Francesco Pinna" \
  --rule "Cells whose conclusive session boundaries agree on a single convention, over at least twenty days of the Eurex schedule published for the period."
```

The output is the file that `quality_audit` reads, with one row per cell recording the convention, the URL of the schedule as source, the reviewer and the hash of the representative file that ties the evidence to the inventory.

A test demonstrates the absence of circularity, since deleting every bar between 13:00 and 15:00, that is, the whole announcement window, changes neither the decision nor the number of days in its favour.
