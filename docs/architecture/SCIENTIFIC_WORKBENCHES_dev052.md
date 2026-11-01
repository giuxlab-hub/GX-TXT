# Scientific application architecture — dev-052

GX-TXT is a scientific application/framework. Tcl/Tk coordinates user workflows; CORE services own canonical data, numerical and native geometry authority, typed UI/configuration, Script Bridge, persistence and publication. Plugins discover actions and renderers through public descriptors, rather than reading private registries or rebuilding numerical engines.

| Resource | Authority and lifecycle |
|---|---|
| Session Dataset | Public requested ID; Canonical Dataset, Schema, Metadata, Table Stream and transactional Publication. CSV/HDF5 storage is independent of consumer semantics. |
| Built-in/Test Curve Fit sample | Local deterministic descriptor, generator and scientific expected result; `source_kind=builtin_sample` / `source_sample_id`. No Dataset identity until explicitly published. |
| Accepted local curve / retained sketch / 3D body | Native2D/Native3D geometry, logical Interactive Document identity and Session-owned resources; no implicit Dataset publication. |
| Source view / temporary operation | Execution/Session/owner-scoped handles, exact complete streamed input; bounded display proxy is not scientific input. |
| Explicitly published result | Common CORE Publication with user ID, source hashes/bindings, effective transform/sampling/units/roles/policies; source payload remains immutable. |
| Group / Selection Set / Layer / Saved View | Transform ownership / remembered logical references / presentation / presentation bookmark are separate records. Stale and missing references are explicit. |
| Recipe / extension | Inert semantic records and public proposals, exact owner/revision/API/plugin/units validation, staged one-Undo acceptance. No arbitrary Tcl evaluation or private host paths. |

Native2D owns definitions, sampling, constraints, geometric measurements, units, snap, CAD gestures, selection and coordinate frames. Numerical API owns fitting/projection/residual science with complete exact input. Native3D reuses the existing OCCT/VTK kernel, renderer worker, picking/gizmos/NavCube and complete geometry operations. Its Workbench provides CAD/CFD preparation; the generic Viewer remains the presentation consumer.

UI callbacks do not clear/rebuild an engine in its active transaction. Point selection coalesces at idle, retains pending changes during native drag, checks scene/curve/lifetime epochs and prevents reciprocal table/canvas recursion. Native3D gesture cancellation waits for the shared worker boundary before ending the native transaction and rebuilding preview presentation. Errors remain visible and pending updates are not silently discarded.

Large scientific coordinates live in owned resources/streams; bounded extrema and pages serve display only. SQLite-backed Transform preserves complete typed tuples and exact uint64/text, with explicit absence masks for Native values without source readings. Shared responsive operations yield in bounded phases and commit without yielding. Document/Session generations prevent A→B→A stale handles; collection validates distinct resource receipts without repeatedly hashing document payloads.

Official exporters receive owner-issued read-only snapshots and public Native geometry. Complete geometry and inert sidecars publish atomically. Script exports return owned resources, while raw destinations and GUI/gesture authority remain host-only. Portable Sessions transport retained resources; the framework does not publish unpublished working geometry into the Dataset Registry.
