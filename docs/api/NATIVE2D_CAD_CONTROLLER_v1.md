# Native2D CAD context — additive NATIVE2D_API_v1 host interface (P016)

Discover with `::GX::native2DCadApiInfo` or CORE API discovery. This is an
extension of **NATIVE2D_API_v1**, not another geometry engine or Document token
registry. C++ owns a managed context over an existing Native2D C scene. Native C
remains authoritative for scientific objects, references, topology, constraints,
snapping, selection and drag transactions. The original native adapter's checked
parsers/result schemas are reused through a direct C function call, without Tcl
evaluation or imports from Curve Workbench. All calls run on the owning GUI thread.

`NATIVE_2D_GEOMETRY_API_v1` continues to own Document-scoped tokens, units and
managed scientific resources. Its object tokens are **not** raw scene/object IDs
and cannot be passed here. Restricted workers acquire no GUI permission from this
host API. No addresses are exposed in Tcl.

## Context, ownership and lifecycle

```tcl
set cad [::GX::native2DCadCreate nativeScene ?nativeSelectionSet0? ?ownerWidget?]
$cad state                         ;# api_id/alive/scene/selection/gesture/native_drag
::GX::native2DCadDispose $cad       ;# idempotent, also: $cad dispose
```

Scene/object IDs are those returned by the existing `::GX::Native2D::core`
interface. The context does not own or copy scientific geometry. The optional
widget owns context disposal, not the scientific scene. Without a widget, dispose
explicitly. Contexts and the retained presenter share a revocable native scene
lease; destroying the scene synchronously detaches presentation, invalidates
contexts and prevents subsequent dereference. `state` and `dispose` remain valid
on a revoked context. Canvas disposal never destroys scientific geometry.

A context adopts an existing semantic selection set or lazily creates one when
applying selection. It deletes only sets it created; an adopted set retains its
original owner. `selection adopt` follows restoration/replacement by that owner.
One native set owns membership; returned UI projections are readouts, not another
selection authority. Multiple contexts may exist, but only one native drag can
own a scene. Do not bypass an owned gesture with raw drag/cancel commands, delete
its selected objects, change its selection or mutate its scene mid-transaction.
Native `busy` and scientific validity checks remain in force.

## Selection

```tcl
$cad selection get                              ;# {id members}
$cad selection snapshot                         ;# also references and object IDs
$cad selection adopt setOr0
$cad selection apply members ?replace|add|subtract?
$cad selection restore members ?replace?         ;# native restore semantics
$cad selection reference object kind index
$cad selection pick scopeIds deviceXY tolerancePx ?detail|local|object?
$cad selection region scopeIds polygonWorld maximum ?detail|local|object?
```

Members use native `{kind object|point|control|segment|fragment id ID index N}`.
Native get adds validity/epoch data. Snapshot returns checked typed `references`
with `semantic_kind`, and unique parent `objects` (including valid fragments).
References contain native object/entity/index and topology/parameter epochs; use
returned references rather than synthesizing their private layout. `reference`
accepts a point/defining-control semantic index or a segment ordinal. Object kind
ignores the index and resolves the whole native object. Native control indices
are not sampled display-point indices. Pick returns a typed reference or `{}`;
region returns native member records. Region is query-only until `apply`.
C owns hit ranking, visible/selectable geometry, additive/subtractive membership,
region geometry and projection to native selection flags.

```tcl
::GX::native2DCadSelectionPresent cad canvas ?options?
::GX::native2DCadComponentPresent cad canvas object partId
```

These shared host operations draw standard transient semantic highlights through
the existing public Canvas presentation owner, preserving native clipping.
Options are native ID lists `exclude_objects` and `point_objects` (whole-object
feedback as point rings). Caller owns the frame/clearing of these overlays; no
persistent scientific state is modified. Object/component feedback uses bounded
existing native projections. Only selected overlays use this Tcl snapshot path;
ordinary retained scene synchronization uses the direct native sprite interface.

## Objects and retained components

```tcl
$cad object create definition sampleCount          ;# native ID, explicit display budget
$cad object definition object                     ;# exact native definition
$cad object controls object                       ;# defining descriptors
$cad object bounds object                         ;# world rectangle
$cad object style object ?changes?
$cad object direction object ?changes?
$cad object transform objectIds affine6 ?copyBool?
$cad object delete object
$cad object join objectIds reversals mode tolerance
$cad object retarget targetObject sourceIds
$cad object separate object
$cad object split_path object vertex
$cad object split_composition object junction
$cad component list object
$cad component pick object deviceXY ?tolerancePx?
$cad component direction object partId ?changes?
$cad component place object partId deviceXY
$cad component render object partId
$cad component marker object partId
$cad component hit scopeIds deviceXY tolerancePx
```

Definitions/styles/affine matrices use the established C adapter schemas; style
color is RGBA, line width positive, native visibility/locking/layers preserved.
Join mode is `0` Compound, `1` ordered, `2` infer connected Path. Reversals is an
empty list or one boolean per input. Native join creates a new exact retained
object; the Viewer decides whether to keep/delete source objects and records its
History. Separate returns new exact constituent copies and preserves the parent.
Split returns new native objects and preserves existing scientific validation.
Retarget keeps original constraint references as supported by C; errors propagate.

Part IDs are parent-scoped stable native identities, not ordinals or input object
IDs. See `NATIVE2D_PARTS_dev092.md` for exact constituent/traversal contracts.
`component hit` consolidates the existing visible constituent **direction-marker**
hit search in native code and returns `{object partId}` or `{}`. Geometry component
picking uses `component pick`. No independent compound leaf transform is invented;
use supported native defining-control edits or Split/Separate, then edit the
resulting exact constituent. Core C remains responsible for topology integrity.

## Defining controls and relationships

```tcl
$cad control inspect object
$cad control resolve reference
$cad control point_index reference
$cad control preview reference targetWorldXY       ;# exact proposed definition
$cad control edit reference targetWorldXY          ;# native validated mutation
$cad relationship options referenceList           ;# compatible native specs
$cad relationship apply existingOr0 specification
$cad relationship create specification
$cad relationship get relationshipId
$cad relationship list
$cad relationship update relationshipId specification
$cad relationship enable relationshipId boolean
$cad relationship remove relationshipId
$cad relationship join objectA indexA objectB indexB mergeBool tolerance
$cad relationship dimension_infer references annotationWorldXY
$cad relationship dimension_preview specification annotationWorldXY
$cad relationship dimension_apply existingOr0 specification drivenBool annotationWorldXY
$cad relationship dimension_geometry relationshipId
$cad relationship state relationshipId ?changes?
$cad relationship location relationshipId
```

Controls come from actual native definitions, including supported Bézier/spline
controls and composite references. C validates epochs and constraints; display
samples never become defining handles. Preview does not mutate the object.
Relationship receipts retain `id/kind/a/b/axis`, semantic indices, `valid`,
`geometry_supported`, measured values/residuals, `disabled`, `solved`, `driven`,
annotation and enforcement status. Kind-specific compatibility is queried through
`options`; unsupported combinations fail, not approximated. Horizontal/vertical,
coincidence, Fixed, tangent, point-on-curve and dimensional support remains exactly
that of C. `join` establishes point coincidence (optionally native merge), whereas
`object join` creates logical retained topology. Native dimension inference,
solver and primitives are reused; Viewer unit declarations/formatting, inspectors
and History remain with their established owners.

## Manipulation transaction

```tcl
$cad gesture begin x|y|free|rotate|pivot|mirror_a|mirror_b startDeviceXY targetIds
$cad gesture begin_points startDeviceXY pivotWorldXY
set proposal [$cad gesture plan currentDeviceXY ?objectSnapBool?]
# Optional caller admission: scientific frame/units/readonly/source rules.
$cad gesture apply
$cad gesture commit
$cad gesture cancel
```

Selection is established before begin. Target IDs define the object-snap exclusion
scope, **not** a second selection. C++ coordinates the existing native gizmo,
world/device conversion, grid snap and object-snap operations. Plan returns the
native `pivot/translation/world_point/radians` fields applicable to the operation,
and optional `snap_target`; it does not move scientific geometry. Apply uses that
stored proposal. This explicit boundary lets a scientific Viewer reject a snap
across incompatible declared coordinate frames before geometry changes, without
callbacks/reentrancy from C++. Begin-points uses the native selection-set projection
for selected defining controls/points and the same C drag engine.

Commit validates in C. A rejected native commit is followed by native cancel,
restoring original geometry and releasing the owned transaction. Cancel restores
native coordinates or the previous pivot/mirror state; repeated cancel is safe.
A failed plan/apply must be cancelled by the caller before changing tools. Disposal
cancels an owned gesture. No internal dragging flag is cleared arbitrarily.
The Viewer wraps successful commits in its existing History/Undo/Redo and source
metadata orchestration. This API neither adds a journal nor publishes a Dataset.

## Independent use

```tcl
::GX::native2DEnsure
set scene [::GX::Native2D::core scene]
set cad [::GX::native2DCadCreate $scene]
set id [$cad object create {family line controls {{0 0} {2 0}}} 64]
$cad selection apply [list [dict create kind object id $id index 0]]
::GX::Native2D::core gizmo $scene {visible 1 mode translate}
$cad gesture begin free {100 100} [list $id]
$cad gesture plan {120 100}
$cad gesture apply
$cad gesture commit
::GX::native2DCadDispose $cad
::GX::Native2D::core destroy $scene
```

The accompanying independent contract consumer does not load Workbench. Ordinary
presentation uses `native2DSpriteSceneSync` with this same scene and object IDs;
no Viewer-specific geometry cache or topology reconstruction is required.
