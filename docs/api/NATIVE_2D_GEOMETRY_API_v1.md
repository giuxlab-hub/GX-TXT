# NATIVE_2D_GEOMETRY_API_v1

Cartesian `render_grid` presentation selects a subset of the configured major
lattice when necessary to retain at least eight pixels between parallel lines.
The distance is perpendicular in the actual viewport, including rotated grids
with unequal X/Y scales. Output remains bounded by 2048 primitives. Zooming in
reveals the original minor lattice. `grid`, `grid_snap`, `grid_snap_delta`,
geometry, source values and serialized presentation keep their original spacing
and identities. CORE canvas, Preview and presentation exporters consume the
same primitive provider; this display thinning does not materialize scientific
coordinates or change a Session's working grid.

The host helper `native2DSourceCoordinateRelations descriptor xVariable yVariable`
returns nondefault unit-relation fields by axis from a frozen Curve Source
descriptor. It performs no numerical conversion. Opaque-scene `metrics`,
`compare` and `compare_geometry` reject unnormalized Variable-specific relations
with Dataset Transform guidance; resource export/restore preserves this guard.
Workbench uses the same inspection before automatic alignment and physical
metrics/comparison. Nominal unit symbols alone cannot override source formulas.

## Shared host grid and export presentation

See the complete [presentation snapshot reference](NATIVE2D_PRESENTATION_SNAPSHOT_v1.md)
and [installed PNG/SVG adapter](NATIVE2D_EXPORT_API_v1.md) for their actual host
signatures, display schema, resource bounds and language exposure. Those owners
do not materialize canonical scientific data.

The Tcl host helper `native2DGridForm window scene changed ?parent? ?presentation?`
accepts an optional captured axis presentation. Existing callers retain Native
coordinates. Each `x`/`y` entry supplies finite nonzero `scale`, `inverse_scale`,
finite `offset`, `inverse_offset`, and a `unit` label. Callers obtain these plans
from CORE Unit Registry or Dataset Metadata; the grid does not infer a physical
conversion. Origins use the affine relation, whereas spacings and compatible
polar radii use its absolute scale. `polar_compatible` enables a common physical
axis frame; otherwise the polar tab is disabled and Apply permits Cartesian only.
`note` explains the frame; optional `guard` is a host callback checked before
opening, applying or resetting. A changed source, unit context or Session must
reject the captured form before any Native mutation.

`native2DGridPresentationApply scene changed presentation values` validates the
presentation and guard, maps fields through their declared inverse plans, then
uses the existing atomic `native2DGridApply`. Rotation remains explicitly in
geometry coordinates. Nonlinear display relations cannot define uniform grid
spacing: Workbench retains and labels the Native grid unit for that axis.

`native2DPresentationSnapshot scene options` accepts optional `x_tick_labels`
and `y_tick_labels`, exactly six strings per supplied axis (at most 256 characters
each), corresponding to the existing six equally spaced Native viewport ticks.
These legacy labels retain their historical six-fraction positions and override
normal axis tick planning for that supplied axis. Otherwise the shared planner
chooses readable numerical positions and uses the same positions for scientific
grid lines and labels. Geometry, clipping and sampling remain Native-owned. Workbench
uses bounded public coordinate conversion for tick text and axis labels before
passing the same snapshot to the SVG/PNG exporters. No Dataset materialization
or scientific unit relabelling occurs.
Snapshot objects may carry an explicit bounded `point_markers` list of device XY
coordinates supplied by the host from Native `render_lod` source/control points.
The exporter draws these separately from curve paths and supports the existing
`part_markers` descriptors. Workbench uses one palette resolver for Canvas and
export, filters invisible objects, and preserves its points-only display mode.

CORE provider `native2d_geometry`, API version 1. This authority
provides retained Native2D geometry to Python and Octave Script Workspace through
the common Script Bridge. It delegates geometry to `NATIVE2D_API_v1`; it does not
implement a second geometry engine or publish Datasets implicitly.

`gxtxt_api_require(['NATIVE_2D_GEOMETRY_API_v1@1:native2d_geometry'])` checks the
provider before execution. Octave uses a cell array of requirement strings.
Call `gxtxt_api_call(api_id, operation, arguments)` with the contracts below.

## Lifetime and ownership

`open(document_id)` returns an opaque scene token owned by this script execution
and the specified Interactive Document's generation/revision and Session lifetime.
Object tokens belong to that scene. Tokens are neither native pointers nor native
object numbers. Cross-scene object use, closed tokens, owner replacement, external
document edits and Session lifetime changes fail explicitly. Reopen/restore after
an external edit. `checkpoint(scene, payload)` updates the document through its
normal API and advances only that scene's captured revision.

`close(scene)` releases all retained native geometry and remains legal after owner
expiry. Script execution cleanup closes remaining scenes. Exported resources are
ordinary content-addressed Interactive Document resources; retain references in
the document payload when saving, and use the common resource collector for
unreferenced temporary resources. No API returns a provider's Dataset file path.

## Operations

Except `api_info()`, `open(document_id)`, and `close(scene)`, operations receive
`[scene, request_struct]`. Required request fields follow. Arrays are numeric
arrays; object collections are lists/cells of opaque tokens. Matrices use the
Native2D affine convention `{a,b,c,d,tx,ty}`:
`x'=a*x+b*y+tx`, `y'=c*x+d*y+ty`.

| Operation | Request fields | Result |
| --- | --- | --- |
| `api_info` | No arguments | Public operation inventory, page limit and ownership/publication policy |
| `sketch` | `definition`; optional `display_samples=257,working_unit,coordinate_units,coordinate_relations` | Retained primitive descriptor and exact definition; pair-aware metadata preserves the coordinate frame, without granting physical metrics for an incompatible frame |
| `sketch_update` | `object_token,definition`; optional `display_samples=257` | Same object identity; invalid/locked/constraint-failing changes roll back |
| `sketch_evaluate` | `object_token,parameter` | Exact world point and derivative with respect to normalized parameter |
| `sketch_sample` | `object_token,total,start,count`; optional `first=0,last=1` | Complete chosen parameter grid, bounded Nx2 page; total ≤1,000,000, page ≤65,536 |
| `sketch_materialize` | `object_token,first,last,total` | Independent Native geometry from the complete chosen finite parameter grid, total ≤1,000,000 |
| `sketch_explode` | `object_token,samples` | New independent generic point curve; retained original stays unchanged |
| `curve` | `points` N×2; optional `kind=curve` (`pointset` or `point`), `working_unit`, `coordinate_units`, `coordinate_relations` | Object descriptor with captured frame metadata; direct input limited to65536 points |
| `from_source` | Execution-owned `source_token` from `CURVE_SOURCE_API_v1` | Complete finite Native geometry, frozen Source descriptor, exact original uint64 row-map resource and gap resource |
| `describe` | `object_token` | Kind, complete bounds, Native style, metadata, point count; curves also have full length/span/signed-area metrics |
| `metrics` | `object_token`; optional `output_units` pair | Native geometric metrics after compatible X/Y normalization; explicit unit and recorded coordinate frame |
| `path_point` | `object_token,distance` | Exact point at nonnegative world arc length; over-end distances clamp to endpoint; infinite construction length is undefined |
| `replace_points` | `object_token,points` Nx2 ≤65536 | Atomic full candidate; native constraints validate once; source-backed point counts must preserve exact row identity |
| `points_page` | `object_token,start,count` | Zero-based start and N×2 points; count ≤65536 |
| `series` | `object_tokens,parameters` | Atomic independent copy descriptors; stable source association; rectangular/circular Native geometry |
| `affine` | `object_tokens,matrix`; optional `copy=false` | In-place target tokens, or new object tokens/descriptors when copying; groups expand once, stable order; original geometry preserved by copy |
| `group` | `object_tokens` | Flat editing container descriptor |
| `group_members` | `object_token` | Stable member-token list |
| `group_add`, `group_remove` | Group `object_token`, geometry `member` | Boolean success; removing the last member deletes only the empty container |
| `ungroup` | Group `object_token` | Removes the container and preserves geometry |
| `delete` | `object_token` | Removes the specified object; references become stale |
| `endpoint_frame` | `object_token,end,reverse,interpolation` (three booleans) | Point, derivative and exact original point index |
| `bridge` | `start,end` object tokens; `kind=straight/quadratic/cubic/smooth`, `subdivisions` 1–4096, `tolerance`, `start_reverse,end_reverse,start_interpolation,end_interpolation` | Object descriptor and retained analytical controls/endpoint frames/C0/C1/tangent-continuity receipt |
| `spline` | `object_token,subdivisions` | Complete Native sampled spline object; no full Tcl/Script coordinate return |
| `compare` | `reference,derived,method=x/path,budget` 6–65536; optional `output_units` pair | Full-input count/RMSE/mean/max and exact maximum source index, bounded residual descriptors/row indices and evaluation frame; view independent |
| `selection` | `object_token,indices` (zero-based) | Atomic replacement and full Native selection summary |
| `pivot` | Optional `arguments` list: `bounds`, `centroid`, `origin`, or `custom,[x,y]` | Native policy and current world point |
| `grid`, `polar` | Optional `arguments` list containing one Native property struct | Typed shared presentation state |
| `view` | Optional `arguments` list containing `{width,height,left,top,right,bottom,world_bounds}` | Typed `frame` (six numbers) and `world` (four numbers) |
| `style`, `direction` | `object_token`; optional Native `properties` | Typed Native style/direction state |
| `export_resource` | `object_token` | Complete XY resource and geometry metadata; no Dataset publication |
| `restore_resource` | `resource`; optional `kind=curve/point_set` | Complete restored Native object, including retained Source gaps |
| `constraint_create` | `definition` | Opaque owned relationship token and native diagnostic receipt |
| `constraint_join` | `a_token,a_index,b_token,b_index`; optional `merge=true,tolerance=1e-8` | Optional immediate exact merge plus one persistent coincidence rule, committed atomically |
| `constraint_get` | `constraint_token` | Parameters, valid/support/enforcement state and scientific residuals |
| `constraint_list` | Empty struct | Owned diagnostic records and `general_solver=false` |
| `constraint_update` | `constraint_token,definition` | Same logical token; invalid enabled parameters reject atomically |
| `constraint_enable` | `constraint_token,enabled` | Disable retains diagnostics; re-enable requires satisfied supported geometry |
| `constraint_delete` | `constraint_token` | Explicit removal; stale/cross-scene tokens reject |
| `checkpoint` | Entire desired document payload | Normal Interactive Document receipt with advanced revision |

Direct array creation and page outputs are bounded. Dataset-backed geometry uses
the exact Curve Source numeric input and native chunk ingestion, independently of
display LOD. Finite-pair omission, gap seams and original source row identity follow
the public Curve Source policy. Source Datasets remain immutable.

Bridge C1 flags describe the analytical curve's incident-segment parameterization;
its explicitly sampled polyline chords do not acquire analytical C1 continuity.
Comparison `x` requires supported single-valued interpolation; `path` compares
normalized ordered paths. These metrics do not claim geometric Hausdorff distance.
Those are separate operations when provided by the Native engine.

## Python example

```python
from gxtxt import gxtxt_api_require, gxtxt_api_call
api = "NATIVE_2D_GEOMETRY_API_v1"
gxtxt_api_require([api + "@1:native2d_geometry"])
scene = gxtxt_api_call(api, "open", [document_id])
try:
    curve = gxtxt_api_call(api, "curve", [scene, {"points": [[0, 0], [2, 0]]}])
    copies = gxtxt_api_call(api, "affine", [scene, {
        "object_tokens": [curve["object_token"]],
        "matrix": [1, 0, 0, 1, 0, 3], "copy": True}])
    resource = gxtxt_api_call(api, "export_resource", [scene, {
        "object_token": copies["object_tokens"][0]}])
    gxtxt_api_call(api, "checkpoint", [scene, {"geometry_resource": resource}])
finally:
    gxtxt_api_call(api, "close", [scene])
```

`document_id` is an existing public Interactive Document ID supplied by the action
context or selected by the caller. The example uses no private Tcl command or
framework/storage path. Octave passes `{scene,struct(...)}`; numeric pages are
N×2 matrices, object lists are cells, and row identities remain exact integers.

The public inventory states the currently supported scoped operations. Host-only
widget and gesture services retain their separate contracts.

`nearest_vertex` accepts `point`, nonnegative world `radius`, optional
`exclude_object_tokens` and `endpoints_only`. It searches complete Native geometry
and returns `found`, owned `object_token`, original Native `index`, world `point`
and world `distance`. Empty searches return `found=false`; invalid/foreign
exclusions are errors. Group exclusions expand to their members. Endpoint mode
includes each disconnected span's endpoints. Hidden/unselectable geometry is
ignored; locked reference geometry remains usable. Python and Octave receive
typed coordinates, integer indices, booleans and distance. No Doc or Dataset is
mutated and no display proxy is used.

Native C `gx2d_scene_nearest_vertex` and `gx2d_scene_nearest_vertex_device` provide
the underlying read-only searches. Device queries return pixel distances in the
effective view. `gx2d_gizmo_snap_translation` keeps a captured pivot and native
X/Y gizmo axis coherent, or produces exact coincidence for the Free handle. It
excludes complete moving objects/groups, searches original reference vertices
within the explicit pixel radius and remains safe during a native drag. Its
captured view is stable if view changes arrive mid-gesture. Device search and
gizmo transactions are host-only; scripts use the world-coordinate operation.

`rescale_coordinates` accepts `source_unit`, `target_unit` and optional explicit
`assume_undeclared`. The public Unit Registry supplies a compatible length-unit
factor. Every known leaf coordinate unit must match `source_unit`; mixed units
require normalization first, and unannotated geometry requires the explicit
assumption. Curve creation can annotate `working_unit`; later curves inherit
an explicitly converted scene's working unit by default.

CORE atomically converts complete geometry, fixed anchors/distance constraints,
selection rectangles, grid/polar lengths, view/pivot/mirror coordinates. IDs,
groups, styles, angles, pixels and point ordering remain. It retains physical
size; this is different from an affine physical Scale operation. Known units,
conversion provenance, length-bearing affine translations and bridge descriptors
update with the frame. Frozen Dataset source descriptors remain unchanged.
The receipt includes units/factor, object count and `physical_scale=false`.
Busy, overflow or unrepresentable projection rejects before any mutation.
Native C `gx2d_scene_rescale_coordinates` supplies the reusable atomic operation;
raw Tcl adapter `rescale_coordinates` takes its positive numeric factor.

## Retained sketch definitions

`definition.family` is `point`, `line`, `construction_line`, `polyline`,
`rectangle`, `circle`, `arc`, `ellipse`, `quadratic_bezier`, `cubic_bezier`, or
`spline`, or `path`. `controls` is an Nx2 array, including a 1x2 center for circular/elliptic
families. Point requires one control; line/construction/rectangle require two;
quadratic/cubic Bezier require three/four; polyline and spline require at least
two. Rectangle controls are opposite local corners. Circle/arc use positive
`radius_x`; ellipse also uses positive `radius_y`. Angles `rotation`, `angle_start`
and signed `angle_sweep` use radians. Arc sweep must be nonzero and at most 2π.
Optional `matrix` uses the documented six-coefficient convention and defaults to
identity. Spline retains the existing Native2D Catmull-Rom definition.

Definitions remain native-owned after creation, including deep-owned controls.
Affine copies and whole-shape drags preserve them; partial sampled-point mutation
is rejected. Explicit explosion creates independent editable sampled geometry.
Bounds are analytic extrema, not the control hull or display envelope. Scientific
length/area use bounded, piecewise eight-point Gauss quadrature with relative
refinement agreement 1e-10 and at most one million evaluations; exhausted budgets
fail explicitly rather than reporting a display-chord measurement.

A construction line is infinite: evaluation accepts any finite parameter,
`finite_bounds=false`, empty bounds and no finite metric. It renders clipped to
the current viewport and cannot masquerade as a finite whole curve for endpoint
bridges or Dataset publication. Explicit finite sampling through `sketch_sample`
or the host `native2DPrimitivePublish` helper's `first,last,total` policy
materializes only the requested finite parameter range. The latter publishes
that finite sample set and retains its policy and exact definition; it does not
publish an infinite array. Workbench publication additionally applies its
geometry-role policy. Other families use parameter [0,1].

Exported resources retain `metadata.sketch_definition` and their complete chosen
sampling cache. Restore verifies the owned resource through the normal resource
API and recreates the native definition. The Script binding preserves Nx2 shape
for a single center as well as multivertex controls. No implicit Dataset exists.

### Rectangular and circular series

`series.parameters` accepts `circular=false,rows=2,columns=2,spacing_x=1,
spacing_y=1,include_origin=false`. Positions use row-major order. Omitting origin
preserves the source objects without duplicating position zero. Circular mode
uses `circular=true,positions=4,angle_step=π/2,pivot=[0,0],rotate_geometry=true`;
angles are radians. `rotate_geometry=false` rotates the combined source-bounds
center around the pivot while retaining each copied object's orientation.
Groups expand once in stable member order. Retained primitive definitions and
complete generic coordinates stay native-owned; source objects stay unchanged.
Results preserve source associations in `metadata.parent_geometry_token` and
parameters in `metadata.geometry_parameters` (provenance, not persistent handles).

The native transaction limits results to 10,000 objects and 8,000,000 copied
vertices. Invalid parameters, output budgets and late coordinate overflow roll
back the entire operation. Native IDs remain monotonic after rollback. No
Dataset is created. Workbench editable series require an explicit Convert to
Native range for a large Dataset-backed source.

Single-point primitives and explicit one-point materializations retain their
`point` kind through resource export/restore. Their disabled direction descriptor
supports common presentation/persistence; they render no direction arrow.
Finite curve materialization/explosion inherits intended direction and resets
secondary spline interpolation because its complete points are already sampled.
Retained curve `path_length`/`path_point` operate on the definition; path points
use bounded native arc-length inversion rather than display chords. A returned
segment/fraction denotes the corresponding display-sample parameter interval,
while point/distance retain scientific curve semantics.

## Image-local ROI, alpha masks and raster composition

The same API includes `raster_roi_set`, `raster_roi_get`, `raster_roi_remove`,
`raster_layer_get`, `raster_layer_update`, `raster_prepare`, `raster_submit`,
`raster_freeze`, `raster_snapshot`, `raster_save` and `raster_restore`.
Native2D retains source-pixel vector ROI geometry and existing image/layer
identity, transforms, order, visibility, lock and opacity. ImageMagick owns
pixel masking, fixed blend modes and explicit derived RGBA exports through
the existing supervised Scientific Execution and Document Resource services.

See [Native2D raster composition](NATIVE2D_RASTER_COMPOSITION.md) for the exact
bounded requests/results, source-unit policy, geometry/mask distinctions,
alpha/inversion/feather semantics, non-destructive processing, persistence and
existing Native3D texture transfer. The host-only
`native2DGeometryViewportAttach` / `native2DGeometryViewportDraw` adapters mount
a scoped scene through the existing ViewportHost and presentation owners.
They do not expose a Script GUI construction protocol or create another scene,
pixel-processing engine, image editor, persistence store or Job queue.

## Native constraints and joins

A constraint `definition` contains `kind,a_token` and optional `b_token,axis_token`,
zero-based `a_index,b_index,axis_index`, dimensional `value`, positive `tolerance`,
separate positive `angular_tolerance`, `disabled=false`, and a world `anchor` for
restoring Fixed semantics. Available kinds are fixed, distance, angle, parallel,
perpendicular, coincident, horizontal, vertical, equal_length, equal_radius,
tangent, concentric, collinear, midpoint, point_on_line, point_on_curve, symmetry,
radius, diameter, lock_x and lock_y. Tokens belong to the same execution-owned
scene. Reports return logical object tokens, never native object numbers.

Active relationships validate native edits atomically. There is no general
parametric/nonlinear solver. Disabled records retain measured residuals; violated
records cannot re-enable until explicit geometry/parameter changes satisfy them.
Unsupported geometry reports `geometry_supported=false`. Radius/diameter and
radius equality require similarity circles/arcs, not an anisotropic affine circle
that has become an ellipse. Concentricity supports retained circular/elliptic
centers. Point-on-curve supports exact lines/construction lines/rectangles,
polylines and similarity circles. Other retained families reject this relationship
until a suitable bounded scientific projection is exposed. Tangency and collinear
checks use separate length and angular tolerances. Original parallel/perpendicular
residuals retain the legacy normalized-direction convention.

A merge Join moves A onto B and creates its coincidence rule as one native
transaction. Generic point geometry and retained point/line or Bezier/spline/
polyline endpoints support immediate merge. Other primitives require explicit
parameter edits followed by `merge=false` to retain a satisfied relationship.
Locks, existing Fixed/dimensional relationships, invalid definitions and failed
new-rule creation preserve previous native definitions/points. Removing the rule
explicitly disconnects it. Coincident selected points should move through one
complete `replace_points` candidate; sequential one-point edits may correctly
reject an intermediate violation. Native sampling-count changes with constraint
references reject to preserve point-index meaning. Host Workbench snapshots store
logical curve/constraint IDs, parameters, anchors and native diagnostic policy;
restore regenerates private native handles while retaining those logical IDs.

### Structured native measurements

`measure` accepts `kind`, `a_token`, optional `b_token`, zero-based
`a_index`/`b_index`, and `pair_budget` (maximum 1,000,000 segment pairs).
Kinds: `point_distance`, `horizontal_distance`, `vertical_distance`,
`segment_length`, `segment_angle`, `tangent_angle`, `path_length`, `radius`,
`diameter`, `arc_angle`, `bounding_width`, `bounding_height`, `signed_area`,
`point_curve_distance`, `object_distance`. Receipts contain `value`, `unit`,
`working_unit`, `unit_declared`, `unit_power`, `angular`, `exact`, `point_a`,
`point_b` and the explicit native evaluation `policy`.

Native definitions govern retained primitive metrics, derivatives and sampled
interval arc lengths. Unsupported nearest-boundary pairs reject explicitly;
exact object distances support complete linear segments and full similarity
circles. General ellipse/Bezier boundary projection is not supplied by this
operation. Axis-only `horizontal_distance`/`bounding_width` use X's declared
unit, and `vertical_distance`/`bounding_height` use Y's declared unit, including
unlike X/Y frames. Other plane measurements require the same exact X/Y unit
symbol and a compatible common physical frame. Any nondefault frozen Variable
relation requires explicit Dataset Transform normalization before measurement.
Undeclared units remain undeclared. Measurement reads create neither geometry
nor Datasets.

### Sketch identities and parent-linked fragments

`identity` addresses the scene by default, or one owned `object_token` or
`fragment_token`. It queries names and a UTF-8 attribute dictionary, or sets
`name` and/or a namespaced `key`/`value`; `remove=true` removes the key.
Compound updates roll back on failure. Names use the native reserved `gx.name`
attribute. Attribute values are inert text (1024-byte keys, 16384-byte values;
4096 scene entries). Native affine/series copies retain attributes. Canonical
owned geometry resources carry their names/attributes through restore.

`fragment_create` / `fragment_update` take `definition` containing `parent_token`,
`parameter`, `first`, `last`. Discrete intervals use inclusive point ordinals;
retained intervals use normalized parameters (finite arbitrary intervals are
allowed for construction lines). Reversed intervals preserve orientation.
Fragments hold references without copying the parent. Get/list return owned
opaque tokens, `valid`, `missing`, and a captured `topology_epoch`. Point reorder,
insertion/removal and discontinuity edits invalidate references; ordinary point
coordinate edits/transforms and retained parameter changes preserve them.
Explicit update validates and rebinds; deleted parents remain visibly missing.

`fragment_sample` pages a uniform grid of up to one million points, with at most
65536 points per call. `fragment_length` computes native scientific arc length.
`fragment_bounds` returns exact discrete/circle-interval bounds and conservative
parent bounds for other nonlinear retained families; its policy says so.
`fragment_materialize` creates independent owned Native geometry with an explicit
sample count, never a Dataset. `fragment_delete` removes the reference and its
attributes. Normal Dataset publication remains an explicit later action.

### Distinct Native selection sets and layers

`selection_set_create` / `selection_set_update` take `members`: each is an object
reference (`kind=object, object_token`), point reference (`kind=point,
object_token, index`), or fragment reference (`kind=fragment, fragment_token`).
They retain membership, without creating editing groups. Get/list return stable
owned set tokens and current per-member `valid`/`missing` state. Native point
topology epochs protect ordinals; reordered/resampled points become stale. Normal
geometry moves retain references. Explicit update rebinds. Activate validates all
members and layer visibility before replacing/adding/subtracting selection
atomically. Delete removes the collection without deleting scientific geometry.
Names/attributes use `identity` with `selection_set_token`.

`layer_create`, `layer_get`, `layer_list`, `layer_update`, `layer_delete` address
presentation collections through owned `layer_token`s. Properties are `visible`,
`selectable`, `locked`, `order`, `opacity`. `layer_assign` assigns owned
`object_tokens`; deleting a layer returns its objects to the default layer.
Layers neither own geometry nor create transforms or selection sets. Names and
attributes use `identity` with `layer_token`. Raw numeric layer IDs cannot enter
the Script geometry style API. Both collection families obey the normal document,
Session, revision and execution lifetime/foreign-token checks.

### Portable presentation states and named views

`view_state` queries or applies a complete snapshot in `view_state`:
`viewport` (typed width/height/left/top/right/bottom/world), `grid`, `background`,
`aspect`, `polar`, `coordinate_mode`, and optional `axis_presentation`. The native scene host validates the entire candidate before
committing. `view_state_rescale` takes a snapshot and explicit positive `factor`;
it converts world/grid/polar lengths, preserves pixel/color/angular state and
changes no live geometry. Both return `geometry_modified=false`.

`saved_view_create(name)` captures that Native snapshot and owned object/layer
visibility with working-unit descriptors into an execution-owned logical view.
`saved_view_get`, `saved_view_list`, `saved_view_update` (`name`, optional
`capture_current=true`), `saved_view_restore` and `saved_view_delete` provide its
lifecycle. Restore reports `missing_refs`, preserves scientific geometry and rejects
changed coordinate units before applying the view. Explicit recapture resolves a
changed unit frame. View tokens obey the normal document/Session/revision/execution
ownership checks; foreign tokens cannot address another scene's bookmarks.

`selection_set_add_member` validates only the new `member`, preserving existing
captured topology epochs. `selection_set_remove_member` takes zero-based
`member_index`, also preserving other captured references. Removing the final
member requires deleting the Set instead. This distinction prevents innocent
membership editing from silently rebinding previously stale point ordinals.

## Parametric rectangular Series

`series_create` accepts source `object_tokens`, a name and `parameters` (`rows`, `columns`, finite two-coordinate `step_u`/`step_v`, `include_origin`). It returns an opaque `series_token`, complete member tokens, logical cells, shape/basis and frame. Originals remain independent; origin is omitted by default, and `include_origin` creates an independent generated copy. A 1×1 omitted-origin pattern is a valid empty container.

`series_get`, `series_list`, `series_members` (zero-based `u`,`v`), `series_bounds`, `series_update`, `series_transform`, `series_delete` and `series_explode` operate on that container. Parameter edits stage complete replacement members from the current independent sources before replacing previous members; stale references are reported, and missing sources reject regeneration. Member replacements have new object identities; callers must explicitly rebind relationships. An affine transform updates the stored frame so later edits retain placement. Working-unit conversion scales basis vectors/frame translation without scaling dimensionless counts or the affine linear part. Explode removes the container while preserving member geometry. Limits: 256 containers, 10000 logical positions/generated objects and 8000000 complete vertices. These logical containers are owned by the public CORE scene authority and are distinct from static Native groups.

Legacy `series` remains an explicit independent-copy operation, including circular patterns. It does not imply a parametric container.

## Construction/reference geometry

`geometry_role` accepts an owned `object_token` and optional `role` (`regular`, `construction`, `reference`). Its receipt includes `role` and `normal_output`. The reusable C getter/setter share reserved Native `gx.geometry_role` metadata; even general attribute APIs reject unknown values. This role changes neither geometry, units nor constraint/measurement behavior. Groups/layers/sets are separate organizational entities rather than geometry-role owners. Retained infinite construction lines default to construction; other finite geometry defaults to regular. Explicit finite materialization creates independent regular geometry. Affine copies and managed resource save/restore preserve declared roles.

Curve Workbench's shared role form persists Native metadata with one Undo action. Normal Dataset publication filters construction/reference members and clearly rejects reference-only publication; explicit finite sampling or changing the role to regular is required to publish them. The common presentation snapshot excludes these entities by default and records excluded IDs; its `include_construction_reference=1` option is an explicit opt-in. The Workbench Export sketch chooser uses that common policy, complete live view/grid/style/legend snapshot and normal PNG/SVG provider, with no Dataset creation or document mutation.

## Bounded geometric deviation

`compare_geometry` takes owned `reference`, `derived`, optional `budget` (6–4096, default 257), and optional `output_units` pair. C computes viewport-independent geometric distances directly from retained uniform-parameter scientific evaluations or complete/bounded extrema-preserving Native vertices, preserving gaps. The receipt contains reference-query RMS/mean/max, symmetric RMS, **sampled** bidirectional Hausdorff, Native length difference, signed-area difference when both curves are closed, closest-boundary witness pairs, and bounded projection rows. Corresponding units must be compatible; CORE normalizes affine scales into one common X/Y evaluation unit before Native computation.

Exact supported target projection and exact supported closest-boundary pairs are flagged separately. Other target families use the explicitly sampled segment policy; nonlinear cache chords never claim an exact retained projection. RMS/Hausdorff are sampled estimates, not continuous extrema guarantees. Closest-pair evaluation is bounded to one million exact segment pairs before using the declared sample approximation. Retained metrics use mathematical definitions independently of display cache count. Each row records the unsigned query distance and projected pair; positions are gap-aware sampled reference chord lengths. Infinite construction lines require explicit finite materialization first. Full scientific geometry remains untouched; a million-row source still produces at most the chosen budget in each direction.

Curve Workbench's `geometry` comparison mode displays the unsigned deviation with this policy, persists definition/fingerprints/receipt and marks changed geometry stale. Publish deviations creates one explicitly named Dataset from bounded projection rows through normal Schema/Metadata/Publication APIs. Named measurements also support geometric RMS, sampled Hausdorff, curve length/closed-area difference and closest-curve distance; their capture/refresh/stale/report/Undo behavior uses the shared measurement lifecycle.


## Bounded polar conversion and host selection

`polar_bulk` accepts `xy_base64`: 1..65536 finite float64 little-endian XY rows, converted in the execution-owned scene's current polar frame. The receipt contains interleaved `theta_r_base64`, `angle_defined_base64`, row count, normalized `polar_frame`, normalization and origin policy. Base64 is ASCII in both Script Bridge languages. Native C owns the math; CORE does not evaluate it in Tcl/Python. `gx2d_cartesian_to_polar_many` is additive and atomic on invalid input.

The host point-selection API coalesces pending updates while a native drag is active and applies them after release. Destructive scene updates are deferred outside active native callbacks; UI recursion is separately guarded. Script geometry remains scoped by execution, Session lifetime and document generation/revision; widget/gesture controller operations remain intentionally host-only.


## CAD workspace

Existing scene/object/constraint opaque tokens, Session/document generation/revision validation and owned-resource persistence remain authoritative. API version1 is unchanged; operations are additive. Legacy constraint PODs and ordinary sample-index meanings retain ABI/behavior.

| Scoped operation | Request / receipt |
| --- | --- |
| construct / construct_preview | family, complete defining points → retained candidate definition; no adoption |
| from_fit | family, existing Numeric parameter vector → Native definition; no fit math |
| controls | object_token → exact handles with entity/index/epoch/role/world point |
| reference | object_token, entity, ordinal (or existing semantic_index) → checked public reference |
| reference_resolve | reference → world point |
| reference_point_index | reference → legacy point_index only for true supported endpoints |
| control_definition | reference, point → inverse-affine candidate, no mutation |
| control_edit | reference, point → atomic edit validated against active constraints |
| constraint_options | references (1..3) → compatible_constraints with existing definitions/defaults; general_solver1 for the existing bounded retained-component solver, not unrestricted nonlinear solving |
| constraint_apply | definition, optional constraint_token → direct drive/update and constraint receipt; atomic other-rule validation |
| constraint_location | owned constraint_token → Native witness point for marker placement |

Retained controls use the Native parameter topology epoch; ordinary points use topology epoch. Same-family parameter edits and display resampling preserve true handle identity. Replaced family/control topology, deleted ownership and malformed entity/index combinations reject references. Legacy endpoint Join maps only true endpoints through Native, never arbitrary render samples. Constraint definitions use existing semantic indices: defining controls start at1000000000, straight segments at2000000000, object reference3000000000. Existing unencoded indices retain the original point-index semantics. These encodings are CORE descriptor data, not ordinary GUI inputs.

Python/Octave expose every scoped operation above through the registered Script Bridge. Effective-device pick/snap/clip and captured canvas lifecycle remain explicitly host-owned; standalone C APIs remain renderer neutral. Host conversion services `native2DPrimitivePublish` / `native2DPrimitiveReconstruct` reuse Canonical Publication/Metadata/Table Stream and immutable source bindings; they create no parallel persistence/publication model. Scripts retain safe scoped sample/sketch APIs and normal Dataset Publication/Metadata, with bounded explicit acceptance. See Script Bridge coverage JSON and Workbench manual for contracts and policy.

C additions: gx2d_sketch_construct, gx2d_sketch_preview_definition, gx2d_sketch_from_fit, gx2d_sketch_controls, gx2d_reference_create/from_index/resolve/point_index, gx2d_control_definition/edit, gx2d_interaction_pick, gx2d_placement_snap, gx2d_constraint_from_selection/apply/location and gx2d_viewport_clip_segment. See gx2d.h for caller-owned output buffers, capacities and atomic errors. CORE owns all geometric calculations. Constraints directly drive supported retained lines/round centers/radii/control locations; other supported shapes may be validation-only. No general solver, implicit representation conversion or implicit constraints.


## retained components and persistent dimensions

These additive operations preserve API version1 and execution-owned object/constraint tokens. All reference inputs use the existing `reference`/`controls` descriptors. Solved relationships retain their existing IDs and can be captured/restored with the existing Document resources.

| Operation | Public request / receipt |
| --- | --- |
| sketch_status | object_token → parameter_count, rank, dof, valid, analysis_complete, rank_scope=local_component |
| sketch_component | object_token → object_tokens in enabled driving component |
| dimension_infer | references(1..2), annotation(world XY) → definition with current measured value |
| dimension_preview | definition, annotation → read-only device lines, label, hit_bounds, value, driven |
| dimension_apply | definition, annotation, optional driven(bool), optional constraint_token → existing-authority relationship receipt; atomic geometry/rule adoption |
| dimension_geometry | constraint_token → current witness/dimension/arrows/arc device geometry and measured value |
| relationship_state | constraint_token, optional presentation{annotation,placed,driven} → same relationship receipt; protected mode transitions |
| relationship_hit | constraint_token, device, label_bounds → hit(bool), renderer-neutral device query |

`constraint_apply` drives supported retained components; `control_edit` maintains their compatible relationships, with a hard defining-control target. `sketch_update` drives coupled definitions while holding changed parameters. Old PODs and enum values1..21 are unchanged; new kinds are horizontal_distance, vertical_distance, point_line_distance, line_distance, axis_angle and curvature. Receipts include solved/driven/placed, annotation, branch, curvature_tolerance and explicit enforcement. For references, measured_value/geometry.value are authoritative current measurements; stored numeric value is an inactive driving literal, never a geometry command while driven.

Whole Fixed/locked objects are excluded from movable parameters; Fixed controls retain their individual position equations. Dimensional overconstraint/redundancy is rejected atomically and can be explicitly retried as driven. State restoration validates already-saved geometry, using `gx2d_constraint_create_state`, without replaying a fresh driving operation. `gx2d_relationship_state` is additive and leaves `gx2d_constraint_v2` ABI intact. Angular tolerance is radians; curvature tolerance is inverse working length and is reexpressed with physical units. Annotation world XY is presentation, independent of scientific dimension value. The resolved numeric value and working unit remain part of the relationship contract.

Bounds/limits and supported mathematical families are documented in [Native2D implementation notes](../../core/native2d/README.md). Rank is local; analysis_complete=false precludes a fully-constrained claim. Unsupported/singular/nonconvergent cases return explicit errors. These public operations do not publish a Dataset, invent identities or accept foreign scene tokens.

## semantic construction

`construct_attached`, `placement_points`, `placement_preview`, `reference_connected` use the existing execution-owned scene/object/constraint tokens. Placement dictionaries have `point: [x,y]`, `reference: defining_control_receipt`, or `earlier: zero_based_prior_placement`; reference and earlier are exclusive. Construction accepts optional ordered `coordinate_units` and frozen `coordinate_relations`; absent pair defaults to two copies of `working_unit` (default empty). A placement reference must have the same complete normalized frame. Native owns placement validation and exact reference resolution. Preview has no history/persistence side effect. Creation takes `family`, `placements`, optional `display_samples` (default257) and `closure_references`, returning the ordinary object receipt plus `definition`, `constraints`, `tail_reference`, `closed`, `periodic:false`. Constraints are ordinary persistent Coincident relationships. Editing connected controls uses the existing solver, checkpoint, Document and recovery contracts. Numeric coordinate equality alone is not semantic connectivity. See the pair-aware contract below for the actual closure-reference and error boundaries.

Portable C APIs: `gx2d_construction_resolve`, `gx2d_construction_preview`, `gx2d_sketch_create_attached`, `gx2d_references_connected`; checked output capacity and failure semantics are documented in gx2d.h. `gx2d_construction_pick` is intentionally host-only: device coordinates and pixel tolerance depend on the effective viewport. No Workbench dependency is required.

## views, retained tangents, reference images and preview

All operations use `[owned_scene_token, request]` in Python and the equivalent
Octave cell arguments. Existing `view_state` remains the sole portable authority.

| Operation | Request | Result |
|---|---|---|
| fit_all / fit_selected | empty struct | view_state |
| fit_bounds | bounds `[x0,y0,x1,y1]` | view_state |
| zoom / pan | factor and device point / device delta | view_state |
| scene_bounds | optional selected_only | bounds |
| world_to_device / device_to_world | point | point |
| pixel_tolerance | pixels | world XY tolerance |
| spline_tangent_get | object_token, zero-based knot, incoming bool | anchor, control point, explicit, definition |
| spline_tangent_edit | same plus world point, optional reset bool | updated retained state |
| image_attach | managed raster resource, working_unit, optional state | owned object, image_state, resource |
| image_get / image_update | object_token / object_token, changes | image state |
| image_calibrate | object_token, pixel point_a/point_b, distance, optional distance_unit | uniform calibrated state |
| image_map | object_token, point, optional inverse bool | world or raster-local XY |
| symmetry_preview | owned axis reference, retained definition | renderer-neutral reflected definition |
| symmetry_construct | axis reference, retained definition; explicit coordinate_units plus optional coordinate_relations, or legacy working_unit; optional display_samples=257 | two objects in the checked axis frame and persistent Symmetry constraint |
| canvas_preview | current or fit mode, bounded options | managed PNG receipt |

Spline state adds dense optional `tangents` records `[flags, incomingXY, outgoingXY]`,
with local knot-relative offsets, incoming bit1 and outgoing bit2. No active flags
preserves the original Catmull-Rom kernel. Existing evaluator, derivatives,
bounds, transforms, unit rescale, solver, history and resources use that same
representation. C callers must zero-initialize `gx2d_sketch_definition` and rebuild
against the extended header; the additive tail changes POD size. Enum values and
serialized legacy definitions remain compatible. Missing endpoint sides reject.
Overrides participate in bounded solver parameters; unsupported spline symmetry
with explicit arms rejects rather than claiming mirrored tangent/G2 enforcement.

Images retain one ordinary Native object identity with a raster-local rectangle
and orientation-preserving similarity matrix. Calibration is uniform; pixels
never become scientific data samples. Its two calibration points become checked
controls (ordinals2 and3), usable as immutable attachment/dimension references.
Locked transforms reject; opacity/show/lock remain independently editable. Raster
identity/dimensions are taken from verified resources, not caller claims. Update
accepts only scale, rotation (radians), translation, opacity, visible and locked.
Nonuniform affine transforms/reflections and reassignment of calibration points
owned by active relationships reject atomically. Whole-scene unit conversion
scales the retained matrix and annotations while leaving raster pixels unchanged.

Symmetric construction delegates to existing reflection and bounded persistent
constraint authority. Supported point/line/construction-line/polyline/Bézier and
legacy spline defining sets fit the existing object-symmetry limit (12 controls);
unsupported arc/ellipse/rectangle/explicit-arm cases reject. Source, mirror and
relationship adoption is atomic; stale/foreign axis references cannot leave copies.
No new solver or relation identity store is introduced.

Preview modes render scene data, not Tk screenshots. `current` preserves the
effective world view while resampling to the requested device size; `fit` uses
Native Fit All and controlled padding, including a deterministic empty view.
Options: width/height16..4096, padding0..0.4, background RGBA, grid, axes,
reference_images, dimensions, constraints, annotations, point_budget6..65536.
Default scientific output excludes chrome, hover, selection/gizmos and registered
transient construction feedback. Reference raster underlays precede vector
geometry; dimensions/optional relationship markers follow geometry. Output is
deterministic for identical retained state and options and always restores real
view/state on success or failure. It returns the existing Document resource
receipt by default; explicit file export options are described below. Pillow>=10 is the portable host raster
dependency, declared in CORE requirements; geometry/calibration/view math stays C.

Widget creation, semantic panel placement, tool activation, tooltips and captured
pointer ownership remain host-only; see `NATIVE2D_VIEWPORT_HOST_v1.md`. Managed
workspace/note services have separate registered scoped APIs sharing Document
resources, not separate filesystem destinations.


## semantic selection and retained straight paths

The shared C selection-set authority holds `object`, `point`, `control`,
`segment` and existing `fragment` references. Dataset/Native point indices are
scientific entities; retained control/segment indices use stable Native reference
encodings (control base 1,000,000,000; segment base 2,000,000,000). Object selection
uses index zero. Reference receipts preserve validity/epoch and opaque ownership.
Mutability is a separate style/backing check after selection. No operation turns
retained display samples into defining points.

| Scoped operation | Request | Result/policy |
| --- | --- | --- |
| `selection_pick` | `object_tokens`, `device` [x,y], optional pixel `tolerance=9` | `hit` and owned `member`; global defining-point/control priority, deterministic scope order, hidden/excluded ignored |
| `selection_region` | `object_tokens`, world `polygon` Nx2, optional `maximum=65536` | Owned point/control `members` and count; shared inclusive-boundary even/odd polygon containment; 3–4096 nondegenerate vertices |
| `selection_set_apply` | `members`, optional existing `selection_set_token`, `mode=replace/add/subtract` | One atomic shared semantic set; zero members removes the set; additive detail selection refines a previously selected whole object |
| `selection_set_bounds` | `selection_set_token` | Native bounds of visible participating logical owners plus selected real defining controls; primary focus is irrelevant |
| `selection_set_restore` | Saved `members`, optional existing `selection_set_token` | Exact valid saved membership, including currently hidden entities; recovery does not silently drop valid hidden selection |
| `path_vertices` | `object_token`, optional `repeat_endpoint=false` | Exact ordered world vertices; shared junctions once, explicit closed endpoint repetition |
| `path_split` | `object_token`, interior `vertex` ordinal | Two retained paths, original preserved; closed input includes the closing edge in the two open results |
| `path_join` | `a`, `b` object tokens; optional `reverse_a=false`, `reverse_b=false`, world `tolerance=0` | One new retained path; endpoint deduplicated, originals preserved, same complete normalized coordinate frame required |
| `primitive_publish` | `object_token`, new `dataset_id`, `sampling` | Create-only Canonical Dataset Publication in the owning Session, preserving source/conversion provenance |
| `dataset_promote` | `dataset_id`, `x_variable_id`, `y_variable_id`; optional `options` filters/order | New owned retained geometry; trustworthy original GX-TXT publication is checked against all rows and reconstructed exactly, otherwise explicit interpolating spline |

`members` are lists/cells of structs containing `kind`, `object_token`, `index`.
Queries do not mutate selection. Regions use world coordinates and can be reused
without Tk; pixel picking uses the explicitly established Native view. Selection
membership is bounded at 65536 and capacity overflow rejects atomically. Restore
is for saved semantic state, not an ordinary hidden-geometry pick. Existing named
sets, layers, fragments and source row locators retain their authorities.

`path` is a retained straight-path definition:
unique ordered `controls`, optional boolean `closed`, and canonical `segments`
containing `family=line`, zero-based `first`/`last` vertex ordinals. Closing edges
refer back to vertex zero. An open two-vertex path has normal finite-line behavior.
Individual segments dimension their real adjacent vertices; moving a shared
vertex updates both incident segments. Coincident constraints between unrelated
objects do not combine their topology. Exact heterogeneous composition extends this authority as described below; straight paths remain compatible.

For a straight path, `sampling` publishes exact authoritative vertices, one
Dataset, optional `index_variable_id` (default `index`, blank omits), and explicit
`repeat_endpoint` (default false). The generated variable's name/ID is user chosen,
its dtype is int64, and its values are global zero-based curve order. It is not a
segment identifier or source-row identity. Direction reversal uses the Native
marker; closed paths anchor vertex zero before reversing the remaining vertices.
Publication accepts at most 65536 vertices, including any repeated closure.
Other primitive publication retains explicit `first`, `last`, `total` uniform
parameter sampling. Original Datasets are never overwritten.

Arbitrary promotion preserves ordered X/Y units and frozen Variable relations;
it requires authoritative knots in one continuous span, rejects reduced inputs
above65536 knots, and delegates valid spline minimum/finite geometry to Native.
It retains source row order/filter request, Dataset/Variable/unit identity,
descriptor, Native Catmull-Rom kernel, parameterization and maximum numeric knot
error. A mixed/custom frame reports scope
`numeric_plane_interpolation_at_authoritative_knots`, with no common physical
error unit inferred. Between-knot values are derived interpolation, not exact
Dataset geometry. Missing spans are rejected rather than silently bridged.
Exact provenance reconstruction separately validates producer, original canonical
receipt, coordinate schema, every XY row, global ordering and retained sampling
before adoption; full details follow below.

## Exact heterogeneous composition

These additive operations use the existing scene/object tokens, Native2D geometry
authority and Interactive Document resources. No Dataset is created implicitly.

| Operation | Request and result |
| --- | --- |
| `composition_create` | `object_tokens`, `arrangement` (`compound`, `ordered_path`, `auto_path`), optional `reversals` and nonnegative `tolerance`. Returns one owned object token. |
| `composition_part` | `object_token`, zero-based `part_index`. Returns exact `definition` with the root affine transform composed into it, plus `reversed`. |
| `composition_split` | Ordered Path `object_token`, interior `junction_index` (1 through part count minus 1). Returns two exact Path copies and `source_modified=false`. |
| `composition_explode` | Composition `object_token`. Returns exact independent primitive copies in stored constituent order, retaining effective direction and `source_modified=false`. |

`composite_path` is one endpoint-connected traversal; `compound` preserves
possibly disconnected or closed constituent geometry without inventing connecting
segments. Both definitions have `parts`, each containing `definition` and
`reversed`, plus a root affine `matrix`. A Path additionally carries truthful
`closed` topology and its reviewed junction `tolerance`. Primitives retain their
analytic parameters, controls, spline tangents and transforms. Structural nesting
is flattened into exact primitive leaves, never into display samples. Each
composition supports at most 256 leaves and 65536 defining controls in total.

Ordered mode validates the supplied sequence and reversals. Automatic mode
infers only unique, unbranched endpoint connectivity; intersections are not
junctions. It rejects explicit nonzero reversals because it owns orientation.
Closed primitives mixed with other leaves, disconnected inputs and branches
require Compound. Inputs survive every operation unchanged. Duplicate inputs,
points and infinite construction lines are rejected atomically.

Path evaluation divides the global parameter interval equally among leaves;
length/distance queries delegate to retained constituent mathematics. Compound
has no global parameter or traversal, so global evaluation is rejected. Compound
area is the additive signed area of its closed constituents, not a boolean union
area; overlaps are counted independently. Bounds and whole-object transforms
operate on exact retained definitions. Display sampling and disconnected display
breaks remain presentation only. Constituent control editing is available after
exact separation; this version does not expose nested control references.

`primitive_publish` accepts `sampling.curved_samples` (2–65536 per curved leaf)
for a composite Path. Straight vertices are exact, shared junctions occur once,
and the existing `index_variable_id`, direction and `repeat_endpoint` options
apply. Total output is bounded at 65536 rows. The `ordered_constituents` provenance
records the exact definition and materialization policy. Reconstruction replays
that policy and validates every canonical value. A Compound requires separate
constituent Dataset outputs; the Workbench's reviewed batch form supplies names
and curved sampling through the existing atomic publication authority.

Primitive publication records the actual publishing module and uses its assigned
Dataset namespace. `producer=core.native2d` identifies the geometry service;
`publishing_module` identifies the caller. Legacy provenance without the latter
continues to require the historical `core.native2d` publication owner.

## exact internal Path controls

The existing `controls`, `reference`, `reference_resolve`, `control_definition`
and `control_edit` operations support a `composite_path` as one logical
object. Control ordinals concatenate each retained leaf's real defining handles
in stored constituent order. They are not display samples. A junction may have
two incident references at the same point; editing either keeps their shared
topological point connected. Root and leaf affine matrices are respected.
References remain stable through parameter edits with unchanged part/control
layout. Topology/layout changes still invalidate them.

C callers use `gx2d_control_definition_owned` to obtain a deep-owned candidate,
then call `gx2d_control_definition_release`. This additive pair is necessary for
the lifetime of nested exact definitions; the legacy caller-control-buffer
function retains its primitive ABI. Tcl/Python/Octave still use the same existing
`control_definition` interface and receive inert definition data, with no raw
allocation pointer or separate geometry authority. Commit validates exact Path
topology and existing constraints atomically. An unsupported coupled edit is
rejected instead of disconnecting or flattening constituents.

## shared aspect default and constituent Spline tangent controls

CORE scenes default to `GX2D_ASPECT_XY_EQUAL` (the existing Tcl spelling is
`xy_equal`). Equal coordinate scale
is applied through `gx2d_view_set`, including the initial effective view. Existing
host C `gx2d_view_aspect_set` and native Tcl `core aspect`/`presentation`/`view_state`
remain the authority for exceptional module-specific overrides. The shared
viewport toolbar and grid form do not offer a user aspect toggle. Script
Bridge exposes no aspect setter and rejects a non-default aspect in a mutating
`view_state` request. Equal-aspect view-state round trips remain compatible.
Saved Workspace presentation is preserved; new Workbench Workspace bounds start
at [-10, -10, 10, 10] before equal-aspect expansion to the device frame.

Existing `spline_tangent_get` / `spline_tangent_edit` accept a composed Path token.
`knot` is then the object's global defining-control ordinal, as returned by
`controls`. It must address a Spline constituent. `incoming` continues to mean
the previous segment in the Spline's own defining order, even if Path traversal
reverses that constituent. World coordinates include root and leaf affine frames.
Missing endpoint sides and non-Spline controls reject explicitly. Editing changes
only an exact leaf tangent offset in a deep candidate, then validates/adopts the
entire Path through the existing scene/constraint authority. No new public
endpoint, raw pointer, constituent top-level object or sampled proxy is created.

## Workspace parameter and retained-network contracts

See [CORE Parameter Service](CORE_PARAMETER_SERVICE_v1.md) for automatic Workspace contexts and descriptor Workspace actions, and the retained-network behavior specified in this API for exact topology/reference/constraint semantics.

## compatible segment and curve placements

Existing `construct_attached`, `placement_points` and `placement_preview` accept
a placement with `point` plus a checked segment or curved `reference`. Native2D
uses its existing finite-edge projection or exact closest-point kernel and records
the existing point-on-line or point-on-curve relationship on adoption. Controls retain their previous semantics. Python and
Octave use the same operation/field names and execution-owned references/units.
`gx2d_reference_render` / Tcl `interaction_render` return device geometry only
for host semantic-selection feedback; no new portable bridge operation is needed.

## compatible semantic target policy

Existing `selection_pick` accepts optional `target`: `detail` (legacy default),
`local` (control/atomic primitive/exact Spline span or composed constituent), or
`object` (complete logical owner). Existing `selection_region` accepts `detail`
(default) or `object` (unique whole owners touched by the existing region query).
Python/Octave requests carry the same field and existing execution-owned tokens.
C adds `gx2d_selection_pick_target` / `gx2d_selection_polygon_target`; original
functions and POD layouts are unchanged. The GUI defaults to `local`.
Standalone Spline span references use the existing encoded segment namespace.
Composed curved/Rectangle constituent references retain Native's whole-leaf slot.
Spline rendering evaluates its exact parameter interval; no display-cache identity
or retained geometry conversion. `interaction_render` stays host-only presentation.
Connection/dimension/constraint tool picking retains legacy detail policy.

## exact span extraction and replacement

Composed Spline local picks identify the actual span rather than the whole leaf.
Additive `selection_definition`, `spline_line_plan`, `spline_span_to_line` operations
are documented in [Sketch Dataset API](SKETCH_DATASET_API_v1.md). They are available
through Tcl and Python/Octave using existing scene ownership and semantic indices.

CORE `native2DCanvasPreview scene document current|fit options` also accepts
`output_format png|pdf` (default png) and `output_file PATH` (otherwise the existing
managed resource result). PDF uses the same presentation plan with vector linework,
text, grid, dimensions and reference images; camera state is guarded and restored.
`::GX::pdfDatasetOpen path identity` launches the integrated read-only PDF reader.

## additive constituent contracts

See the constituent contracts specified in this API for stable scoped
part identities, independent marker state and batch updates, device picking and
placement, compound semantic references, atomic owned-definition persistence,
truthful traversal/materialization and public image calibration reset. Python
and Octave expose the same additional operations under API version 1.

### Comparison semantics

`compare` and `compare_geometry` preserve existing numerical receipt fields and
add `statistics`: public `STATISTICAL_RESULT_SEMANTICS_API_v1` records named
`reference` and (for nearest-curve geometry) `bidirectional`. Python and Octave
receive typed records and can use the public report/validation/publication APIs.
Coordinate units come from the actual owned geometry or stable source-variable
bindings. Positive affine conversions on corresponding axes are resolved through
Unit Registry; path/geometry additionally require compatible X/Y dimensions and
one common proportional output unit. Their labelled axes use the existing Unit
Registry homogeneous-coordinate plan: equal opaque symbols or absolute affine
units do not establish a valid physical norm. Explicitly normalize such source
coordinates through Dataset Transform before physical comparison or metrics.
No implicit geometric fallback is used for invalid X.
Undeclared-unit legacy geometry stays inspectable with unavailable physical
statistical quantities. Existing raw receipt keys remain compatible.

Native module hosts share Tcl `native2DComparison SCENE REFERENCE TARGET METHOD
BUDGET REFERENCE_XY_UNITS TARGET_XY_UNITS PROVENANCE ?OPTIONS?`; opaque public scene calls
resolve ownership and source units before entering that common boundary.
It computes one native comparison and attaches CORE interpretations of Numeric's
existing reductions. Display rows are never reduced again as scientific data.

`options.output_units` (Script request `output_units`) chooses the actual numeric
evaluation frame. X matching defaults to the reference X/Y units; path/geometry
default to the reference X unit on both axes. Unlike axes remain valid only for X
matching. Nonlinear or nonpositive conversions are rejected with an explicit
Dataset Transform normalization requirement. Wholly undeclared identity frames
retain legacy numeric inspection with unavailable physical statistical quantities.
This does not grant physical meaning to an opaque label. X-wise matching retains
its independent-axis affine conversion contract.

Every receipt adds `coordinate_frame`: `schema_version=1`, `method`, ordered
`reference_units`, `target_units`, `output_units`, and `reference_matrix` /
`target_matrix`. The six-value diagonal affine matrices use Native's
`{a b c d tx ty}` convention and map original coordinates into reported units.
They are typed arrays/lists in both Script languages. All row positions, projected
points, closest pairs, distances and statistics use the recorded output frame;
the same descriptor accompanies CORE statistical provenance and publication.
Host `native2DComparisonPoint receipt reference|target point` maps a reported
point back using the captured matrix, including after Unit Registry changes.
Historical receipts without a frame retain their original point coordinates.

`native2DComparisonFrame method referenceUnits targetUnits ?options?` is the pure
bounded planner. `native2DMetrics scene object units ?options?` and Script `metrics`
use the same common-unit rule before the Native metric evaluation. Temporary
affine Native copies retain full geometry and are released on success or failure;
identity frames allocate no copies. The original objects and scientific source
payloads are not changed. This is evaluation normalization, independent of
Dataset calibration, display LOD and Workspace viewport zoom.


## View-scoped axis presentation

The additive `axis_presentation` operation queries the current descriptor or accepts
`{axis_presentation DESCRIPTOR}`. It shares the ordinary scene/document/Session
lifetime checks. The same descriptor is carried by `view_state`, named views and
saved owner payloads. See [axis presentation](NATIVE2D_AXIS_PRESENTATION_v1.md)
for exact fields, mapped numeric anchors, supported formats and calibrated units.
Python and Octave use the same typed request and response dictionaries/structs.
This is presentation metadata; it never changes Dataset values or scene geometry.

## Canonical diagram edit validation and History (dev108)

`native2DGeometryDiagramEdit document expected operation request ?mode?` keeps
its existing four-argument commit behavior. Optional `mode` is `commit` (default)
or `preview`; other values are rejected. Both modes require the same exact
Document generation/revision/SHA and run the same typed request, catalog,
component/value/name/topology and complete candidate-payload validators.
`native2DGeometryApiInfo` advertises `diagram_edit_modes`.

Preview returns `status VALIDATED`, the unchanged `source` receipt,
`object_id`, `operation` and `proposed_payload`. A prospective object ID is not
allocated or reserved: the canonical payload, revision and `next_id` remain
unchanged. Commit revalidates the source and candidate; a preview is no authority
to commit after a source or Session change. No new runtime SDK method or generic
Document mutation grant is exposed to restricted C++.

The existing Native2D diagram viewport previews a candidate before a History
branch confirmation. Thus an invalid duplicate component name, invalid value or
malformed edit cannot discard a legitimate redo tail. A valid edit still needs
normal branch confirmation before its guarded canonical commit. Accepting a
same-checkpoint History branch retains the live editor/selection/focus; ordinary
Undo/Redo/navigation still restore snapshots. Cancelling a keyboard command
returns `status cancelled` without a canonical mutation or Tk background error;
other errors retain their existing diagnostics. Native pointer/dialog editing
uses the same model/History authority and validated source receipts.

The diagram viewport presents a dragged component or label through the same
validated `preview` payload and `native2DGeometryDiagramProject document
?preview_receipt?`. An optional receipt must match the current Document identity,
generation, revision and SHA; its complete candidate payload is revalidated.
The transient scene is disposed after drawing and does not update the Document,
allocate canonical IDs or create History steps. Release performs the normal
guarded commit; Escape/tool changes discard the gesture. Selection uses a thicker
stroke and a dashed outline. Wire/label/probe tools expose actual catalog pins
and junctions; the approached valid terminal gains a larger crosshair marker,
and a pending wire snaps its presentation to that exact endpoint. Topological
attachment still requires the existing validated terminal click.

## Existing wire route and endpoint edits (dev108; GAP039)

### Electrical values, source symbols and segment attachments (dev109)

Symbol and net-label Properties drafts retain the Document ID, generation,
revision and SHA shown when opened. Apply rejects a draft after another edit or
History navigation before preparing a History branch. A successful Apply advances
only that draft's source guard; repeated valid edits remain available. This
matches the existing wire Properties policy. Native stale-dialog/Redo acceptance
remains a separate dev109 GUI gate.

The existing `electrical.basic` catalog normalizes its declared numeric
attributes using engineering suffixes: t=1e12, g=1e9, meg=1e6, k=1e3,
m=1e-3, u/µ/μ=1e-6, n=1e-9, p=1e-12, f=1e-15. Suffix comparison is
case insensitive: `M` means milli, and mega requires `meg`. Thus1k=1000,
4.7k=4700,470n=4.7e-7,1u=1e-6,10u=1e-5 and1meg=1e6 in the catalog
attribute's SI unit. Plain decimals/scientific notation remain valid. The
owner parses a combined decimal exponent once, rejects nonfinite/underflow and
existing field-bound violations before mutation, and stores numeric SI values.
Suffix strings never become canonical physical values. Generic Numeric/UI
number contracts retain their existing behavior. Properties and schematic
labels use engineering text only when it parses back to the identical double;
otherwise they retain a full precision SI representation.

A catalog symbol may declare `variants {attribute CHOICE_ATTRIBUTE marks
{CHOICE PATHS ...}}`, bounded to16 declared choices/32 paths per choice/128
vertices per path. These marks extend its existing paths in the same renderer.
The voltage symbol selects DC polarity, sine or pulse marks from its canonical
`waveform`; nonzero small-signal `ac` amplitude does not select a sine waveform.
Pins, stable identities, polarity and scientific netlist semantics are retained.

For `wire start/end`, `junction target`, and `label endpoint`, the existing
edit owner additionally accepts a transient `{kind wire wire_id ID point
{x y}}`. The point must lie on that actual current wire within1e-7 diagram
world units. Existing Native2D C segment projection validates it. Wire/junction
edits split targeted segments atomically, reuse existing endpoints/cuts, preserve
the original wire ID on its first piece, retain bends and allocate remaining
canonical IDs without collisions even for imported low-counter payloads.
Both targets of one wire are resolved against the same original payload.
Label resolves the existing canonical net endpoint without a topology mutation.

`junction targets {TARGET ...}` intentionally connects1..1024 coincident
targets. Newly created cut junctions coalesce; existing component/junction IDs
remain. Distinct existing nodes at one position use an explicit canonical
joining wire, reused on repeated joining. Merely crossing drawn wires never
joins them. Exact guarded preview/commit and Interactive Document persistence
remain authoritative; generated ngspice nodes come from the existing provider.

The existing `route` operation accepts the exact allowed keys `id`, `route`,
`start`, `end`. `id` identifies an existing wire and at least one other key is
required. Omitting a field preserves it; legacy `id/route` calls retain their
original behavior. `start/end` are existing stable component-pin pairs or
junction IDs, validated by the same complete diagram model. They must differ.
`route` is an ordered list of at most128 two-coordinate finite points, each
within+/-1000000. Neither geometric crossings nor bend coordinates create an
electrical join. The wire ID and `next_id` allocator remain unchanged. Preview
and guarded commit use the same request and topology validation.

For example, `native2DGeometryDiagramEdit $id $receipt route
{id wire_4 start junction_3 end {component_2 n} route {{40 60} {80 60}}}`
reconnects that wire and replaces its bends in one canonical commit.
`native2DGeometryApiInfo` exposes `diagram_route_fields` and
`diagram_route_semantics`. This extends an existing operation; it introduces no
API family, raw Document access or new restricted C++ Host method.

## Pair-aware retained frames and canonical reconstruction

This is an additive contract of this existing API, not a new Script or C++
family. It also documents the existing reusable host publication helpers. The
`NATIVE2D_PRIMITIVE_PUBLICATION_v1` identifier below is a provenance schema ID;
it is not a newly registered invocation endpoint. Internal `_native2D*` helpers
remain CORE implementation details.

### Frame identity, adoption and physical quantities

`coordinate_units` is an ordered two-element list `{X_UNIT Y_UNIT}`; each symbol
is at most256 characters without CR/LF and is resolved through Unit Registry.
Optional `coordinate_relations` is an axis dictionary containing only `x,y`;
each axis accepts only `canonical_unit`, `to_canonical`, `from_canonical`.
The owner merges nominal registry fields with the supplied relation, requires
a canonical unit for formulas, and checks the declared conversion plan. It
stores only axis relations that differ from nominal registry definitions.
No numeric values are converted by merely recording this metadata.

The normalized frame contains `coordinate_units`, `coordinate_relations`, and
`working_unit`. The common `working_unit` is the exact symbol only when X and Y
symbols are identical; otherwise it is empty. Empty common working_unit does
not erase the pair or infer dimensionless physical geometry. A nominal symbol
also cannot erase nondefault frozen Variable calibration formulas.

`sketch` and `curve` accept the explicit pair plus optional relations and adopt
that frame. Without a pair they retain their existing working_unit behavior.
`from_source` keeps the frozen source descriptor; the geometry owner derives
the selected stable X/Y Variable units and nondefault relation fields from it.
Resource export/restore carries geometry metadata. Later source disposal does
not authorize rereading unrelated mutable Variable metadata to replace a frozen
frame. Explicit scene rescaling records coordinate_conversions and clears the
old variable-specific relation metadata according to its existing contract.

Combining objects for composition/path joining or constraints requires the
same complete normalized frame. Current equality is the actual Tcl value
comparison of the complete frame dictionary, not a fresh numeric conversion
or a units-only compatibility test. Different symbols, frozen relations or
unequal normalized dictionary values can reject. Explicit Dataset Transform
normalization owns scientific conversion; do not bypass the check by relabeling.

Metrics/comparison reject nonempty variable-specific relations until explicit
normalization. Plane measurements additionally require common compatible units;
axis-only horizontal_distance/bounding_width use X and
vertical_distance/bounding_height use Y. Existing checked affine comparison
frames still govern x-wise versus Euclidean/path/geometry comparisons. Retaining,
editing, displaying or canonically publishing a pair does not by itself establish
a common physical distance, angle, tolerance, uncertainty or metrological claim.
Here `metrics` means the explicit public operation with its checked coordinate
frame. The ordinary `describe` receipt also embeds raw Native `metrics` for finite
curves; that embedded field is a numeric native-plane diagnostic, without the
explicit operation's checked physical frame/unit receipt. Do not treat it as an
independent proof of physical validity for unlike/calibrated axes.

### Publication calls and sampling

| Exact public host signature | Context / result |
|---|---|
| `::GX::native2DPrimitivePublish session requested definition unit sampling logicalId ?name={Retained primitive}? ?moduleId=core.native2d?` |Explicit Session and new requested Dataset ID; returns the ordinary Canonical Dataset Publication v2 receipt. Actual active publication context overrides the caller's moduleId with its module owner |
| `::GX::native2DPrimitiveReconstruct session datasetId xId yId` |Checks existing canonical rows and retained publication provenance; returns an inert exact definition/frame receipt, without adopting an opaque object or modifying the Dataset |
| `::GX::native2DDatasetPromote session dataset x y ?options={}?` |Exact reconstruction when trusted provenance exists and no filters/order override is supplied; otherwise explicit spline interpolation receipt |

For Python/Octave the existing admitted geometry operations are
`primitive_publish(scene, request)` and `dataset_promote(scene, request)` through
`gxtxt_api_call`, using their normal two-element argument array/list/cell.
The schema descriptions here name the authoritative Tcl fields. The existing
binding decodes coordinate_units as a Python list / Octave cell array, and
coordinate_relations and original_source_variable_schema as nested axis
dictionaries / structs. Unit and formula fields retain literal strings; the
transport does not evaluate their scientific relations. It also decodes sampling
traversal_contract and curved_samples as integer wire scalars, and constituents
as a list / cell array of typed dictionaries / structs, including part_id,
ordinal and nested direction fields. Python receives integer scalars as int;
the existing Octave client preserves small integer scalars as exact doubles and
uses native integers for larger identity values according to its wire contract.
Operation admission, consumer ownership and typed C++ exposure remain their
separate existing contracts; no private decoder or generic invoke is needed.
`primitive_publish` requires `object_token,dataset_id,sampling`; optional
`name` defaults to `Retained curve`. It gets the retained definition, actual
direction marker and complete source frame/provenance from the owned object;
these authoritative fields override conflicting sampling fields. Publication
uses the currently owned Session and real calling module. It does not checkpoint
the Interactive Document automatically.
The metadata owner attributes an exact core.native2d publication with matching
canonical producer_module to its existing System actor; installed module
publication retains its actual module actor. This does not rename the canonical
producer/provenance or admit arbitrary unknown module identities.

The direct host publication helper selects pair-aware mode **when the
`sampling.coordinate_units` key exists**. It uses that ordered pair and optional
`sampling.coordinate_relations` (default empty), replaces the legacy `unit`
argument with the derived common unit, and publishes x/y Variable descriptors
with their actual per-axis units and nondefault relations. A direct legacy call
with no pair rejects a coordinate_relations key, requires declared length-
compatible `unit`, and retains historical common-unit provenance. Missing pair
does not silently reinterpret legacy data as an arbitrary scientific plane.

Retained straight paths publish exact authoritative vertices. Optional
`repeat_endpoint=false` controls explicit closure repetition;
`index_variable_id=index` supplies global zero-based order (empty omits it).
The ID must match `[A-Za-z][A-Za-z0-9_]*` and differ from x/y; generated ordering
Variable is int64 with empty unit, index_start0/index_step1, meaning
`global_curve_point_order`. Maximum materialization is65536 ordered points.

An ordered composite Path samples straight leaves exactly (line2, polyline real
controls, rectangle5 including closure) and curved leaves with
`curved_samples=257`, integer2–65536 per curved leaf. It requires a continuous
chosen traversal, orders/reverses constituents using actual direction states,
deduplicates equal shared junctions, and applies explicit root closure policy.
Total remains at most65536. Its policy records `method=ordered_constituents`,
`traversal_contract=2`, actual constituents, curved_samples, and
`reversal_anchor=constituent_boundary`. Compound has no global traversal and
rejects; review separate constituent outputs rather than inventing one order.

Other retained families require `sampling.first,last,total` and use Native
uniform-parameter sampling. `forward` defaults true for a direct host call;
reversed direction swaps first/last before recording the policy. Sampling
first/last must be finite, within0–1 except for retained construction lines;
total must be an integer1–65536 because this helper materializes one Native
page. The general paged sampler's larger total limit does not extend this
single-output publication limit. Retained geometry validity and publication
schema are delegated to Native/Canonical Publication; the finite sample set does
not replace the exact retained definition or establish continuous interpolation
accuracy.

The structured `native2d.primitive_publication` metadata equals the canonical
receipt's provenance and contains schema ID/version, operation
`retained_primitive_to_dataset`, framework_version, exact normalized definition,
working_unit, sampling, source_logical_identity, x/y Variable IDs, producer
`core.native2d`, actual publishing_module, source_dataset_ids and
conversion_provenance. Pair-aware publications additionally capture
`coordinate_units`, normalized `coordinate_relations`, and
`original_source_variable_schema.x/y`, each with exactly the scientific fields
unit/canonical_unit/to_canonical/from_canonical. Geometry authority and
approximation-policy text are explicit companion structured metadata. Display
LOD and point_budget are not canonical sampling authorities.

### Exact reconstruction checks and returned contract

Reconstruction first requires the structured publication record, matching
canonical producer_module/publishing_module and exact canonical provenance,
supported schema/version/producer/operation, and the original selected X/Y IDs.
For pair-aware records it normalizes the retained pair/relations and checks:

1. Recorded working_unit equals the frame's derived common symbol.
2. Each captured unit equals its axis's recorded unit.
3. Current canonical Variable scientific fields unit, canonical_unit,
   to_canonical and from_canonical exactly match the captured normalized schema.
4. Captured schema exactly equals that implied by the recorded frame/relation.

Absent coordinate_units selects legacy reconstruction: both Variables must
still have the recorded common unit and its nominal normalized relation; that
unit must remain declared length-compatible. Pair-aware support does not weaken
the legacy check. These checks concern the listed scientific schema fields;
they do not claim equality of every display-name or optional Variable field.

Only `uniform_parameter`, `authoritative_path_vertices` and
`ordered_constituents` policies with total at most65536 are supported. The owner
recreates a temporary Native retained object and replays recorded sampling.
An ordered-constituent record without traversal_contract uses the existing
historical replay path; current records retain contract2 behavior. A declared
ordering Variable must still be int64/unit-empty with index_start0/index_step1.

Canonical Table Stream reads X/Y and optional order in chunks of4096. Every
order value must be an integer equal to the global row ordinal. Row count must
equal the replayed sample count. Each XY value must parse as a strict double
and satisfy `abs(actual-expected) <= 1e-12*max(1,abs(expected))`; malformed numeric
evaluation fails rather than authorizing an unchecked result. This is the actual
recorded-sampling comparison tolerance, not an uncertainty or physical accuracy
estimate. Current Variable relation/schema changes, row edits/order changes,
unsupported sampling or mismatched canonical provenance reject reconstruction;
use a reviewed scientific fit/interpolation workflow for arbitrary data.

Success returns `definition`, the complete normalized frame,
`method=exact_provenance_reconstruction`, source_dataset_id, full provenance,
direction.forward, `materialization_verified=1`, and
`original_dataset_modified=0`. The temporary Native scene and stream are closed
on success/failure. No geometry token is adopted by this helper itself.

`dataset_promote` requires `dataset_id,x_variable_id,y_variable_id`, optional
`options` (copies `filters,order_variable_id` only). With provenance and neither
option present, reconstruction failure is an error, not a silent fallback.
Otherwise Curve Source supplies up to65536 unreduced authoritative knots in
one span; Native constructs an interpolating Catmull-Rom spline in source order.
Receipt records original descriptor/request/source rows, frame, kernel and
uniform-source-order parameterization. `quality.maximum_knot_error` is the
largest numeric hypot error at authoritative knots. Its scope is
`numeric_plane_interpolation_at_authoritative_knots` for mixed/custom frames;
only common-symbol/no-custom-relation frames use
`interpolation_at_authoritative_knots` with that common unit. The owner does not
infer a common physical norm for unlike axes or validate between-knot accuracy.
`quality.maximum_knot_error_by_axis` gives the separate maximum absolute knot
differences as `x` and `y`; `quality.coordinate_units` retains the ordered native
X/Y units. The Workbench review labels each component with its own unit and
identifies the combined mixed/custom-frame result as a numeric plane norm.
Promotion review and bridge-settings forms capture the source coordinate
context; Apply rejects a changed context before modifying retained geometry or
composition parameters. Bridge derivative tolerance names both native axes.

The opaque `dataset_promote` operation explicitly creates/adopts a new retained
object with the returned pair/relations, restores direction when present, and
stores the conversion receipt. It returns the ordinary object receipt plus
`conversion` and `original_dataset_modified=0`. Original canonical Dataset is
preserved; caller owns Document checkpoint/history under existing contracts.

### Pair-aware construction and symmetry

`construct_attached`, `placement_points`, `placement_preview` accept optional
coordinate_units/coordinate_relations. Without a pair they use two copies of
working_unit (default empty). Every placement reference is mapped through the
owned scene and checked against the complete normalized requested frame before
Native placement resolution. `placement_points` returns points;
`placement_preview` returns definition; neither adopts persistent geometry.
Creation adopts the exact frame and returns the ordinary object receipt plus
definition, tail_reference, constraints, closed and periodic=false. If post-
creation adoption fails, its owned map is restored and the created object removed.

The Tcl wrapper checks closure_references through the same complete-frame and
owned-reference helper as placement references, before calling Native
construction_create. Different X/Y pairs and same symbols with different frozen
relations reject before construction can add an object or relationship. Native
still owns actual closure geometry/connectivity semantics; passing a frame check
alone does not prove that a candidate is geometrically closed.
`reference_connected` only queries existing reference connectivity and takes no
new construction frame.

`symmetry_preview` requires an owned axis reference and retained definition and
returns Native's renderer-neutral preview definition. It does not adopt objects
or validate an optional requested pair. `symmetry_construct` takes the same
axis/definition and optional display_samples=257. An explicit coordinate_units
pair with optional relations defines its frame; otherwise its required legacy
working_unit must be length-convertible and is duplicated. The axis object's
complete frame must equal that frame. Both source/mirror objects are adopted
with it; the result contains two ordinary object receipts in `objects` and the
persistent relationship receipt in `constraints`. Post-creation adoption error
restores the prior owned map and deletes created source/mirror objects. Native
retained solver/constraint support remains authoritative; publication or frame
identity does not add a new physical-symmetry/angle guarantee for unlike units.

### Source-backed use and exposure limits

The host may publish an already validated retained definition in unlike units
with explicit pair metadata; no relation means each axis uses its registry
nominal definition. This example is illustrative and unexecuted here, requires
an explicitly owned Session and new Dataset ID, and creates canonical data:

```tcl
set sampling [dict create first 0 last 1 total 101 \
    coordinate_units {s V} coordinate_relations {}]
set receipt [::GX::native2DPrimitivePublish $session $newDatasetId \
    $retainedDefinition {} $sampling $logicalIdentity]
```

Use only a definition/sample policy appropriate to its retained family (Path
uses its authoritative-vertex policy). Actual Dataset Publication owns schema,
writer, create-only identity, persistence and errors. Python/Octave use the
existing owned geometry operations rather than invoking these host helpers or
private `_native2D*` functions. Current C++ typed Host methods remain their actual
declared component methods; no generic geometry invoke, primitive-publish,
reconstruction or arbitrary Tcl dispatch is created by this reference.


## Retained image annotations (dev109, Tcl owning host)

These scoped operations extend the existing Native2D image identity owner.
They are currently Tcl host operations, not registered Script Bridge operations
or arbitrary C++ geometry calls. The Builder anchored annotation editor remains
a separate unfinished integration gate.

Call the existing scoped service:

```tcl
::GX::native2DGeometryCall $scene raster_annotation_get [dict create object_token $image]
```

`scene` is an already admitted Native2D scene token. `object_token` is an existing reference image in that same scene. The existing Document, Session, canonical Dataset identity/schema/content and retained Resource checks apply. No source filename, pointer, Dataset substitution or alternate annotation store is accepted.

| Operation | Request fields | Result |
| --- | --- | --- |
| `raster_annotation_get` | `object_token` | Current collection dictionary. |
| `raster_annotation_set` | `object_token`, `annotation_id`, `expected_revision`, `definition` | Updated collection; semantically equal canonical definition returns the unchanged collection/revision. |
| `raster_annotation_remove` | `object_token`, `annotation_id`, `expected_revision` | Updated collection; absent ID is an error. |
| `raster_annotation_project` | `object_token` | Dictionary with `annotations` **list** of definition dictionaries augmented with `id`, collection `revision`, and `source_resource_id`. Returned `point` uses current Native2D world coordinates. |

The collection has `format=gxtxt.native2d.image_annotations.v1`, `source_resource_id`, nonnegative integer `revision`, `annotations` (ID→definition dictionary), and `generations` (ID→positive integer identity generation). IDs match `[A-Za-z][A-Za-z0-9_.-]{0,63}`. A new ID gets the next collection revision as its generation; edits retain its generation; delete/recreate gets a new generation. `expected_revision` must equal the current collection revision, including for a no-op. An expired revision fails without overwriting the retained collection.

Definition fields:

| Field | Contract/default |
| --- | --- |
| `point` | Required pair of finite numbers in **retained source-image pixels**. The operation does not impose an inside-image clipping constraint. Native `image_map` owns conversion to world coordinates; `world_to_device` owns device mapping. |
| `text` | Required text, at most 256 UTF-8 bytes, no NUL. This is annotation text; it is not a physical unit declaration or numerical measurement. |
| `anchor` | `n/ne/e/se/s/sw/w/nw/center`; default `sw`. |
| `font_family` | Default `Sans`; trimmed nonempty name, at most128 UTF-8 bytes; no NUL/CR/LF. |
| `font_size` | Finite 6..96 **device pixels**, default14. It is independent of image/world scale. |
| `color` | Existing UIField color contract; default `#233746`. Returned color uses its canonical RGB/alpha representation. |

Unknown definition fields fail. Normalization canonicalizes field order, finite numeric values and UIField color before no-op comparison. A reordered equivalent dictionary or an unchanged returned normalized definition does not create a revision.

Both limits apply: at most512 annotations **and at most16,384 UTF-8 bytes for the entire serialized retained collection**, including IDs, definitions, generation records and envelope fields. This is the existing Native2D identity-attribute capacity; it does not promise that512 maximum-length texts fit. Oversize updates fail before native write and retain the previous collection. The separate131,072-byte presentation-input limit does not expand persistent annotation capacity.

Mutation respects existing image/layer locks and the source/Resource guards. Stale collection revisions, missing IDs on remove, invalid/nonfinite fields, expired scenes, replaced canonical sources and capacity violations return errors. Get/project perform the same existing scientific identity admission; they are not a bypass for expired sources.

For an already owned image, an exact source-backed Tcl example is:

```tcl
set old [::GX::native2DGeometryCall $scene raster_annotation_get [dict create object_token $image]]
set request [dict create object_token $image annotation_id note_1 \
    expected_revision [dict get $old revision] \
    definition [dict create point {12 10} text {Source note} font_size 18]]
set current [::GX::native2DGeometryCall $scene raster_annotation_set $request]
```

The example edits only the retained native image. It does not create a Dataset or implicitly checkpoint the Document. Ordinary native Resource export/save/restore carries `gx.image.annotations`; canonical Document/History adoption remains the existing explicit owning workflow.

The existing Tcl viewport panel target may use `kind annotation`, `scene_token`, `object_token`, `annotation_id`, optional `annotation_generation`, and optional two-device-distance `offset` (each finite, absolute value≤1024). It captures current generation if omitted, rejects an expired generation, and follows current native source→world→device mapping. Hidden image/layer presentation hides the anchor. This is host substrate, not a generic script GUI callback or completed Builder editor.


Independent execution verified 17 focused owner/presentation/lifetime checks,
including reordered no-op updates, the real 16,384-byte capacity boundary,
unchanged state after rejection, generation replacement and a real native
`scene_bounds` live/closed transition. This is not installed GUI acceptance.
