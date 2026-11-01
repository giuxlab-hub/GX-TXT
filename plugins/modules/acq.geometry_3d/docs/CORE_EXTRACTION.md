# CORE extraction boundary

## What can move

`portable/formats.json` and `portable/geometry_probe.py` form the reusable unit.
Neither imports GX-TXT nor reads/writes Session, configuration, Registry or viewer
state. Python 3.10+ standard library is their only runtime dependency.

```python
from geometry_probe import catalog, inspect_file
result = inspect_file(path, deep=True, progress=callback, cancel=is_cancelled)
```

`catalog()` returns a mapping indexed by the stable format IDs `stl`, `obj`,
`step` and `vtu`. The JSON schema version is 1. Each entry contains its label,
extensions, canonical extension, contract, MIME, parser ID and viewer-use hint.
The viewer hint is descriptive; it does not activate or require a viewer.

`inspect_file()` returns `format_id`, the catalogue `format` entry, namespaced
`metadata`, and a list of `warnings`. It reads only the source. `progress` takes
`(bytes_examined, source_size, stage)` and `cancel()` returns a boolean.
Invalid/unsupported content raises `GeometryError`; cancellation raises
`Cancelled`. `deep=True` fully inspects STL/OBJ geometry records, not STEP B-Rep
or VTU/VTP/VTI scientific arrays. Keep the declared validation levels intact on migration.

The metadata map is plain data: numeric values, booleans and strings. JSON
strings retain richer array/material declarations without adding private SQL or
Session tables. The GX-TXT adapter converts scalar values to UTF-8 strings for
the existing Dataset Metadata API. Stable useful keys include:

```text
geometry.format
geometry.encoding
geometry.validation_level
geometry.units_status
geometry.triangle_count
geometry.vertex_count
geometry.cell_count
geometry.bounds_x_min / geometry.bounds_x_max (and y/z)
step.schemas
vtu.arrays_json
vtu.array_metadata_omitted
vtu.payload_decoded
obj.material_library_references
```

Bounds exist only when actually calculated. Preview-only counts are explicitly
labelled as prefix records. No absent count, unit or variable is manufactured.

## What remains with the plugin

`runtime/acquisition_handler.tcl` owns callback translation, metadata preview and
Dataset descriptor construction. `runtime/geometry_worker.py` owns the process
wire adapter and exact-copy operation. They call only the supplied request
callbacks and the public Runtime Tools service. Dataset registration, hashing,
transaction commit, metadata validation and rollback remain in GX-TXT.

The helper-to-Tcl protocol is `GX3DIMPORT1`. `F` fields, `M` metadata and `W`/`E`
diagnostics are tab-separated base64 UTF-8 values; `P` has integer byte counters
and a base64 stage; success requires the terminal `OK` record. Source metadata
is data, never Tcl source to evaluate.

## Migration procedure

Move the two portable files to a shared public service and expose their result
contract. Change the worker/import adapter to use that service. Move format
ownership into a generic CORE registry only when such a registry exists; until
then `module.ini` legitimately declares public acquisition formats. Preserve
format IDs, Dataset contracts and metadata names so old Sessions need no rewrite.

`tools/build_package.py` refreshes the descriptor's format blocks from the JSON
catalogue before building the ZIP. This avoids drift between runtime recognition
and installer-visible format declarations. The build tool runs only during
packaging, never as a plugin install hook.

No compatibility monkey-patches, CORE procedure redefinitions, private registry
files, bundled native viewer libraries or exact-version viewer dependencies need
to be carried into CORE. The package has a minimum framework version but no
maximum-version pin and no dependency on a particular renderer release.

## Existing 0.9.8.09 Preview dispatch limitation

The final `refreshCsvPreview` definition in `core/tcl/dataset_preview_api_v1.tcl`
routes binary-looking pending sources to `datasetPreviewSafeBinary` before
calling the installed acquisition handler. That guard is hardcoded around
existing media classes. Binary STL and raw-appended VTU therefore receive the
safe generic source preview, despite this plugin implementing the public preview
callbacks. Registered Dataset preview still renders persisted Dataset Metadata.

A future CORE task can preserve binary safety while consulting the selected
handler's read-only Preview Descriptor before falling back. No change to source
bytes, format parsers, Dataset contracts or this plugin's metadata layout is
needed. This delivery deliberately contains no wrapper, rename, trace or global
procedure replacement for the guard. This is an existing dispatch limitation,
not a new table or registry installed by the plugin.
