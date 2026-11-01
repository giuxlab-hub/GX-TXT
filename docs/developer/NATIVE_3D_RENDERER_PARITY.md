# Native 3D renderer and Viewer Provider parity — dev-032

This inventory compares the additive `libgx3de` renderer and
`viewer.engine_3d/engine_3d` provider with the frozen
`plugins/modules/viewer.native_3d`. The old provider remains installed as a
separately selectable route. `COMPLETE` means the stated generic workflow was
exercised through the public C header or real GX-TXT GUI; it does not imply
identical controls or image pixels. `PARTIAL` identifies a precise remaining
legacy interaction or backend limit. `SUPERSEDED_NOT_REQUIRED` identifies a
legacy implementation detail whose user-visible purpose has an alternative.

## Renderer and data presentation

| Capability | Classification | Evidence and limit |
|---|---|---|
| Offscreen RGBA, PNG, native X11 target | COMPLETE | `test_render_pixels.c` checks nonblank RGBA/PNG, two viewports and independent scenes/targets/engines. `test_native_x11_target.c` creates a real X Window, renders, reads pixels and picks through its XID. GUI shows PNG from isolated native worker. Native Win32 target has ABI support but no Windows runtime validation in this Linux run. |
| Camera, view isolation and scene hierarchy | COMPLETE | Public C tests render independent engines, targets, scenes, viewports and cameras; GUI real wheel, left orbit and middle pan survive a fresh-process Session reopen. Six axis presets, isometric and scene/object/selection fit have public C coverage. |
| Opaque and translucent mesh, object styles, lighting and background | COMPLETE | `test_view_presentation.c` compares actual overlap RGB for opacity between zero and one; exercises surface, edges, wire, points, gradient background, directional light and explicit render dimensions. The integrated scene combines translucent mesh, custom lighting and background in one image. |
| Mesh, STL/OBJ, derived LOD | COMPLETE | Public C import, preview, LOD and render tests cover geometry and source fingerprints; GUI errors mode verifies ASCII STL preview fallback, malformed OBJ rejection and rollback. Main GUI run observes OBJ preview pixels before full stage. Proven CORE decimation and thin/disconnected protection remain in place. |
| B-Rep and STEP/XDE | COMPLETE | Public C tests cover generic box/cylinder B-Rep tessellation, rendering, triangle/byte budgets, source immutability, sync/async jobs and cache recovery; STEP fixture covers hierarchy, shared prototype occurrences and their placements. `test_render_step_repeats.c` checks visible occurrence pixels. Real GUI `step` mode imports the bundled 12-occurrence STEP artifact, checks visible preview before full, more than one placed render object and Session manifest save. |
| Repeated mesh components | PARTIAL | Public C repeated discovery and opt-in shared mapper presentation render captured prototype placements and unmatched remainder. The generic provider has no equivalent of every frozen viewer pattern proposal/edit control; frozen provider remains available. Re-detection is needed after a source pose change because placements are captured. |
| Scientific VTP/VTU/VTI, image isosurfaces | COMPLETE | `test_render_scientific.c` exercises point/cell scalar roles, range/colormap, VTP/VTU arrays, VTI multiple isovalues, vectors, radii, trajectory tube and per-point opacity. `test_integrated_scene.c` combines scalar/vector/radius particles, tube, volume, slice, field lines, multiple isosurfaces, animation frame, and transformed world-space vector sampling in one scene. GUI creates scientific artifact and Dataset point/trajectory/volume layers and restores them. Visual equality with legacy screenshots is not asserted. |
| Particle count and render buffers | COMPLETE with explicit limits | Renderer preflight rejects an RGBA buffer above 256 MiB; public C test checks this without allocating the frame. Displayed triangles/points/glyphs have native budgets and explicit rejection rather than silently truncated geometry. Large VTK/OCCT allocations can still occur within a blocking third-party call. |
| Sections, profiles and projections | COMPLETE | `test_render_annotations.c` checks visible curves, styles, source transforms, captured result and explicit refresh. Integrated scene displays them together. GUI stores section definitions in provider metadata and recreates them on reopen. Derived curve results are snapshots until refreshed. |
| Clipping | PARTIAL | Two independent planes and a six-face box render separately. VTK OpenGL allows at most six simultaneous mapper planes: two user planes plus the full box return `GX3DE_UNSUPPORTED` with a diagnostic; stale RGBA/PNG is rejected. The view state can still store/query all descriptors. Public C tests cover side inversion, clip pixels and failure cleanup. |
| Working plane | PARTIAL | View-local guide grid and outline change pixels, clear cleanly and do not leak into another view; numeric origin/normal/U-axis editing and visibility persist in GUI Session. The frozen draggable VTK plane widget is not reproduced by the generic GUI. |
| Markers, measurements, selection and gizmo | COMPLETE for supported rigid objects | Public C tests cover vertex/edge/face selection pixels, scene/view markers, source-following annotations, measured values and rendering. Gizmo tests cover world/local/reference axes, handle pixels/hits, axis/plane/free/rotation ray and screen drags, hover, pivot modes, preview/commit/rollback, dependent and fixed constraints, and active view/object destruction. Real X11 handle drag commits a layer transform that survives Session reopen. This is a rigid placement tool, not a parametric CAD solver. Multi-occurrence STEP layers have no single-object GUI gizmo. |
| Geometry pick to API anchor | COMPLETE with topology lifetime limit | Public C pixels tests create mesh anchors from hits, and B-Rep picking exposes an OCCT face lookup when unique. GUI click creates persistent marker definitions from source/local information. VTK cell and handle IDs are transient and are not serialized as source identity. OCCT topology indices belong to the exact immutable shape, not later rebuild/boolean/reimport. |

## Runtime and Session

| Capability | Classification | Evidence and limit |
|---|---|---|
| Startup, Mesa fallback, environment isolation | COMPLETE | Real GUI fallback mode starts with `LIBGL_ALWAYS_INDIRECT=1`; failed child GL initialization is retried once with Mesa llvmpipe and yields nonblank pixels. The parent Tcl environment retains its original value. The worker uses a separate process. |
| Preview/full import and cancellation | COMPLETE with blocking-call limit | GUI observes visible OBJ and STEP previews before their fuller stages. Errors mode checks ASCII STL fallback, malformed OBJ rejection, explicit cancel during full-stage work, terminal `Cancelled` state, no restarted worker and temporary PNG cleanup. In-process VTK/OCCT calls cannot be interrupted internally; cancellation is honored at their boundaries or by killing the isolated worker. |
| Source identity and derived cache | COMPLETE | Public C tests tamper cache data and verify SHA-256 rejection/rebuild for B-Rep, scientific, LOD and repeated representations. GUI stores source SHA/provenance and rejects changed/missing Session artifacts and a changed Dataset CSV SHA, then renders after restoration. Complete PNGs are staged and atomically published; mutable camera/selection state stays in the Session descriptor. |
| Budgets | PARTIAL | Public API has explicit mesh triangle/byte, point/glyph and RGBA limits. The GUI worker has a default 8 GiB address-space limit and Linux parent-side RSS watcher at 4 GiB, sampled every 250 ms; the module manual records an isolated 128 MiB limit killing a 264.6 MiB child and a 4096 MiB pass. Sampling permits transient overshoot, and this is not an exact replica of frozen viewer GPU residency accounting. |
| Viewer Provider and Session | COMPLETE | Real Tk test creates five geometry/scientific/Dataset layers, manipulates camera and gizmo with actual X11 events, picks markers and measurement, saves, closes, reopens in a new process, checks second-Session isolation, source SHA diagnostics and recovery. The manifest contains compact provider definitions, not Dataset payload rows. Exported PNG and Tk window screenshot survive close/reopen. |
| Dataset Preview route and legacy fallback | COMPLETE | GUI route test checks that enabled mesh preview selects the new provider, explicit legacy preference is honored, and disabled/missing bridge conditions fall back to frozen `viewer.native_3d`. Frozen provider discovery/open is exercised in a disposable Session. |
| Plot Dataset graph/Variant-specific controls | SUPERSEDED_NOT_REQUIRED for this generic provider | The new provider consumes supported Dataset IDs and Variable IDs through Viewer Provider manifests. Specialized frozen `viewer.native_3d` graph and Variant UI remains available; this continuation does not migrate `plot.dataset` or plotting modules. |

## Validation scope

The renderer clients are C programs compiled against
`native_3d_engine_api_v1.h`; none claims coverage through a private backend.
Structural pixel comparisons check nonblank regions and state-dependent changes
instead of driver-specific image hashes. The integrated OCCT scene is in
`test_integrated_scene.c`; GUI acceptance is `run_real_gui.sh` using seven fresh
Tk modes and disposable Sessions. X11/OCCT-specific tests are platform or
configuration gated. Linux/Xvfb/Mesa/OCCT validation does not establish a
Windows renderer build or native Win32 window behavior. The frozen viewer's
source remains byte-identical; it was not rewritten for this provider.

## Generic API continuation after the initial renderer stage

| Capability | Classification | Evidence and limit |
|---|---|---|
| Named capability groups and ABI capacity | COMPLETE | `gx3de_get_capabilities` has four versioned, four-word groups for CORE, renderer, animation and field without changing the original ABI v1 info word. `test_camera_capacity.c` and the public-header Windows-mode C syntax check cover the additive form. |
| Resizing, navigation and image quality | COMPLETE on Linux | Public C tests exercise target resize/DPR, viewport rectangles, orthographic height, orbit/pan/dolly/zoom, screen/world conversion, supersampling, renderer statistics and unchanged-geometry camera frames. GUI input forwards navigation to CORE and coalesces busy worker input; the final pointer state renders. |
| Volume, scalar slice and field lines | COMPLETE for structured images | `test_field_volume.c` checks transfer controls, visible ray-cast pixels, clipping/transform/picking and source immutability. `test_field_animation.c` checks structured VTI/image scalar slices, RK4 field lines, list/line/plane seeds, bidirectional integration, budgets and time-dependent pathlines. The GUI can add, save and reopen a VTI volume layer. Unstructured-vector streamline integration is not provided. |
| Animation timeline | PARTIAL | A separate versioned public API has frame/time seek, play/pause/stop, loop/ping-pong, lazy resident-frame budgets, object/camera tracks and deterministic PNG sequences. `test_field_animation.c` exercises rollback, wrong ownership and scene cleanup. One changing scientific source layer is supported per timeline; unsupported topology/array interpolation is explicit. The generic GUI has no timeline editor or Session serializer, and field-line regeneration across a timeline must be driven by the caller. |
| Runtime backend diagnostics | COMPLETE for Linux OpenGL | `test_render_backend.c` queries backend, adapter, driver, software path and failure state. The Linux test records Mesa llvmpipe under Xvfb. Hardware acceleration depends on the available display/GPU. |
| Native Windows Direct3D 11 presentation | PARTIAL | The public ABI and backend selection are neutral and a Windows-only D3D11 device/adapter probe exists. D3D11 target selection fails explicitly; there is no D3D11 pixel presentation or Windows bridge package. `core/native3d/WINDOWS_RENDERER_ARCHITECTURE.md` records the implementation boundary. This Linux host has no Windows SDK/toolchain to compile or runtime-test the Windows branch. |
| Prolonged GUI motion stability | COMPLETE for tested scene | The seven-mode real Tk suite repeats orbit, pan and wheel input, requires every captured frame to be complete, checks nonblank final pixels and minimized/restored state, and rejects new renderer dialogs. This structural test cannot prove visual quality on every driver or very-large-coordinate scene. |
