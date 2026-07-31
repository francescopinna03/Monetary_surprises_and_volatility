# Phase-specific counterfactual protocol

This extension estimates normal intraday continuation separately for the
press-release (`PR`), press-conference (`PC`) and aggregate monetary-event
(`ME`) windows. It does not overwrite the historical Step-18 files.

The extension is blocked unless both `timezone_v1` and
`window_semantics_v1` are certified. Provider labels are converted to
canonical interval-end UTC before any return is formed.

## Frozen timing and selection rules

| Run | Phase pre-window | Phase response | Component definition |
| --- | --- | --- | --- |
| PR | PR −55:−5 endpoints | PR +5:+25 endpoints | PR MP and CBI |
| PC | PC −25:−5 endpoints | PC +5:+45 endpoints | PC MP and CBI |
| ME | PR −55:−5 endpoints | PR +5 through PC +45 | ME MP and CBI benchmark |

On every event and control date, contract selection uses only coverage and
volume attached to return endpoints from PR −55 to PR −5. The PC contract is
therefore not selected with information revealed during the PR. Phase-pre
coverage may still make the selected contract ineligible, but it never changes
the ranking.

For the PC normal-continuation model, the phase pre-window is deliberately the
interval immediately before the scheduled conference. On ECB dates it may
contain the PR response: the PC abnormal outcome is therefore incremental to
the market state reaching the conference. The interaction state is different:
it is always standardized PR-pre bipower variation, so it is predetermined for
all three phase regressions.

## Components and inference status

The primary pooled regressions include squared MP and CBI shocks jointly,
together with their algebraic cross term and interactions with the PR-pre
state. This preserves the full energy identity
`(MP+CBI)^2 = MP^2+CBI^2+2 MP CBI`. Marginal component and asset-specific
models are robustness checks. Standard errors are clustered by event date and
the selected component terms receive null-imposed wild-cluster bootstrap
p-values.

These regressions are exploratory until the fresh-export certification has
passed on the replication machine and component support, rotation sensitivity
and leave-one-event-out diagnostics have been inspected. The bootstrap is
conditional on the estimated shock decomposition and selected root-day
windows; it does not re-estimate the PCA and sign-restricted rotation.

Outputs are written under `Output/phase_counterfactuals`, with one prefix per
phase: `phase_counterfactual_pr_`, `phase_counterfactual_pc_` and
`phase_counterfactual_me_`.
