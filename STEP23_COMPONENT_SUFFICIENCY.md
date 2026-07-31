# Step 23: sufficiency of the MP–CBI decomposition

Step 23 asks a deliberately narrower question than Step 22: after separating
monetary-policy (`MP`) and central-bank-information (`CBI`) shocks, does the
remaining shape of the OIS curve contain stable information for abnormal
announcement volatility?

The design was frozen after an initial inspection of the Step-22 and
phase-counterfactual outputs. It must therefore be described as a disciplined
specification audit, not as a preregistered test untouched by the data.

## Hierarchy of specifications

The broad MP–CBI pair remains the primary structural decomposition. It enters
each volatility regression through MP energy, CBI energy, their algebraic
cross term, and interactions with the PR-pre state.

The only candidate refinement is squared curve PC2 and its state interaction.
PC2 is allowed to become a **secondary refinement**, never a replacement for
MP–CBI. Two additional models are diagnostic only:

- total residual curve energy, `PC2^2 + PC3^2 + PC4^2`;
- the target/path energy representation and its cross term.

PR and PC are the decision phases. ME is an aggregate descriptive benchmark
and cannot promote a refinement.

## Frozen decision rule

For each of PR and PC, PC2 is promoted only if all four gates pass:

1. The two-term PC2 block is significant at 5 percent for abnormal log BV and
   abnormal log RV after Holm adjustment across the four PR/PC-by-outcome
   block tests.
2. For both outcomes, leave-one-event-out squared-error loss improves and the
   one-sided paired event bootstrap rejects non-improvement at 5 percent.
3. The OOS comparison is numerically invariant, to a tolerance of `1e-8`
   percentage points, over the Step-22 rotation grid. Because the baseline
   includes `MP^2`, `CBI^2` and `2 MP CBI` (and all three state interactions),
   it spans the full quadratic form and rotation invariance is an algebraic
   identity. This gate is an implementation audit, not additional evidence.
4. For both outcomes, the OOS improvement remains positive after removing the
   top 1, 3 and 5 events ranked by PC2 energy.

Failure of any gate retains MP–CBI as the sufficient primary representation
and labels PC2 diagnostic. A passing result promotes PC2 only to secondary
refinement status; it does not identify four target/path-by-information
structural shocks.

## Inference and limitations

The baseline and candidate designs are compared on identical rows. In-sample
covariances are CR1 clustered by event date. OOS predictions leave out the
entire event, including both asset observations. The paired bootstrap
resamples the resulting event-level cross-fitted loss differences.

The bootstrap treats the Step-22 PCA/rotation and phase windows as fixed. The
rotation grid verifies the expected quadratic-basis invariance; leave-top-k
exposes sensitivity to concentrated support. Neither constitutes a full
re-estimation bootstrap of the raw OIS and intraday pipeline.

Run the final 999-draw analysis from the repository root:

```bash
./Run_component_sufficiency.sh /path/to/Econometrics_data
```

For a quick smoke run, supply at least 19 draws:

```bash
./Run_component_sufficiency.sh /path/to/Econometrics_data 19
```

Outputs are written to `Output/component_sufficiency`:

- `step23_model_comparison.csv`
- `step23_oos_comparison.csv`
- `step23_oos_bootstrap.csv`
- `step23_rotation_sensitivity.csv`
- `step23_leave_top_k.csv`
- `step23_component_support.csv`
- `step23_decision.csv`
- `step23_manifest.csv`
