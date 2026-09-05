# Step 22: MP–CBI shock components

This extension leaves Steps 1–21 and their outputs unchanged. It constructs
the broad monetary-policy (MP) and central-bank-information (CBI) components
from the run-level surprise source using the Jarociński–Karadi sign
restrictions. `EA_EMPD` is the primary default; legacy `EA_MPD` is a
reproducible robustness source.

The primary definitions are separate median rotations in the **Press Release**
and **Press Conference** windows. The Monetary Event Window is retained as an
aggregate benchmark. The poor-man split remains a transparent robustness
check.

The two structural labels are intentionally broad. Per-event standardized
curve PC1--PC4 scores, the raw one-month target proxy and the 1Y-minus-1M path
slope proxy are exported as diagnostics. They are not additional identified
shocks. A target/path refinement is warranted only if the residual curve
dimensions are material, stable under leave-one-event-out estimation and
predict phase outcomes beyond the broad MP/CBI pair.

The code deliberately does not treat the median rotation as point-identified.
It writes rotation-quantile sensitivity at 0.05, 0.16, 0.50, 0.84 and 0.95,
PCA diagnostics for the four OIS maturities, and leave-one-event-out estimates.
These outputs determine whether the broad two-component split is stable enough
for Step 23 or whether target/path or phase-specific refinements are needed.

The phase extension is gated on a certified window-semantics manifest. From
the repository root, run:

```bash
chmod +x Run_shock_components.sh
./Run_shock_components.sh /path/to/Econometrics_data
```

The default run expects `Raw/EA-EMPD/EA-EMPD.xlsx`. The legacy column is
regenerated, rather than preserved as a dated output folder, with:

```bash
SURPRISE_SOURCE=EA_MPD ./Run_pipeline.sh /path/to/Econometrics_data
```

The corresponding workbook is resolved under `Raw/EA_MPD`; supported legacy
spellings are accepted only when exactly one workbook exists. Step 6 writes
`Output/manifests/surprise_source_manifest.csv`, including the source input
hash, the Step-6 output hashes, the code commit/dirty flag and hashes of the
source-routing code. Downstream policy-data steps reject a mixed or modified
source. Outputs are written under `Output/analysis`:

- `shock_components_by_event.csv`
- `shock_components_audit.csv`
- `shock_components_window_comparison.csv`
- `shock_components_leave_one_out.csv`
- `shock_components_rotation_sensitivity.csv`
- `shock_components_manifest.csv`

Shock values are stored in the native Jarociński–Karadi percentage-point scale
and in 10-basis-point units. A positive policy indicator is oriented as a
tightening surprise.

The implementation is pinned to commit
`07a8015a11cd2fce0f425794db210d5f9e2e463f` of the public
`marekjarocinski/jkshocks_update_ecb_202310` repository. The public ME
construction is reproduced exactly; PR and PC repeat that frozen construction
on the harmonised windows exposed by the selected source.
