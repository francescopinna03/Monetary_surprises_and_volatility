# Step 26: official long-horizon factors and phase-gap attribution

Step 25 locates the press-release/press-conference (`PR`/`PC`) volatility gap
in an MP-like sector of the observed short-policy/equity plane. It does not
establish rank one, but it also does not reject rank one in favour of a second
channel; exact median-rotation MP/CBI attribution remains unsupported. Step 25
also shows that the remaining PCs of the 1M--1Y curve do not explain the gap.
Step 26 tests the remaining economically relevant alternative: information in
the yield curve beyond one year.

## Official factor construction

The step reproduces the public Altavilla--Brugnolini--Gürkaynak--Motto--Ragusa
(ABGMR) construction rather than attaching economic names to unconstrained
principal components. For each window, the input matrix contains changes in
the 1M, 3M, 6M, 1Y, 2Y, 5Y and 10Y risk-free rates. OIS is used when present;
German sovereign yields fill unavailable 2Y, 5Y and 10Y observations in the
early sample. Factors are estimated from 2 January 2002 onward after the three
exclusions in the authors' public implementation.

Principal components are computed from centered but otherwise unstandardised
rate changes. In the PR window, the retained factor is the direction in the
three-PC space that loads on the 1M rate and is normalised to have unit impact
on it (`Target`). In the PC window:

- `Timing` is the only direction allowed to load on the 1M rate and is
  normalised on the 6M rate;
- `Forward Guidance` (`FG`) and `QE` have zero 1M loading;
- `QE` is the direction in that orthogonal subspace with the smallest
  pre-crisis second moment, through 7 August 2008;
- `FG` is its orthogonal complement and the two factors are normalised on the
  2Y and 10Y rates respectively.

The constrained rotation has a closed-form eigensolution, so Step 26 does not
require an optimisation toolbox. A leave-one-event-out reconstruction freezes
and reapplies the complete PCA, rotation and normalisation. Named attribution
is disabled if its full/LOO correlation is below 0.90, its median absolute
change exceeds 0.25 full-sample standard deviations, or any loading-vector
cosine falls below 0.90.

## Incremental phase model

The official factors are not substitutes for the Step-25 policy/equity basis.
Each is first residualised on the Step-22 policy indicator within its own
window. This isolates curve information not already spanned by the short-rate
indicator. The paired stacked model then augments the complete quadratic
policy/equity surface with:

- each residual factor's square;
- its cross-products with policy and equity;
- all within-window factor cross-products; and
- the interaction of every new monomial with the pre-announcement state.

PR receives the Target residual block. PC receives the Timing, FG and QE
residual blocks. The primary outcome remains abnormal log bipower variation;
abnormal log realized variance is a robustness outcome.

Step 26 first tests the complete additional block. It then re-tests equality
of the six baseline PR/PC policy-equity coefficients. Calling the phase gap
"accounted for" requires all of the following:

1. the original BV gap remains significant before augmentation;
2. the joint long-curve block passes conventional and null-imposed
   wild-cluster tests;
3. grouped leave-one-event-out loss improves with a positive 95% paired
   bootstrap interval;
4. after augmentation the baseline gap is not detected by either test and
   its covariance-scaled RMS magnitude falls by at least 50%; and
5. the joint-block/gap result survives removal of the 1, 3 and 5 events with
   the largest residual-factor energy.

Target, Timing, FG and QE are tested by dropping every quadratic term that
contains that factor. A named factor must additionally survive Holm correction,
its own grouped-OOS comparison, leave-top-k analysis and generated-factor LOO
stability. Cross-terms necessarily belong to both participating drop-one
blocks; therefore several factors may be jointly necessary, and the procedure
does not force a single-component conclusion.

## Identification boundary

These four objects are policy-curve signals. They do **not** by themselves
separate a structural monetary-policy shock from central-bank information.
Even if one explains the phase gap, the valid conclusion is that a named
curve dimension has incremental content. An exact MP/CBI causal label still
requires an additional equity-sign or external-instrument restriction.

## Execution and outputs

Smoke test:

```bash
./Run_long_horizon_attribution.sh /path/to/Econometrics_data 19
```

Final run:

```bash
./Run_long_horizon_attribution.sh /path/to/Econometrics_data
```

The runner requires the final 999-draw Step-25 manifest. Outputs are written
under `Output/long_horizon_attribution` and include factor series/loadings,
factor-construction and LOO audits, residualisation diagnostics, cluster tests,
grouped-OOS bootstrap draws, leave-top-k results, the Step-26 decision and a
hash manifest.

Method sources: the [ECB working paper](https://www.ecb.europa.eu/pub/pdf/scpwps/ecb.wp2281~3303fd281b.en.pdf), its [formal rotation appendix](https://www.ecb.europa.eu/pub/pdf/annex/Appendix_Measuring_Euro_Area_Monetary_Policy.pdf), and the [authors' replication archive](https://www.bilkent.edu.tr/~refet/ABGMR_replication_files.zip).
