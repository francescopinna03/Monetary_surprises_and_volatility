# Step 22: MP–CBI shock components

This extension leaves Steps 1–21 and their outputs unchanged. It constructs
the broad monetary-policy (MP) and central-bank-information (CBI) components
from EA-MPD using the Jarociński–Karadi sign restrictions.

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

The script expects `Raw/EA_MPD/Dataset_EA-MPD.xlsx` (underscore variants are
also accepted) and the completed `timezone_v1` manifest. Outputs are written
under `Output/analysis`:

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
on their respective EA-MPD sheets.
