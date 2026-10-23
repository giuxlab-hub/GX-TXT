# Native3D GUI Host API v1

SPDX-License-Identifier: GPL-3.0-or-later

The existing Engine3D controls, renderer worker, IPC, progress/cancellation,
graphics policy and navigation implementation live in the shared CORE host
`core/tcl/native3d_gui_host_v1.tcl`. The generic Viewer's runtime entrypoint delegates to it. `native3DGuiHostApiInfo` describes its public scope.

`Engine3D::configureHost module_id viewer_id callbacks` selects a registered view
provider and accepts `panel` and `close` callback prefixes. All scene/layer,
attribute, navigation and persistence operations use the selected provider's
identity. Switching providers closes the prior host and its owned worker;
changing host identity during an active worker request fails explicitly.
`Engine3D::backend`, `panel`, `rpc` and `close` preserve the existing generic
Viewer workflow. This shared infrastructure does not by itself implement CAD
editing or imply 3D Workbench acceptance.


## Gestures and canonical geometry intake

Native3D gesture cancellation is coalesced until the worker is idle, ends the native gizmo/plane transaction before preview rebuild, and checks worker/session/gesture generations. Generic Dataset intake recognizes `geometry.mesh`/`model.cad` complete payloads before point/trajectory bindings, disables irrelevant table fields and retains real Dataset ID/SHA/units. Read-only `gizmo_pick` reuses the existing public native controller query; it does not mutate selection or geometry.

Embedded hosts route Escape through the actual toplevel, scoped to descendants
of the current Native3D host. Tk does not include ancestor frames in child
keyboard bindtags. Mount/suspend/close removes only this owner's handler and
preserves other toplevel bindings; newly created descendants need no copied
bindings. Repeated Escape retains the first pending rollback transaction.
Final update/end RPC replies are checked against the captured gesture, worker
and Session before any scientific edit. Cancellation during native end
refreshes retained authority without ending that completed native transaction
twice. Closed-owner error cleanup cannot reopen rendering. An unchanged
manipulator matrix does not create a geometry edit or History entry.

## Read-only embedded preview

`native3DPreviewAcquire parent datasetId sourceKey checkCommand prepareCommand
?options?` and `native3DPreviewRelease parent` extend the existing Dataset Native3D
host, rather than creating a renderer/worker/scene authority. Preparation supplies
existing Native layers and a view; host-only `tools_y` may avoid other container
controls. Two retained owners share the same host dictionary and DatasetViewer
state/lifecycle. `native3DPreviewXYZActivate` and `native3DPreviewPlotActivate` are
application entry points. There is no Script Bridge publication action.

The transport adds `compact` rendering (native cube disabled), `camera cameraDict
png` (existing native camera set/render; captured initial state), optional direct
`color_array` and `sphere_glyphs=0` roles backed by existing native ABI operations.
These are read/render operations accepted by the isolated readonly worker. Existing
preview/full stages and structural sphere defaults retain their behavior. Native
kernel/library ABI is unchanged. The same camera state and RAM photo survive tab
unmapping. Details/bounds/unsupported axes are in the shared preview guide.


## Scientific figure consultation and export

`native3DPreviewAcquire` retains its existing shared DatasetViewer host/worker and
RAM frame. Plots' eligibility control is a placed canvas child, with no layout row;
`PLOT_DATASET_API_v3.previewCompatibility ref` gates supported prepared XYZ Variants.
No persistent Viewer Document is needed. Ordinary 2D/static double-click is unchanged.
The compact controls provide orbit left/right/up/down, native camera roll clockwise/
counterclockwise, exact reset, Exit and a presentation-only scientific axes/grid toggle.

`::GX::native3DPreviewEnlarge host` moves the shared consultation into a resizable
independent Tk window. It reuses the same prepared VTP/native objects/worker/camera.
Resize uses the existing native target/viewport APIs; no Dataset reload or Octave
preparation occurs. Closing returns the synchronized camera to the embedded host.
The frame remains cached across unchanged tabs. Source/Session guards and cancellation
remain authoritative. Destroying the original owner closes enlarged/export resources.

Only explicit Render & Publish in Save High-Resolution Image creates a Dataset.
Full HD (1920×1080) and 4K (3840×2160) use native offscreen rendering and the current
CORE graphics export-supersampling policy; intermediate pixel/GPU/worker budgets apply.
The PNG includes the current geometry, calibrated axes/grid when enabled, original
scalar-bar palette/limits/label when present, compatible title/legend and opaque
background. No Tk screenshot enlargement. Existing IDs are rejected; no replacement.
CORE `DATASET_FILE_PUBLICATION_API_v1` publishes `image.raster`, binary PNG/image/png
transactionally and verifies SHA-256. Structured metadata retains graph/Variant identity,
source IDs/digests/bindings, exact camera/projection, dimensions, figure calibration,
scalar palette/limits and graphics settings. The normal Dataset GUI lists/reopens it.

Calibrated axes use linear increasing displayed scientific ranges mapped to effective
aspect-scaled world bounds. Original units/labels and scalar mapping are retained.
The native cube axes follow projection, orbit and roll, with camera-calibrated label
margins. Flat source surfaces retain constant per-cell RGB on both triangles of each
original quad; interpolated source colors remain interpolated. No scientific smoothing.
Ticks/grid/font layout follows Native3D's scientific presentation rather than Octave's
pixel layout. Logarithmic/reversed axes still require a nonlinear calibrated coordinate
mapping contract and are rejected, never labeled as linear. Other providers/base graphs
need an exact prepared-scene identity API. Transparent figure backgrounds remain unsupported.

## Layer presentation and planar integration

Modern `viewer.engine_3d` hosts the integrated working-plane dialog and uses existing
Curve Workbench. `viewer.native_3d` is historical/deprecated, retained for compatibility.
`Engine3D::setLayerPresentation layer fields` filters unchanged fields; changes limited
to visibility, opacity, base color, line width and point size use the selective native
object presentation operation. Unrelated native mappers, camera, selection and worker
remain; no scientific Document checkpoint is made. Unsupported volume/texture/repeat
selective presentations return explicit errors and restore metadata; use the existing
full scene refresh for representation changes. Numerical renderer counters verify that
ordinary selective updates do not increment whole-scene geometry rebuilds.

Depth peeling with translucent props uses effective MSAA0 because VTK's multisampled
render target can omit translucent props. Requested MSAA remains for opaque scenes;
the native diagnostics state the effective policy. Transparent mesh/plane behavior is
tested on llvmpipe. This does not add transparent scientific-image background support.

## Editable host in an arbitrary Tk container

`native3DGuiHostMount parent module_id viewer_id ?callbacks?` mounts the existing
editable Engine3D controls and native image viewport as a real child frame of
`parent`. Pack/grid the returned frame in the caller. The same registered
provider, Scene/Layer state, native worker, renderer, camera, picking, manipulator
and optional editing callbacks remain authoritative. A mount does not create
another scene/controller/worker. Only one editable host is active. Moving the
same owner between frames changes widgets; changing providers follows the normal
explicit close/cleanup contract. Finish or cancel active requests/gestures first.

Callbacks are the existing `panel`, `close`, `edit` and `selection` prefixes.
The caller must supply its actual registered provider adapter, not claim that
read-only Dataset Multiview is an editable CAD host. Workbench3D uses its existing
real geometry/edit/History implementation in either host. Destroying the mounted
parent closes the owned worker, photos and editing adapter through existing close.
The host renders at the actual bounded canvas size (160..4096 by120..4096 pixels),
coalescing resize through its existing request controller.

`native3DGuiHostSuspend` removes only the host widgets, retaining the existing
Scene, native worker, camera, photo, selection and callbacks. It returns a transient
`NATIVE_3D_GUI_HOST_STATE_v1` receipt. A caller may show an ordinary2D consultation
in the vacant parent. `native3DGuiHostResume parent receipt` recreates the same
editable host and consumes the receipt generation. Session change, worker/owner
replacement, changed suspended view or repeated receipt use is rejected. Receipts
contain UI lifetime state only; do not serialize them as scientific Workspaces.
Use the normal close operation if the suspended controller is no longer needed.

A retained2D edit returns to its originating3D Workspace through the guarded
[planar return contract](NATIVE_3D_PLANAR_RETURN_v1.md). Planar extraction and
originating Workspace commit are distinct owner transactions.

## Managed planar RGBA appearance

The existing layer's optional `texture` field is persisted through the same
manifest. `native3DLayerTextureAnchor`, `native3DLayerTextureBind` and
`native3DLayerTextureValidate` expose managed resource validation and actual
source-face mapping through the installed native texture engine. See the
[complete current contract](NATIVE3D_MANAGED_TEXTURE_v1.md) for units, source
geometry guards, transparent pixels, native picking, ownership and limitations.

### Responsive embedded view controls (dev109)

The existing Native3D host provides a normal **Show/Hide view controls** button.
An embedded host automatically hides its secondary controls below 760 logical
pixels of available host width, leaving the scientific canvas visible. Wider
embedded hosts allocate 200–360 pixels to that sidebar; the full controls
remain accessible through its existing scrolled container with horizontal
scrolling. A manual toggle overrides automatic visibility until a fresh mount.
Standalone controls retain their original 460-pixel width. Mount, suspend and
close retain their existing scientific ownership and cancel pending layout
callbacks. No camera, geometry, worker or graphics-quality setting changes.

The sidebar's scrollable content also respects the controls' natural requested
width. Increasing the GUI font can therefore enlarge the content without
widening the bounded viewport or clipping a button within its own frame. The
existing horizontal scrollbar reaches that complete content. Content/font and
viewport size changes update the same scroll region; commands, fonts and
scientific state are unchanged.

The typed mapped-host contract verifies 950×650 and 1380×900 outer clients,
manual show/hide, suspend/resume, automatic narrow resize and cleanup against
an unchanged copied scientific Session. Actual installed pointer/keyboard
acceptance and narrow screenshots are additional required evidence.

A successful native pick now invalidates the existing host's retained display
frame after installing the actual source anchor. The same viewport painter
refreshes it before returning to ordinary interaction, even if canvas size is
unchanged. A busy renderer defers through the existing resize drain; close
clears the pending display state. Source geometry, worker generation and
scientific History are unchanged. This reuses the current cache PNG filename:
content/frame state, rather than filename uniqueness, demonstrates the refresh.
The typed original-box/cylinder contract verifies two different immediate
frames at unchanged 404×712 dimensions using one worker generation; actual
installed cold retesting remains required. Failed test01/02 filename oracles
are preserved with their actual changed-frame observations.

## Scientific animation video adapter (dev111 source implementation)

The existing Scientific timeline group adds **Export scientific animation/video…**.
It uses the separately owned trusted-host `native3DAnimationDescribe` and
`native3DAnimationExportAsync` routes when present. A missing route is an explicit
unavailable diagnostic. The dialog selects an inclusive original sample range,
even pixel resolution, rational FPS or playback duration, bounded quality and a
new external MP4 destination. One video frame corresponds to one original sample;
video playback time is distinct from declared scientific time, especially for
nonuniform samples. The MP4 is a presentation derivative, never a canonical
Dataset. Source data and live timeline position are not changed.

The private `_native3DAnimationDescribeSource` seam returns `description` and
`expected_source`. It reads only bounded existing public registry projections,
including unsaved view/layer state and declared Dataset variable metadata. It
first requires an enabled registered module and Viewer Provider through their
existing public owners, and uses the existing plugin new-load guard to reject
pending replacement/restart state without activating an entrypoint. The private
snapshot binds the bounded declared module definition/version and logical
provider definition; the worker compares that identity before/after capture.
The public description reports the declared module version, without inferring
an active implementation version. Source rechecks therefore also reject a
changed definition/version or a disabled owner.
It does not read scientific payloads, hash files, enrich schemas, probe native
rendering, copy or launch work. The full private projection is capped at 1 MiB;
the initial limits are 256 scene layers and 256 variables per Dataset. The
public facade returns only its inert description and reports runtime admission
as not checked. No Script Bridge, C++ SDK or worker opcode grant is added.

`_native3DAnimationCaptureSource` runs only in the owned headless worker. It
reconstructs unsaved view/layers in that process through existing public setters,
resolves actual supported sources and prepares existing native renderer inputs.
It never saves the original Session. Captured source copies use the existing
FilePublication complete-file owner within the allocated operation Resource;
total input bytes are bounded to 256 MiB. Registered metadata, existing Dataset
revision tokens and every original dependency are checked around capture.
Private paths/revision tokens stay in the worker, outside public receipts.
Original identity and render input copies remain distinct.

This first export slice captures base Viewer scenes only. The editable Engine3D
host may add an active ScientificDocument's scientific figure after ordinary
scene resolution; Describe explicitly refuses that presentation for the matching
host owner, including a stale/missing document Session identity. It does not read
the document, omit its figure silently or promise Document-backed video capture.
Private source identity also binds that matching host's presentation-open and
mount generations. Switching into/out of Document mode, reopening, closing or
rebinding during capture therefore invalidates the parent's later source check,
even when the base scene projection happens to return to the same values. An
unrelated host owner does not turn another provider's base scene into a Document
presentation. The isolated worker does not recreate a GUI incarnation; the
parent's existing current-source gate compares this private context.

The retained source receipt includes `dataset_identities`, keyed by actual
Dataset ID, with the verified canonical SHA-256, byte count, CSV format,
Session-relative `payload_reference` and captured variable schema. The schema
keeps its version, row count, delimiter and full bounded stable-variable fields,
including canonical positions and units. `render_bindings` records each Dataset
layer's selected stable variable IDs and actual prepared zero-based native column
mapping. `dependency_identities` records payload, registered metadata and artifact
SHA-256/byte counts using logical Dataset/layer IDs and Session-relative Resource
references, without private copy paths. These identities reuse the verified
capture copies; optional layer source-hash fields are not substituted for the
actual CSV identity. The export owner's existing 4 MiB retained-manifest limit
still applies and rejects an oversized complete receipt.

Initial source support is canonical CSV Dataset frames and self-contained
VTI/VTU/VTP artifacts. External attributes/textures, sparse selected slots,
legacy unresolved schemas, remote/non-CSV Dataset payloads, unsupported formats
and unregistered metadata resources are explicit errors. No dependency is
silently dropped, no HDF5 file is relabelled CSV, and no solver is run. A private
CSV scalar mapping uses the existing Engine3D stable-variable column resolver.
Export additionally refuses literal LF/CR in renderer scene/layer data and in
actual scientific figure text before the initial worker render. The native
capture boundary independently refuses control-bearing original captions before
seeking or output. Interactive figure APIs retain their existing behavior; this
export path does not claim multiline-caption transport support.

Dialog callbacks bind the host/dialog window incarnations, mount generation,
Session token and captured source. A chooser cannot apply to a recreated host.
Closing cancels only that dialog's existing managed request; CORE retains the
actual operation outcome. After commit authorization, interruption can mean
**finalization outcome unknown**, since the destination may already contain the
complete MP4. Do not equate cancellation with removal or deletion of a committed
file. Publication/reconciliation and retained diagnostics belong to the export
owner; this UI creates no process, publication or export-history manager.

This section documents source implementation. A rebuilt precompiled bridge,
central API adoption, allocated native/encoding checks and actual GUI acceptance
are still required. No render, video, caption readability, codec initialization,
scientific demonstration or installed-runtime PASS follows from this source batch.
