# Native2D image ROI, masks and composition

These additive operations belong to `NATIVE_2D_GEOMETRY_API_v1`. They use the
existing scoped Native2D scene and Interactive Document tokens. Native2D owns
image-local vector geometry, image transforms, ordinary layer order/style and
identity attributes. ImageMagick performs every pixel operation through the
registered `core.native2d.raster` provider and existing Scientific Execution,
Script Job, Runtime Tool, managed temporary and Document Resource authorities.
There is one retained layer stack and no separate image editor, raster resource
store, renderer or Job queue. Scientific Image Inspector remains independent.

## Retained geometry and layer operations

Call `::GX::native2DGeometryCall scene operation request`; Python/Octave Script
Bridge use the same operation IDs with `scene, request`.

| Operation | Request and result |
|---|---|
| `raster_dataset_bind` | `dataset_id`, optional `options {expected_source_sha256 SHA state {...}}`; admits an actual `image.raster` Dataset and returns its original managed image resource, scoped `object_token`, native image state and canonical source identity. |
| `raster_roi_set` | `object_token`, stable `roi_id`, `definition {kind rectangle|polygon points {{x y}...}}`; returns the native ROI collection. Rectangle takes two opposite corners and stores four normalized corners. Polygon takes 3–128 distinct ordered vertices without repeating the first. |
| `raster_roi_get` | `object_token`; returns `revision`, actual `source_resource_id`, and `rois` keyed by stable ROI ID. |
| `raster_roi_remove` | `object_token`, `roi_id`; removes that ROI and increments the native collection revision. |
| `raster_roi_geometry` | `object_token`, existing `roi_id` or a source-pixel `definition`; returns canonical source points, projected device points and vertex handles. |
| `raster_roi_pick` | `object_token`, `device {x y}`, nonnegative pixel `tolerance`, optional `roi_id`; resolves an actual native vertex, boundary or interior. Hidden image/layer targets are excluded. |
| `raster_roi_propose` | `object_token`, `operation create`, `kind rectangle|polygon`, `device_points`; or `operation translate|vertex`, existing `roi_id`, `start_device`, `end_device`, and vertex `index`. Returns a nonmutating source-pixel definition and its native admission result. |
| `raster_layer_get` | `object_token`; returns existing image identity attributes for `blend`, `mask_uuid`, `mask_channel`, `mask_invert`, `mask_only`, `roi_id`. Defaults are Over, no mask, luminance, false, false, no ROI. |
| `raster_layer_update` | `object_token`, `changes`; accepts `blend`, `mask_object_token` (empty detaches), `mask_channel` (`luminance|alpha`), `mask_invert`, `mask_only`, `roi_id` (empty detaches). A mask source must be an owned image in the same scene. |

ROI points are floating source-image pixel coordinates. They remain authoritative
when the scene zooms, pans, rotates or recalibrates. Native validation rejects
nonfinite, zero-area and self-intersecting polygons atomically. Geometry outside
the image remains stored unchanged; rasterization clips it to the output canvas.
The receipt reports actual image intersection and clipped bounds. Native storage
uses one existing `gx.image.rois` identity attribute; the existing 16 KiB total
attribute-value bound applies to the collection. It contains vector coordinates,
not millions of mask samples. Collection and per-ROI revisions identify edits.

The three interaction operations accept optional `expected_revision` and
`source_resource_id` guards; Set and Remove also accept `expected_revision`.
Stale collection or foreign resource requests fail before modifying the ROI.
Projection, picking, pixel conversion and edit proposals use the existing native
image mapping and geometry kernel. Proposals never update `gx.image.rois`:
the controller commits a valid definition explicitly through `raster_roi_set`.
Rectangle proposals expose two opposite input corners and four canonical
vertices/handles. A polygon draft with fewer than three vertices is reported as
`INCOMPLETE`; an invalid completed proposal retains its projected ghost and
reports its native admission failure without changing the accepted geometry.

Dev109 kernel and public-adapter checks cover rotated/scaled images, edge and
vertex picking, rectangle corner crossing, invalid polygons, locked/hidden
targets, source/revision guards and snapshot restore. These checks do not
constitute Builder, restricted SDK or installed human-GUI acceptance.

Canonical raster binding uses the existing Dataset inspection/registry and
Document Resource writer. The admitted bytes and SHA are preserved exactly;
the original Dataset is neither converted nor published again. Source identity,
Variable schema and content hash accompany the image's existing metadata.
Source-pixel unit `px` is opaque and has no automatic conversion to metres.
Physical calibration remains an explicit native image operation. Binding state
may set scale, translation, rotation, opacity, visibility and lock only.
A numerical XYZ Dataset or a caller-selected source filename is not admitted.
Changed source identity/schema/content/file version rejects subsequent raster
edits and hides dependent editors while retaining the previous valid frame.
Portable restore verifies the original source once and reacquires its current
Session file stamp. Transient file stamps/readers never enter the saved payload.
Managed resource readers are released when their image or scene closes,
including after Session expiry. This API addition alone does not establish
Builder/SDK interaction or installed GUI acceptance.

Use the existing `image_map` operation with `inverse 1` to convert scene/world
pointer coordinates into source pixels. `image_map` without inverse maps them
back for retained overlays. Rectangle and polygon remain distinct shape kinds.
Image/layer lock prevents ROI or raster-property edits.

Use existing `layer_create`, `layer_assign`, `layer_update` and `image_update`
for order, visibility, lock, opacity and image scale/rotation/translation. These
properties remain owned by those services. Raster export applies image opacity,
ordinary layer opacity and any object opacity multiplicatively. The unlayered
native layer zero has no additional layer opacity/visibility modification.
Images sharing an order retain their existing scene object order.

A layer alpha mask uses the mask image's original grayscale luminance or its
actual alpha channel, according to `mask_channel`, mapped by
its own retained image transform; `mask_invert` exchanges black/white. It does not
use a composited preview as its source. `mask_only` keeps that image available as
a mask without drawing it as a visible color layer. Foreign, missing, ambiguous
or cyclic image identities are rejected. Chained mask bindings are unsupported;
materialize an explicit derived grayscale mask before binding it. An optional
`roi_id` on a layer applies that image's editable geometric ROI as another alpha
factor. This differs from an ROI processing mask, which limits an effect while
preserving the pixels outside it.

## Managed processing and outputs

| Operation | Contract |
|---|---|
| `raster_prepare` | `base_object_token`, `operation mask|extract|composite|effect`, optional `roi_id`, optional `options`; returns a ticket and managed composition-manifest receipt. |
| `raster_submit` | `ticket`; verifies that live ROI, layers, resources and transforms still match the captured snapshot, then submits the existing prepared Scientific Execution token. Returns actual `job_id`, `state`, `provider_id`. |
| `raster_freeze` | `job_id`, `output_token`; freezes an actual terminal Job output into the scene's existing Document Resource owner. Caller retains the returned receipt in the Document payload. |

`mask`, `extract` and `effect` require the base image's current `roi_id`.
`composite` uses the existing image stack. Options are `antialias` boolean,
`feather` Gaussian radius in source pixels (0–16), `invert` boolean, `effect`
(`negate`, `grayscale`, `blur`) and `effect_radius` (0–16 pixels). No caller can
supply ImageMagick command expressions or arbitrary argv. Minimum blends are
`Over`, `Multiply`, `Screen`, `Overlay`, `SoftLight` and `DstIn`.

The base image defines a full rectangular source-pixel canvas. Each layer is
mapped into that canvas through actual Native2D forward/inverse image maps.
Image calibrations/translations must use one explicit common scene length unit;
mixed declared working units reject. Normalize incoming physical coordinates
through the existing Unit Registry before attaching them to the common scene.
The native source geometry and calibration are unchanged. Pixels outside an
extraction ROI have alpha zero, including polygon corners inside the rectangular
canvas. A mask has black outside, white inside and optional fractional
antialiased/feathered edges. Inversion applies after rasterization/feathering.
An effect creates a separate derived raster: its processing mask preserves the
original composite outside the ROI. It never changes an input resource.

Limits are 16 image layers, 16,777,216 canvas/source pixels, the existing 8 MiB
total prepared input snapshot, and the existing 16 MiB terminal freeze boundary.
Only PNG resources with verified signature, declared bounded dimensions and
supported PNG sample depths/color types are accepted. Malformed decoder input
fails the real Job. ImageMagick runs with explicit memory/map/disk/thread/time
limits under the existing guardian. Source profiles and bit depths remain in
unchanged inputs; display composition explicitly uses sRGB, 16-bit RGBA
intermediates and 8-bit RGBA output. A grayscale mask is explicitly exported at
16 bits. This display composition is not a radiometric measurement conversion.
The JSON provenance explicitly identifies the base image object, Document and
generation, actual image calibration/transform state and original managed
resource receipt. It also records actual bit depth/color type, software version,
source SHAs, native mapping, ROI, blend/opacity/mask settings and output SHA.

Use the existing Scientific Execution Status/Log/Cancel/Outputs operations.
Completion and scientific validation are distinct; inspect `validated_structure`
and the provenance output. Outputs have `raster` and `provenance` roles, each with
an existing output `token`. Freeze and retain both when adopting an export.
Closing a host does not transfer or remove the durable Job.

## Persistence, History and texture consumers

`raster_snapshot` returns bounded references to existing native geometry
resources plus ordinary layer properties, identities and view state. It writes
no new scientific registry. `raster_save` stores that snapshot under
`native2d_raster` in the existing Document payload and checkpoints the same
scene authority. Optional `retained_resources` are stored as `raster_exports`.
Other Document payload fields remain intact.

`raster_restore` accepts optional `snapshot`; otherwise it reads that Document's
saved snapshot. It requires an empty existing scene and rejects foreign or
replaced Document generations. It reconstructs existing native layers, images,
attributes, mask identities and view state. Partial failure cleans newly created
objects/layers and leaves the Document unchanged. For History, capture a public
snapshot and restore it into a fresh scoped scene; replace/close the old scene
only after successful restoration. Use the existing Scientific Recipe History
host, not a private Undo stack.

A frozen RGBA export is an ordinary verified managed image resource. Existing
Native3D image/texture/material services consume it; the exporter creates no 3D
renderer. The export receipt keeps the full base-image canvas, pixel origin
`{0 0}`, dimensions and original calibration/scene transform so a consumer can
choose explicit UV/physical placement. It does not guess a scale or crop origin.

For a small independent Tk host, the host-only adapter
`native2DGeometryViewportAttach scene container canvas changed_callback` mounts
that scoped scene in the existing ViewportHost and reuses its native geometry,
shared presentation and bounded asynchronous reference-image painter.
`native2DGeometryViewportDraw scene canvas ?changed_callback?` redraws through
the same owners after an explicit edit. The callback can draw transient ROI
outlines from public `image_map`/`world_to_device` results; those display points
never replace native source-pixel ROI geometry. Each draw validates Session,
Document generation/revision and actual canvas lifetime. Destroying the attached
canvas detaches existing viewport resources and closes that scoped scene; the
caller must create a fresh scene before attaching another host. These host-only
Tk functions do not form a Script Bridge GUI construction protocol.
