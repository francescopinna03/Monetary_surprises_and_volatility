# Step 28: gated SBB time-series extension

Step 28 is sequential. No downstream module can reopen a failed upstream
gate, and an attractive SBB cost cannot compensate for missing data, an
unstable factor subspace or an underpowered memory test.

## Implemented boundary

`Run_step28.m`, `Run_step28.sh` and `step28_prepare_barchart.py` implement
the first admissible boundary and the analytic kernel:

1. an outcome-free, fail-closed audit and canonicalisation of the complete
   Barchart Schatz--Bobl--Bund history;
2. the exact Dirac--Gaussian Schrödinger--Bass transition cost and its
   near-identity numerical self-test.

The inventory contains 102 event dates, 454 unique controls and 1,020 links,
with ten matched controls per event. These are acquisition counts, not the
usable estimation sample. The latter is the audited three-contract
intersection after missing transitions and frozen historical lags.

The preparation stage maps the frozen logical contracts to Barchart symbols
(`HF`, `HR`, `GG`), ignores raw files outside the 165-contract universe and
selects a contract using only PR-pre coverage, PR-pre volume and nearest
expiry, in that order. Raw Barchart wall clocks are interpreted as
`America/Chicago` interval-start labels and converted to UTC interval ends.
`Latest` becomes canonical `Close`.

The data gate writes under `Output/step28_sbbts`:

- `Output/step28_sbbts/step28_data_gate_audit.csv`;
- `Output/step28_sbbts/step28_data_gate_decision.csv`;
- `Output/step28_sbbts/step28_barchart_data_manifest.csv`;
- `Output/step28_sbbts/step28_barchart_file_audit.csv`;
- `Output/step28_sbbts/step28_barchart_contract_map.csv`;
- `Output/step28_sbbts/step28_barchart_request_windows.csv`;
- `Output/step28_sbbts/step28_candidate_coverage.csv`;
- `Output/step28_sbbts/step28_selected_contracts.csv`;
- `Output/step28_sbbts/step28_canonical_bars.csv`;
- `Output/step28_sbbts/step28_phase_coverage.csv`;
- `Output/step28_sbbts/step28_date_phase_intersection.csv`;
- `Output/step28_sbbts/step28_event_control_support.csv`;
- `Output/step28_sbbts/step28_stage_gate_decision.csv`.

Run it with:

```bash
./Run_step28.sh /path/to/Econometrics_data
```

A missing, duplicate or malformed required contract produces
`blocked_data_gate` and stops before sample-size calibration. Extra raw files
are recorded and ignored. Missing five-minute trades are never interpolated:
only exact adjacent endpoints form transitions. Incomplete controls are
excluded without replacement and the surviving controls are equally
reweighted within event.

## Full-history identity contract

The preparation stage creates
`Output/step28_sbbts/step28_barchart_data_manifest.csv`. It contains hashes of
all frozen acquisition inputs, the per-contract identity audit, the canonical
panel and the code that created them. Its binding fields include:

| Field | Binding value or meaning |
|---|---|
| `schema_version` | `step28_barchart_data_v1` |
| `status` | `certified` |
| `data_provider` | `Barchart` |
| `n_required_contracts` | `165` |
| `n_present_contracts` | `165` |
| `n_valid_contracts` | `165` |
| `frequency_minutes` | `5` |
| `raw_time_zone` | `America/Chicago` |
| `raw_bar_label_semantics` | `interval_start` |
| `canonical_time_zone` | `UTC` |
| `canonical_bar_label_semantics` | `interval_end` |
| `raw_price_field` | `Latest` |
| `canonical_price_field` | `Close` |
| `primary_panel_ready` | `1` |
| `control_rule` | `exclude_incomplete_without_replacement_equal_reweight` |
| `contract_selection_rule` | `pre_pr_coverage_then_volume_then_nearest_expiry` |

The MATLAB boundary recomputes the manifest, output and preparation-code
hashes. The historical acquisition files retain their old `lseg` names only
as frozen design provenance; their empty RIC field is not used by Barchart.
The generated provider map contains the verified Barchart symbol instead.

## Exact SBB kernel

For a normalised transition (X_0=z),
(X_1\sim\mathcal N(m,\Sigma)) and \(\kappa>1\),
`SBB_dirac_gaussian_cost.m` evaluates the analytic drift and volatility costs
mode by mode. `SBB_cost_profile.m` accepts a strictly increasing grid and
returns every value without aggregating along \(\kappa\). This preserves the
complete profile as the primary object; a single \(\kappa\) remains
illustrative only.

When \(|1-P|\le 10^{-4}\), the solver uses the degree-six Horner expansion of
the removable ratio and the second-order expansion of \(\Delta c=c-1\). It
does not form `c - 1` by subtraction in that branch. The deterministic
self-test checks:

- zero cost at \(m=z,\Sigma=I\);
- the covariance-cost coefficient
  \(\kappa/[4(\kappa+2)]\) at \(\lambda=1\pm10^{-8}\);
- orthogonal invariance;
- the strict domain \(\kappa>1\);
- preservation of the complete \(\kappa\) grid.

## Deliberate stopping point after Step 28A

The first successful run stops at
`ready_for_outcome_free_sample_size_calibration`. The coverage output is then
used to freeze the synthetic spectral sample-size calibration, eigengap
frontier, reconstruction and projector thresholds before event returns are
inspected. The final history dictionary, Gaussian coverage diagnostics,
\(\kappa\) grid, contiguous robustness interval and boundary-bar perturbation
family remain downstream binding choices. Empirical SBB profiles remain
forbidden until the spectral gate, the separate mean and covariance
Markov-power gates, and the Gaussian calibration gate have all passed.

## SBB estimation layer

The layer that turns the exact kernel into an estimand is implemented and
tested, and it is closed behind every upstream gate.

| File | Note reference | Role |
|---|---|---|
| `Step28_sbb_authorisation.m` | Section 11.1 | Fail-closed reader of the six gate decisions. A missing decision file is a failure, never an absence. |
| `Step28_expanded_levels.m` | Sections 6--7 | Shared event/control expansion, leave-year-out whitening and phase-specific matching boundary used by gates and estimator. |
| `Step28_whiten_increments.m` | equation (29) | Leave-year-out normal moments on control dates; increments whitened before cumulation. |
| `Step28_factor_subspace.m` | equation (30) | Whitened second moment, eigendecomposition and rank-`r` projector. Rank selection stays with the spectral gate. |
| `Step28_projector_distance.m` | equation (31) | `d_P(P,P*)`. |
| `Step28_principal_angles.m` | equation (32) | PR--PC principal angles. |
| `Step28_conditional_gaussian_fit.m` | equations (34)--(35) | Affine mean, log-scale diagonal, shrunk correlation with the penalty selected by fully nested control-only cross-validation and then frozen. |
| `Step28_conditional_gaussian_predict.m` | equations (34)--(35) | Per-transition mean and covariance. |
| `SBB_multistep_cost.m` | equations (48)--(49), (63) | Multi-step decomposition; phase sum and per-transition mean. |
| `SBB_abnormal_cost.m` | equations (27)--(28) | Matched abnormal cost and paired PR--PC contrast. |
| `SBB_profile_inference.m` | Section 10.1 | Simultaneous sup-t bands over `K`, uniform verdict on `K_rob`, leave-year-out, leave-top-K and boundary-bar stability. |
| `Step28_sbb_panel.m` | Sections 5--6 | Synchronised three-asset transition panel from certified Step-28A outputs. |
| `Step28_sbb_estimate.m` | Section 10.1 | One complete re-estimation: moments, whitening, subspace, law, endpoints, costs, contrast. |
| `Step28_sbb_specification.m` | Table 4 | Reader of the frozen choices; supplies no defaults for anything Table 4 leaves to be frozen. |
| `Run_step28_sbb.m` / `.sh` | Section 11.1 | Runner. Records a blocked gate; never produces a profile before the gates. |
| `Step28_sbb_self_test.m` | — | Deterministic tests of every component and of the whole chain. |

Nothing is cached between bootstrap draws. `Step28_sbb_estimate` recomputes
the normal moments, the whitening and the factor subspace on the meetings it
is given, because freezing them across draws would understate upstream
uncertainty.

A control date matched to several drawn meetings is replicated so that each
event keeps its own control leg, but only one replica of each distinct
control date estimates the normal moments. Weighting the normal law by match
multiplicity would let the matching design, not the normal continuation,
determine the reference.

### Two choices the note leaves open

The note fixes the conditioning set `(Z_k, S_e, xi_e, p, k)` for events and
is silent about controls, which carry no announcement. It also fixes that
the penalty is tuned on controls without fixing which dates estimate the law
itself. Both are therefore required entries of the frozen specification
rather than defaults:

- `control_conditioning_rule` in `state_and_surprise_zeroed`,
  `inherit_matched_event`, `state_only`;
- `law_fit_sample` in `controls_only`, `pooled`.

Under `state_only`, a control inherits the state of its phase-specific
matched event while its surprise block is set to zero. Under
`inherit_matched_event`, it inherits both blocks. There is no fallback to an
arbitrary event on the same date.

These interact. Fitting on controls only while the control rule zeroes the
state and surprise blocks leaves those columns constant in the fit sample,
so their coefficients are not identified. MATLAB would return a
minimum-norm solution and warn; `Step28_conditional_gaussian_fit` refuses
the combination with `STEP28_LAW_RANK_DEFICIENT` instead, because the
alternative is an arbitrary law extrapolated to events that do vary in those
coordinates.

The shrinkage penalty is selected by fully nested cross-validation: in every
held-out control fold, both the affine mean and Harvey log-scale nuisance
fits are re-estimated using the remaining controls. Reusing full-sample
nuisance residuals during penalty selection would leak the held-out fold.

### Frozen specification

Copy `config/step28_sbb_specification_template.csv`, freeze every empty
value, and pass it to the runner:

```bash
./Run_step28_sbb.sh /path/to/Econometrics_data /path/to/step28_sbb_specification.csv
```

Without the second argument the runner looks for
`Raw/Certification/step28_sbb_specification.csv`. An empty required value
stops the run with `STEP28_SBB_SPEC_UNFROZEN`.

Schema `step28_sbb_specification_v3` also freezes the minimum group support
and residual floor of the Gaussian law, requires the full admissible
calibration-rank set `1|2`, fixes five PR level positions (four transitions),
and requires a non-empty, duplicate-free subset of the four supported
boundary perturbations.  It does not freeze a numerical factor rank: the
binding rule is `factor_rank_rule=selected_by_spectral_gate`, because the
note requires the empirical gate to select in `{1,2,3}` and makes `r=3`
terminal.

## Gate modules

Gates two to five of Section 11.1 are implemented and tested. `Run_step28_gates.sh`
runs them in the binding order and stops at the first failure; each writes the
decision that `Step28_sbb_authorisation` reads.

| File | Note reference | Role |
|---|---|---|
| `Step28_spectral_rank.m` | Section 7 | Procedures one and two of the rank rule and their agreement. Keeps `low_rank_accepted`, `full_rank_terminal`, `no_signal_terminal` and `unstable_subspace` apart. |
| `Step28_sample_size_calibration.m` | equation (33) | Outcome-free synthetic calibration of `G_min^spec`. |
| `Step28_sample_size_gate.m` | equations (26), (33) | `N_use`, `G_use` after the frozen lag, against `G_min^spec`. |
| `Step28_spectral_gate.m` | equations (30)--(32) | Rank, projector stability, PR--PC angles against a length-aware null and a length-matched PC subsample. |
| `Step28_markov_design.m` | Section 8.2 | Conditioning set and history block; its rows are exactly `N_use`. |
| `Step28_conditional_residuals.m` | Section 8.2 | Out-of-fold standardised residuals of the law. |
| `Step28_markov_score_test.m` | equations (37)--(39) | Score statistic with one wild sign per meeting. |
| `Step28_markov_power.m` | equations (40)--(41) | Worst-direction power curve and `R2_80`. |
| `Step28_state_partial_r2.m` | equations (42)--(43) | Out-of-fold partial `R2` of the state block and its meeting-bootstrap lower bound. |
| `Step28_markov_power_gate.m` | equation (44), Section 8.3 | Conjunctive verdict on the mean and covariance branches; PR binding. |
| `Step28_gaussian_calibration_gate.m` | Section 11.1, gate five | Out-of-fold mean, covariance and coverage diagnostics. |
| `Run_step28_gates.m` / `.sh` | Section 11.1 | The binding order, stopping at the first failure. |
| `Step28_gates_self_test.m` | --- | Deterministic tests of all four modules. |

### The null the rank rule is measured against

Equation (29) whitens the increments to the identity, which fixes what a
low-rank structure in the levels can and cannot be. It cannot come from the
increment covariance, which is the identity by construction; it comes from
serial correlation concentrated in a few directions. Two consequences are
built into the code.

For the empirical gate, the parallel-analysis null is calibrated from the
distinct exact-clock control paths. Each draw samples whole control
sequences to the event meeting count, permutes whole increment vectors
across dates within each intraday position and re-cumulates. Event paths,
not controls, identify the observed spectrum and common PR--PC subspace.
Permuting coordinates separately would preserve each coordinate's marginal
variance, which is exactly where an axis-aligned factor lives, and the
procedure would then depend on the basis the panel happens to be written in.
The synthetic sample-size calibration uses the corresponding self-null
because it is deliberately outcome-free.

Held-out low-rank reconstruction is judged against the same null rather than
against an absolute floor. In whitened coordinates the complement always
carries energy, so a genuine rank one can never capture most of the held-out
energy; what identifies structure is the excess over a panel with no serial
persistence. This removes a threshold that would otherwise have had to be
frozen arbitrarily.

The synthetic generator of the calibration follows the same logic: the `r_0`
factor directions get an AR(1) increment and the complement stays serially
independent, both with unit marginal variance, and `rho` is solved so that
the induced eigengap equals the frozen frontier value.

Finite Monte Carlo estimates at adjacent values of `G` can fluctuate. The
calibration therefore uses a conservative right-tail monotone envelope:
`G` is admissible only when it and every larger value on the frozen grid
meet both the rank-recovery and projector-distance criteria. An isolated
lucky simulation point cannot define `G_min^spec`.

### Corrections after review

The review corrections that changed the estimand or the fail-closed contract
are recorded here because the code alone does not explain why it looks the
way it does.

**The common PR--PC space is now built, not only tested.** Section 7 asks
for enough transferability to define a space in which the costs can be
compared. Testing the angles and then projecting each phase on its own basis
would leave equation (28) as a difference between two coordinate systems.
`Step28_common_basis.m` returns the dominant invariant subspace of the
average projector, and the estimator, the Markov design and the spectral
gate all use it. It is rebuilt inside every bootstrap draw.

**The authorised rank and the used rank are now tied together without
preselecting the answer.** The calibration runs for every `r_0` in the
frozen set `{1,2}`, taking `G_min^spec` as the largest of the per-rank
minima.  The authorisation then returns the current spectral gate's
`accepted_rank` only if it is 1 or 2, and the SBB runner injects that value
into the runtime specification.  A CSV cannot preselect rank 1 or rank 2,
and rank 3 remains terminal as required by the note.

**The panel applies the certified intersection and respects the matching.**
`three_asset_eligible` is read from `step28_date_phase_intersection.csv`
rather than rediscovered from bar availability; the matched set is expanded
per phase, because an event whose PR control survives and whose PC control
does not has different control legs, and taking the union added thirty
control-phase sequences on the certified panel; and a transition is formed
only between adjacent five-minute endpoints, so a missing interval is never
bridged.

**The spectral bootstrap resamples what it says it resamples.** Meetings
travel with their matched control block, the normal moments and the
whitening are re-estimated inside every draw, leave-top-K is ordered by
shock energy as everywhere else in the project, and the frozen boundary-bar
perturbations are executed.

**The two Markov branches have different history dictionaries.** Lagged
factor increments for the mean, lagged quadratic and cross products for the
covariance, as Section 8.2 requires. Passing the linear block to both would
have tested the covariance branch against the wrong alternative.

**The state benchmark is measured before the state is removed.** Equations
(42)--(43) need two out-of-fold predictions of the original outcome, one
without and one with the state block. Measuring it on residuals that already
condition on the state erases the quantity it benchmarks.

**The law is tuned on controls.** The Markov design now carries control
transitions alongside the event ones and flags them; the sufficiency test
runs on events, `n_use` and `g_use` count events, and `law_fit_sample` and
the shrinkage tuning use the control rows. Penalty selection is fully nested,
so the held-out fold is absent from the nuisance mean and scale fits too.

**Decisions are bound to their inputs.** `Step28_provenance.m` stamps each
decision with the hashes of the data manifest, frozen specification, state
panel, surprise workbook, surprise manifest and Step-28 code; the
authorisation requires the complete current stamp. `Run_step28_gates.sh`
and `Run_step28_sbb.sh` revalidate the selected surprise source and time
alignment, and supersede downstream decisions and SBB outputs before doing
fallible work, so a stopped rerun cannot leave an earlier positive readable.
The Step-28 data manifest hashes all six CSV outputs consumed downstream,
including the selected-contract, phase-intersection and event-control-support
tables.

**The Markov gate is executable as a unit.** Its public wrapper now always
returns the branch-detail and overall decision tables, and the gate self-test
invokes that wrapper directly rather than only testing lower-level helpers.

**Zero signal is not full rank.** If parallel analysis selects rank zero, the
spectral decision is `no_signal_terminal`; it is not mislabeled as the
full-rank terminal case. Sample-size calibration records that outcome
separately.

**The boundary-bar perturbations exist.** The frozen family is
`drop_first_post`, `drop_last_post`, `shift_forward_one_bar` and
`shift_backward_one_bar`, each a real alternative window built by the panel.

### What still blocks the empirical profile

All five gate decisions have a producer, but the empirical profile remains
fail-closed until a real MATLAB run on the certified inputs writes current,
passing decisions:

| Decision | Produced by |
|---|---|
| `step28_data_gate_decision.csv` | `Run_step28.sh` |
| `step28_sample_size_gate_decision.csv` | `Run_step28_gates.sh` |
| `step28_spectral_gate_decision.csv` | `Run_step28_gates.sh` |
| `step28_markov_power_gate_decision.csv` | `Run_step28_gates.sh` |
| `step28_gaussian_calibration_gate_decision.csv` | `Run_step28_gates.sh` |

For a new design, copy `config/step28_sbb_specification_template.csv` and
freeze every empty value under schema v3.  The current empirical design has
a versioned, fully frozen contract in
`config/step28_sbb_specification_frozen.csv`; it was fixed after acquisition
and the data audit, but before inspecting the spectral, Markov, Gaussian or
SBB outcomes.  Copy that file without editing it to
`Raw/Certification/step28_sbb_specification.csv` and run

```bash
./Run_step28.sh       /path/to/Econometrics_data
./Run_step28_gates.sh /path/to/Econometrics_data /path/to/step28_sbb_specification.csv
./Run_step28_sbb.sh   /path/to/Econometrics_data /path/to/step28_sbb_specification.csv
```

The grid of `G`, the frontier eigengap, `tau_P`, the `R2` grid, the coverage
diagnostics, the history dictionary, law regularisation constants and the
seed must be fixed before the certified intersection is inspected. The
sample-size and spectral outcomes may legitimately block estimation; a code
path existing is not itself evidence that the empirical gate passes.
