# Frozen protocol for Barchart time-zone and bar-label certification

## Purpose

`timezone_v1` establishes that the archived Barchart wall clocks must be
localized in `America/Chicago` before conversion to UTC. It does not establish
whether a five-minute timestamp labels the beginning or the end of its OHLCV
interval. That remaining ambiguity is economically material for an event that
occurs exactly on a bar boundary.

No phase-specific coefficient may be estimated until this protocol returns a
certified manifest. The tests use only data provenance and OHLCV aggregation;
they do not use a monetary-policy regression, a preferred sign or a volatility
result.

## Inputs

Create `Raw/Certification/window_semantics_inputs.csv` from the template under
`config/`. It identifies four roles for the same contract and overlapping
dates (the same fresh five-minute file may serve two roles):

1. an archived five-minute file used by the project;
2. a fresh five-minute Barchart Premier futures export;
3. one-minute Premier bars;
4. five-minute Premier bars covering the one-minute sample.

The project-specific preset
`config/window_semantics_inputs_fxu23_premier.csv` records the frozen FXU23
filenames and can be copied directly into `Raw/Certification/`; it avoids
manual placeholder substitution without embedding raw licensed data in the
repository.

Barchart Premier does not expose a time-zone selector in its historical-data
download form. The frozen evidence record
`config/window_semantics_timezone_evidence.csv` therefore records Barchart's
published convention that futures times are Central Time (CT), the supporting
URL and the access date. The test must not manufacture a UTC-labelled copy of
the Premier export.

At least 100 common five-minute observations are required. A 2023 contract is
preferred because it lies within current intraday download coverage and can be
matched to an archived project file. The 14 September 2023 ECB date is useful,
but the test must cover ordinary bars as well as the event interval.

## Time-zone decision

The archived and fresh Premier files are independently localized in
`America/Chicago`, converted to canonical UTC and joined by timestamp. The
comparison must retain at least 95 percent of the smaller file, include at
least 100 common bars and match complete OHLCV rows at a rate of at least 99.9
percent. Certification rests on two distinct provenance elements: the
provider's published CT convention and exact reproduction of archived wall
clocks and OHLCV by a fresh Premier export. Full-sample session-clock and
announcement-volume diagnostics remain corroborating evidence rather than a
substitute for either provenance element.

## Bar-label decision

Every five-minute bar is reconstructed twice from one-minute OHLCV data.

- `interval_start`: minute labels `t,t+1,...,t+4` form the five-minute bar
  labelled `t`;
- `interval_end`: minute labels `t-4,...,t` form the five-minute bar labelled
  `t`.

Open is the first one-minute open, close is the last one-minute close, high and
low are extrema, and volume is summed. The selected convention must match at
least 95 percent of aggregatable OHLCV rows and exceed the competing convention
by at least 20 percentage points.

## Canonical representation

Once the decision passes, all new phase-specific code converts provider labels
to `interval_end_utc`. If labels mark interval starts, five minutes are added;
if they mark interval ends, the timestamp is unchanged. PR, PC and ME returns
are defined only after this conversion.

## Outputs and gate

Run `Window_semantics_self_test` and then `Window_semantics_certification`.
Diagnostics are written under `Output/diagnostics`; the binding result is
`Output/manifests/window_semantics_manifest.csv`. The helper
`Require_window_semantics_manifest.m` prevents phase-window construction when
the status is missing, failed or unresolved.
