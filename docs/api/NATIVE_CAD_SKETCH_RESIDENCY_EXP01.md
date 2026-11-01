# Native Sketch residency — experimental additive contract

**DEV111-P023-EXP01 — REVIEW ONLY. NOT FOR INSTALLATION. NOT ACCEPTED.**

SPDX-License-Identifier: GPL-3.0-or-later

This extends `NATIVE2D_API_v1`, the existing Native3D GUI Host surfaces, and
`INTERACTIVE_DOCUMENT_API_v1`. It does not introduce a scientific model, solver,
History service, renderer, or independent Canvas. The unchanged Native2D C kernel
owns definitions/constraints; P017 and Interactive Document own scientific
transactions/durability. Native3D's existing C ABI owns projection, picking,
depth, lighting, and rendering. The implementation is currently Linux x86-64.

## Consumer entrypoints

```tcl
set view [::GX::native3DViewportCreate .consumer.viewport]
::GX::native3DViewportBind $view {kind demo}
set surface [::GX::native3DViewportSurface $view]
set sketchView [::GX::nativeCadSketchSceneAttach $surface $documentId \
    [dict create working_unit mm edit_command [list MyViewer::enterSketch]]]
$sketchView show 1
```

`nativeCadSketchSceneAttach surface documentId ?options?` borrows an existing
public surface and binds a saved exact `gxtxt.native_cad_sketch.v1` Document. It
creates no new Canvas, scientific scene, solver, or History writer. Options are
`working_unit` (display conversion through Unit Registry) and `edit_command`
(a trusted Tcl command prefix). One shared display lease per Canvas batches
multiple Sketch admissions. Existing scene geometry and camera are retained.

The native display identity includes Session, Document, and owner generation.
Scientific revision/SHA admission is distinct from derived geometry SHA. A
History-only save can therefore update provenance without reparsing unchanged
native geometry. Resource handles contain no native addresses.

`nativeCadSketchSceneResolvePick surface nativePickReceipt` returns an empty
dictionary for unrelated geometry or a receipt containing `document_id`,
`generation`, `revision`, `sha256`, `display_part`, `binding`, and
`exact_subelement 0`. A preview cell is **not** a defining control, scientific
segment, constituent ID, or Dataset row. Enter the exact existing controller
before addressing those entities. Native3D's existing picking tolerance and
occlusion rules are unchanged.

## Binding methods

| Method | Meaning |
|---|---|
| `info` | Owner identity, geometry revision, visibility/edit state, pending/error state, surface; no scientific mutation. |
| `show ?boolean?` | Presentation visibility only; no Document or History step. |
| `ready` | Latest requested body is admitted in a completed native frame and compatible with active presentation quality. |
| `edit` | Checked exact read, owner/revision validation, then the consumer's `edit_command` callback. |
| `editing boolean` | Selects edit presentation policy; normally managed by the shared Sketch component. |
| `saved` | Rebinds to the current checked canonical preview after successful save; never saves science itself. |
| `detach` | Retires only this binding's owned display resource and releases its GUI lease. The Document survives. |
| `configure options` | Updates display unit or edit callback. Unit changes refresh derived display through Unit Registry. |

The edit callback receives `{document_id generation revision}`. It decides
layout and domain admission and normally calls the existing
`nativeCadSketchCreate parent {document_id ... viewport ... working_unit ...}`.
That component retains Native2D, P017, save/cancel, guards, and source policies.
Closing it unbinds input/overlays and destroys its transient solver scene;
recent verified payloads and independently derived native curves remain usable.
No raw solver or History handles are cached across editor destruction.

For a custom authoritative CORE controller, `requestUpdate model authority stamp`
queues an immutable **derived** display proposal. `authority` is a valid public
Native3D geometry-context token, not an address; `stamp` is a bounded opaque
generation supplied by the owning controller. The latest proposal is prepared
when the existing transport is free. Superseded display proposals may coalesce;
scientific operations and History never do. `update` is the corresponding
synchronous admission operation for a quiescent transport. Neither operation
applies mathematical edits or persists the supplied model.

Callbacks and all Tk operations run on the Tk thread. Asynchronous display
failure cannot roll back an already accepted Native2D/P017 mutation. Consult
`info pending/update_error`, surface `resourcesInfo`, and component
`renderer_error`; retain the existing overlay and canonical save capability.

## Native presentation and quality

The bridge retains public Native3D C objects backed by bounded polydata. It uses
`gx3de_scientific_create_polydata`, existing object/style/visibility/destruction
APIs, the existing target, and its unchanged rasterizer. Camera commands do not
regenerate the scientific graph or retransmit those descriptors. A full owning
scene reset replays disposable descriptors into the replacement native scene.

Ordinary curves have genuine scene depth/occlusion. Grid, controls, selection,
snap indicators, arrows, dimensions, and proposals remain deliberate editing
overlays on the **same** Canvas. An active drag can temporarily hide the native
body while showing its genuine Native2D preview. The overlay remains until the
matching native body frame is confirmed, preventing an unpainted handoff.

Preview geometry comes from the existing Native2D full-bounds LOD service at
16384 virtual pixels, at most65536 points/object. Polyline corners are retained.
Assets carry their resolution. Active views exceeding that resolution use the
existing camera-adaptive Native2D presentation rather than silently lowering
editing fidelity. Closed display remains an explicitly bounded preview.

The protected Native3D style ABI does not express all 2D dash/marker forms.
Such active Sketches use the existing overlay for faithful styles; their active
body consequently has overlay depth. Closed previews retain P022's solid native
fallback. This limitation is explicit; no new renderer or speculative engine
extension is introduced.

## Quick-open descriptors

Public operations:

```tcl
::GX::nativeCadSketchQuickOpenList $documentIds ?targetUnit? ?rebuildBoolean?
::GX::nativeCadSketchQuickOpenPresentation $documentId ?targetUnit?
::GX::nativeCadSketchQuickOpenPublish $documentId ?savedPayload? ?targetUnit?
::GX::nativeCadSketchQuickOpenStatus
```

`List` batches canonical metadata/file-identity checks and reads the disposable
index once. With rebuilding disabled, missing entries return `unavailable 1`.
`Presentation` verifies the selected asset SHA and provides ready world-space
layers. A stale, absent, malformed, or corrupt index/asset is rebuilt from a
checked exact read, or uses the established verified display fallback. Omitting
the target unit means the original Sketch unit, not an arbitrary cached unit.

Canonical creation/update succeeds **before** optional derived publication.
Publication failure records `last_error` and cannot undo that save. Supplied
payloads must equal the checked saved payload. Descriptors are data, never Tcl
scripts, solver inputs, or an alternative scientific authority.

The versioned descriptor carries source owner/generation/revision/SHA, native
file identity, schema, plane/normalized frame, source/display units, local
bounds, object/relationship counts, display resolution, style fallback policy,
asset identity/SHA/size, and its own checksum. It contains no exact model or
History. Atomic replacement is used for index/assets; no durability promise is
made for disposable caches. Interrupted publication or eviction falls back to
canonical authority. A bounded nonblocking lock distinguishes live and abandoned
publishers by PID/start tick/boot ID; scientific workloads never wait for it.

Cache storage is under the configured CORE cache directory, scoped by canonical
Session directory identity. It is observed by existing resource management as
`cache_reusable`, with no scientific recovery obligation. The owner bounds its
managed asset set at128 MiB /512 assets per Session. Source paths, file handles,
and cache filenames are not public Viewer inputs.

## Budgets, invalidation, and lifecycle

- Checked exact payload cache:8 MiB /128 entries by default; configurable through
  the existing Document family. LRU eviction releases bytes, not science.
- The native capture path is bounded at64 MiB; larger valid Documents use the
  unchanged explicit reader. Explicit `interactiveDocumentRead` still verifies
  SHA on every call. Cached warm reads check complete native file identity,
  including nanosecond mtime/ctime, before reusing verified bytes.
- One display entry is bounded at32 MiB, a shared display lease at64 MiB. Native
  scene admission additionally caps512 resources,4096 layers, and one million
  presentation points. Temporary staging and Tk/VTK allocations are additional
  to descriptor accounting; these are not claims of total RSS/GPU measurement.
- Geometry SHA, scientific revision, projection frame, and worker generation
  are distinct. Selection/camera changes do not create scientific revisions.
- Session switch, deletion, owner replacement, Canvas destruction, or explicit
  detach invalidates the corresponding leases. Pending removals are drained or
  cancelled when their native owner ends. No callback retains a dead editor.
- Renderer/device rebind invalidates stale native surface references. Closed
  presentations can be attached again from checked cache data. Automatic
  recovery of an **unsaved active solver/History context** across a worker/device
  restart is not promised by this prototype; do not discard its exact state.

The independent executable consumer and actual-input tests are in
`validation/dev111_p023_exp01/`; they import no Workbench private runtime.
This Tcl public draft is not an arbitrary-evaluation bridge for the C++ Viewer
SDK. Existing authored TEST CAD1/2 consumers continue through their admitted
shared component path; any later SDK exposure must remain typed and reviewed.

## Shared stock icons (additive existing GUI Host resource operation)

`viewerGuiStockIcons ids sizes` returns admitted assets for1..64 distinct fixed
CORE catalog IDs and warms their exact existing Tk photo cache at1..4 sizes
(8..192 pixels). It grants no arbitrary resource path. The same SVG admission,
PNG validation, provenance and two-stage raster pipeline are used; individual
public operations remain compatible. The CAD menu uses this bounded batch to
avoid repeated Python startup. Representative old/new display PNG bytes are
identical in the independent contract; this is not a new icon catalog or theme.
