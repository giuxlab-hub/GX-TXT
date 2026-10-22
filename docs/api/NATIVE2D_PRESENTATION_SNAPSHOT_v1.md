# NATIVE2D_PRESENTATION_SNAPSHOT_v1

CORE API version1, existing owner `core/tcl/native2d_presentation_v1.tcl` and its
shared `native2d_axis_presentation_v1.tcl` support. The discovery owner maps this
family to `::GX::native2DPresentationSnapshot`. That command takes a live host
native scene; it is not an API-info command and must not be called without a
scene to discover metadata. This reference documents its inert display schema
and actual host helpers, not a new registry or geometry engine.

## Public host entrypoint and access

`::GX::native2DPresentationSnapshot scene ?options?` has exact Tcl formals
`{scene {options {}}}`. It returns a renderer-neutral Tcl dictionary. The host
must own a valid Native2D scene and established view. `scene` is the host's
native scene handle, not a Python/Octave execution-owned opaque geometry token.
No implicit Interactive Document, Session, Job or canonical Dataset is created.

There is no direct registered Python/Octave binding or typed C++ SDK method for
this snapshot family at this checkpoint. The existing geometry Script family
uses `open(document_id)` and opaque tokens; those tokens do not grant arbitrary
host helper access. The typed SDK retains `diagram_open`, `diagram_tool`,
`diagram_command` for its viewport component contract. No generic C++ invocation
of a snapshot, exporter or `_native2D*` internal is admitted by documenting it.

## Options

Unknown option names fail. Dictionary/list values are Tcl inert data.

| Option | Default / checked contract |
|---|---|
| `point_budget` |4096; integer6–65536, applied independently to each displayed object |
| `font_size` |14 device pixels; number6–96 |
| `include_construction_reference` |false; boolean. Unless true, non-group objects whose native geometry role is not `regular` are excluded and listed in `excluded_object_ids` |
| `axes_visible` |true; boolean. Controls axis graduation text and planner-generated scientific grid lines. Separate axis title/title text remains independently constructed |
| `axis_presentation` |`__scene__`: use stored scene presentation, falling back to shared default. Explicit descriptor is validated by the existing axis owner |
| `axis_plans` |Normally generated. Optional dict with exactly `x` and `y`; each plan's `lower/upper` must match current world bounds, with at most64 unique finite in-range tick values and labels at most256 characters |
| `x_tick_labels`, `y_tick_labels` |Absent; a supplied axis requires exactly six strings, each at most256 characters. Legacy positions are world fractions0,1/5,…,1, overriding that axis's planned labels |
| `x_label`, `y_label` |Absent: descriptor title plus verified displayed unit, if any. Explicit text, including empty, overrides that default |
| `title` |Empty text |
| `object_labels` |Empty dict; maps native numeric object IDs to labels. Default `Object ID` |
| `legend` |Empty list: no entries. `auto` includes visible objects; otherwise list of native object IDs |
| `annotations` |Empty list; at most512 entries and131072 total Tcl bytes. See schema below |

The snapshot does not impose a total byte/object limit or a maximum length on
all titles/object labels. Its per-object budget must not be described as a global
64K/4096 scientific point cap. Supplied plans retain caller text and must be
treated as host-authored presentation; their position checks do not independently
prove a scientific conversion for arbitrary text.

An annotation contains required `point` (two finite world coordinates) and `text`
(at most256 bytes, no NUL), optional `anchor` (`n,ne,e,se,s,sw,w,nw,center`, default
`sw`), and optional stable `id` matching `[A-Za-z][A-Za-z0-9_.-]{0,63}`. Unknown
fields fail. The owner maps world position to device coordinates and omits an
annotation whose anchor position is outside the plot. Actual font bbox clipping
and hit identity belong to the renderer; supplied text is never an identity.

## Returned schema and coordinate meanings

| Field | Actual content |
|---|---|
| `api_id`, `api_version` |`NATIVE2D_PRESENTATION_SNAPSHOT_v1`,1 |
| `presentation` |Native presentation dictionary, including background RGBA and grid style |
| `view` |`{width height left top right bottom {x0 y0 x1 y1}}`; first six are device pixels/margins, last four world bounds |
| `axis_presentation`, `axis_plans` |Validated descriptor and effective per-axis plans; ordinary plan has world `lower/upper`, `step`, `ticks` with `value,label`. Converted plans also carry display values/mapping/limits |
| `axes_visible`, `point_budget`, `include_construction_reference` |Effective option values |
| `excluded_object_ids` |Native IDs excluded because of reference/construction geometry role; not a complete list of every hidden object |
| `objects` |Visible non-group object snapshots in ascending integer `style.order` |
| `grid_primitives` |Lines with device `a,b`, classification and RGBA/width/style; ordinary scientific grids share planned axis positions |
| `legend_primitives` |Device swatch lines with native `object_id`, style and endpoints |
| `texts` |Device `position`, `text`, `anchor`, `rotation`, `font_size`, RGBA `color`; optional axis/value, object_id, role/annotation_id. X and rotated Y titles include positive pixel `wrap_width` measured before rotation; `text` remains the full original scientific label. |
| `legend` |Requested legend selector, not a complete canonical object catalog |

Each object has `id`, `kind`, `style`, `paths` (lists of device XY lists split at
Native-rendered breaks), `point_indices` from the same display operation, and
`label`. The normal curve path source is Native `render_curve_lod`; other objects
use Native `render_lod`. Group containers are skipped; hidden object/layer is
skipped; visible layer opacity multiplies object color alpha. Ordinary curves
may include `marker` and `marker_style`; compound/composite curves include
`part_markers` entries `{part_id geometry style}` for present visible direction
markers. Directions come from retained Native identity, not sample ordering.

These are device presentation paths and native host identities. They are not
the original canonical Variable arrays, semantic control references, Script
opaque tokens or a retained exact definition suitable for reconstruction. Hosts
may add an explicit bounded `point_markers` list for exporters that support it;
the snapshot owner itself does not synthesize that extension field.

Legend layout uses the visible object styles/labels and is capped by available
viewport/font space and28 rows; omitted entries produce `+N more curves (see
table)`. Equal label text is allowed; object IDs preserve identity. Text, width,
font and marker geometry use device pixels; text rotation is in degrees. A
displayed unit label does not relabel or convert canonical source Variables.

When construction references are excluded and neither legacy tick-label option
is supplied, construction grid primitives are replaced by the shared planned
major scientific grid when visible. With references included, or either legacy
label override, authored Native grid presentation is retained. Clipping and LOD
remain Native-owned; this dictionary is presentation, not scientific export.

## Existing presentation and canvas helper functions

The following are host Tcl helpers in this owner. None becomes a Script/C++
operation merely because it has a public Tcl spelling. Canvas calls require Tk
and change the supplied canvas; their command result is not a structured API
receipt unless stated below. Native object IDs and scenes remain host-owned.

| Exact call, optional defaults | Contract / effect |
|---|---|
| `native2DAxisPlan lower upper pixels ?font=14?` |Increasing finite bounds and positive finite pixel span; returns `lower upper step ticks`, readable nice steps1/2/2.5/5/10 and up to64 ticks. This direct helper expects a sensible positive font; the snapshot validates font6–96 |
| `native2DAxisPlans scene ?font=14? ?descriptor=__scene__?` |Returns `x,y` shared axis plans for actual view/validated descriptor |
| `native2DAxisLabelMargin scene ?font=14?` |Returns ceiling of required Y-label pixel margin, at least60; uses Tk font metrics when available, otherwise width estimate |
| `native2DAxisTitleView scene titles ?font=14?` |Returns a requested view with measured space for supplied `x_label`, `y_label` and graduations; caller applies it through the native view owner. Does not mutate geometry, bounds or source identity. With Tk available, actual font metrics jointly reserve horizontal and rotated multiline title bands, keeping the Y band separate from tick labels. Canvas titles wrap within their available span while retaining the complete original text, units and font size. Without Tk, the helper returns the existing requested view. |
| `native2DPresentationObjectSnapshot scene id ?budget=4096? ?label=""?` |One object dictionary or empty for group/hidden object/layer; budget6–65536, blank label becomes `Object ID` |
| `native2DPresentationMarkers object` |Returns `part_markers` plus an ordinary marker/style entry if present |
| `native2DCanvasDrawGizmo canvas scene background ?tags={}?` |Draws Native-rendered line/circle/box gizmo with composited colors and native handle tags |
| `native2DCanvasDrawObject canvas object background ?tags={}?` |Draws snapshot paths, sample glyphs and direction markers; empty/zero-alpha objects produce no drawing |
| `native2DCanvasSnapshot canvas snapshot` |Deletes prior canvas contents; draws background/grid/objects/legend, clips using a temporary Native view, draws border/text and stable annotation/legend tags; temporary scene is destroyed |
| `native2DAnnotationHit canvas x y` |Transforms event point to canvas coordinates; returns `{hit 1 annotation_id ID bounds BBOX}` for topmost tagged text bbox hit, else `{hit 0}` |
| `native2DLegendHit canvas x y` |Returns `{hit 1 object_id ID bounds BBOX}` for actual combined swatch/text bbox (3px allowance), else `{hit 0}` |
| `native2DCanvasClipItems canvas scene items` |Native segment clipping with half-stroke inset for lines; may split/delete/recreate items. Deletes crossing oval/polygon/text; intersects rectangles with plot bounds |
| `native2DCanvasViewportClip canvas scene ?textTags={axis_label}?` |Clips items except supplied text tags plus `axis_graduation`, `plot_border`, `viewport_margin`; no margin-mask or geometry translation |

The companion axis owner supplies these exact shared host functions:

| Exact call | Result / boundary |
|---|---|
| `native2DAxisPresentationValidate scene descriptor` |Normalized validated x/y descriptor; image_id context becomes stable image_resource_id after verification |
| `native2DAxisImage scene context` |Native image ID from explicit image_id or unique matching retained image_resource_id; missing/ambiguous resource fails |
| `native2DAxisCoordinatePlan scene axis settings` |`kind scale offset unit` for verified invertible display mapping |
| `native2DAxisPresentationRescale scene descriptor factor` |Validated descriptor with explicit tick step rescaled by positive finite factor; non-world context with factor other than1 requires explicit rebinding/revalidation |
| `native2DAxisPresentation scene ?descriptor=__query__?` |Query stored Native descriptor, or delegate explicit set to Native axis presentation |
| `native2DAxisPresentationDefault scene` |When the scene contains exactly one native object and it is a visible uncalibrated image, validated original-pixel integer axes; otherwise empty descriptor |
| `native2DAxisPresentationPlan scene axis lower upper pixels font settings` |World-position ticks, display labels/values and verified mapping; empty settings uses ordinary planner; incompatible precision/interval or duplicate labels fail |

Axis descriptor keys are only `x,y`; settings accept `title`, `unit_label`,
`ticks`, `context`. Titles/unit labels are at most256 characters. Tick policy:
`placement=auto|integer`, `step=auto|positive_finite`,
`format=auto|integer|fixed_decimal|significant_digits`; precision is0–15 decimals
or1–15 significant digits only for the corresponding format. Integer format
implies integer placement. Explicit step must match precision/placement; effective
step may be multiplied for readable pixel spacing. No unit is fabricated by
numeric formatting.

Context defaults to `{kind world}` (no arbitrary unit label). `conversion` uses
`source_unit,target_unit` and a validated affine Unit Registry plan. `image_pixel`
requires a verified axis-aligned Native image mapping and uses `px`, without a
physical target unit. `image_physical` requires actual calibrated Native image,
its declared length unit and an optional compatible target_unit with proportional
zero-offset conversion. A requested unit_label must equal the verified mapping's
unit. Image movement/calibration can invalidate captured mapping; validation is
repeated against actual Native image state. These are view-only label/tick
conversions; geometry and Dataset units stay with their scientific owners.

## Host example and error boundary

With a live already-owned native scene and optional existing Tk canvas:

```tcl
set options [dict create point_budget 4096 legend auto \
    annotations [list [dict create id note1 point {0 0} text Origin anchor sw]]]
set snapshot [::GX::native2DPresentationSnapshot $nativeScene $options]
# Optional host rendering, not a requirement for obtaining inert data:
::GX::native2DCanvasSnapshot $canvas $snapshot
```

This example is source-backed and unexecuted here. Invalid scene/Native state,
unknown options, malformed/missing dictionaries, out-of-bounds budget/font/
annotations/ticks and invalid/stale axis mappings raise errors. Drawing can fail
on a missing/destroyed canvas or Tk/color/font issue. There is no transactional
canvas rollback claim. The snapshot call does not independently prove a supplied
Document/Session revision or the authenticity of arbitrary caller labels/data.
Use the owning host lifetime and public Document/geometry contracts. Successful
snapshot/render/export is not full Dataset materialization, scientific
uncertainty propagation or numerical/installed GUI acceptance.

## Canvas text alpha and resource lifetime

The shared `native2DCanvasTextDraw` adapter keeps opaque text on the existing Tk
text-item path. For alpha below one, its matching precompiled Native2D device
adapter obtains coverage using the same Tk font and multiline layout, rotates
the coverage with the existing Cairo dependency and supplies a transparent RGBA
Tk photo. Canvas composition therefore uses the actual items below each glyph
pixel, including nonuniform rasters. No background sample, scientific Dataset
mutation, intermediate file, worker or runtime compilation is needed.

The photo is owned by the canvas/item pair. Repaint and clipping release deleted
items, and canvas destruction releases remaining photos. The existing omission
policy for text crossing the plotting bounds also applies to these owned text
photos; generic raster images are not classified as text. Retained item tags and
actual rendered bounds remain the hit-testing and annotation-panel contract.
The internal device command `::gx::native2d::text_photo photo font text anchor
angle rgba` is a host adapter, not an unrestricted Script Bridge or Viewer SDK
entrypoint. A mismatched older device adapter produces a precise compatibility
error; normal runtime never rebuilds it.
