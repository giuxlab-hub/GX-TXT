# CORE Native3D Geometry Export host contract v1

SPDX-License-Identifier: GPL-3.0-or-later

The public owner is `core/tcl/native3d_geometry_export_v1.tcl`. It implements
complete scientific geometry export for host-issued Workbench extension
contexts. This is distinct from the module adapter family
[NATIVE3D_GEOMETRY_EXPORT_API_v1](NATIVE3D_GEOMETRY_EXPORT_API_v1.md).
This existing reference name alone is not a separately registered API declaration;
the host commands remain owned by the existing Native3D/Workbench services.

## Exact signatures

| Host command in `::GX` | Required / optional arguments |
|---|---|
| `native3DGeometryExportData context format ?mode?` | required context dict and format step/stl/vtp; mode default `bytes`, choices bytes/resource |
| `native3DGeometryPublishDataset context format requested` | all required; same context/format and requested public Dataset name/ID |

These are the actual argument order/defaults. There is no extra options argument;
tessellation parameters are in context.parameters. Do not pass a Dataset ID as
the second Publish argument. Use the ordinary registered extension path rather
than inventing a host snapshot to call these functions.

## Context and scientific coordinate policy

Context needs document_id, revision, workbench_id/version, parameters and a
presentation_snapshot with api_id NATIVE3D_GEOMETRY_EXPORT_SNAPSHOT_v1,
api_version1, matching document_id, working_unit, object_id and exact object.
The object supplies its owned geometry resource, kind, name, provenance,
source_bindings and (for publication metadata) attrs. The owner checks current
Document revision, matching snapshot Document, regular geometry_role and managed
resource. Working units must convert through the public Unit Registry to mm.
Scaling uses the intrinsic working-unit/mm ratio.

A separate public Native scene loads the full owned B-Rep/mesh. STEP requires
B-Rep; STL/VTP can tessellate B-Rep using context parameters (defaults
linear_deflection .01, angular_deflection .3, weld_tolerance1e-8,
max_triangles1000000, max_output_bytes134217728). Linear/weld values are working
length units, angular value radians. The final resource must not exceed
134217728bytes. Normal export excludes construction/reference roles. No
viewport LOD or implicit Dataset publication substitutes for complete geometry.

## Distinct transport results

`mode=resource` returns a dict with status ok, format, owned resource receipt,
working_unit, source_object_id and object. It returns before byte buffering and
the byte branch's final revision recheck; callers must retain their existing
owner guard. The resource stays under the Interactive Document resource owner,
not a raw Native pointer or arbitrary filesystem path.

`mode=bytes` reads that resource with the public bounded reader and rechecks
Document revision after reading. Result keys are status ok, format, bytes,
sidecars (one suffix `.gxtxt.json`/bytes dict), warnings and export_policy.
Sidecar JSON values are strings (`json_string_fields_v1`), including serialized
compound provenance; they are inert data. Metadata records geometry format,
working units, logical source/object/Document/revision, source geometry SHA,
role, API/producer, complete-world policy and tessellation/source provenance.
The function returns data; the normal extension/File Publication owner commits
the destination and sidecar atomically. This function itself has no target path.

`native3DGeometryPublishDataset` normalizes requested ID with default geometry,
rejects an existing ID, requests resource transport, streams it through a
temporary file, rechecks revision and calls public Dataset File Publication.
Output is model.cad/STEP or geometry.mesh/STL/VTP, binary, with source Dataset
lineage and structured units/logical IDs/attributes/provenance. Its result merges
the actual publication receipt with status ok, created_ids and
implicit_dataset_publication0. Readers, temporary files and Native scenes are
closed in finally. There is no cross-owner scientific transaction inferred
beyond those actual checks and publication owner guarantees.

## Exposure and failure boundaries

This host-issued snapshot API has no Script Bridge family or typed C++ SDK
method. Python/Octave retain separately admitted scoped
NATIVE_3D_GEOMETRY_API_v1/export_resource and normal publication bindings; no
Workbench/private pointer access follows from them. C++ uses actual reviewed
typed SDK capabilities, never a generic invoke.

Invalid transport/format/snapshot, stale revision, nonregular role, incompatible
unit/resource, mesh-to-STEP, output budget, existing Dataset ID and Native or
publication failures raise the actual owner error. Geometry completeness,
units/provenance transport and successful publication do not independently
validate a domain model, numerical accuracy or uncertainty. This reference
corrects the old signature/order prose; it is not a fresh runtime/science test.
