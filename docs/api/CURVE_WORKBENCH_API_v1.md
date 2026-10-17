# Curve Workbench API v1

Owner: `viewer.curve_workbench`. Activate through
`modulePublicApiActivate viewer.curve_workbench CURVE_WORKBENCH_API_v1`.

`::GX::CurveWorkbench::datasetIds` lists compatible Session Dataset IDs;
`variables dataset_id` returns stable IDs and display labels.
`loadCurves dataset_id x_id y_id filter_id filter_value family_id order_id`
reads exact canonical rows through Table Stream, preserving source identity.
Optional filter, family and ordering bindings remain explicit.

`open ?context?` opens the Tk Workbench, with optional `dataset_id` preferred
source. The Native2D CORE retains geometry and view authority. GUI controllers
with underscore-prefixed names are host implementation details, not Script
Bridge entry points.

`publish window requested_dataset_id ?curve_ids?` publishes selected workspace
geometry through Dataset Publication v2. The supplied ID is validated and
retained unchanged; collisions reject create-only publication. Point identity,
source row ordinal, source order, segment identity where applicable, source
bindings and workspace provenance are preserved. Payload, schema and structured
metadata commit as one transaction. Publication is explicit and source Dataset
payloads remain immutable.

Point-table events coalesce into one pending request scoped to the active curve
and selection-scene generation. The controller compares requested and actual
selection before mutation, queries the native drag lifecycle, and applies atomic
`selection_replace` only after drag commit/cancel. Matching canvas-to-table
events do not mutate the scene. Failed native operations surface normally;
selection failures are not swallowed. Scene replacement cancels stale requests.
Selection-only table refresh retains row objects, scrolling and range anchors.

Single-point selection populates X/Y fields. Dataset-backed selected points
receive separate red outline row-locator items, retaining exact source-row tags
and native device coordinates across edits and view changes. Pure native curves
have no Dataset-row locator. Saved Interactive Documents retain selected indices;
legacy version-2 documents without them remain readable. Escape cancels a point
drag and restores its original geometry. Plain canvas clicks do not create an
edit/history entry when geometry did not move.

The active curve's direction marker uses Native2D device primitives and hit
testing. Show, Flip, drag and typed settings operate on independent intended
direction. Escape restores a drag's previous marker state. Publication uses
native intended source-index order for every complete output tuple. Direction
presentation does not alter source Dataset coordinates or row identities.

Construction-grid visibility and snapping are separate controls. The shared
Grid / view form validates every typed field before one atomic native
presentation update. Origin, positive spacing, rotation, major/minor/axis
styles, background RGBA and coordinate aspect are retained in the Interactive
Document together with requested view bounds. Point dragging snaps its pivot
once in native grid coordinates and applies a coherent delta to all selected
points. Hiding the grid leaves explicitly enabled snapping active. Grid drawing
uses bounded clipped native primitives; the host does not invent grid geometry.

See the [manual](../../plugins/modules/viewer.curve_workbench/MANUAL.md) and
[Native2D API](../../core/native2d/README.md).

`importFitGeometry name transfer` is the headless provider payload adapter for
`gxtxt.fitter_workbench_transfer.v1`. It validates retained Native2D geometry and
independent axis units, creates a new Workspace and adopts the archived model
resources. Scripts use the end-to-end Fitter `result_workbench` operation; no Tk
window is required. [Transfer contract](FITTER_WORKBENCH_TRANSFER_v1.md).

`openFitTransfer workspace_id` is a host-only GUI adapter: ordinary Session
Workspace opening plus a visible exact/sampled notice. Scripts use the headless
transfer and Workspace API operations.


## Explicit scientific coordinate declarations

Tcl `::GX::CurveWorkbench::createCoordinateCurve window name points units rationale`
creates one exact Native point curve in the live Session Workspace. `points`
contains2–65536 finite XY pairs; `units` contains independent X/Y registered
physical units, including canonical`1` for dimensionless coordinates. It returns
the stable logical curve ID. No example observations are invented.

`::GX::CurveWorkbench::declareCoordinates window ids units rationale` records an
explicit interpretation of original unbound geometry or missing-unit Dataset
columns without changing numeric values. It returns
`gxtxt.coordinate_declaration.v1`, units, rationale, curve_ids,
`numeric_values_changed=0` and `source_dataset_modified=0`. Rationale is a
nonempty single line of at most1024 characters. The current Session is checked.

Known source units and established source assumptions cannot be relabelled to
incompatible meanings. Parent/derived dependencies, constraints, locked unbound
geometry and metric primitives are guarded. Read-only original Dataset bindings
retain their lock: a missing-unit assumption changes only Workspace meaning.
One canonical Variable cannot receive two different axis declarations.

Each record keeps ordered `coordinate_declarations`, previous units and ordinary
operations provenance. Dataset assumptions use stable Variable IDs in existing
`source_assumed_units`; source schema/values remain unchanged. The actual
`coordinate_units` owner feeds CAD validation, comparison, publication and
reconstruction. Undo/Redo and normal Workspace persistence use existing owners.
Native/API publication consumers see physical units and explicit provenance;
Python/Octave read/convert the published data through public Dataset and Unit
Registry APIs. This live-window API does not expose a separate headless fitting
or numerical implementation.


## Coordinate-aware controls and persisted native semantics

Move/Pivot/Physical scale forms reuse `DATASET_METADATA_API_v1` coordinate snapshot
conversion and `UNIT_REGISTRY_API_v1` affine plans. They preserve existing
Native2D operation semantics and canonical constraint values. Translation/scaling
accept independent physical axes in a common working frame; metric rotation and
reflection require equal native axis units. Multiple targets use the first
selected curve's displayed coordinate basis. Captured coordinate keys prevent
stale form application. `parameters.presentation_input` records the entered
values, basis and coordinate context alongside the actual native parameters.
No existing operation ID or saved scientific coordinate is renamed.

Dimension forms show the applicable X/Y unit and convert numeric input before
Native2D evaluation. Existing symbolic parameter bindings stay in native units;
the inline editor states this explicitly. Persisted numeric expressions are
canonical. Coordinate locks include affine offsets; dimension differences and
translations use only the shared plan's scale. Nonlinear constant-displacement
requests are rejected. Physical geometry, source bytes and canonical Variable
metadata remain distinct from display state. Existing Script consumers continue
to use the public Native/Dataset/Unit APIs; no new private unit engine is exposed.
