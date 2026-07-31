# Step 24: paired PR–PC phase and component contrasts

Step 24 tests whether the abnormal-volatility response differs between the
rate-decision press release (`PR`) and the press conference (`PC`). Every test
uses exact event-date-by-asset pairs, and inference is clustered by event date
so the two phases and both assets may be dependent within an ECB event.

The design was fixed after inspecting the separate phase regressions and the
Step-23 sufficiency audit. It is therefore a disciplined post-selection
contrast analysis, not a preregistered test untouched by the data.

## Two layers of inference

The primary test is rotation-invariant. For each phase, the median MP–CBI
quadratic regression spans the same response surface as a quadratic model in
the policy indicator and the contemporaneous equity surprise. Step 24 writes
that common reduced-form basis explicitly:

- policy-indicator energy;
- equity-surprise energy;
- their algebraic cross term;
- all three interactions with the PR-pre state.

A six-restriction Wald test compares the complete PR and PC shock surfaces.
Abnormal log bipower variation is the primary outcome inherited from the
counterfactual design; abnormal log realized variance is a separate robustness
outcome. Both receive clustered and null-imposed wild-cluster p-values, but RV
does not enter the primary BV decision. The result must also survive removal
of the top 1, 3 and 5 events ranked by total PR-plus-PC MP–CBI energy.

The secondary layer attributes phase differences to MP or CBI under the
Step-22 median rotation. It reports:

- PC-minus-PR isolated MP and CBI effects at states -1, 0 and +1;
- PC-minus-PR differences in their state slopes;
- within-phase CBI-minus-MP profiles;
- pooled and asset-specific estimates.

The four mean-state/slope component contrasts across two outcomes form an
eight-test Holm family and receive wild-cluster p-values. A component label is
called robust only when both outcomes pass at the median rotation, every
rotation-grid estimate has the same sign and p <= 0.05, and the same holds
after removing the top 1, 3 and 5 events ranked by that component's energy.
This demanding rule distinguishes evidence that PR and PC response surfaces
differ from the generally weaker claim that the difference is point-identified
as MP or CBI.

ME is descriptive only. Its abnormal outcomes are correlated with PR, PC and
their sum, but it cannot determine any Step-24 decision.

## Execution

Step 24 requires the final 999-draw `step23_v1` manifest and the Step-23
decision retaining MP–CBI as the primary decomposition.

Run a 19-draw smoke test:

```bash
./Run_phase_component_contrasts.sh /path/to/Econometrics_data 19
```

Run the final 999-draw analysis:

```bash
./Run_phase_component_contrasts.sh /path/to/Econometrics_data
```

Outputs under `Output/phase_component_contrasts` are:

- `step24_coefficients.csv`
- `step24_reduced_form_tests.csv`
- `step24_component_contrasts.csv`
- `step24_wild_bootstrap.csv`
- `step24_leave_top_k.csv`
- `step24_rotation_sensitivity.csv`
- `step24_me_benchmark.csv`
- `step24_decision.csv`
- `step24_manifest.csv`
