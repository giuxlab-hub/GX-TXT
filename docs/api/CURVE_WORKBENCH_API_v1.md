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
