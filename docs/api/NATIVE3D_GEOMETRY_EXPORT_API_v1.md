# Native3D Geometry Export module API v1

SPDX-License-Identifier: GPL-3.0-or-later

`NATIVE3D_GEOMETRY_EXPORT_API_v1` (no underscore after NATIVE) is the installed
`export.native3d_geometry` module's version1 extension API, namespace
`::GX::Native3DGeometryExport`, entrypoint
`api/native3d_geometry_export_api_v1.tcl`. It delegates to CORE host commands
documented in the separate
[NATIVE_3D_GEOMETRY_EXPORT_API_v1 reference](NATIVE_3D_GEOMETRY_EXPORT_API_v1.md).
That reference name is not an alias for this registered module family and does
not by itself declare another installed public API family.

## Exact public entries

Each takes one required Tcl `context` dictionary and has no optional arguments.
The existing Workbench extension owner issues and validates the context.

| Entry in `::GX::Native3DGeometryExport` | Actual delegation / return |
|---|---|
| `step context` | `::GX::native3DGeometryExportData context step`; byte-mode export receipt |
| `stl context` | same owner, format stl; byte-mode export receipt |
| `vtp context` | same owner, format vtp; byte-mode export receipt |
| `publish context` | `::GX::native3DGeometryPublishDataset context context.parameters.format context.parameters.dataset_id`; canonical Dataset publication receipt |

The host-issued context includes document_id/revision, workbench identity,
parameters and `presentation_snapshot` with API ID
NATIVE3D_GEOMETRY_EXPORT_SNAPSHOT_v1/version1, exact regular source object,
owned geometry resource, source object ID/document and working unit. Do not
manufacture it from a viewport mesh or private Native pointer. Use normal
extension discovery/execution and its current guarded snapshot. Source Document
revision and managed resource identity remain authoritative.

## Parameters and units

For STL/VTP mesh preparation and publication, descriptor parameters are:

| Name | Default | Meaning / declared bound |
|---|---|---|
| linear_deflection | .01 | positive working-unit length; descriptor min1e-300 |
| angular_deflection | .3 | radians; min1e-300, maxπ |
| weld_tolerance | 1e-8 | positive working-unit length; min1e-300 |
| max_triangles | 1000000 | integer1..10000000 |
| max_output_bytes | 134217728 | integer1..134217728 |
| format (publish only) | stl | choice stl, step, vtp |
| dataset_id (publish only) | empty | requested public Dataset name/ID, normalized by Publication requested-ID owner |

STEP requires an accepted B-Rep. STL/VTP use complete mesh resources or explicit
tessellation of a B-Rep; construction/reference geometry is excluded. CORE
computes the working-unit-to-mm scale and exports through its public Native
resource owner, retaining working-unit provenance. No physical unit is guessed
from a file extension or viewport size; STL itself has no intrinsic units.
The CORE output resource has an explicit128MiB bound in this path.

Byte-mode return contains status `ok`, format, bytes, sidecars, warnings and
export_policy. The `.gxtxt.json` sidecar bytes describe exact source/object,
document/revision, working units, source hash/bindings/provenance, role and
tessellation parameters as JSON **string** fields. File destination/atomic
file-plus-sidecar publication belongs to the existing extension/File Publication
owner; the adapter alone returns bytes and does not write a selected file.

Explicit publish streams the full owned resource through Dataset File
Publication, create-only: STEP contract `model.cad`, STL/VTP `geometry.mesh`.
The receipt contains the publication result plus status `ok`, created_ids and
implicit_dataset_publication0. File export itself creates no canonical Dataset.
No independent scientific numerical/uncertainty validity is asserted by export.

## Context/errors and language exposure

An active current Document/Session and compatible Native3D/units/resources are
needed. Invalid format/snapshot, stale revision, nonregular geometry, absent
resource, incompatible unit, mesh STEP, tessellation/output-budget or existing
Dataset ID failures propagate from existing owners. The module declares no
independent result normalization or error-code map. The separate CORE reference
documents bytes/resource transport and exact signatures.

This Workbench-context API is host-only; it has no registered Python/Octave
Bridge family and no typed C++ `gx::Host` method. Scripts may have separate
scoped Native3D resource/export and Publication grants; they do not receive this
private Workbench snapshot. No generic C++ invoke exists. See
[Workbench Extension](WORKBENCH_EXTENSION_API_v1.md),
[Native3D Geometry](NATIVE_3D_GEOMETRY_API_v1.md) and the installed module's
MANUAL.md. No new export, engine, persistence or scientific acceptance campaign
was executed to prepare this reference.
