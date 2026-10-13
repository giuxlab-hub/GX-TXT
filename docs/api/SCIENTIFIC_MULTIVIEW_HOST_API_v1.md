# CORE Scientific Multiview Host API v1 — dev075

An optional Tk coordinator for genuine Native2D and isolated Native3D viewports.
It reuses CORE's retained presentation, calibrated raster worker, ViewportHost,
Native3D renderer worker, camera/pick protocol and document lifecycle subscriptions.
`VIEWER_PROVIDER_API_v1` open/rerender behavior and all existing plugins are unchanged.

## Public Tcl contract

All commands are in `::GX`. `scientificMultiviewHostCapabilities` is headless-safe;
create/attach/interaction require a real Tk desktop. No GUI is promised through the
headless Script Bridge. A host creates widgets under the supplied parent, which may
be a notebook page, and supports up to four slots and sixteen concurrent hosts.

| Command | Contract |
| --- | --- |
| `scientificMultiviewHostCreate parent document ?options?` | Returns an opaque host; binds Session, document generation/revision. Options: `layout horizontal|vertical`, trusted `selection_command`, trusted `refresh_command`. |
| `scientificMultiviewHostAttach host slot native2d options` | `scene_token`, optional `owned 0|1`, `title`. Independent scene instance required, bound to the host document. Reuses CORE Native presentation and raster overlay. |
| `scientificMultiviewHostAttach host slot native3d options` | `layers`, optional `title`. Opens an independent existing read-only renderer worker for that viewport; imports validated target-owned managed resources. |
| `scientificMultiviewHostBindIdentity host map ?frames?` | `logicalId {slot objectHandleOrLayerId ...}`. Validates actual objects/layers and common declared coordinate units. Frames are declarations, not guessed transforms. |
| `scientificMultiviewHostSetSelection host logicalIds ?origin?` | Reversible selection, no scientific writes. Returns logical IDs, unmapped IDs, origin, revision, epoch; synchronous echoes are suppressed. |
| `scientificMultiviewHostModelChanged host revision changedIds reason` | Validates authoritative revision, invalidates old work, and invokes the explicit refresh procedure. Same revision returns `refreshed 0`. No procedure returns `regeneration_unavailable` and disables obsolete rendering/mapping. |
| `scientificMultiviewHostConfigure host options` | `layout`, `order` naming every attached slot once. Preserves widgets, workers and cameras across layout/reorder/tab/resize. |
| `scientificMultiviewHostInfo host` | Instance state and actual backend status/receipts, without channels/paths/images. |
| `scientificMultiviewHostDestroy host` | Idempotent cleanup; cancels timers, removes subscriptions, stops workers, releases owned scenes/images/staged resources/widgets. |

Native2D: fit, zoom, middle-drag pan and exact Native picking for explicitly mapped
objects. Native3D: orbit with left drag, middle-drag pan, wheel zoom, fit/front/iso
presets and layer-level picking. Native3D cells are never treated as scientific
identity. One layer can map to more than one logical ID; its pick selects those
explicitly associated IDs. Unmapped IDs are reported. There is no raw VTK widget
embedding, independent geometry model, arbitrary gesture promise or global event bus.

Native3D layer descriptors are `{resource REF unit mm representation surface color
{.2 .5 .8} derivation DESCRIPTION}`. Formats: managed `native3d.vtp.v1`,
`native3d.stl.v1`, `native3d.step.v1`; default color/representation are supplied.
Declared units are required. STEP actual normalized unit exposure retains the
existing CORE limitation; callers must not mistake their declaration for an OCCT
measurement. Up to 64 layers, 64 MiB each and 256 MiB staged at once; obsolete
staged files are removed after their render returns. Renderer AS budget reuses
existing configuration. Each worker owns its own scene and camera. The adapter uses
the established Software policy for this embedded path, preserving existing full
Viewer/hardware policy. Native failure is reported without touching the document.

## Owner-authorized model updates

The host never grants write permission. Editing uses the document owner's existing
transactions. An accepted commit yields a revision; only then call `ModelChanged`.
A trusted `refresh_command ownerMetadata changedIds reason` returns:

```tcl
dict create views [dict create \
    image [dict create scene_token $new2d] \
    surface [dict create layers $explicitlyGenerated3dLayers]] \
    mapping [dict create $logicalId [dict create image $handle surface curveLayer]]
```

The owner adapter explicitly defines how to derive 3D geometry, creates resources
under that document, and restores exact 2D definitions. It owns failure cleanup for
its preparation. CORE switches bindings, closes replaced owned scenes, and refreshes
only supplied slots. Omitted/failed slots stay disabled with an honest status; an
old geometry image cannot acquire the new model epoch. A cancelled owner edit has
no commit and requires no scientific refresh. Pure view/camera changes never rebuild
the model or publish a Dataset. Refresh callbacks can be costly; this v1 contract
is synchronous for owner preparation, while drawing and 3D rendering are scheduled.

Resize/layout requests debounce for 35 ms. Each viewport has one in-flight worker
request plus a replaceable latest request; responses carry the recorded model epoch.
Document deletion, owner replacement, Session switch or widget destruction invalidates
the host. Late worker images are rejected, including across actual model commits.
The existing document lifecycle watcher bounds automatic invalidation to its 250 ms
poll/idle delivery; explicit destroy is immediate. An existing resource changed
outside its authority requires an explicit refresh and will fail integrity validation
when reattached; there is no invented external Dataset subscription.

## Example

```tcl
set h [::GX::scientificMultiviewHostCreate .viewer.content $doc \
    [dict create refresh_command ::MyModule::refresh]]
::GX::scientificMultiviewHostAttach $h image native2d \
    [dict create scene_token $retainedScene owned 1]
::GX::scientificMultiviewHostAttach $h surface native3d \
    [dict create layers $managedLayers]
::GX::scientificMultiviewHostBindIdentity $h \
    [dict create $localId [dict create image $objectToken surface curve]]
```

`validation/core_foundation_dev075/multiview.tcl` is an independent desktop fixture,
not a SEM product. It uses an unchanged Workbench saved model, exchanged exact
Bezier/line, a calibrated image, and a labelled sampled surface obtained by explicit
2 mm extrusion. The surface is a derived approximation, never the exact source.
Real X mouse input, actual Native camera/picking, two hosts, owner dimension edits,
stale-frame rejection, resize/reorder/tab, unavailable backend and process cleanup
are tested on Linux Xorg at 1366×768 and 1920×1080.

## Dev076 delayed owner revision response

A response delivered after an owner commit, before its explicit `ModelChanged`, is
rejected as stale. The host, other views, camera and worker remain available;
`status model_refresh_required` records the pending revision. Stale picks never update
selection, and queued requests for the old revision are cleared. The stored host
revision remains unchanged until the existing owner refresh contract is invoked.
Session expiry, document deletion/replacement and explicit destruction still dispose
owned resources. Worker READY during this interval records readiness but schedules no
obsolete render. Public signatures and model editing authority are unchanged.

## Dev088 durable element correspondence

A Native3D mapping value may now be `{layer_id L association point|cell logical_id N}`
instead of the historical bare layer ID. N resolves the retained scientific array
`logical_point_id` or `logical_cell_id`, exact integer0..2^53-1. Mapping validation
requires an existing layer and common explicit physical units. A real Native3D pick
returns the source logical ID and selects only matching explicit references, so100
features in one scientific layer do not need100 rendering layers. A mapping to a
Native2D object remains its owned object token. No transient renderer index is stored
as identity. Lossless VTP preserves the arrays used to resolve fresh renderer indices.

2D selection highlights the mapped object; 3D element selection focuses a native
anchor at the logical point or cell's vertex centroid. Multiple selected IDs are
retained by the coordinator; the last mapped 3D element is the focus marker. This
is not a filled per-cell selection overlay. Bare layer mappings keep their former
whole-layer color behavior. Owner generation/revision/epoch invalidation still applies.
