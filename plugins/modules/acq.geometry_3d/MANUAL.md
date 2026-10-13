# 3D Geometry Import

**Module:** `acq.geometry_3d` · **Version:** 1.1.0 · **Baseline:** GX-TXT 0.9.8.10-dev

## Install and import

Open **Modules → Install plugin...** and select `acq.geometry_3d_1.1.0.zip`.
Select **3D Geometry Import** in Acquisition. Use **Browse...** to select the
first source, then **Add sources...** for additional files. Edit the Dataset IDs
in the framework's batch table, enable the wanted rows, and run acquisition.
To extend an open Session, use the existing **Import enabled pending into current
Session** action. Imported rows retain their normal Imported/Pending status.

One input file produces one independent Dataset. Mixed-format batches are
supported. STL, OBJ, VTU and VTP produce `geometry.mesh`; STEP/STP produce
`model.cad`; VTI produces `field.scalar_3d`.
The returned format determines the contract even in a mixed batch. No primary
Dataset, source-variable mapping or analysis module is required.

The importer uses the Python executable configured in GX-TXT Runtime Tools.
**Python 3.10 or newer** and its standard library are required. No pip packages,
VTK Python bindings, OCCT, NumPy, Octave or viewer activation is needed for import.
The native viewer has its own separate runtime requirements.

## Supported sources and what is checked

| Source | Canonical extension | Import inspection |
|---|---|---|
| STL ASCII | `.stl` | Triangle grammar, finite coordinates/normals, closed solids; triangle count and bounds. |
| STL binary | `.stl` | Exact count/record-length layout, finite coordinates/normals; triangle count and bounds. Binary files whose header begins with `solid` are supported. |
| Wavefront OBJ | `.obj` | Mesh vertex/face/line/point records, finite numeric coordinates and positive/negative index references. Polygon records are preserved, not triangulated. |
| STEP / STP | `.step` | ISO 10303-21 opening/closing envelope, mandatory HEADER declarations and DATA section delimiters. CAD entities and topology are **not decoded or validated**. |
| VTU | `.vtu` | `VTKFile type="UnstructuredGrid"`, XML structure, piece counts, point/cell array declarations, appended-data envelope and raw offset bounds. Inline ASCII/binary and appended raw/base64 containers are accepted. Scientific array values, topology and compressed blocks are **not decoded or validated**. |
| VTP | `.vtp` | `VTKFile type="PolyData"`, piece point/cell counts, coordinate and topology array declarations, appended-data envelope and raw offset bounds. Atom-like point arrays and indexed lines remain in the source payload. Array values and connectivity are decoded by the native VTK reader at render time. |
| VTI | `.vti` | `VTKFile type="ImageData"`, nondegenerate 3-D extent, finite origin/spacing, numeric array declarations and appended-data envelope. Scalar values and compressed blocks are decoded by the native VTK reader at render time. |

The exact inspection scope is stored in `geometry.validation_level`. A successful
STEP/VTK XML import means that the checked container can be preserved and registered;
it does not certify that every CAD entity or scientific payload can be decoded.
VTK/OCCT consumers may still report malformed or unsupported payload content.

The extension is a chooser hint, not proof of format. STL/OBJ/STEP content with a
mismatched extension generates a warning and receives the canonical extension.
VTK XML files must use the extension matching their declared grid type.
The original filename is retained. `.stp` and `.step` share the same STEP format;
renaming the canonical extension does not rewrite any bytes.

Other formats, such as legacy `.vtk`, `.pvtu`, `.pvd`, IGES, PLY, GLTF or
OpenFOAM case directories, are not advertised by this plugin. It does not claim
support merely because a third-party library can read a format.

## Preview and viewing

The plugin supplies metadata, validation scope and warnings through the
acquisition Preview contract. It does not launch a renderer or generate a
tessellated thumbnail. On large OBJ/STL
text files the initial preview may use bounded inspection; import performs the
full record checks. Complete imported metadata is available through the normal
Dataset Metadata workspace. The Variables workspace is intentionally empty:
these are opaque geometry objects, not artificial CSV tables.

**Known baseline Preview limitation:** in GX-TXT 0.9.8.09, the final generic binary
safety guard can intercept binary STL, raw-appended VTU and other binary-looking
sources before the plugin inspection callback is displayed. Such pending sources
show a safe generic binary preview instead of the plugin metadata. Textual OBJ,
ASCII STL, STEP and textual VTU normally reach the plugin preview. Acquisition
still uses the handler and persists its metadata. After import, the normal
registered-Dataset preview displays that metadata. This package does not override
or patch CORE functions to bypass the guard; the small future integration point
is documented in `docs/ARCHITECTURE.md`.

After import, open Native 3D and choose the canonical Dataset from the Session
selector. Opening the viewer does not open a filesystem chooser. STL/OBJ/STEP
use its geometry worker; VTU/VTP/VTI use its shared VTK scientific scene.
VTI needs an explicit scalar array and semicolon-separated isovalues. Source
point/cell arrays, connectivity, units and compressed data remain in the
original payload. The importer records array declarations in `vtu.arrays_json`,
`vtp.arrays_json` or `vti.arrays_json` without converting them to artificial
tabular Dataset variables.

## Preservation, units and dependencies

The framework makes its normal RAW snapshot. The plugin inspects that exact
snapshot and writes a byte-identical canonical payload. Copy verification is
performed before success; the framework independently computes source and
canonical SHA-256, registers the Dataset and commits its metadata. Save/reopen
uses ordinary Dataset Registry and Dataset Metadata APIs. Imported files remain
inside the Session, independent of the original source location.

There is no mesh repair, simplification, resampling, implicit triangulation,
coordinate conversion, CAD tessellation or scientific field extraction. No unit
is guessed or assigned to a source. Embedded units remain in the preserved file.
STL/OBJ bounds are inspection metadata, not a transformation of the source.

OBJ `mtllib` references are listed and warned about. Material files and textures
are **not copied or fetched**: the mesh geometry is preserved, but external
appearance dependencies are not made portable. Sources and referenced files are
never executed. VTK XML DTDs/entities and network resource resolution are rejected.

The RAW snapshot and canonical payload normally consume **two copies of the
source size**, plus small metadata. The plugin does not bypass the framework's
storage/provenance lifecycle with private links or storage tables.

## Progress and failure behavior

Inspection and preservation run in a separate Python process. The Tcl adapter
waits through the event loop and forwards progress/cancellation through the
Acquisition Handler callbacks. The optional begin/step/cancel callbacks support
framework cooperative acquisition. Cancellation waits for the worker to close
its files before rollback; this also avoids removing open destinations on Windows.

The framework still owns RAW snapshot creation and registry hashing. Those
framework-controlled phases retain their existing responsiveness; this plugin
does not alter CORE to add a new batch scheduler.

Malformed sources are rejected with diagnostics. Invalid IDs, destination
collisions and import/metadata failures use the existing framework transaction.
The importer never overwrites an existing payload. It creates files only within
the provided output directory and does not edit Dataset registries or metadata
sidecars itself.

Inspections use bounded records (16 MiB per text record), a 2 MiB STEP header
window, and a 4096-array metadata listing limit for VTK XML. The latter truncates only
the descriptive listing, with an explicit omitted count; original arrays are
never dropped. Very unusual text records or STEP headers above these limits
receive an explicit diagnostic rather than an unbounded allocation.

## Code organization and future CORE extraction

`portable/formats.json` is the format catalogue. `portable/geometry_probe.py` is
a framework-neutral inspector. They are explicitly marked **CORE EXTRACTION
CANDIDATE**, contain no registry writes and can move together without carrying
the GUI, package installer, Tcl adapter or a native renderer. See
`docs/ARCHITECTURE.md` for the small interface and migration boundary.

`runtime/geometry_worker.py` handles the application process protocol and exact
copy. `runtime/acquisition_handler.tcl` translates public Acquisition requests
and returns normal Dataset descriptors. `module.ini` declares contracts and the
Acquisition Format Registry entries through the existing public mechanism.
There are no SQL tables, private Dataset registries, CORE overrides or installer
scripts. The distributed ZIP contains only this plugin.

## Tests

Run `python -B tests/test_probe.py` from the extracted package. The fixture files
are self-authored small examples. `envelope.step` / `envelope.stp` test the
explicitly limited STEP envelope scope; they are not a tessellated solid.

Integration and GUI verification must use an **expendable extracted framework**
and the plugin ZIP. Do not run these checks against a production installation.
