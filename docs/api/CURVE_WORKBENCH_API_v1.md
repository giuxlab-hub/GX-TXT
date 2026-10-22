# Curve Workbench API v1

Owner: `viewer.curve_workbench`. Activate through
`modulePublicApiActivate viewer.curve_workbench CURVE_WORKBENCH_API_v1`.

Restoring a saved workspace re-evaluates its existing driving dimensions without
creating a scientific edit when the complete retained geometry, constraints and
parameter definitions are unchanged. Such a no-op preserves the curve's prior
`edited` flag, empty focus, scientific recipe, canonical payload SHA and revision.
Actual geometry changes still mark the curve edited; actual parameter-definition
changes remain History changes even when their evaluated geometry is identical.
The existing parameter transaction and rollback, source-lifetime guards and
recovery journal lifecycle continue to apply. A live recovery journal's `unclean`
status alone does not mean the scientific document was modified.

Undo/Redo restores workspace parameter definitions through their existing
transactional owner together with the retained native geometry and constraints.
A later Undo/Redo failure restores the previous parameter definitions, geometry,
recipe and both command stacks before reporting the original failure.
After a completed Planar intake, subsequent parameter definitions and edits
also enter normal History. Only an actively running import suppresses these
steps; an existing false transaction flag is not an active import. The original
Planar source remains unchanged until the existing explicit Accept operation.

`::GX::CurveWorkbench::datasetIds` lists compatible Session Dataset IDs;
`variables dataset_id` returns stable IDs and display labels.
`loadCurves dataset x y ?filter=""? ?value=""? ?family=""? ?order=""?`
reads exact canonical rows through Table Stream, preserving source identity.
It returns a dictionary mapping each family key to its sample list, with at most
65,536 canonical source rows per curve in this point-list loader. Larger sources
use the existing paged source path. Optional filter, family and ordering
bindings remain explicit.

`open ?context?` opens the Tk Workbench, with optional `dataset_id` preferred
source. The Native2D CORE retains geometry and view authority. GUI controllers
with underscore-prefixed names are host implementation details, not Script
Bridge entry points.

`publish w requested ?ids={}?` publishes selected workspace
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

`importFitGeometry name transfer ?coordinateConfiguration={}?` is the headless provider payload adapter for
`gxtxt.fitter_workbench_transfer.v1`. It validates retained Native2D geometry and
independent axis units, creates a new Workspace and adopts the archived model
resources. It returns a `gxtxt.fit_workbench_receipt.v1` dictionary, including
`workspace_id`, `curve_id`, `representation`, `reason`, `parameter_domain`,
`coordinate_units`, `source_reference`, `independent_resources=1` and
`fit_performed=0`. Explicit coordinate configuration preserves independent X/Y
units. Scripts use the end-to-end Fitter `result_workbench` operation; no Tk
window is required. [Transfer contract](FITTER_WORKBENCH_TRANSFER_v1.md).

`openFitTransfer workspace_id` is a host-only GUI adapter: ordinary Session
Workspace opening plus a visible exact/sampled notice. Scripts use the headless
transfer and Workspace API operations. Its result is the actual Tk window path.


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


## Source-bound numerical comparison presentation

`comparisonDisplaySource w` returns a binding to the live enabled comparison's actual window/incarnation, Session token, Document identity/generation, explicit reference/target/method and unchanged comparison record. Source provenance is sampled at admission; cached editable geometry does not assert that its original canonical Dataset remains current.

`comparisonDisplayValidate binding record` returns `valid=1` only while the same owner, active definition, exact record/receipt, geometry fingerprints, coordinate signature, Document generation and referenced resources remain valid. Otherwise it reports a precise stale/closed/inactive condition. Neither operation evaluates geometry, saves a Workspace or publishes data. Both are trusted host APIs; Script Bridge and C++ SDK grants are unchanged.

The residual display uses public Plot v4 `comparisonModel` and its existing native widget. Numerical/statistical authority remains the original comparison receipt, including evaluation indices, maximum and sampling policy. Display points are derived comparison samples, never canonical Dataset row identities. Editable main geometry remains under Native2D. Closing or invalidating its owner retires the residual controller and child surface. A stale comparison requires the ordinary Compare action to refresh. Saving an authorized Workspace may rebind its presentation; display failure does not undo a committed scientific save.

The dev109 implementation is integrated separately from focused runtime/GUI acceptance; see `docs/development/plot_comparison418/IMPLEMENTATION.md` in the framework.
