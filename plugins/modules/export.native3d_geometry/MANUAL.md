# Native3D Geometry Export

The normal exporter chooser supplies exact STEP and complete-world STL/VTP.
Select one accepted regular Workbench object, choose Export geometry, choose a
provider, configure explicit tessellation quality/limits where needed, and select
a file through the native Save dialog. Mesh STEP export rejects clearly.

Geometry and `.gxtxt.json` scientific metadata sidecar publish atomically through
CORE File Publication. Neither file overwrites existing content. The sidecar
records working units, logical source, document/version, geometry hash, role,
source bindings and producer/tessellation provenance. This is essential for STL,
whose coordinates have no intrinsic unit. JSON fields are strings; compound
provenance is explicitly inert Tcl dictionary/list data, never executable code.

The exporter uses public CORE geometry/resource APIs and a separate Native
scene. File export preserves accepted geometry/document revision.
Reference/construction geometry is excluded. Native supports STEP, binary STL
and VTP writing in this audited path; other formats are not advertised.

The ordinary **Publish selected as Dataset…** action invokes this provider's
`publish` action. Enter the public Dataset name/ID and choose its canonical
format. Complete meshes publish as `geometry.mesh`; exact STEP B-Reps publish
as `model.cad`. CORE streams owned Native resources through trusted create-only
Dataset File Publication, preserving units/logical IDs/source Dataset bindings,
scientific provenance/attributes and explicit tessellation parameters. File
export and Dataset publication are separate explicit user actions. There is no
implicit Dataset, source mutation or viewport mesh export. A disabled/missing
provider rejects clearly through normal extension discovery.

This owner-context export API is intentionally host-only. Python/Octave use
scoped `NATIVE_3D_GEOMETRY_API_v1.export_resource` and the normal Dataset
publication APIs; scripts receive no private Workbench scene or native pointer.
