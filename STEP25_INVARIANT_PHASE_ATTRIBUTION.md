# Step 25: invariant attribution of the PR–PC phase gap

Step 24 establishes that the complete policy/equity quadratic response surface
differs between the press release (`PR`) and the press conference (`PC`) for
abnormal log bipower variation. It does not point-identify that difference as
the median-rotation MP or CBI component. Step 25 asks the narrower question
that remains identified: **in which sector of observed policy–equity surprise
space is the phase difference concentrated?**

## Primary geometry

For phase \(h\), state \(s\), and observed surprise vector
\(x=(policy,equity)'\), write the shock part of the fitted response as

\[
x' A_h(s) x, \qquad A_h(s)=A_{h,0}+s A_{h,1}.
\]

Step 25 forms \(\Delta A(s)=A_{PC}(s)-A_{PR}(s)\). Directions are evaluated on
the one-standard-deviation ellipsoid of the pooled PR–PC shock covariance
\(\Sigma\). The eigenvalues of
\(\Sigma^{1/2}\Delta A(s)\Sigma^{1/2}\) are invariant to nonsingular changes of
units or basis. Its dominant eigenvector is mapped back into the observed
policy/equity plane and classified as:

- `MP_LIKE` when policy and equity have opposite signs;
- `CBI_LIKE` when policy and equity have the same sign.

This is a sign-restricted sector attribution in the sense of Jarociński and
Karadi. It is not the stronger claim that one particular median rotation has
point-identified the structural MP shock.

Event-cluster bootstrap confidence intervals are reported at states -1, 0 and
+1. An MP-like geometric attribution requires, for all three states in the BV
model, a negative dominant-eigenvalue confidence interval, at least 95 percent
bootstrap probability in the MP sector, and the same sector and eigenvalue sign
after removing the top 1, 3 and 5 events by total PR-plus-PC MP–CBI energy.
Whether one direction alone is sufficient is a separate decision: the dominant
absolute-eigenvalue share must exceed 80 percent in at least 95 percent of
bootstrap draws at every state. Thus an MP-like dominant direction can be
reported without incorrectly declaring the phase gap rank one.

## Falsification layers

Step 25 also reports:

- separate wild-cluster tests of the mean-state and state-slope BV surfaces;
- median-JK MP, CBI and MP-by-CBI blocks;
- the rotation-free but deliberately coarse poor-man sign split;
- a full quadratic PC2 block, including policy-by-PC2 and equity-by-PC2 terms;
- rotation-invariant residual short-curve energy from PC2–PC4.

The last two screens can detect omitted shape information in the OIS maturities
currently used by Step 22 (1M, 3M, 6M and 1Y). Failure to detect them is **not**
evidence against longer-horizon Forward Guidance or QE components: maturities
beyond 1Y and the official Target/Timing/FG/QE factor construction remain
outside the Step-25 information set and require a separate extension.

## Execution

Step 25 requires the final 999-draw `step24_v1` manifest and decision.

Smoke test:

```bash
./Run_invariant_phase_attribution.sh /path/to/Econometrics_data 19
```

Final run:

```bash
./Run_invariant_phase_attribution.sh /path/to/Econometrics_data
```

Outputs under `Output/invariant_phase_attribution` are:

- `step25_phase_blocks.csv`
- `step25_geometry.csv`
- `step25_geometry_bootstrap.csv`
- `step25_geometry_summary.csv`
- `step25_leave_top_k.csv`
- `step25_auxiliary_attribution.csv`
- `step25_decision.csv`
- `step25_manifest.csv`
