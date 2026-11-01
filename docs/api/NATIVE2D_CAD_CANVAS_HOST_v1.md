# Embedded CAD Canvas Host — NATIVE2D_API_v1 (DEV111-P018)

This additive GUI host composes the existing native C++ CAD controller, Native2D
ViewportHost, P014 grid, P016 scientific sprite synchronization and public GUI
scheduler. Native2D C remains the geometry, selection, snapping, constraints and
transaction authority. This is an optional host, not another scientific engine.
Discover Create/Attach with `::GX::native2DCadApiInfo`.

## Embed or attach

```tcl
set host [::GX::native2DCadCanvasCreate parent nativeScene ?options?]
pack [$host canvas] -fill both -expand 1   ;# consumer chooses geometry manager
set host [::GX::native2DCadCanvasAttach existingCanvas nativeScene ?options?]
$host context                            ;# existing native C++ CAD command
$host canvas
$host state
$host associate nativeScene ?options?
$host configure ?options?
$host detach
$host dispose
```

Create makes one child Canvas; neither operation creates a toplevel, toolbar,
inspector, mandatory panel or scientific scene. Attach reuses an existing host
and ViewportHost. Both accept an existing native scene ID, never an address or a
Document-scoped geometry token. `context` can adopt an existing public CAD
controller over that scene; `selection` can adopt its native selection set.
These two options are accepted on Create/Attach/associate only. An adopted context
or set is not destroyed by the host. A context created by the host is disposed on
source replacement/detachment. Scientific geometry is always consumer-owned.

Destroying the Canvas disposes the host, pending scheduler work, owned interaction
context and presentation resources. Explicit `dispose` detaches without destroying
the consumer's widget or scientific scene. `detach` cancels interaction and releases
the context; `associate` permits reuse. Source destruction revokes native references;
future input returns a rejection receipt. Invalid association/configuration is
validated before replacing the current context. Reassociation increments the host
generation. Consumers must provide a guard for their Session/Document lifetime.

Options (dictionary):

| Option | Default | Meaning |
|---|---|---|
| `bind_events` | 1 | Install host-owned bindtag for pointer, Escape/Return, wheel and resize |
| `advanced_dispatch` | 1 | Dispatch the same Host's optional advanced-tools controller before basic input |
| `external_render` | 0 | With 1, the mandatory `refresh` callback owns redraw scheduling/rendering |
| `selection_target` | `local` | Existing native `local`, `detail` or `object` picking |
| `object_snap` | 0 | Enable existing native object snapping in manipulation proposals |
| `tolerance_px` | 9 | Native pick tolerance, positive and at most256 pixels |
| `callbacks` | empty | Command-prefix dictionary below; all run on the Tk thread |

Attach to a Viewer with existing advanced input priorities using `bind_events 0`,
then explicitly route the admitted events. Attach with `external_render 1` to keep
its established rendering callback and scheduler: the host creates no second queue.
Without external rendering the host uses the shared scheduler (normal16ms, global
configured adaptive profile), retained Cairo/grid presentation and transient CAD
selection/gizmo overlays. It replaces its transient items each frame. It does not
reconstruct authoritative geometry or cache scientific state privately.
P019 adds `$host advanced`: the same owned, lazily created controller provides
[shared advanced construction, topology, controls and direction tools](NATIVE2D_ADVANCED_CAD_TOOLS_v1.md)
and [constraints, dimensions and configurable editors](NATIVE2D_CAD_TOOLS_RELATIONSHIPS_v1.md).
Retrieval is read-only and requires a live context/widget; mutations retain domain
admission. A consumer with established input priorities can set `advanced_dispatch 0`
and call these public tools explicitly. Workbench uses that route to preserve its
scientific input priority, logical adoption and P017 History boundaries.

## Tools, selection, navigation and dispatch

```tcl
$host tool ?select|rectangle|polygon|translate|rotate|pivot|mirror|pan?
$host tools ?enabledList?
$host pick deviceXY ?detail|local|object?
$host select nativeMembers ?replace|add|subtract? ?nativeReference?
$host activate objectIds
$host begin operation deviceXY objectIds ?nativeHandle? ?nativeReference?
$host event down x y modifierState
$host event move x y ?modifierState?
$host event up x y ?modifierState?
$host event key Escape|Return
$host event wheel x y signedDelta
$host event pan_start|pan_move|pan_end x y ?modifierState?
$host event resize
$host cancel ?reason?
$host refresh ?reason?
$host overlays
$host render
$host fit ?selectedBoolean?
```

`tools` lists admitted capabilities: select, rectangle, polygon, translate, rotate,
pivot, mirror, pan, control, points, zoom, fit. Controls and points are selectable
native defining entities, not sampled curve points. `begin` supports control,
points, translate, rotate, pivot and mirror using native references/handles from
the CAD controller. Prefer normal `event` dispatch for ordinary input. Scope and
member/target lists are bounded to65536; pointer coordinates must be finite and
bounded to1e12. Native entity records and proposal schemas are unchanged from
[NATIVE2D_CAD_CONTROLLER_v1](NATIVE2D_CAD_CONTROLLER_v1.md).

Default bindings: Control adds selection; Shift subtracts; rectangle is a drag;
polygon accepts successive world vertices and Return completes it; Escape cancels.
Native hit-testing/selection handles whole objects, segments and supported native
points/controls. Constituents keep their existing component references; this host
makes no promise of unsupported in-place compound constituent editing. Use existing
public component/Split/Separate owners where required. Advanced construction,
constraints and dimensions use the additive P019 controller in this same context.
Ordinary Motion supplies staged hover previews, B1-Motion supplies drag updates,
and pointer-down focuses the Canvas before an advanced tool consumes the event.
Unhandled ordinary Motion continues through the consumer's existing bindtags
(for example a coordinate readout); consumed CAD previews retain input ownership.
Explicitly selecting a basic tool cancels staged advanced input, including when
the basic tool name is unchanged. Escape cancels every owned staged/navigation
scope; neither cancellation nor presentation submits a scientific History edit.

Move/Rotate use the existing native gizmo and its pivot. Admission runs at begin,
plan before apply, and commit. Native C++ begin/plan/apply/commit/cancel is the sole
transaction sequence. Defining-control preview obtains a native proposed definition
without mutating the committed control; release applies the native edit. Failed
native validation cancels/restores using existing C semantics. Escape changes
neither committed geometry nor History. Pivot changes can be recorded by the
consumer's normal History owner. Native navigation, zoom factors and pointer
anchoring remain unchanged. Pan/zoom never create scientific edit History steps.

`state` returns api_id, canvas, scene, context, attached, generation, tool,
enabled_tools, active, gesture, polygon and receipt. Input dispatch rejects
reentrancy. A handled or rejected input returns1; unsupported keys/resize return0.
On failure `receipt` has `status rejected`, `error` and `errorcode`; an optional
error callback presents it. Direct configuration/query methods raise Tcl errors.
Do not infer success from the dispatch return value alone: inspect the receipt
and actual native state. Successful commits include the domain receipt.

## Domain callbacks

Each prefix receives one dictionary. Common keys: `host`, `canvas`, `scene`,
`generation`, `phase`. Gesture dictionaries add `operation`, native `objects`,
`handle`, `reference`, `device`; later phases add opaque `context`, `changed`,
`proposal` and/or native proposed `definition`/`target`. No callback runs from a
worker or receives raw addresses. Do not reenter input or replace a source inside
an input callback. Keep callbacks bounded and use the established domain owners.

| Callback | Contract |
|---|---|
| `guard` | Boolean live Session/Document/source check; false rejects stale input and pending presentation |
| `scope` | Return eligible native object IDs (default existing scene IDs) |
| `targets` | Return admitted native manipulation targets (default native selected objects) |
| `admit` | Boolean or error at begin/plan/commit, before corresponding mutation; validate units, readonly/domain rules |
| `begin` | Capture domain rollback/History state and return opaque token ≤256 characters; keep snapshots in the domain owner |
| `selected` | Receive authoritative `selection` snapshot and optional reference; update domain tables/active logical identity |
| `preview` | Present proposed native defining-control geometry; never promote samples to canonical data |
| `committed` | Native operation succeeded; synchronize domain records and submit exactly one accepted change to public P017 History; return its receipt |
| `cancelled` | Release domain preview/frozen controls; `reason` identifies Escape/rejection/source change/disposal |
| `rollback` | Restore the domain's captured scientific snapshot if its post-native commit/History hook fails |
| `refresh` | Required for external rendering; receives reason and final boolean, delegates existing redraw owner |
| `navigation` | changed/finished navigation notification, e.g. existing deferred viewport persistence |
| `error` | Rejection receipt for the consumer's inline status/error presentation |
| `presentation` | Default renderer only: optional `plans` axis dictionary and sprite `descriptors` using existing public schemas |

A callback cannot transfer scientific ownership to the host. In particular, a
consumer with heterogeneous physical axes must admit componentwise movement in
its declared coordinate frame and reject metric rotation/constraints unless an
explicit normalized Euclidean frame exists. Numeric defaults are suitable for a
dimensionless independent fixture, not automatic scientific unit conversion.
Scientific axes/units are supplied through existing axis-plan services and the
presentation callback or existing Viewer renderer.

History is optional and remains owned by P017. Register the scientific owner and
attach `scientificHistoryContextAttach` callbacks, then submit accepted mutations
from `committed`. The host holds no second History or Workspace representation.
Source Dataset IDs, original row identities, publication and read-only policies
remain the consumer's responsibility through public Dataset/Curve Source services.

## Minimal independent consumer

```tcl
frame .domain
pack .domain -fill both -expand 1
::GX::native2DEnsure
set scene [::GX::Native2D::core scene]
set host [::GX::native2DCadCanvasCreate .domain $scene]
pack [$host canvas] -fill both -expand 1
# Create scientific geometry with existing public Native2D operations.
ttk::button .move -text Move -command [list $host tool translate]
pack .move -side top
$host fit
# When the domain closes: $host dispose; destroy .domain
# Destroy the scientific scene only when its scientific owner chooses to.
```

`validation/dev111_p018/independent.tcl` is a real executable public CORE consumer
with an external toolbar, real XTEST selection/Translate/Rotate/control editing,
region selection, cancellation, P017 Undo/Redo and source/widget cleanup. It loads
no Curve Workbench files. The production Workbench attaches the same Host class
and adopted native controller, retaining only logical/scientific domain callbacks.

## Target synchronization during redraw (P019)

`$host targetsMutable` and `state.target_flags_mutable` report whether the native
CAD target flags may be synchronized. This requires no Host-owned gesture, no
adopted C++ gesture and no native scientific drag. Pan and control previews can
own the Host while the C drag flag is false. Render callbacks must defer target
activation while this value is false; render the current authoritative selection
instead. Once the owning gesture commits/cancels, the next ordinary refresh may
synchronize targets. `activate` continues to reject violations; no native guard
or transaction flag is cleared to permit a redraw.
