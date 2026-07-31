# Step 27: sequential feasibility protocol

Step 27 is a gate, not yet an estimator of the dynamic transmission operator.
Its two modules are logically sequential:

1. **Module A** asks whether a common-direction rank-one representation is
   admissible for the Step-25 PR-PC quadratic gap.
2. **Module B** measures the power frontier for a conference-time jump only
   if Module A passes. If A fails, B is not run and the rank specification is
   reopened.

Both modules are implemented. `Run_step27.m` and `Run_step27.sh` enforce their
ordering: Module A is always run first, and Module B is launched only after a
final 999-draw pass. A failed or smoke-only Module-A gate cannot authorize
Module B.

## Frozen reference-direction convention

Step 25 does not contain a point vector \(v_{MP}\) fixed by the ABGMR
restrictions, nor does it estimate a separate structural MP vector. Its
`MP_LIKE` label is the sign-restricted sector in which policy and equity have
opposite signs. The reported angle is measured from the policy axis in the
pooled-covariance-standardised policy/equity geometry.

Module A therefore does not test an angle against a fictitious fixed
\(v_{MP}\). Under its null,

\[
\Delta A(s)
=
(a_0+a_1s)\,\Sigma^{-1/2}ww'\Sigma^{-1/2},
\]

where \(w\) is a common direction estimated jointly with \(a_0\) and \(a_1\)
by profiled constrained least squares. In every bootstrap draw Module A
re-estimates the unrestricted surface, the shock covariance \(\Sigma\), the
common null direction, and the unrestricted eigenvectors. This propagates all
directional uncertainty that exists in the actual Step-25 estimand. `MP_LIKE`
remains a sector attribution only.

## Null bootstrap and calibrated triad

The null is imposed on the six PC-minus-PR quadratic coefficients. Entire ECB
meeting clusters are sampled with replacement, carrying their PR and PC shock
vectors and both market outcomes. A Rademacher sign is then applied to the
restricted residual vector of each sampled meeting. Thus within-meeting
PR-PC/cross-market dependence is preserved while the shock covariance is
re-estimated rather than held fixed.

At states \(-1,0,+1\), Module A recomputes the Step-25 generalised spectrum and
uses the following global statistics:

\[
T_1=\max_s |\widehat\lambda_2(s)|,
\qquad
T_2=\max_s
\frac{|\widehat\lambda_2(s)|}
{|\widehat\lambda_1(s)|+|\widehat\lambda_2(s)|},
\]

\[
T_3=\max_s
\angle_{\mathrm{proj}}\!\left(
\widehat v_1(s),\widehat v_{R1}
\right),
\]

where \(\widehat v_{R1}\) is the jointly fitted common rank-one direction in
that same sample. The third statistic therefore tests common-direction
stability, not proximity to a point-identified structural MP shock.

The triad is tested once on the full sample and again after removing the top
1, 3 and 5 meetings by the same total shock-energy ranking as Step 25. Holm
adjustment is applied within the three full-sample tests and, separately,
within the nine leave-top-k tests.

## Gate

Module A passes only when:

- no full-sample statistic rejects the rank-one null at family-wise 5%;
- no leave-top-k statistic rejects after its family-wise correction; and
- the observed leading direction remains negative-eigenvalue and MP-like in
  the full and leave-top-k samples, as required by the inherited Step-25
  interpretation.

A pass means **rank one is admissible, not established**. A failure blocks
Module B; it is not permissible to report a rank-one jump frontier in that
case.

## Module-B boundary

If A passes, Module B calibrates 5%-level, 80%-power frontiers separately for:

- an intensity jump of the common mode;
- delayed decay or reactivation of that mode;
- rotation of the cross-market risk direction.

Every injected-signal draw re-estimates the shock projection and operator
directions. The frontier cannot reuse a direction estimated once from the
observed outcome. Module B is a power calculation and is structurally unable
to estimate the observed conference-time jump. Its complete frozen design is
documented in `STEP27B_DYNAMIC_JUMP_FRONTIER.md`.

## Execution

Module A requires the final 999-draw Step-25 and Step-26 manifests.

Smoke test:

```bash
./Run_rank_one_feasibility.sh /path/to/Econometrics_data 19
```

Final run:

```bash
./Run_rank_one_feasibility.sh /path/to/Econometrics_data
```

The 19-draw smoke test writes under `Output/rank_one_feasibility_smoke`, labels
the inferential rows `not_evaluated_smoke_only`, and cannot be mistaken for or
overwrite the final run. The 999-draw outputs are written under
`Output/rank_one_feasibility`:

- `step27a_rank_calibration.csv`;
- `step27a_observed_geometry.csv`;
- `step27a_null_fits.csv`;
- `step27a_null_bootstrap.csv`;
- `step27a_decision.csv`;
- `step27a_manifest.csv`;
- `step27a_run.log`.

To run the complete sequential step on existing final Step-25 and Step-26
outputs:

```bash
./Run_step27.sh /path/to/Econometrics_data
```

In the certified 999-draw run, the full-sample minimum unadjusted p-value was
0.201 and the minimum Holm-adjusted p-value was 0.603. The rank-one
representation remained admissible after excluding the top 1, 3 and 5 events.
This result authorized Module B; it did not establish that the true response
is rank one.
