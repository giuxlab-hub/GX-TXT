# 3D Geometry Import — Architecture and validation scope

The module separates portable content inspection from GX-TXT acquisition and Dataset publication. It does not replace CORE registries or modify Native3D rendering.

## Portable inspection

The files `portable/formats.json` and `portable/geometry_probe.py` are independently usable from Python 3.10+ with standard-library dependencies only. The catalog defines stable format identifiers and public acquisition contracts. The geometry inspector is called as:

```python
from geometry_probe import catalog, inspect_file

formats = catalog()
result = inspect_file(path, deep=True, progress=callback, cancel=is_cancelled)
```

The result contains a format entry, namespaced metadata and warnings. It reads the supplied source without writing Session, Registry or viewer state. Progress reports examined bytes, total source size and stage; cancellation raises `Cancelled` and invalid inputs raise `GeometryError`.

Deep inspection validates supported STL/OBJ geometry records. STEP and VTK-family formats have bounded/declared validation levels; a preview count is not a full geometry or scientific-array verification. Never treat optional unavailable fields as measured values.

Stable metadata include `geometry.format`, `geometry.encoding`, `geometry.validation_level`, `geometry.units_status`, available bounds and counts, and format-specific fields such as `step.schemas`, `vtu.arrays_json` and `obj.material_library_references`.

## GX-TXT integration

- `runtime/acquisition_handler.tcl` implements public Acquisition Handler callbacks, metadata previews and Dataset descriptors.
- `runtime/geometry_worker.py` owns the exact-byte copying and isolated process protocol. Successful inspection does not independently register a Dataset.
- CORE owns Dataset identity, provenance, hashing, registration, atomic commit, Dataset Metadata validation and rollback.
- The helper wire format `GX3DIMPORT1` uses typed tab-separated/base64 diagnostic and metadata fields. It never evaluates user-provided source text as Tcl.
- `tools/build_package.py` synchronizes installer-visible format declarations with `portable/formats.json` during packaging, not during installation.

## Preview and downstream usage

Pending files recognized as binary by CORE may receive a safe generic source preview before the acquisition handler's specialized preview. Persistent imported Datasets expose the stored Dataset Metadata to the Dataset and Native 3D viewers. Generic pending-source preview is not evidence that the source's exact scientific data were analyzed.

The importer supports its installed descriptor's formats and does not bundle an entire Native3D viewer, create a private Dataset storage format, read external OBJ material files automatically or replace public CORE APIs.

Consult [the module manual](../MANUAL.md) and its `module.ini` for the current user workflow, formats and runtime dependencies.
