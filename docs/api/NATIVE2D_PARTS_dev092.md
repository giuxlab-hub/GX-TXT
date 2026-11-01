# Native2D constituent contracts — dev092

Additive to `NATIVE_2D_GEOMETRY_API_v1` version 1. Existing operation signatures
and the public C `gx2d_sketch_definition` POD layout remain unchanged. The C
implementation owns all constituent identities, directions, picking, geometry,
projection and presentation. The Viewer stores only transient gesture/focus targets.

## Identity and lifetime

`composition_parts {object_token}` returns `parts` and `traversal`. Each part
contains `part_id` (positive int64), `ordinal` (zero based), `definition` (exact
leaf in the parent frame), `reversed` (retained topological orientation),
`direction`, `effective_direction`, `topology_epoch` and
`part_ref {object_token part_id}`. Always use the pair; IDs are parent scoped.
No canvas ID, sample index, or surviving input object is a constituent identity.

Affine, units, parameter and control edits retain the constituent identity.
An unannotated layout replacement mints new IDs; old references fail lookup.
An explicitly owned serialized definition restores its recorded leaf identities
and state atomically. The root `part_identity_counter` persists the allocation
high watermark, preventing reuse after removed leaves and save/reopen. A native
clone retains local IDs under its **new parent**. Split retains the corresponding
IDs under the two new parents. Explode creates new independent object identities
and transfers each marker and chosen direction. Flattening a new composition
mints IDs under the new parent, preserving constituent marker state; existing
public parent-geometry tokens and Workbench ancestry record input lineage.
Deleted parents, unowned public object tokens and unknown part IDs are rejected.
Topology epochs belong to existing semantic references; marker-only edits do not
invalidate them. Part references locate a retained leaf by identity rather than
requiring a rendered-sample epoch.

## Independent state and interaction

`part_direction {object_token part_id ?changes?}` gets or updates the marker.
`part_direction_batch {object_token updates}` accepts a list of
`{part_id changes}` dictionaries and validates **every** update before committing.
Empty/invalid/nonfinite/out-of-range or unknown fields obey the existing marker
validator. One failure leaves all marker and geometry state unchanged.

Marker fields retain existing names and limits: `present`, `visible`, `forward`,
`fraction` (0–1), `offset_px`, `length_px`, `line_width`, `head_scale`, `color`
(RGBA), `interpolation`. Newly loaded legacy constituents are hidden, with native
IDs and forward direction derived from retained `reversed`. Their unconfigured
marker inherits current parent appearance upon the first individual edit. Native
part rendering uses retained geometry, never a module interpolation model;
`interpolation` is ignored for exact retained leaves. Ordinary/simple Path parent
markers keep their established state and controls. Direction changes do not
reverse controls, move nodes or rewrite the exact definition.

`part_render {object_token part_id}` returns a bounded device polyline for precise
feedback. `part_marker_geometry` returns `geometry {anchor tail tip head_left
head_right fraction}`, or an empty dictionary when hidden. `part_marker_hit`
takes `device {x y}` and optional `tolerance_px` (default 5); `part_marker_place`
projects the device location onto **that leaf only** and updates `fraction`.
`part_pick {object_token device ?tolerance_px?}` maps the existing checked semantic
pick to a constituent ID; no hit returns an empty/null ID. Fraction uses native
sampled **physical arc length**, including the parent's affine transform, with
4097 curve samples for marker projection and tangent display. It is a presentation
metric, not an analytic length promise or a materialization sampling policy.
Placement/flip is reflected by the shared geometry API and both Script Bridges.
Device operations use the current scene viewport. `part_render` is bounded at
4096 display points; source controls and publication are unaffected.

Public C exports are declared in `gx2d.h`: composition states/restore,
identity counter, atomic `gx2d_sketch_update_parts`, part ordinal/direction,
render/hit/place/pick, and traversal. Tcl `sketch_definition` adds per-part
`part_id`/`direction` and root `part_identity_counter`; legacy dictionary parsers
remain tolerant of these additive fields. The ordinary C mathematical definition
query is unchanged; C clients explicitly obtain/restore the adjacent state array.

## Compound references and publication

Existing checked control/segment reference, pick and render APIs now cover
unordered compounds. No new unsupported solver family is silently enabled.
A constraint overlay resolves its stored `a_index`, `b_index` and `axis_index`,
and paints only those references. Whole-object feedback is used only for an
actual whole-object semantic reference.

`composition_traversal` returns `unordered` for a Compound, `continuous` for a
validated chosen endpoint chain, or `network` when the stored/chosen order is
not a continuous walk or native node incidence is branched. Retained composite
networks from dev065 remain exact networks. Storage order is never silently
promoted to a scientific traversal. Parent forward reverses an ordered chain;
individual directions remain separate from retained topological reversals.

New single ordered publication requires `continuous`; other compositions use
reviewed separate constituent outputs. Each separate output records the complete
source definition, durable part ID, ordinal, direction and logical ancestry.
Ordered publication records `traversal_contract 2` and constituent state in its
sampling provenance. Only identical shared boundary rows are deduplicated;
near-coincident but distinct endpoints are retained, even within join tolerance.
Curved sampling remains the explicit existing uniform-parameter policy.

Exact reconstruction of already published `ordered_constituents` provenance
without `traversal_contract` replays its historical recorded policy, including
its former boundary removal. This replay is **only** a verification path for
existing immutable Datasets; it is unavailable to new publications. Native exact
geometry and original Dataset values are never rewritten by reconstruction.

Existing document resources, workspace payloads, recovery, recipe patches and
Undo/Redo carry the owned dictionaries; no second journal or schema migration is
introduced. Python and Octave share registration and typed transport. Typed part
IDs remain integers, colors/marker points remain numeric vectors, and resources
preserve provenance `origin` dictionaries rather than misreading them as XY
origins. The existing selection-set add-member scoped binding now passes its
required one-element native list; the original Python/Octave consumer regression
exercises this correction.

## Calibration reset

`image_calibration_reset {object_token}` delegates to existing native image
update with `calibrated 0`. It retains raster bytes, transform, opacity, unit and
identity. Native relationship guards remain active: incompatible live driving
reference dimensions reject reset rather than silently detach constraints.
Recalibration uses the existing two-point uniform similarity transform. Units
are converted by the shared Unit Registry; pixels alone never claim metrology.

## Shared scene presentation

`native2DPresentationObjectSnapshot` adds `part_markers` (durable part ID,
geometry and style) for compositions, suppressing the misleading parent marker.
`native2DPresentationMarkers` supplies the common list to the existing native
canvas and raster-preview presenters. Workbench paints only transient subpath
highlight feedback; arrow painting is shared CORE functionality. Hidden parts
avoid marker sampling. Object/layer opacity applies consistently in both outputs.
Calibrated image dimensions are reference measurements, with the existing native
read-only geometry guards retained. The scale readout in a calibrated image form
is read-only; reset/recalibrate is the explicit way to change physical scale.

Octave preserves ordinary integer receipts as doubles for compatibility. IDs at or
above `flintmax` use exact int64/uint64 bridge scalars; typed integer arguments use
integer transport. Avoid constructing an imported large ID from a rounded double.

Native display layout also retains near-but-distinct constituent boundary vertices.
The existing explicit `sketch_materialize` uniform-parameter contract requires a
continuous composition, applies its chosen constituent directions and root reversal,
and rejects compounds/branched or disconnected networks atomically. Uniform
parameter sampling remains distinct from boundary-preserving `primitive_publish`
constituent sampling. Noncomposition signatures and sampling behavior are unchanged.
