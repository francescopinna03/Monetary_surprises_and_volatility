# Step 27B: frozen dynamic-jump power frontier

Module B is conditional on the final 999-draw pass of Step 27A. It is a
pre-estimation feasibility calculation, not a test of the observed
conference-time jump. The implementation is structurally unable to report an
observed jump coefficient or p-value. If the frontier is inadequate, the
dynamic operator is not estimated.

## Estimand and primary dynamic outcome

The primary Step-25 result concerns abnormal bipower variation. A dynamic
response based on the instantaneous matrix \(r_{e\tau}r_{e\tau}'\) would
instead be an RV object and would ignore the Step-24 failure of RV to confirm
the primary BV result. Module B therefore constructs a multivariate bipower
matrix.

Let \(r_{1,e\tau}\) and \(r_{2,e\tau}\) be synchronized five-minute Stoxx and
Bund returns, divided by the non-event scales frozen in Step 20. The diagonal
contributions are

\[
B_{ii,e\tau}=\frac{\pi}{2}
 |r_{i,e,\tau-1}|\,|r_{i,e\tau}|.
\]

The off-diagonal is obtained by polarization:

\[
B_{12,e\tau}=
\frac14\{BV_\tau(r_1+r_2)-BV_\tau(r_1-r_2)\}.
\]

The response vector uses Frobenius-preserving coordinates

\[
y_{e\tau}=\bigl(B_{11,e\tau},\sqrt2 B_{12,e\tau},B_{22,e\tau}\bigr)'.
\]

Only within-segment adjacent returns are used. The frozen common grid is
\(-20,-15,-10,-5\) minutes before the PC and
\(+10,+15,\ldots,+45\) minutes after it. Thus no bipower product straddles
conference time.

The phase-counterfactual inputs contain separate PR-pre standardized states
for Stoxx (`fx`) and Bund (`gg`). These are not duplicate estimates of one
number and are not required to coincide. Module B first verifies that each
root-specific state is identical in the PR and PC files, as required by the
phase protocol, and then defines the scalar cross-market state as

\[
s_e=\frac12\left(s_{e,fx}+s_{e,gg}\right).
\]

This equal-weight rule is symmetric across markets, predetermined, and fixed
before any observed conference-jump statistic is estimated.

## Rank-one input and cross-fitted PC innovation

In every bootstrap draw, the Step-27A restricted aggregate model is refitted
after resampling complete meetings and applying a common meeting-level
Rademacher sign. If \(w\) is the refitted direction and \(\Sigma\) is the
refitted shock covariance, PR energy is

\[
z_e^{PR}=\{w'\Sigma^{-1/2}x_e^{PR}\}^2,
\]

standardized within the draw. PC energy is defined analogously. For each
calendar year, the PC energy is projected using all other years on an
intercept, PR energy, pre-state and hiking regime. The held-out residual
\(\nu_e^{PC}\) is standardized and enters the post-PC model with unrestricted
risk coordinates. It is therefore not forced to share the PR risk direction.

## Risk direction and continuous null

The cross-market loading is parameterized by

\[
b(\psi)=(\cos\psi,\sin\psi)',\qquad
u(\psi)=\operatorname{svec}\{b(\psi)b(\psi)'\}.
\]

The risk direction \(\psi\) is estimated using pre-PC contributions only.
Consequently, an injected post-PC jump cannot help estimate its own
direction. The direction is re-estimated in every bootstrap draw.

Conditional on this direction, the PR operator has a short continuous basis

\[
a(\tau,s)=
\sum_{j=1}^{5}\alpha_j B_j(\tau)
+s\sum_{j=1}^{5}\gamma_j B_j(\tau),
\]

where

\[
B(\tau)=(1,t,t^2,t_+,t_+^2),\qquad t=\tau/45.
\]

This permits different slopes and curvatures before and after the PC while
imposing equality of the left and right limits at zero. Time-by-risk fixed
effects, state-by-risk controls, regime-by-risk controls, and two
unrestricted risk profiles for the cross-fitted PC innovation are nuisance
terms.

## Frozen alternatives

All alternatives are one-dimensional additions to the null and are tested
with an empirical, null-imposed critical value.

1. **Intensity:** a permanent post-PC step of the common PR mode.
2. **Reactivation:** a pulse that equals one at the first eligible post-PC
   bipower contribution and decays with a frozen 15-minute time constant.
3. **Risk rotation:** a post-PC movement in the unit tangent direction of
   \(u(\psi)\).

The injected size is

\[
\rho=\frac{\|J\|_F}{\|\mathcal K_{PR}\|_{RMS}},
\]

where the denominator is the RMS norm of the operator fitted only on the four
pre-PC contributions. Both signs are simulated. For an exact rotation of a
rank-one projector,

\[
\rho=\sqrt2|\sin\phi|,
\]

so the reported rotation frontier also has an angular interpretation.

## Bootstrap, grid and decision rule

The frozen grid is

\[
\rho\in\{0.10,0.20,0.30,0.40,0.50,0.75,1.00\}.
\]

Each draw resamples complete meetings and applies the same event-level wild
sign to the aggregate Step-27A residuals and the dynamic residual path. Shock
direction, PC innovation and pre-PC risk direction are all re-estimated.
The test statistic is the normalized residual-sum-of-squares gain from adding
the relevant one-dimensional jump profile. Its 95th percentile under the
null is the finite-sample 5% critical value.

Power is evaluated separately in both directions. The conservative power
curve is their minimum and is made non-decreasing by isotonic regression.
Linear interpolation gives the 80%-power frontier.

The predeclared moderate-jump threshold is \(\rho=0.50\). An alternative is
feasible only when its final 999-draw frontier is at or below this threshold.
Module C may later estimate only alternatives that pass this gate. If none
passes, dynamic operator estimation is blocked. A 19-draw run is only an
execution smoke test and always reports `not_evaluated_smoke_only`.

## Execution

Smoke test:

```bash
./Run_dynamic_jump_frontier.sh /path/to/Econometrics_data 19
```

The smoke test writes to `Output/dynamic_jump_frontier_smoke` and always
reports `not_evaluated_smoke_only`. The final frontier is:

```bash
./Run_dynamic_jump_frontier.sh /path/to/Econometrics_data
```

The complete Step-27 sequence can instead be run with:

```bash
./Run_step27.sh /path/to/Econometrics_data
```

## Certified result

The final run used 999 valid draws, 111 eligible events and 1,332 dynamic
contributions. All three 80%-power frontiers remained above the frozen grid:

| Alternative | Worst-sign power at \(\rho=0.50\) | Worst-sign power at \(\rho=1\) |
| --- | ---: | ---: |
| Intensity | 4.5% | 4.9% |
| Reactivation | 5.3% | 13.5% |
| Risk rotation | 8.8% | 22.4% |

Accordingly, `MODULE_C_OPERATOR_ESTIMATION` is `blocked`. This does not imply
that the observed process has no conference-time jump. It means that, under
the frozen rank-one design, the 111-meeting sample cannot detect jumps of the
considered sizes with adequate power. No observed jump was estimated.
