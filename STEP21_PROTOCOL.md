# Step 21 protocol: bias-adjusted announcement risk resolution

## Status and scope

This protocol is locked after observing the Step-20 spectrum but before
estimating the Step-21 bias-adjusted results.  Step 20 established a precisely
estimated negative eigenvalue, but the positive eigenvalue was not identified.
Step 21 therefore does not test or search for a positive "risk creation"
component.  Its sole confirmatory object is the negative eigenvalue of the
abnormal second-moment matrix after correcting normal pre/post continuation.

The Step-20 date matrix
`Output/analysis/announcement_rotation_date_matrices.csv` is immutable input.
No intraday window, return scale, contract choice, state transformation or
surprise measure is re-selected in Step 21.

## Estimator

For each paired date, let

```
D = Q_post - Q_pre
```

denote the standardized two-asset second-moment change constructed in Step 20.
The nuisance function `m_0(X) = E[D | X, non-event]` is estimated exclusively
on non-ECB dates.  `X` contains log pre-window equity variance, log pre-window
Bund variance, Fisher-transformed pre-window correlation, the two slow
volatility measures, release-clock regime, weekday and a quadratic calendar
trend.  The five continuous pre-release variables enter additively.  This
parsimonious specification is fixed to avoid high-order extrapolation of a
three-element matrix outcome. Predictions are leave-year-out cross-fitted and
use a numerically negligible, fixed ridge stabilization.

The nuisance correction is subject to a control-only predictive guard. For
each matrix element, the cross-fitted linear prediction is contracted toward
the corresponding leave-year-out training mean. The contraction weight is the
OOS least-squares weight computed exclusively on non-event observations and
clipped to `[0,1]`. Thus a nuisance model that does not improve control-date
prediction receives zero weight and cannot inject extrapolation noise into the
ECB estimand. Both the unguarded and guarded OOS R-squared and the contraction
weight are reported. No event outcome enters this choice.

Events are matched to ten non-event dates with the same release-clock regime
and weekday and within two calendar years.  Matching uses only the five
pre-release continuous variables.  Common support is imposed in two ways:

1. every event covariate must lie between the control 1st and 99th percentiles
   in the same release-clock regime;
2. the event's ten matches must lie below a distance caliper equal to the 95th
   percentile of control-to-control tenth-neighbour distances.

The event-level bias-adjusted matrix is

```
A_d = [D_d - m_0(X_d)]
      - mean_c [D_c - m_0(X_c)].
```

The principal estimate is the mean of `A_d` over retained ECB dates.

## Inference

The bootstrap resamples ECB dates and non-event dates separately.  Every draw
recomputes covariate standardization, common support, the leave-year-out
nuisance regressions, matching and the final spectral decomposition.  The
published run uses 999 draws.  Matched placebos are reported as a diagnostic
and do not replace the event-date percentile interval.

Three samples are fixed in advance:

- `full`;
- `exclude_2020`;
- `exclude_2020_2021` (reported robustness, not an additional binding gate).

## Binding decision rule

The risk-resolution result passes only if all of the following hold:

1. the 97.5th percentile of the full-sample bootstrap distribution of
   `lambda_minus` is below zero;
2. the same upper endpoint is below zero after excluding 2020;
3. at least 80 percent of the input ECB dates are retained in each of those
   two samples;
4. at least 95 percent of requested bootstrap draws are usable in each of
   those two samples.

The positive eigenvalue and the Bund-minus-equity rotation are secondary
descriptive results.  They cannot turn a failed negative-eigenvalue decision
into a pass.  The `exclude_2020_2021` sample, matched placebos and eigenvector
loadings diagnose interpretation and influence but are not alternative routes
to significance.

## Modes and outputs

`smoke` mode accepts at least 19 draws and writes to
`Output/analysis/step21_smoke`.  It never issues a final research decision.
`final` mode refuses fewer than 999 draws and writes to
`Output/analysis/step21_final`.

All output files use the prefix `announcement_resolution_`.  The decision,
configuration, Git commit, MATLAB version and input-file hash are written to
machine-readable CSV files alongside the estimates.
