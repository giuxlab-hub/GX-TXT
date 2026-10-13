# Native3D ordered profiles, extrusion and staged export

These additions belong to the existing public `NATIVE_3D_ENGINE_API_v1` C ABI.
They use the same scene, plane, profile, B-Rep, tessellation and renderer engine
as the Native 3D Engine Viewer. They create no Dataset implicitly.

`gx3de_profile_create_contours` copies ordered U/V points into the supplied
working plane. An explicit closed flag creates the closing edge; a repeated
end/start within the declared positive join tolerance is normalized. Open input
remains open. It rejects nonfinite coordinates, collapsed edges, ambiguous joins,
self crossings and touching/overlapping contours. It preserves submitted point
order and snapshots the plane frame. Up to 4096 contours and one million total
input points are allowed. Existing section-derived profiles remain supported.

`gx3de_profile_extrude` constructs an exact OCCT prism using that captured plane
normal and a finite nonzero signed distance. All contours must be closed. Strict
containment determines material and holes: even depth is material, immediate
odd-depth children are holes, and nested islands remain material. Concave
boundaries, either input winding and several separate islands are supported.
The profile and source geometry remain unchanged. Positive and negative distances
have identical area/volume semantics. The returned object has world identity
placement. A Workbench must retain this same result for preview and acceptance.

New/Join/Cut/Intersect use this result and the existing public B-Rep Boolean API.
Boolean algorithms operate on independent geometry copies so OCCT updates to
working tolerances/p-curves cannot alter authoritative input fingerprints.
Invalid input or construction returns an explicit failure before retaining a
profile/object. Callers own successful outputs through normal scene lifecycles.

`gx3de_brep_write_step` writes complete world geometry to a new owned staging
path. Its explicit positive `millimeters_per_working_unit` asserts physical
length: use 1 for mm and 1000 for m. Per-writer model units avoid global OCCT
configuration changes. Transfer uses a geometry copy and preserves source
fingerprints. `gx3de_mesh_write_file` writes complete world mesh geometry as
binary STL (format 1) or VTP (format 2), using the existing VTK writer. It never
uses display LOD. STL has no embedded physical-unit field; record the asserted
working unit in publication metadata. These calls do not overwrite an existing
path and do not publish/register a Dataset. Hosts stage output and pass it to
normal File Publication with `geometry.mesh`/`model.cad` contracts and provenance.

Capabilities are advertised in the second CORE word as `INPUT_PROFILE`,
`PROFILE_EXTRUDE` (OCCT builds) and `GEOMETRY_EXPORT`. No opaque native pointer or
unscoped private path should cross a Script Bridge boundary.
