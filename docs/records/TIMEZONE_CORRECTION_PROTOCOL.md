# Frozen protocol for the event-time correction

## Status

This protocol was written after identifying a timestamp-semantic error and
before inspecting any model estimated on the corrected event windows. It is a
data correction, not a new outcome specification. All scientific outputs from
Steps 5--21 produced before schema `timezone_v1` are superseded.

The earlier pipeline was computationally reproducible but compared Frankfurt
ECB wall clocks directly with Barchart futures wall clocks. The raw Barchart
files use Central Time, while the ECB calendar uses Frankfurt/Berlin time. As a
result, the legacy event windows were generally six or seven hours after the
scheduled announcement.

## Frozen clock conventions

1. Every raw Barchart timestamp is interpreted in the IANA zone
   `America/Chicago`.
2. Every ECB press-release and press-conference wall clock is interpreted in
   `Europe/Berlin`.
3. Both clocks are converted with the timezone database, including daylight
   saving transitions, to UTC.
4. Cleaned CSV files serialize the UTC wall clock in the existing `Time`
   column. The MATLAB datetime is timezone-neutral only after conversion, so a
   CSV round-trip cannot depend on the referee's computer locale.
5. Event files retain both `*_datetime_local` and `*_datetime_utc`. Only the
   UTC columns may be used for market-data comparisons.
6. No fixed six- or seven-hour subtraction is permitted.

The deterministic test `Time_alignment_self_test.m` freezes five reference
dates, including the March weeks in which the United States and Europe switch
daylight saving time on different dates. The full pipeline stops before
estimation if those mappings fail.

## Provenance and anti-mixing rule

Step 2 writes
`Output/manifests/time_alignment_manifest.csv`. Every step that reads cleaned
bars or downstream decisive outputs requires this manifest and verifies its
schema and timezone fields. Therefore current code refuses to combine old
cleaned files with corrected event clocks or corrected cleaned files with old
Step-18/Step-20 panels.

The event-level diagnostic `Event_time_alignment_audit.m` is run after Step 4.
For each preferred event-contract observation it reports:

- the corrected release-time five-minute return and volume;
- one-bar perturbations at -5 and +5 minutes;
- the legacy Barchart wall-clock bar selected by the old code.

These magnitudes are descriptive and cannot select the primary alignment. The
primary event clock is the exact IANA conversion. The one-bar perturbations
diagnose the unresolved provider bar-label convention and must be compared
with an independent one-minute or tick source before a final paper claim.

## Rerun and evidentiary status

The correction requires a clean rerun from the raw Barchart CSV files. Reusing
any prior `Output/cleaned`, `Output/event_windows` or `Output/analysis` file is
not allowed. The OIS surprise series and the ECB calendar dates are not changed,
but every statistic that uses a Barchart event or pre-event window must be
recomputed.

In particular, the following legacy conclusions are void pending the rerun:

- the original state-amplification coefficients;
- the BV/JV localization and Hurst-based diagnostics;
- the Step-18 counterfactual coefficients;
- the Step-19 validation and matched-placebo results;
- the Step-20 spectrum;
- the Step-21 `FAIL_RISK_RESOLUTION` decision.

The concentration of OIS shock energy remains a design limitation because it
is calculated from the surprise series rather than Barchart outcomes. The
conceptual result that an unconditional Hurst exponent cannot establish
conditional-state sufficiency also remains unchanged.

## Decision discipline after the corrected run

The corrected outputs must be archived in a new results directory or release
and explicitly labelled `timezone_v1`. They may be compared with legacy
outputs only as a measurement-error audit. No window, transformation, control
set or inference method may be selected according to which corrected estimate
best restores the original hypothesis.

The project direction will be reconsidered only after the exact-clock results,
the +/-5 minute audit, support diagnostics and event-date inference are viewed
together. A restored amplification result is not credible unless it survives
the already-developed counterfactual and concentration tests on the corrected
sample.
