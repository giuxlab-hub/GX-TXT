# NATIVE_3D_ENGINE_API_v1 (GX-TXT 0.9.8.10-dev-052)

TASK-9 adds `gx3de_scientific_triangle_mesh_create(source,max_triangles,
max_output_bytes,out)`. This explicit geometry-only conversion accepts pure
polygon/triangle-strip scientific PolyData and returns an independent complete
indexed mesh with the source world placement. Scientific source fields and
fingerprints remain unchanged; fields stay in the source, rather than becoming
mesh arrays. Mixed vertex/line cells and nonsurface data return unsupported.
Nonzero output budgets bound materialized triangles and bytes; failures retain
the source and return no result. The returned object supports mesh world
diagnostics and normal mesh editing/export. See the size/lifetime contract in
the public header and [scoped geometry](../../docs/api/NATIVE_3D_GEOMETRY_API_v1.md).

The engine-wide graphics policy is described in
`docs/api/NATIVE_3D_GRAPHICS_POLICY_v1.md`. It is inherited by targets and
does not alter Session scientific state.

`libgx3de` is the existing C++17 Native 3D engine with a plain, size-tagged C
ABI in `include/native_3d_engine_api_v1.h`. This dev-032 continuation adds a
VTK/OpenGL presentation layer to the validated non-rendering CORE. It does not
move geometry algorithms into Tcl or modify the frozen `viewer.native_3d`.

## Renderer ownership and data flow

An engine owns scenes and targets. A scene owns geometry, anchors,
measurements, sections, profiles and views. A target owns one VTK render
window, its viewport renderers and top-left RGBA8 pixels. Each viewport reads
one view's camera, background, lighting and clipping; several views or scenes
can share a target without sharing mutable view state. Viewports use top-left
integer coordinates in the C API. A view is independent of any GUI window.
Setting a view working plane renders a view-local 11-line-per-axis grid and
outline centered on its origin. The extent follows the visible scene bounds
with a minimum screen size; display is capped at 10,000 scene objects and a
one-million-world-unit half extent. Clearing the working plane hides it. The
plane widget has no pointer drag control in the PNG based Tk host; placement
continues through the public plane API.

`gx3de_target_create_headless`, `gx3de_target_render`,
`gx3de_target_read_rgba` and `gx3de_target_write_png` produce pixels and
transactional PNG output. `gx3de_view_render_rgba` and
`gx3de_view_write_png` render a chosen view at the caller's explicit width and
height through a temporary target. `gx3de_target_create_native` accepts an
opaque X11 Window or Win32 HWND integer for an embedding host; the public
header exposes no X11, Win32, Tk or VTK type. The caller owns the native
window. `gx3de_target_render_diagnostics` reports startup and budget failures
or the VTK/OpenGL capability report after success.

The first 64 feature flags remain in `gx3de_info.capabilities`. The ABI v1
extension word `gx3de_info.reserved[0]` advertises
`GX3DE_CAP2_RENDER_MARKERS` and `GX3DE_CAP2_TRANSFORM_GIZMO`; the remaining
reserved words remain zero. Bit 63 of the primary word belongs to generic
B-Rep mesh conversion when OCCT is enabled.

Every render constructs display props from the authoritative immutable mesh,
B-Rep and scientific data. B-Reps are tessellated from a copy using the same
OCCT foundation as STEP prototype meshing. STEP occurrence meshes and
imported/derived LOD objects are ordinary positioned mesh objects. Opt-in
`gx3de_mesh_repeats_presentation_set` displays all captured placements through
one shared prototype mapper plus unmatched remainder, without copying the
prototype mesh for each placement. The captured placement state is refreshed
by rediscovery after source changes.

Scientific rendering supports named point/cell scalar roles, selected range,
three generic color maps, point and sphere-glyph modes, point radius and
opacity arrays, trajectories/tubes, deterministic sampled vector arrows,
VTU surface presentation, image-grid exterior surfaces, and explicit VTI
isosurface objects. Source VTK arrays are not modified for display. Mesh and
scientific opacity are per object; translucent actors use VTK depth peeling.
Visible scene markers, view-local markers, selection highlights, measurements
with live anchor positions and numeric labels, sections and profiles are
separate display props. A projected mesh is an ordinary scene object linked to
its source and plane. Refresh operations explicitly rebuild linked snapshots.
Selected mesh edge anchors draw their source edge; selected face anchors draw
the three source edges in world space, without changing source triangles.

`gx3de_viewport_pick` returns the hit object, world/object point and normal.
Mesh cell IDs identify source triangles for that immutable mesh. Scientific
point IDs are exposed only when a nearby original data point can be identified;
generated sphere/arrow IDs are not returned as source IDs. A unique nearby
trimmed OCCT face yields a topology index and normalized UV for the exact
immutable B-Rep; ambiguous edge/corner hits fall back to a local point.
Repeated-component picks create captured world-point anchors because a
prototype display cell does not identify stable source topology. Any display
cell ID is transient across rerenders, tessellation or rebuilds.

The view-local gizmo displays world or object-local XYZ translation handles,
plane and free translation handles, and XYZ rotation arcs. Independent world
and local axis guides can be shown together; an anchor tangent/normal may be
shown as a separate reference-axis guide. `gx3de_gizmo_pick` returns a
handle from a rendered viewport; public top-left pixel helpers turn it into a
camera ray. The drag solver also accepts rays directly without a renderer.
Gizmo begin snapshots all scene object poses. Each update derives its proposed
local matrix from the original pose, and transactionally solves every scene
constraint that references the dragged object. In live mode (`preview_only=0`)
the temporary solved poses render until `gx3de_gizmo_end`: accept commits,
cancel restores all original poses. Data-only preview mode returns the proposed
matrix and restores all poses before returning, even if end accepts. Unsatisfied,
overconstrained or unsupported systems roll back. A fixed constraint that
undoes the requested drag reports overconstrained. Sheared local frames and
ray-plane intersections behind the pointer are rejected. An axis exactly
aligned with the pointer ray has no well-defined drag plane and returns
`GX3DE_DEGENERATE`; rotating the camera resolves it. No geometry buffer
is modified during manipulation.

## Limits and diagnostics

The ABI v1 `gx3de_info` layout and its original capability word are unchanged.
`gx3de_get_capabilities` exposes four words for each named CORE, renderer,
animation and field API group; a group with version zero is not implemented.
The camera has an explicit orthographic height in world units, independent of
distance to the target. Navigation, projection and unprojection use the
authoritative double-precision camera in CORE. Target geometry distinguishes
physical render pixels from logical GUI dimensions and reports both device
pixel ratios. Resize and viewport rectangle updates reject an out-of-bounds
configuration without changing the current target or camera. Resize and
quality changes invalidate the previous RGBA frame until the next successful
render. Output is top-left-first RGBA8; a caller may request 1–4 times
supersampling with deterministic box downsampling, within the pixel budget.

Renderer targets and their OpenGL contexts belong to the thread that created
the target. `gx3de_target_render` rejects calls from another thread. Scene,
view, target and viewport mutators and pixel readers are likewise intended for
that owner thread; only documented job state/progress/cancel operations may be
used concurrently. CPU-side geometry and camera coordinates remain double
precision. This OpenGL backend currently sends double points to VTK but has
no camera-relative floating-origin mode, so very large world coordinates with
tiny local features can still lose GPU depth or raster precision. `near_clip`
and `far_clip` remain explicit authoritative camera values and are not reset
on each frame.

On repeated camera motion, the renderer compares the current immutable scene,
view and target presentation state with the last completed frame. When only the
camera has changed, it retains the existing mesh, B-Rep, scientific and repeat
actors and refreshes only camera-dependent overlays such as the working plane,
markers, measurements, axes and gizmos. Public render statistics report frames
with reused geometry and frames requiring a full rebuild. A source, style,
clip, viewport or quality change triggers a full rebuild. This reduces ordinary
camera interaction cost without making GUI code own scene geometry. A renderer
failure invalidates the prior RGBA buffer. The target's API-level thread
ownership and frame publication do not imply asynchronous rendering or
arbitrary cross-thread mutation safety.

The target RGBA buffer is limited to 256 MiB and 16,384 pixels per axis.
Displayed mesh/repeated geometry is limited to four million drawn triangles.
Scientific display preflight permits at most one million source points and one
million source cells. Unstructured tetra/hexa cells are also bounded to four
million possible exterior faces before VTK's geometry filter. The resulting
scientific exterior is limited to four million points/cells. Tubes permit
100,000 line cells and 150,000 referenced line points
for tubes, 20,000 sphere glyphs, and 20,000 sampled vector arrows. Section
and profile display is limited to one million segments/points each. B-Rep
display tessellation is limited to two million triangles and 256 MiB output;
unique-face picking searches at most 10,000 faces. A limit failure returns
`GX3DE_RANGE` with target diagnostics rather than publishing incomplete pixels.
Each scene may present at most 10,000 markers and 10,000 measurements, and each
view at most 64 gizmos, in one render. Scientific point sets above one million
are explicitly rejected for display before VTK filters, while the authoritative
scientific object remains queryable; this bound preserves source array and
point-picking correspondence without an implicit lossy representation.

VTK OpenGL supports at most six active clipping planes. Rendering a view with
more than six enabled planes, counting an enabled clip box as six, returns
`GX3DE_UNSUPPORTED` and an explicit diagnostic. The eight view-local plane
descriptors remain independently queryable for non-rendering use. The renderer
does not claim exact transparency ordering on all OpenGL drivers; depth
peeling is requested and source geometry remains unchanged.

The Linux VTK build uses GLX and requires an X display, including for
offscreen targets. An unset `DISPLAY` or inherited
`LIBGL_ALWAYS_INDIRECT=1` is rejected before VTK initialization with a
diagnostic. The GX-TXT adapter may run the renderer in an isolated child with
Mesa llvmpipe (`LIBGL_ALWAYS_SOFTWARE=1`) and retry there, as the frozen
viewer does. VTK can abort inside an uninterruptible OpenGL context creation;
process isolation is therefore required for robust GUI startup and cleanup.
Long OCCT tessellation and some VTK filters likewise cannot be canceled inside
their blocking call; cancellation is honored at the surrounding job stages.

## Validation

Run `validation/native_3d_engine_api_v1/run.sh [new-build-dir]
[OCCT-development-sysroot]`. With Xvfb installed it builds and runs the full
public-C CORE plus renderer suite inside an isolated software-GL display,
unsetting inherited indirect GLX. Without Xvfb it uses an existing `DISPLAY`;
without either display it runs non-rendering tests and explicitly skips tests
whose CTest names begin `gx3de_render_`. Without OCCT, B-Rep and STEP tests are
omitted. The published Linux build includes OCCT.

The additive field and animation API, including deterministic structured-grid
field lines, scalar slices, volume transfer controls, time-dependent pathlines,
lazy timeline frames and PNG sequences, is documented in
`docs/api/NATIVE_3D_FIELD_ANIMATION_API_v1.md`. The renderer backend boundary
and the unimplemented Windows D3D11 presentation path are documented in
`core/native3d/WINDOWS_RENDERER_ARCHITECTURE.md`. Linux runtime backend query
reports the actual OpenGL adapter/driver and whether software rendering was
selected. A Windows-only D3D11 adapter/feature-level probe exists, but D3D11
target selection explicitly returns unsupported until its presentation path
is implemented and validated on Windows.

The API contract and legacy/scientific parity records are in
`docs/api/NATIVE_3D_ENGINE_API_v1.md`,
`docs/developer/NATIVE_3D_LEGACY_COMPATIBILITY.md` and
`docs/developer/NATIVE_3D_SCIENTIFIC_PARITY.md`.
# dev-034 navigation cube and checkerboard background

`gx3de_view_navcube_set/get` configure visibility, corner, size, margin and
hover/active state per view. A viewer sends viewport-local physical pixel
positions to `gx3de_viewport_navcube_pick` and
`gx3de_viewport_navcube_click`; the latter changes the CORE camera.
`gx3de_view_navcube_hover_set` updates highlighting after a pointer move.
Region IDs encode signed X/Y/Z directions (six faces, twelve edges, eight
corners). `synced_region` is derived from the current camera on every query and
render. The cube is a separate screen-space renderer layer; it never changes
scene geometry, bounds, measurements or exported meshes.

`gx3de_view_checkerboard_set/get` configure viewport-stable pixel checkers and
two RGB colors. The checkerboard is a renderer background texture, independent
of the shadow-receiving support plane and omitted from picking. Existing
`gx3de_object_style_set/get` and `gx3de_object_set_opacity` handle arbitrary
mesh color and transparency.

Camera selections are immediate. Cube drag/orbit and animated transitions are
not yet implemented. Semitransparent geometry contributes an opacity-attenuated
shadow through ordered shadow-map coverage and a filtered receiver lookup;
opaque shadows retain the existing map path. The 4 x 4 coverage pattern gives
16 discrete opacity steps and a narrow filtered edge. This is neutral object
transmittance, without colored transmission, volumetric absorption, or area
light penumbra. Depth-peeling quality remains OpenGL backend dependent.

## dev-035 surface-conforming canvas and shadow policy

`gx3de_object_curved_texture_add_from_pick` resolves a rendered mesh hit to an
immutable source triangle and object-local anchor. The distinct curved texture
API clips image UVs to source triangles in an edge-connected region with
`max_distance`, `max_edge_angle_radians`, and `max_seed_angle_radians` limits.
The image geometry follows each source triangle, stays attached under object
transforms, and leaves the source mesh unchanged. Since dev-038 the chart is
transported across shared edges by unfolding each reached triangle in a
shortest-distance traversal from the picked face. Propagation never crosses
an unshared edge or a nonmanifold edge. It is bounded by intrinsic traversal
distance, the requested image extent, and the two normal-angle limits. Cycle
edges whose transported coordinates disagree are explicit seams, queried with
`gx3de_curved_texture_seams_get`; `gx3de_curved_texture_status_get` reports
the rendered triangle count and limit/stop reasons. Curvature and closed
topology can still require a seam or a smaller front-facing patch. The original planar
texture API remains available for planar faces. Curved assignments expose
normalized anchors, rotation, U/V flips, move, proportional/stretch resize,
object-local footprint segments, and the shared planar handle IDs through CORE.

`gx3de_graphics_policy.shadow_policy` is an engine default for all targets:
`GX3DE_SHADOW_OFF` disables shadow passes, `GX3DE_SHADOW_OPAQUE_ONLY` excludes
translucent casters from shadow maps, and `GX3DE_SHADOW_FULL` retains opacity
attenuation. Scene, object cast/receive, and per-light flags continue to apply.
The field occupies the former `reserved32` slot, preserving the ABI v1 struct
layout. New capability bits advertise curved textures and shadow policy.
