# Native 3D Viewer changes

## 0.9.6

- Debian package host now resolves the bundled library through `$ORIGIN/../lib`, removing an absolute development-build RPATH. Public IDs, cache data and scientific algorithms are unchanged.

## 0.9.4

- Retry a renderer that fails during OpenGL or GLX initialization once with Mesa llvmpipe on non-Windows systems. Preserve hardware rendering as the first attempt and show the active software mode in Viewer status.
- Capture renderer startup diagnostics and report unrelated startup failures or crashes after interactive startup without a software retry.
- Disable inherited indirect GLX only for the software renderer child. The explicit `GXTXT_NATIVE3D_SOFTWARE=1` override remains available.

## 0.9.3

- Added draggable VTK implicit working plane, U/V/N axes, and real surface mouse-pick events through the public Native 3D interaction API.

## 0.9.2

- Show scalar-array and isovalue controls only for VTI scalar grids. Explain the
  meaning of an isovalue and show recorded field range where available.
- Keep mesh and normal geometry selection free of VTI-specific input.

## 0.9.1

- Cached stable STEP representation links during OCCT 7.8.1 assembly transfer on Linux. This removes repeated scans of the same shared-part links for large assemblies while retaining XDE names, hierarchy, transforms, geometry and cache format.
- Kept STEP meshing inside the serial native worker. Existing geometry cache keys remain valid because the output chunks are byte-identical on the small, medium and 20,000-occurrence fixtures.
- Added separate STEP read, transfer, traversal, meshing, triangle extraction and VTK conversion timings to worker events.

## 0.9.0

- Added Plot Dataset graph/Variant source selection, independent representation listing, status and explicit Sync to the control panel.
- Added named public renderer operations for camera, LOD, display, lighting, background, screenshot, layer presentation, source verification and external-file compatibility; raw host commands remain adapter-private.
- Replayed Viewer background, lighting, projection and absolute clipping plane state in scientific scenes. The native host now accepts a validated absolute clipping plane.

## 0.8.0

- Added Session Dataset selection as the normal startup workflow. Opening the viewer no longer opens a file chooser; external file opening remains an explicit compatibility command.
- Added scene-only startup and generic VTK XML scientific layers (VTU, VTP and VTI), point glyph radii, line tubes, scalar coloring and multi-value isosurfaces using the existing VTK backend.
- Persisted Dataset source identity and scientific scene presentation through Session reopen. The native worker still handles imported STL, OBJ and STEP geometry.

## 0.7.3

- Aligned native library, worker cache key and cache manifest identifiers with the module version; existing display caches rebuild on demand.

- Added `GXTXT_NATIVE3D_SOFTWARE=1` for a Linux/X11-safe Mesa llvmpipe renderer. The renderer child receives the software settings while the normal launch keeps hardware acceleration available.
- Validated geometry rendering, LOD, camera orbit, opacity, clipping, and clean host shutdown under Xvfb with software rendering.

## 0.7.2 — pre-delivery candidate

- Validate OBJ vertex, texture and normal references before VTK import. An out-of-range face index previously terminated the worker process; malformed references now produce a structured error without committing a display cache. Existing valid relative references and the large indexed OBJ still import.
- Passed disposable malformed STL/OBJ/STEP/unsupported-format checks on Linux and pinned-MSVC Windows workers. Derived repeated-component cache corruption was detected, rebuilt and then warm-reused on Linux.
- Report STEP read, XDE transfer, assembly inspection and tessellation phases in the GX-TXT progress panel. A 20,000-occurrence Debian profile isolated XDE transfer as the cold-import bottleneck; the small instanced Windows STEP workflow still passed through the real framework.

## 0.7.1 — pre-delivery candidate

- Corrected coarse LOD construction for disconnected or thin geometry: clustering uses source points, decimation preserves volume, and a bounds-envelope check falls back to clustering when decimation drifts. The worker cache key invalidates older derived LODs.
- Audited a 320,000-triangle curved OBJ and an 80,000-triangle disconnected repeated mesh for finite geometry, monotone LOD counts, per-axis bounds and sampled geometric distance. Both passed after the correction. Real Windows GX-TXT framework import/reopen passed for the OBJ, a 1,000,000-triangle STL, rotated STEP instances and 20,000 repeated components; large OBJ cancellation remained responsive.

## 0.7.0 — pre-delivery candidate

- Added linear, rectangular, circular and Session-owned explicit CSV display patterns. One bounded source-cell patch is shared across placements; a rejected native pattern is not persisted.
- Added user-assisted disconnected mesh component matching with bounded geometry signatures and proper axis rotations plus translation. Users review highlighted proposals and accept or reject them. Accepted components use one prototype and instance transforms; unmatched geometry remains visible.
- Stored accepted repeat prototypes and placements in an integrity-checked derived cache, with Session restoration from the cache or reconstruction when it is absent. A 20,000-component real Windows GX-TXT hardware run used 1,280,368 bytes of active representation chunks instead of 1,920,064 bytes of explicit Full LOD geometry and passed a 76-frame interaction sequence at 60.03 average FPS on an RTX 3060.
- Added early bounded OBJ preview scanning for large positive-index meshes, with full-import fallback for unsupported indexing. A 320,000-triangle OBJ passed Linux and real Windows GX-TXT cold/warm and cancellation checks.

## 0.6.0

- Stream bounded binary STL preview triangles before VTK loads the full mesh,
  allowing native interaction while quality LOD construction continues.
- Key the changed binary STL preview algorithm separately so older derived
  STL caches cannot be mistaken for this format.
- Add a reproducible native interaction benchmark with warm-up, azimuth,
  elevation, pan, zoom, reverse pan and camera restoration phases.
- Add Session-owned VTU scientific surface and sampled vector layers through
  Viewer Provider scalar/vector capabilities, with Session reopen and per-layer
  visibility controls in the native viewer panel.
- Add canonical CSV Dataset point layers through stable X/Y/Z, scalar and vector
  variable IDs. Persist source identity and layer visibility across Session reopen.
- Persist and restore per-layer opacity for VTU and Dataset scientific layers.
- Show STEP prototype parts in the control panel and persist each part's
  visibility independently of the complete assembly.
- Store STEP prototype placements in checked, 64-byte aligned binary records that the host reads from a memory mapping.
- Start tall instanced assemblies from a broadside camera view so their geometry is visible immediately.
- Persist and restore model opacity alongside the other native view controls.
- Persist and restore background color and model lighting from the viewer control panel.
- Added a persisted clipping plane with axis and position controls.
- Enforce the configured preprocessing memory budget against measured worker resident memory during mesh construction.
- Reject display LODs that exceed the configured display-memory budget before loading them; Auto chooses within both the triangle and display-memory limits.
- Fail closed if the worker cannot measure resident memory.
- Preserve cancellation state when an in-flight preview host sends late interactivity events.
- Report native worker and renderer peak resident memory alongside timing and frame evidence.
- Limit declared Viewer Provider primitives and capabilities to the geometry path implemented by this release candidate.
- Build and validate the Windows host, worker and C ABI with pinned MSVC against app-local VTK/OCCT/OpenSSL. Stage the recursive DLL closure and package license texts with the module.

## 0.5.0

- Replaced VTK XML LOD files with a compact versioned geometry format containing 64-byte aligned, memory-mappable vertex and triangle buffers.
- Retained per-chunk SHA-256 validation and invalidated older derived caches by changing the worker cache key.
- Added host PNG capture and corrected Session camera restoration to show the model on reopen.

## 0.4.0

- Added the stable C ABI shared library and host cache/LOD integration.
- Added progressive first preview, checksum-validated cache recovery, memory and presentation budgets, and bounded cancellation.
- Added STEP XDE import and assembly/object metadata, with shared prototype display geometry and occurrence placements.
- Added Dataset Preview mesh opening, camera restore, portable source, and verified external-source relinking.

## 0.1.0

- Native VTK host with interactive camera, picking, display modes and five LODs.
- Isolated native mesh/STEP preprocessing worker and transactional display cache.
- Viewer Provider and Session Interactive Document integration.
