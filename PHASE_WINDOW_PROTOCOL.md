# Frozen non-overlapping PR–PC–ME window protocol

The legacy Step-5 and Step-18 outputs remain available for audit. New
phase-specific work uses separate files under `Output/phase_windows` and cannot
run without a certified `window_semantics_v1` manifest.

All provider timestamps are first converted to canonical interval-end UTC.
Return endpoints are then fixed as follows:

| Phase | Pre-window return endpoints | Response return endpoints |
| --- | --- | --- |
| PR | −55 to −5 minutes | +5 to +25 minutes |
| PC | −25 to −5 minutes | +5 to +45 minutes |
| ME | −55 to −5 minutes from PR | +5 minutes from PR through PC +45 minutes |

The PR response therefore ends 20 minutes before the conference in the early
timing regime and five minutes before it in the post-July-2022 regime. No bar is
shared by the PR and PC response outcomes. The ME window is a deliberately
broader benchmark and is not interpreted as a pure phase.

The 25-minute PR horizon is chosen before observing phase-specific estimates.
It is the longest fixed five-minute horizon that leaves at least one complete
bar between PR and PC in both calendar regimes. PC uses a fixed 45-minute
horizon. ME has regime-dependent duration, so its primary scale is realized
variation per observed return; totals remain descriptive.

Windows are anchored to scheduled ECB clocks. Volume profiles validate that
both phases matter but may not shift or select an event time. Preferred
contracts are inherited from the pre-existing event-contract stage; the new
phase outcome never enters contract choice.

The phase-specific non-event design is frozen separately in
`PHASE_COUNTERFACTUAL_PROTOCOL.md`. In that design all phase runs use the same
PR-pre contract-selection rule, while their outcome windows remain distinct.
