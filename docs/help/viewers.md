# Viewers

The [Curve Viewer manual](../../plugins/modules/viewer.curve_viewer/MANUAL.md) describes family selection and publication. The [Dataset Curve Fit manual](../../plugins/modules/viewer.dataset_curve_fit/MANUAL.md) covers fitting and plot layout; the [Curve Workbench manual](../../plugins/modules/viewer.curve_workbench/MANUAL.md) covers retained geometry and workspace operations.

Viewer Providers present Session Datasets and artifacts without changing scientific source data. A Session can preserve interactive Viewer state, including selections and scene configuration where the provider supports it.

The Spectral Library Viewer can browse managed scientific reference libraries and user-authored references. Install a compatible library package from the Viewer, then choose references for inspection and comparison. The Scientific Library Manager keeps the managed package registry and payloads under the configured Libraries path.

See each Viewer plugin manual for supported formats, interactions and scientific interpretation.

## Dataset Curve Fit models and sources (dev-052)

The existing output-domain/sample-count controls also support circular arc, quadratic/cubic Bézier, PCHIP, smoothing spline and Fourier with user-selected order. Arc/Bézier use parameter-domain sampling. Internal samples stay local. Accept as new CORE curve and Publish as Dataset are distinct actions; fit/sample publication is explicit. CSV export includes reproducible model/provenance metadata. See the Dataset Curve Fit manual.

## Scientific workspaces (dev-052)

Curve Viewer opens additive read-only Dataset curves. Curve Workbench edits local source/native geometry, retained primitives, gaps, constraints, measurements and CAD groups/series. 3D Workbench prepares complete solids/meshes through the existing Native3D engine; the generic3D Viewer remains a distinct consumer. Source Preview uses the real Dataset ID; local samples/accepted curves/bodies do not enter the Registry until explicitly published. Enter your requested public Dataset ID, choose complete Cartesian/polar/both and table/long/wide representation as applicable, then Publish. Collisions are explicit.

Point-table and canvas selection remain synchronized, including Ctrl/Shift and one-point numeric X/Y. Red rings locate real Dataset source rows. The scrollable sidebar and shared forms follow keyboard focus at narrow widths/larger fonts. Exporters, recipes, extension actions, units, recovery and saved views use shared public CORE authorities. See the component manuals for scientific policies, supported workflows and limitations.
