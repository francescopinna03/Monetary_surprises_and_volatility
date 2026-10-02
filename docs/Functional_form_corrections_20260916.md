# Functional-form diagnostics after opening: correction protocol

This module is exploratory. The 14 September confirmation verdict and the
existing level-1, history, PPML, convexity and calibration outputs are not changed.
Source reviewed: the code and outputs in
`Monetary_surprises_testing_facility_confirmation_exploratory_20260916_123011_1780.zip`.

## Changes fixed before evaluating the corrected spline

* Keep all six columns of the original scalar mean branch and add the equity
  signed/absolute terms and both equity state interactions. Nine exploratory
  coefficient tests receive a separate Holm adjustment; this is not a claim
  of preregistration or an adjustment for the complete history of analyses.
* Classify MP by strictly opposite signs and CBI by strictly equal nonzero
  signs. Exact zero in either coordinate is a boundary observation. Retain
  these observations in regression surfaces, exclude them from binary sector
  comparisons and report their counts explicitly. No estimated zero tolerance.
* Retain the old two model families and add the other two cells of a 2x2
  comparison: quadratic/absolute angular profiles, radial degree one/two.
  Compare equal-weighted paired annual MSE. No independent-fold significance
  test is asserted. Cone integrals are at state zero in the existing metric.
* Radius-bin edges remain full-sample descriptive tertiles. A within-bin
  association adjusted for state is NOT a fixed-radius uniformly weighted
  angular functional. Report sector-specific radius ranges and medians.
  Cell counts are only a count gate. The three bin tests use a fixed
  exploratory Holm family, with unestimable tests treated as p=1.
* Replace the unstable reference with natural cubic marginal bases (two
  internal quantile knots per coordinate) and their full tensor product,
  including state interactions for every basis feature. Natural marginals
  have linear tails. Each inner and outer training fold learns knots,
  centring and scales separately. Maximum feature count is 32.
* The spline uses coefficient ridge on standardized nonlinear features and
  their state interactions, not a curvature-integral smoothing penalty.
  Intercept, state, linear coordinate terms and their state interactions
  remain unpenalized. The fixed penalty grid is 0.001, 0.01, 0.1, 1, 10, 100.
  Select minimum inner mean annual MSE; exact ties choose the larger penalty.
  Do not extend the grid based on the new outcome. Report all outer fold
  penalties, inner losses and extrapolation counts.

## Scope and limitations

All comparisons condition on the same previously computed coordinates,
cross-fitted state and abnormal log-BV. Nested preprocessing here is that of
the event-regression spline, not a nested re-estimation of the full normal
continuation model. Leave-year-out fits use both earlier and later years;
they are not real-time forecasts. Selected coefficients and model comparisons
are exploratory. A more flexible model is not assumed to be better.

## Standalone rerun

`Run_functional_form_checks.py --facility <testing-facility> --source-results <zip-or-folder>`
reads only an already completed `complete_reestimation_after_opening` bundle,
its primary sample registry and its archived frozen specification. It verifies
manifest/specification integrity and creates a fresh directory and ZIP under
the facility's `runs`. Raw files and MATLAB are not required. Without an
explicit source it searches for the reviewed final bundle in Downloads and
the facility, matching the reviewed frozen-build hash rather than recency.

Outputs record the input hashes, executed source code and diagnostic version.
No commit or push is performed. The ordinary exploratory driver also picks
up the corrected module in its next separately named output run.

## Validation on the supplied 160-event registry

Tests cover boundary classification, restoration of the scalar design,
radial homogeneity and the origin, nested fold isolation, invariance to
positive changes of coordinate units, natural linear tails, multiplicity
with unavailable tests, and reproduction of the original paired losses.
The three existing functional-form tests also pass.

| Quantity | Corrected result |
|---|---:|
| Original quadratic annual mean MSE | 1.645116 |
| Original absolute-basis annual mean MSE | 1.133168 |
| Quadratic angular profile, radial degree one | 1.132969 |
| Absolute angular profile, radial degree two | 1.664071 |
| Corrected spline annual mean MSE | 1.694928 |
| Conditional absolute Schatz coefficient / wild p | 0.372748 / 0.00120 |
| Conditional absolute equity coefficient / wild p | 0.691204 / 0.00435 |
| Boundary observations, retained in surfaces | 22 |
| First radius-bin MP-CBI / p / Holm p | 0.571538 / 0.03075 / 0.09225 |

Monte Carlo p-values above use 19,999 draws and the recorded seed. Do not
interpret the comparison as a new confirmatory validation or choose another
specification in order to preserve these numbers.
