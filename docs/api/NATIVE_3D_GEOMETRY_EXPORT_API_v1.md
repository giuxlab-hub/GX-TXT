# NATIVE_3D_GEOMETRY_EXPORT_API_v1


## TASK-9 dev-052 final behavior

CORE host commands `native3DGeometryExportData context format options` and `native3DGeometryPublishDataset context requested_id format options` accept host-issued `NATIVE3D_GEOMETRY_EXPORT_SNAPSHOT_v1` context only. Complete owned STEP/mesh resources, logical Document/object/revision, working units, role and provenance are required. STEP requires B-Rep; STL/VTP use complete mesh or explicitly parameterized Native tessellation. Quality includes chordal/angular/merge tolerances, max triangles and output bytes. Normal default excludes construction/reference roles. Export returns bytes or an owned resource plus inert JSON scientific sidecar; Dataset publication streams the resource through trusted normal Publication/Schema/Metadata and returns the requested canonical ID. The API is intentionally host-only because the host owns snapshot/revision policy. Scripts retain safe scoped Native3D resource export and explicit Dataset publication.
