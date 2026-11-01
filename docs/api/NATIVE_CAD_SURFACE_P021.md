# CAD on an existing Native3D Canvas — P021

SPDX-License-Identifier: GPL-3.0-or-later

This is additive functionality in `NATIVE2D_API_v1`,
`NATIVE_3D_GUI_HOST_API_v1/v2` and `NATIVE2D_SPRITE_SCENE_API_v1`.
The Native3D engine C ABI and renderer are unchanged.

```tcl
set surface [::GX::native3DViewportSurface $existingV2Handle]
# For the existing mounted v1 Workbench instead:
# set surface [::GX::native3DGuiHostSurface]
set sketch [::GX::nativeCadSketchCreate $resourceContainer [dict create \
    viewport $surface working_unit mm plane $declaredPlane]]
$sketch canvasControls
```

The resource container owns component controls and lifetime; it need not be
packed as a second display. Omit `viewport` to create one ordinary embedded v2
viewport in the component's chosen container. The same public Builder
`cad_sketch` component and restricted C++ `Host::cad_command` contract are used
by Test CAD 1/2. No private Viewer code is imported.

The managed component takes ownership of its surface adapter, not the borrowed
Canvas, native 3D scene or renderer. An owned v2 viewport is released on disposal;
a borrowed viewport stays alive. Destroying the resource component disposes its
Native2D scene, projected sprites, callbacks and P017 History context. It never
deletes a consumer's scientific 3D geometry. Do not share one adapter between
managed Sketch owners. `get surface`, `get projection`, `get viewport` and
`get host` distinguish these handles; `get viewport` is empty for a v1 surface.

## Input and frame ownership

The surface registers a bounded input adapter on the actual renderer Canvas.
The shared P018/P019 Host and advanced controllers still own selection,
construction, controls, native snapping, transactions and constraints. Pointer
coordinates are mapped from the latest admitted native camera receipt. No
worker/Document request is made for each motion. Alt or Space plus primary drag
navigates the existing native camera; Shift chooses pan. Native Navigation Cube
input remains reserved for the existing native pick/click implementation.

`surface info` reports Canvas, owner kind, source stamp, current frame and busy
state. Its `guard`, `frame`, `busy`, `canvas`, `navigation`, `fit` and `dispose`
methods expose the corresponding finite services. Session, source, worker,
mount and frame identities are checked. Pending camera work blocks new input;
admitting a different mapping cancels an active scientific pointer transaction
through its existing rollback owner. Placed construction points retain their
local scientific coordinates. Behind-camera, horizon-crossing and edge-on
planes are rejected explicitly. Opening fits through native `FitObject` before
admitting a mapping, including when the plane was behind the previous camera.

Projection uses the existing native world/screen APIs. Depth is camera-forward
distance, not NDC. Details and exact bounds are in
[native projection](NATIVE_3D_GUI_HOST_PROJECTION_P021.md). The shared projected
adapter is `native2DCadProjectionAttach host mapper ?options?`; its `info`
reports readiness, reason and frame. No raw native address is exposed.

## Rendering and compatibility

One retained alpha-cleared Cairo sprite layer draws projected geometry/grid;
existing Tk labels and handles remain on the same Canvas. Overlay depth is
explicitly **always on top** of scientific solids. Native Navigation Cube raster
chrome is preserved above CAD and is never redrawn by a second Cube renderer.
Manual sprite colors accept their existing Tk strings or a public UI Field
`{rgb COLOR alpha NUMBER}` descriptor. Alpha blends against actual native frame
pixels, preserving transparent gaps and styles without opaque background panels.
Axis values, units, labels and exact geometry retain their existing CORE owners.

`presentation_scene` is the lightweight background/context descriptor used by
ordinary v2 refreshes; it does not reconstruct CAD geometry. The P020 public
`world_scene` method remains available as an explicit bounded, potentially
expensive compatibility snapshot. It is never called by normal frame, pointer,
selection or camera updates. Display samples remain noncanonical and cannot
become Dataset source rows or a publication authority.

## Lifecycle

Finish returns an automatically completed construction tool to Select and
commits eligible variable-length definitions. Native rejection preserves the
staged proposal. Actions focus the drawing Canvas; modal numeric editors retain
their own focus. Escape/Cancel uses existing cancellation/rollback semantics.
Neither harmless focus/selection nor cancellation adds a scientific History step.

`pending` distinguishes staged placements/active pointer edits from a tool that
is merely armed. Save rejects a pending edit. Close offers Finish, discard only
the staged edit, or keep open. The owning Workspace's normal dirty guard includes
Sketch pending/dirty status. `Workbench3D::guiInspect` additively reports
`sketch_pending` and `sketch_dirty`; its original Document/History identity stays
unchanged. Save/Reopen retains the same exact Sketch Document association.

Consumers that do not attach a CAD surface do not enable native projection
sampling or receive extra frame fields. The general P012 scheduler and P017
History service are not changed.
