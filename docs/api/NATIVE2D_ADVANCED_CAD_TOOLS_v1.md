# Shared advanced CAD tools — additive NATIVE2D_API_v1 / CAD Canvas Host (P019)

The **same** public CAD Canvas Host owns one optional advanced-tools controller:

```tcl
set host [::GX::native2DCadCanvasCreate chosenParent nativeScene ?options?]
set tools [$host advanced]
$tools host
$tools context
$tools scene
$tools state
$tools cancel ?reason?
```

Attach to an existing Canvas/context instead with `native2DCadCanvasAttach`.
The consumer chooses packing/grid, toolbar/editor/panel location and scientific
Document/Session lifetime. No new Canvas, renderer, geometry/constraint engine,
History stack or scientific registry is allocated by the advanced controller.

Retrieving `$host advanced` requires a live native context and Canvas, like
retrieving `$host context`; it does not admit a scientific edit. Read-only
presentation remains available while the domain owns an import/publication.
Mutating controller operations still run the Host lifetime/domain guard and
explicit scientific admission before changing geometry or relationships.

Tcl/Tk coordinates tools on the GUI thread. Existing C++ context/lifetime/gesture
and retained Cairo/sprite owners remain authoritative; Native2D C computes exact
scientific definitions, control references, attachment, topology, solver results
and dimension primitives. This GUI API does not grant restricted workers Tk or
raw-pointer access. Manual P015 sprites and existing APIs remain compatible.

## Ownership, admission and receipts

Every scientific mutator checks the existing Host guard/context/source generation,
rejects overlapping native/Host gestures, admits the operation, invokes one checked
native backend and returns its original receipt. A Host callback named `advanced`
may receive a single event dictionary with common Host fields (`host`, `canvas`,
`scene`, `generation`) and:

| Phase | Contract |
|---|---|
| `admit` | operation and native object IDs plus proposed data; return Boolean before mutation; dimension previews also admit physical meaning |
| `begin` | capture domain recovery/History state and return opaque token≤256characters; scientific snapshots remain with the domain owner |
| `committed` | native `receipt` plus original proposal/context; adopt domain records and record one accepted change through public P017 History, where this hook owns that boundary |
| `rollback` | recover domain scientific state when post-native domain adoption fails; no parallel core Undo stack |
| `rejected` | native operation rejected without accepted mutation; explicit error receipt for cleanup/diagnostics |
| `preview` | native proposed definition/geometry; return `{handled 1}` to present through an existing external renderer, otherwise default construction feedback is used |
| `exclude` | construction: temporary native feedback IDs to exclude from snapping, default empty |
| `cancelled` | tool cancelled/replaced/disposed, including reason; clear domain-only readouts, never submit an edit |

The callback's `phase` and qualified `operation` are reserved controller fields.
Proposal dictionaries cannot override them: for example a native topology plan
named `join_path` produces `operation topology.join_path` in every lifecycle hook.

Hooks are optional. A consumer which already owns admission, before/after logical
adoption and P017 History may keep that existing domain boundary and leave begin/
committed hooks empty, as Workbench does. Do not record the same operation twice.
No History is submitted by input collection, preview, selection or ordinary redraw.
Unchanged domain records must not become scientific edits. Callback failures are
explicit; post-native domain failure invokes its recovery callback. Do not call
reentrant tool mutations from a commit hook. Source lifetime is rechecked after
admission/capture, before native mutation. Sessions and unit/source policy remain
the domain's responsibility, never inferred from renderer point arrays.

`state` exposes current construction/topology proposal, last actual receipt and
busy status. Native errors propagate to callers; the Host input dispatcher presents
rejection receipts through its existing error callback. GUI editors display their
native failure reason and retain entered text for correction. No busy flag or
constraint guard is cleared to hide an error.

## Construction

```tcl
::GX::native2DCadConstructionCount family
$tools construction start family ?options?
$tools construction state
$tools construction pick deviceXY
$tools construction preview ?nativeCandidatePlacement?
$tools construction click deviceXY
$tools construction adopt nativePlacements
$tools construction commit ?optionOverrides?
$tools construction overlay
$tools construction cancel
```

Supported existing native families: point, line, construction_line, rectangle,
circle, arc, ellipse, quadratic_bezier, cubic_bezier, path, polyline and spline.
Count0 denotes variable-length creation, not an absent definition. Default Host
bindings send actual pointer/Return/Escape to this controller; an existing Viewer
can dispatch explicitly with `bind_events 0`. No private Workbench runtime is used.
Ordinary pointer Motion updates construction and dimension previews; B1-Motion
continues to drive the existing drag owner. Tooltips and domain input remain under
their existing owners.

Options: `auto_commit` (default1), `samples` (257,2..65536), `chain` and `symmetry`
(existing native typed references), `placement_color` (shared transient marker
presentation). Sampling affects existing native presentation, not replacement of
an exact retained definition by display points. The checked Native2D construction
API owns snapping/attachment/closure/retained controls. `adopt` accepts native
placement records for an explicitly reviewed scientific input form; it does not
convert Dataset row identities or display samples into controls.

Click returns placement/places/points/ready, or outside/finished status. Fixed
count tools commit automatically by default; variable-length tools finish with
Return. Workbench chooses `auto_commit 0`, validates scientific source/coordinate
policy and adopts the native result under its existing logical History boundary.
Workbench's existing user-facing Line tool creates one retained Path, deliberately
distinct from an independent consumer choosing the native two-point `line` family.

Preview first tries the cursor-extended native definition, then the valid placed
prefix. Invalid native proposals are not approximated. Escape discards staged
input/feedback, never scientific geometry. The controller stays available for the
next primitive after commit. A source generation change rejects old staged input.

## Topology

```tcl
$tools topology prepare operation nativeObjects ?options?
$tools topology state
$tools topology commit
$tools topology apply operation nativeObjects ?options?
$tools topology cancel
$tools topology connected nativeSeeds
```

Operations: `join_path`, `compound`, `separate`, `split_path`, `split_composition`
and `join_points`. Options: tolerance, index, target_index and merge, applicable
only to their native operation. Native typed source references are retained and
resolved again on commit. Native geometry, part IDs, intended direction and exact
constituents remain authoritative.

Join Path uses native connected-network validation; Compound preserves independent
constituents. Separate and Split create exact copies and preserve the source.
The consumer decides reviewed logical source consumption/ancestry and uses existing
native retarget/delete operations only after adopting the accepted result, with
its existing recovery/History boundary. `connected` checks actual native connected
retained eligibility; it does not invent topology from Viewer private records.

Join points is the distinct existing native coincidence/optional-merge operation,
using original native point indices, not sampled rendering ordinals or Tk IDs.
Use actual native selection/control queries to obtain these identities. It is not
an alias for Join Path. Unsupported rigid movement inside a Compound is not added;
use the supported Separate/Split workflow before independently editing a part.

## Defining controls

```tcl
$tools control inspect nativeObject
$tools control preview nativeReference nativeXY
$tools control edit nativeReference nativeXY
```

The existing Host pointer-drag lifecycle remains shared. This additive direct edit
route validates the native proposed definition before applying it and uses the
same admission/result hooks. True defining references, retained vertices, display
samples and canonical Dataset source rows remain different identities. Scientific
row conversion is explicit and remains the existing source owner's operation.

## Relationships, dimensions and embedded editors

The companion shared relationship/dimension component extends this same controller;
its exact operations, editor options and native reference/driving conventions are
documented in [NATIVE2D_CAD_TOOLS_RELATIONSHIPS_v1](NATIVE2D_CAD_TOOLS_RELATIONSHIPS_v1.md).
`driven=1` in Native2D
means a **reference** measurement; `driven=0` drives geometry where supported.
Consumers keep physical-unit/parameter interpretation with existing Unit Registry,
Dataset Coordinate and Parameter owners; incompatible metric proposals must be
rejected rather than silently normalized. Numerical parameters and visual
annotation placement are separate operations.

## Direction markers

```tcl
$tools direction get nativeObject partOrEmpty
$tools direction properties nativeObject partOrEmpty nativeChanges
$tools direction start nativeObject partOrEmpty
$tools direction move deviceXY
$tools direction state
$tools direction commit
$tools direction cancel
```

An empty part selects the main marker; a nonempty value is an actual native
constituent ID, including zero where valid. Native marker placement and component
direction operations own the position, orientation and intended direction. The
controller retains the native descriptor for cancellation, reports accepted
changes through the same domain lifecycle, and submits no History of its own.
Properties use the existing native descriptor fields for visibility, Flip and
style. Workbench retains logical target selection and its accepted History
boundary; it does not compute replacement arrow geometry.

## Disposal and compatibility

Cancel tools before replacing sources. Host association/detachment/disposal clears
staged tools/editor callbacks while preserving consumer-owned scientific geometry.
No background thread accesses Tk. Existing Workbench menus, native grid, axes,
Dataset/History/publication contracts and nonparticipating consumers remain intact.
An explicit `$host tool select` leaves a staged advanced tool even when the basic
tool was already Select; querying `$host tool` is read-only. The Host focuses its
Canvas on pointer-down before dispatching advanced input. Escape cancels both
staged advanced proposals and any overlapping owned navigation scope.
The independent executable consumer exercises this same Host/tools implementation
with its own toolbar and editor placement, public P017 History and no Workbench
imports. Human VNC acceptance remains separate from focused agent verification.
