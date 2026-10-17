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
