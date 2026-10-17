# Replicate / Consensus Curves

Open **Viewers → Replicate / Consensus Curves**. Opening performs no analysis and
does not enable the optional legacy Replicate Analysis. The Viewer uses the same
public Numeric replicate/statistical engine as the retained Analysis interface.
The deposited dev101 contained that Numeric engine and legacy Analysis, but no
independently callable Replicate service; dev102 adds its public orchestration.

Declare a study ID, method, design, common physical frame and units. Confirm the
frame only after verifying the physical alignment. Matching unit strings do not
establish a common frame. Add sources using canonical Dataset and Variable IDs,
observation/point-set/calibration/source-group identities and one physical feature.
Different edges require different studies even when stored in one Dataset.

Use **yx** for strictly increasing X traces with a shared X domain. Use **xy_path**
for ordered open/returning or closed paths. Declare the order Variable, topology,
corresponding physical start landmark, traversal direction and closed-path phase
index. Correspondence is explicitly anchored normalized source chord length,
evaluated by CORE's parametric spline. It is suitable only when that physical
correspondence is justified. Crossing, overlapping, degenerate or incompatible
paths fail explicitly. A smooth curve alone does not prove valid correspondence.

Choose **repeatability** only for independent observations and point sets.
**calibration_sensitivity** uses multiple calibrations of one observation/point
set and counts one independent observation. **hierarchical** requires multiple
source groups and repeats within sources. Descriptive sample dispersion, conditional
independent SEM and identifiable Numeric within/between-source components are
separate quantities. Shared calibration covariance, confidence/prediction intervals
and a covariance-aware shared-factor estimator are explicitly unavailable. Exact
zero localization uncertainty stays zero. Do not interpret sensitivity spread as
SEM or a confidence band.

Press **Analyze** to submit a managed Python Job; Cancel uses the existing Jobs
supervisor. Results are adopted only if Session/source/script identities remain
valid. The canvas shows consensus and actual original observations. Wheel zooms,
middle drag pans and Fit restores bounds. Curve checkboxes retain native buffers;
they do not rerun science. Native picks report genuine source identities/rows.
The inspector shows the qualifications alongside the result.

**Publish results** creates three new canonical Datasets under
`module/curve.replicate_analysis/studies/<study-id>`: profile, original/aligned
traces, and feature summary. Publication is atomic and create-only. Choose a new
study ID for a separate study. Original rows keep their canonical ordinals;
aligned derived samples use explicit source-row `-1`. Profile metadata contains
full role/Variable and statistical bindings; linked trace/summary prototypes are
clearly scoped reference interpretation. **Publish Graph** creates an editable
GX-TXT Plot v4 Graph Variant. Existing Analysis Dataset and Graph IDs stay intact.

Save Workspace to retain the recipe, results, visibility, view and Graph reference.
Save before adopting a large result; receipts above 512 KiB use the Workspace's
managed resources. An unsaved large result remains in the completed Job when
adoption refuses; save and explicitly Analyze again. Saved unpublished results
require a fresh Analyze before new canonical publication after reopening; saved
published outputs/Graphs retain their ordinary lifecycle. Scripts/jobs never run
merely because a Workspace opens. F1 opens this guide.

Bounds: 1–64 traces, 65536 canonical points per trace, 3–2048 aligned grid points,
32 MiB encoded control receipt. Native topology validation accepts at most 4096
vertices; denser XY paths fail rather than silently reducing scientific geometry.
These are bounded supported contracts, not unlimited geometry promises.
