# Confirmation v2: outcome-free quality and unresolved design decisions

This branch changes only `Monetary_surprises_clone`. It includes the previously
local preparation/inventory fixes, the raw OHLC and exact-window audit, and now
the remaining chain: reviewed decisions, protected control build, outcome-free
calibration, freeze and v2 estimation. See `CONFIRMATION_ESTIMATION_V2.md`.
No confirmation outcomes have been computed in development.

The five decisions below are no longer open questions in prose: they are entries
in `Raw/Certification/confirmation_decisions_v2.json`, which the runner refuses
to resolve on its own. Two blockers remain deliberately unresolved, external
window timing and the verified US release calendar.

Two evidence tables that used to be filled in by hand are now extracted and then
reviewed: the ECB event calendar, from the official annual indices of monetary
policy decisions and introductory statements, and the bar-label convention, from
the published Eurex session boundary rather than from the announcement itself.
Both extractors write candidates and refuse to promote them without a named
reviewer and a written rule. See `CONFIRMATION_EVIDENCE_V2.md`.

## Run the next safe stage

Use the Python environment and raw data already on the Mac. This command selects
the most recent successful `confirmation_inventory_*/audit` under the existing
run. It does not clone or modify the raw archive, and never reruns MATLAB or the
generation bridge.

```bash
bash Run_confirmation_quality.sh \
  "$HOME/Desktop/Monetary_surprises_FULL_rqjB5J"
```

An explicit inventory and raw directory can be supplied if desired:

```bash
bash Run_confirmation_quality.sh \
  "$HOME/Desktop/Monetary_surprises_FULL_rqjB5J" \
  --audit-dir /absolute/path/to/confirmation_inventory_RUN/audit \
  --canonical-raw-dir "$HOME/Desktop/Econometrics_data/Raw/Barchart_futures"
```

Paths in an inventory are verified against file hashes; this is deliberately not
a relocation tool. When moving data, rerun the metadata inventory. Output goes to
a fresh directory and the command prints a ZIP path even after a failed audit.
The ZIP contains diagnostic counts/flags, provenance and executed source code,
not market prices or confirmation returns. Exit code zero means the audit ran,
**not** that estimation is authorized.

## What is implemented

- One primary file per contract cell. New inventories persist the priority;
  legacy inventories use an explicit canonical directory or a recorded
  `Raw/Barchart_futures` preference. Never select a source by outcome, size or
  number of rows. Other candidates remain in the metadata inventory.
- Finite positive OHLC, consistent high/low, finite nonnegative volume, DST-aware
  raw timestamp parsing, duplicate-label flags. Low-volume prices are not
  deleted. Raw files remain byte-for-byte unchanged.
- Exact price pairs on one shared grid for subsequent RV/BV. No interpolation,
  carrying forward, gap bridging or selection by post-announcement volume.
- Pre-PR ranking uses completeness, coverage, pre-PR endpoint volume, filename
  and finally path. Spike checks for a window cannot use a price after its last
  endpoint. The audit flags spikes; it does not yet approve a cleaning policy.
- Separate state, phase and pre-PC continuation checks, followed by a joint
  phase eligibility registry. Observed session spans and internal gaps are both
  checked; these are not represented as official exchange-session evidence.
- Unverified calendar times/bar labels yield diagnostics, never certified event
  eligibility. A verified absent PC remains excluded. Known PR/PC overlap is
  flagged. A missing raw file, including `fxh11`, is not imputed.
- Readiness checks table, raw input and code hashes; stale or changed artifacts
  are rejected. The report explicitly retains methodological/development blocks.
- Generation-only cone tests, signed restricted wild bootstrap, resolution and
  historical DST self-tests from the earlier local preparation are included.

## Evidence files

Place user-reviewed evidence under `Econometrics_data/Raw/Certification`:

| File | Required fields |
|---|---|
| `ecb_calendar_verified_v2.csv` | `event_date,phase,actual_phase_present,event_datetime_utc,source_url,verification_status,notes` |
| `bar_label_evidence_v2.csv` | `root_code,period_start,representative_sha256,bar_label_semantics,evidence_source,reviewer,verified` |

Calendar booleans are `true/false`. Verified calendar rows require an ECB URL and
an explicit timezone when the phase is present. Bar-label evidence covers starts
2000, 2003, 2006, 2009, 2012 per available root; it binds a nonempty representative
primary file in that period. A URL and reviewer are an attestation, not an
automated verification of the contents of the provider page. These files must
not be fabricated from nominal announcement schedules or volume peaks.

## Decisions needed before further implementation

1. **Window support.** Five PR return endpoints `5,10,15,20,25` use six prices
   from PR through PR+25. Their support is `(PR,PR+25]`, not `(PR+5,PR+25]`.
   The same applies to nine PC returns over `(PC,PC+45]`. No change to these
   canonical grids has been made. For pre-PC continuation, v1 endpoints
   `-25,-20,-15,-10,-5` imply `(PC-30,PC-5]`. The plan prose says
   `(PC-25,PC-5]`, which has only four returns. The diagnostic retains the v1
   grid; its use for estimation requires an explicit resolution.
2. **Lagged daily state and blinding.** `final_analysis/data.py` computes
   `day_rv` also on event days and then `slow5_log_rv` from the preceding five
   selected contract-days. The strict prohibition on constructing *any*
   confirmation event outcome before freeze is incompatible with reusing that
   builder for pre-freeze controls. Options require methodological review:
   pre-freeze use of lagged event daily RV as a permitted covariate, or an
   event-day-excluded slow-state rule validated on generation data. This branch
   adopts neither silently and never calls the v1 window builder on confirmation.
3. **Equity source and metric.** The already observed bridge proposes the plan's
   homogeneous external fallback, but the four checks do not all pass. A reviewed
   source/scale decision is required; do not claim equivalence to aligned futures.
4. **Secondary family and sufficiency interval.** The plan needs an exact finite
   test list and a simultaneous coverage rule for the interval. Keep the
   scientific reference margin distinct from a design-specific detectable floor.
5. **External evidence.** Verify actual ECB phase existence/times, EA-EMPD
   baseline/endpoints for extraordinary dates, provider bar labels and US release
   coverage. A Thursday 08:30 screen is not a verified release calendar.

After these decisions, implement and validate the blinded control/design build,
event-unit power calibration, frozen manifest, primary/secondary estimation and
separate descriptive sensitivities. Steps 26–28 must not become confirmation
estimators; only the separate outcome-free Step 28 calibration is allowed.

The explicit remaining blocks are intentional, not evidence that these later
modules already exist or a substitute for their implementation.
