# Native 3D Viewer API v1

`viewer.native_3d` registers `gx3d_native_host` through Viewer Provider API v1.
The backend is activated only when the viewer opens. Preprocessing and rendering
run in separate native processes; Tcl receives progress and camera events through
nonblocking channels.

The dev109 adapter registers a single root-destruction hook when starting the
host. It closes the dedicated interactive process through its ordinary QUIT
protocol, independently of preprocessing cancellation. The native event loop
also handles command-pipe EOF, so loss of its owning application cannot leave
an idle scientific window behind. The normal shutdown drain is bounded at
250 ms. This is process-lifetime handling, not a new scientific renderer.

Closing the standalone native window flushes its existing `closed` event and
terminates the dedicated host process immediately, using the same process-exit
policy as QUIT and command-pipe EOF. Its detached stdin reader must not outlive
the stack-owned Host or race with global stream destruction while the owning
application remains open. Later root shutdown therefore has no lingering native
reader to command. Rendering, camera events and scientific data are unchanged.

## Canonical scientific workflow (0.9.0)

Import STL, OBJ, STEP or VTU through `acq.geometry_3d`, then bind the Session
Dataset with the public Viewer Provider API. Opening the provider does not
invoke a filesystem chooser. Its panel lists compatible Session Datasets.
Modules set `scene_mode=scientific`, register Dataset or Session-artifact
layers with `viewerLayerSet`, then call `viewerOpen viewer.native_3d native_3d`.
VTP points/radii and lines/tubes express atoms and bonds. VTI scalar grids
with isosurface layers express reconstructed density and other scalar fields.
The generic contract is in `docs/api/VIEWER_PROVIDER_API_v1.md`.

The explicit `openExternalModel` operation is for user-triggered compatibility
with external files. It never runs automatically and is not the normal module
path. Native host commands, worker files and VTK/OCCT objects are private.

```tcl
::GX::modulePublicApiActivate viewer.native_3d NATIVE_3D_VIEWER_API_v1
::GX::Native3D::openExternalModel /absolute/model.step 0 ;# external reference
::GX::Native3D::openExternalModel /absolute/model.step 1 ;# explicit Session copy
::GX::Native3D::cancel
::GX::Native3D::setLod low
```

## Stable named operations

Normal scientific scenes use Viewer Provider API v1 for scene and layer
creation, removal, order, visibility, opacity, representation, scalar/vector
mapping, camera, projection, clipping, artifact verification, open and
rerender. This adapter adds named renderer conveniences:

| Operation | Public path | Persistence |
| --- | --- | --- |
| Imported Dataset source | `openDataset datasetId ?scalar? ?isovalues?` | Viewer scene/layers and source digest |
| Plot Dataset graph source | `PlotDatasetAPIv3::interactiveSources`, `openInteractive`, `activateInteractive`, `syncInteractive` | Independent representation document |
| External file compatibility | `openExternalModel path ?copyIntoSession?` | Interactive Document reference/copy |
| Camera presets and rotation | `cameraPreset preset`, `rotateView direction`, `setCamera position target up ?projection?` | Camera events and Viewer scene |
| Projection and absolute clipping plane | `setProjection`, `setClippingPlanes` | Viewer scene |
| LOD and display mode | `setLod`, `setDisplayMode` | Native document for imported model |
| Lighting and background | `setLighting`, `setBackground` | Viewer scene and native document |
| Global visibility and opacity | `setVisible`, `setOpacity` | Native document for imported model |
| Layer presentation and removal | `setLayerPresentation layerId fields`, `removeLayer layerId` | Viewer layers |
| Screenshot and redraw | `screenshot path`, `refreshScene` | Screenshot file / Viewer scene |
| Cancel and close | `cancel`, `closeViewer` | No source mutation |
| Source identity check | `verifySourceIdentity` | Read-only |
| Repeat and pattern display | `addPatternRegion`, `proposeRepeats`, `acceptRepeats`, `rejectRepeats` | Native Interactive Document |

`setLayerPresentation` accepts only named presentation fields and validates
them through Viewer Provider. `setClippingPlanes` accepts the Viewer Provider
`nx,ny,nz,d` plane form; the current native backend supports one plane. The
GUI's axial fraction slider is a native convenience. The private adapter
translates these operations into host commands; module authors must not send
protocol strings.

An open Session is required. The provider stores a versioned Interactive
Document and a Viewer scene/layer. The original source is authoritative; the
user cache is derived and rebuildable.

## Derived display cache

The worker writes a transactional `GX3D_DISPLAY_CACHE_v1` directory. Its
`manifest.json` records source SHA-256, size and format, worker/importer
versions, bounds, LOD triangle counts, and STEP object/instance metadata.
Each LOD or unique STEP prototype is a `.gx3d` geometry chunk with a separate
SHA-256/size marker. The complete manifest is published only after all chunks
are written and checked. A key change invalidates earlier derived caches.

`GX3D_GEOMETRY_v1` chunks have a 64-byte little-endian header (`GX3DGEO1`,
version, endian marker, vertex/triangle counts, float bounds and index offset),
followed by tightly packed float32 XYZ vertices and uint32 triangle indices.
The index array starts at a 64-byte boundary. The host memory maps the chunk,
validates its shape and indices, then loads only the selected LOD into VTK.
STEP instance transforms use `GX3DINS1` in `step_instances.gx3di`: a 64-byte
header followed by 64-byte records containing prototype index and seven
float64 pose values. This chunk has its own SHA-256/size marker.
The source STEP/STL/OBJ and Session viewer document remain authoritative.

For large positive-index OBJ files, a bounded preview is scanned before full
VTK parsing. Unsupported indexing falls back to the full importer. The cache
key records the changed preview algorithm.

The 0.7.1 worker key also separates caches built with source-point clustering,
volume-preserving decimation and bounds-envelope fallback. These are derived
display LODs; a stale or invalid cache is rebuilt from the original source.

## Repeated geometry and display patterns

`::GX::Native3D::addPatternRegion` creates a bounded display-only patch from
a selected Full LOD mesh cell. It supports `rectangular`, `linear`, `circular`
and `explicit` layouts. Explicit layouts refer to a hash-checked, Session-owned
CSV with `x,y,z` columns. The Interactive Document is updated only after the
native `pattern_ready` event. The source mesh remains independently available.

`::GX::Native3D::proposeRepeats`, `acceptRepeats` and `rejectRepeats` drive a
user-reviewed component match. The native host discovers connected triangle
components, compares bounded quantized geometry signatures under 24 proper
orthogonal rotations and translation, and highlights the proposed matches.
Acceptance persists the selected source cell in the Interactive Document.
The derived cache stores one `prototype.gx3d`, a `placements.gx3di` transform
array and any unmatched `remainder.gx3d` under `repeat_cell_<cell>/`, with
per-chunk SHA-256/size markers and a transactional completion marker. On
Session reopen the host validates and reuses that representation or rebuilds
it from the authoritative source display cache. An accepted representation
does not modify the source model.

## Interactive working plane and surface picks

`::GX::Native3D::setWorkingPlane origin normal uAxis ?visible?` sends a real `vtkImplicitPlaneWidget2` plane to the native host; the host displays U/V/N axes and emits a `plane` event when the user drags it. `workingPlane` returns the most recently requested plane. The inputs are three numeric XYZ triples and visibility is `0` or `1`.

`subscribeInteraction callback` and `unsubscribeInteraction callback` manage Tcl callbacks. A callback receives one event dictionary. `plane` carries `origin`, `normal`, `u_axis` and `visible`; `pick` carries world `position`, surface `normal`, `cell_id`, `point_id` and source identity. `latestPick` returns the last pick. Surface picks come from actual VTK mouse interaction and the Section/Profile Viewer uses these values to define three-point and surface-tangent planes. Callback errors are reported through Native 3D progress.
