# Native 3D legacy behavior to preserve in later engine work

`viewer.native_3d` is the golden behavioral reference until an explicitly authorized migration and validation phase. Dev-032 does not edit or activate it. Later engine features must retain these proven behaviors, with focused parity tests before claiming equivalence:

- OpenGL/GLX initialization diagnostics and a single Mesa llvmpipe retry; child-only environment isolation.
- STL, OBJ and STEP ingestion, including malformed OBJ index rejection before VTK parsing; progressive binary STL and bounded large-OBJ preview.
- Transactional cache publication, SHA-256 chunk and source checks, invalid or incomplete cache rejection and rebuild, immutable source identity and portable-copy semantics.
- Worker resident-memory and display/GPU budget checks; responsive cancellation and temporary-stage cleanup.
- Thin/disconnected geometry LOD: source-point clustering, volume-preserving decimation, bounds-envelope fallback; repeated-component representations.
- STEP XDE hierarchy, labels, occurrences, transforms, shared prototypes and instanced display; serial STEP meshing and cached Linux transfer lookup.
- Scientific VTU/VTP/VTI and Dataset layers, presentation controls, independent source identity, working plane, camera, surface pick and Session persistence.

Relevant frozen sources: `plugins/modules/viewer.native_3d/native/src/worker.cpp`, `host.cpp`, `display_cache.hpp`, `step_transfer_cache.cpp`, module `CHANGELOG.md`, `MANUAL.md`, and `NATIVE_3D_VIEWER_API_v1.md`.

Dev-032 conservatively ports the strict OBJ index preflight, bounded binary-STL/large-OBJ preview foundations, the viewer's source-point clustering, volume-preserving decimation and envelope fallback, the OCCT 7.8.1 repeated-occurrence transfer lookup, shared STEP prototype tessellation, and rigid repeated-component detection. The public C API exposes source SHA-256, immutable geometry fingerprints, resource budgets, independent occurrence transforms and queryable scientific VTP/VTU/VTI data. Mesh, LOD, STEP prototype, repeated-component and nonempty scientific-isosurface caches use namespace-scoped SHA-256 validation, transactional publication, corruption rejection and rebuild; they never share mutable camera or selection state.

The viewer remains the golden reference for OpenGL/GLX/Mesa behavior, actual display/GPU and process RSS budgets, automatic preview-to-full presentation, pixel-level scientific presentation, surface mouse picking, Session persistence and GUI interaction. The in-process CORE checks cancellation around blocking VTK/OCCT calls but cannot interrupt those calls internally. Renderer and GUI parity must be validated separately before migration.

## Dev-032 renderer and GUI continuation

The preceding inventory describes the non-rendering CORE milestone. The same-version dev-032 continuation adds a VTK pixel renderer and the additive `viewer.engine_3d` Viewer Provider. The provider runs the C API in a child process, retries GL startup through Mesa llvmpipe when required, stages and checks a complete PNG before publication, renders an import preview before fuller geometry, and stores source identities and compact presentation definitions in Session metadata. It retains the frozen `viewer.native_3d` as a separately selectable fallback. Native rendering, scientific fields, markers, measurements, sections, projections, clipping, source picks, camera interaction and Session reopen are exercised through public C clients and real Tk GUI workflows. The detailed evidence and explicit limits are in `docs/developer/NATIVE_3D_RENDERER_PARITY.md`.

The generic gizmo API and new provider do not change the legacy module's source, its behavior or its Session schema. The native API returns object-local/world hit data and solved gizmo transforms; the Tcl provider only forwards pointer events and records committed layer transforms. Transient VTK cell IDs and gizmo handle IDs are never used as persistent source identities. The Linux GUI worker has both an address-space ceiling and a parent-side sampled resident-memory ceiling; an isolated low-budget run verified worker termination with an explicit diagnostic. OCCT/VTK blocking calls remain uninterruptible within the call, so worker cancellation takes effect at the next boundary or by terminating the isolated child. A real Windows renderer build remains a platform validation item; the public header retains the portable C ABI and Windows import/export annotations.
