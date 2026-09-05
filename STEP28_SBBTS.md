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
