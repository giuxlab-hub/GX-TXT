# Managed RGBA appearance on a Native3D planar face

This contract extends the existing Native3D GUI Host and Viewer Layer owners.
It uses the installed Native3D engine's planar texture API, renderer and worker.
It creates no image editor, compositing registry, geometry engine or scientific
Dataset implicitly.

## Actual user workflow

Retain a transparent RGBA PNG using the managed raster workflow. Open an owned
3D Workbench solid or mesh and click its rendered planar face. Choose **Managed
image on picked face…**, select an actually retained managed RGBA image from the
current Session, and enter image width/height in the Workbench's displayed length
unit. Rotation is radians around the face normal; U/V flips are explicit.
**Apply** copies the image into this destination Document's managed resources and
commits appearance through its existing History. **Remove selected object's
image** removes appearance without changing the solid. Undo/Redo and reopening
retain the same source geometry and texture descriptor.

Width and height are explicit decorative placement dimensions. They do not
recalibrate the source image or imply that its pixels are physical measurements.
The original source resource/provenance and the target physical dimensions/unit
remain separate in `mapping`. PNG alpha remains alpha: the rectangular texture
contains transparent pixels outside an extracted polygon rather than pretending
the image itself has a polygonal file boundary.

The face resolver uses the existing native `add_from_pick` and `get` contract.
It resolves the actual immutable source triangle from local position and normal;
it never treats a transient display cell ID as scientific topology. Mapping is
object-local, anchored to the connected, consistently oriented coplanar patch.
The native engine clips appearance to that patch and does not wrap onto adjacent
faces. A changed view/owner while a placement form is open requires a fresh pick.

## Shared host boundary

`::GX::native3DLayerTextureAnchor resource x y width height` verifies/materializes
the managed PNG through existing resource and Viewer Artifact APIs, then asks the
current native worker to resolve the picked source face. It returns layer ID,
occurrence index, stable source triangle and object-local anchor. The source
image and geometry remain unchanged.

`::GX::native3DLayerTextureBind module provider layer resource placement` requires
the loaded worker's `managed_planar_texture` capability and an actual artifact
layer. Required placement fields are `source_triangle`, `local_anchor` (semicolon
XYZ), positive `width`/`height` and `working_unit`. Defaults are occurrence 0,
normalized UV anchor 0.5/0.5, rotation 0 and no flips. Callers must use the actual
source geometry's local length unit. The 3D Workbench adapter enforces its own
unit and commits the returned descriptor in the existing object style.

`::GX::native3DLayerTextureValidate descriptor layer` checks source geometry SHA,
managed resource owner/generation/SHA, finite mapping, registered physical length
unit and true RGBA PNG header. Images are bounded to 8192 per dimension, 16 million
pixels and 128 MiB; bit depth is 8 or 16. The Workbench picked-face resolver also decodes the image before committing
placement. Direct layer clients must treat a native decode/render failure as
unavailable appearance; a header check alone is not full PNG validation.

The ordinary Viewer Layer `texture` field stores schema
`gxtxt.native3d.planar_texture.v1`, the managed resource, geometry SHA, source
triangle/occurrence, local anchor, normalized UV anchor, physical width/height,
rotation/flips, working unit, actual PNG dimensions/depth, mapping and provenance.
The existing layer manifest and Session persistence retain these values. A
verified temporary `source_path` exists only in worker input; it is not canonical
metadata. Managed nested resource references use the existing collectors and
portable owner-remapping machinery.

## Limits

The adapter exposes one planar assignment per Workbench object. Curved UV mapping,
multiple overlapping assignments and appearance compositing order are not part
of this interface. Existing lower-level native capabilities remain unchanged.
A different geometry SHA requires removal and an explicit new anchor; the host
never guesses a corresponding face. Appearance changes do not alter geometry,
physical units, source pixels, calibration, original raster values or topology.

For extraction, masks, blend modes and source-pixel ROI semantics, see
[Native2D raster composition](NATIVE2D_RASTER_COMPOSITION.md). Closed profile
extrusion is an independent geometry operation, described in
[Native3D profiles and extrusion](NATIVE_3D_PROFILE_EXTRUDE_v1.md). No CAM,
toolpath, G-code or machine operation is implemented by this appearance contract.
