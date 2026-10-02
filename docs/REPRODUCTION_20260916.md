# Reproducing the exploratory comparison of 16 September 2026

The latest analysis compares 160 historical Bund press-release meetings
(2000–2012) with 111 recent meetings (2013–2025). Both samples were already
opened. The code keeps this exploratory status, the original directional
historical tests, and the existing pre-freeze protection. It does not make
the comparison a new confirmation or override the dynamic feasibility gates.

## Included code

- `confirmation_analysis/exploratory.py`: corrected post-opening history,
  convexity, PPML, ridge and power diagnostics, including the recorded
  treatment of code drift on an already opened build.
- `confirmation_analysis/functional_form.py`: the two-by-two radial/angular
  comparison, training-fold spline transformations, sector diagnostics and
  tests conditional on the precomputed response.
- `confirmation_analysis/cross_epoch.py`: common metrics, common-support
  targets and the symmetric composition/response decomposition.
- `Prepare_cross_epoch_inputs.py`: reconstructs the comparison from the
  required archived builds and checks their provenance.
- `Run_functional_form_checks.py`: reruns the historical functional-form
  diagnostic from an already opened result bundle.
- `Run_cross_epoch_checks.py`: runs the complete final cross-period diagnostic
  from the prepared input directory.

The scientific code is copied from the tested facility. The eight files
named in the final run's `code_sha256` map retain their exact hashes.
The update contains no manuscript, raw provider prices, Python environment,
or operating-system/test caches.

## Reproduce the final comparison from included derived inputs

The following block uses the existing Desktop facility and its Python
environment. Run it from the updated checkout, or replace `monetary_repo`
with the checkout path printed by the update installer. An output directory
must not already exist. The runner refuses to overwrite one.

```bash
monetary_facility="$HOME/Desktop/Monetary_surprises_testing_facility"
monetary_repo="$monetary_facility/Monetary_surprises_clone"
monetary_python="$monetary_facility/python_env/bin/python"
monetary_output="$monetary_facility/runs/cross_epoch_$(date -u +%Y%m%d_%H%M%S)_$$"
cd "$monetary_repo"
"$monetary_python" -m pip install -r requirements-final-analysis.txt
"$monetary_python" Run_cross_epoch_checks.py \
  --inputs reference_outputs/cross_epoch_20260916/inputs \
  --out "$monetary_output" \
  --draws 19999
```

For a separate clean checkout, create a Python virtual environment and
install `requirements-final-analysis.txt` there. MATLAB is not required
for this derived-input calculation. A smaller `--draws` value is only a
smoke test and cannot reproduce the full reference inference.

The runner writes results and an archive beside the output directory. The
reference manifest records 19,999 wild draws and seed 20260916. It preserves
the original environment, timestamps and source hashes; those fields must
not be rewritten to look as though the archived run was executed by the
new repository commit. Regenerated CSV estimates and p-values can be
compared with the files in `reference_outputs/cross_epoch_20260916`.
Floating-point last digits can depend on the numerical environment.

## Integrity checks on the reference package

From the repository root, this standard-library check verifies the archived
CSV files, protocol, input manifest and the eight analysis-code files:

```bash
python3 - <<'PY'
from pathlib import Path
import hashlib
import json

root = Path('reference_outputs/cross_epoch_20260916')
manifest = json.loads((root / 'run_manifest.json').read_text())
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
for name, expected in manifest['table_sha256'].items():
    if sha(root / name) != expected:
        raise SystemExit('Reference CSV differs: ' + name)
for name, expected in manifest['code_sha256'].items():
    if sha(name) != expected:
        raise SystemExit('Analysis code differs: ' + name)
assert sha(root / 'inputs/input_manifest.json') == manifest['input_manifest_sha256']
assert sha(root / 'inputs/analysis_protocol.json') == manifest['analysis_protocol_sha256']
print('Reference files and executed-code hashes verified.')
PY
```

These checks establish file identity, not the validity of every modeling
assumption. Future scientific edits will correctly cause the old-code hash
check to fail and require a separately documented run.

## Reconstruct inputs from the earlier opened archives

`Prepare_cross_epoch_inputs.py` accepts four explicit directory arguments:

```bash
python Prepare_cross_epoch_inputs.py \
  --generation /path/to/frozen-generation-build \
  --historical /path/to/opened-historical-result-bundle \
  --bridge /path/to/generation-bridge \
  --out /path/to/new-derived-input-directory
```

The generation directory must contain `status.json`, `specification.json`,
`windows.csv` and `ea_source.csv`, with status `frozen`. The historical root
must contain `estimated/` and `frozen_manifest/`, and its estimation status
must be `complete_reestimation_after_opening`. The bridge supplies
`bridge_decision.json` and `bridge_cone_tests.csv`. Provenance and the
archived bridge estimates are checked before writing the new inputs.

The prepared directory contains five CSVs and `input_manifest.json`.
For the specific protocol of 16 September, place an unchanged copy of
`reference_outputs/cross_epoch_20260916/inputs/analysis_protocol.json` in that
directory before invoking `Run_cross_epoch_checks.py`. The protocol records
the exploratory scope and is hashed separately. It is not a permission to
open new data or to claim preregistration after observing outcomes.

The preparation reconstructs normal-continuation responses from archived
tables, not from raw prices. The recent source remains the frozen build of
11 September with the slow-state harmonization. The historical source is
the corrected re-estimation of 15 September.

## Tests

The relevant suites use `unittest`; pytest is not required. With the same
Python environment used for analysis:

```bash
python -m unittest discover -s tests -p 'test_confirmation_v2.py'
python -m unittest discover -s tests -p 'test_functional_form.py'
python -m unittest discover -s tests -p 'test_cross_epoch.py'
```

All 37 tests passed during the integration review on 17 September. The
tests include synthetic data preparation, freeze protection, post-opening
labels, PPML score centering, Frobenius weights, spline fold separation,
scale invariance, common support and decomposition identities. This does
not claim a fresh execution of the MATLAB pipeline on provider prices.

## Interpretation and historical material

Read [Cross_epoch_findings_20260916.md](Cross_epoch_findings_20260916.md) for
the reported effects and inferential families, and
[Functional_form_corrections_20260916.md](Functional_form_corrections_20260916.md)
for the functional-form corrections. Common-metric and common-distribution
contrasts are different estimands. Composition contributes to the fitted
gap change; non-rejection of a response difference is not equivalence.

The inherited US release calendar remains a candidate screen. The external
equity window is not made identical to the Schatz window by scaling.
Inference conditions on the constructed outcomes, coordinates and support.
Five PR return endpoints at +5 through +25 represent support (0,+25], not
(+5,+25]. Bipower is a short-window proxy, not a certified structural
continuous/jump decomposition. Older README sections and numbered-step
results are retained as dated research history.
