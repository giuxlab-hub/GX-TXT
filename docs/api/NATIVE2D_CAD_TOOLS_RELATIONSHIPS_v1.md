# Shared advanced constraints and dimensions — NATIVE2D_API_v1 (P019)

These operations extend the same public embedded CAD Host and its Advanced tool
controller. They are not a second Canvas, solver, selection registry or History.
`set tools [$host advanced]` uses the existing native C++ CAD context; Native2D C
owns all references, compatibility, inference, solving and projected primitives.
No private Curve Workbench procedure is imported by CORE.

## Constraints

```tcl
$tools constraint start kind ?nativeReferences?
$tools constraint input nativeReference ?add|subtract|replace?
$tools constraint state
$tools constraint options ?nativeReferences?
$tools constraint apply existingRelationshipOr0 nativeSpecification
$tools constraint inspect nativeRelationship
$tools constraint list
$tools constraint reference_proposal nativeRelationship
$tools constraint manage nativeRelationship remove|toggle|enable|disable|reference
$tools constraint manage nativeRelationship update nativeSpecification
$tools constraint present canvas relationshipIds ?options?
$tools constraint pick deviceXY nativeIdToBounds
$tools constraint cancel
```

The controller owns collecting, ready, rejected and committed proposal states.
It accepts one to three actual typed native references, preserves point/control/
segment identity, queries native compatibility and updates the authoritative
native selection set through the same Host. No sampled point becomes a defining
control. `options` retains the existing general-solver/fixed eligibility filter.
An incompatible set is rejected and cleared; Native C validates again on apply.
Application is an existing native apply/dimension_apply, not new mathematics.

`reference_proposal` is read-only and returns a native dimensional specification
whose measured value/driving flag can be admitted before apply. Native `driven=1`
means **reference measurement**, whereas0 requests driving behavior where supported.
`manage reference` performs that same proposal/apply workflow. Source/units/readonly
and History are enforced through the existing Host advanced admission/commit hooks
or an external consumer's scientific orchestration.

`present` options: selected/hover native IDs, show_constraints/show_dimensions
booleans and optional format_command prefix(receipt,value,referenceBool)→text.
It returns nativeId→device bounds. Native dimension/relationship primitives and
hit scores remain authoritative; the bounds represent typography/GUI feedback.
Presentation/picking are read-only and require a live native context, rather than
an edit-busy admission guard. Mutation, inference and previews retain normal
source/generation/domain guards. Unavailable presentation sources return empty.

## Dimensions and annotation

```tcl
$tools dimension start ?forcedKind? ?nativeReferences?
$tools dimension input nativeReference modifierBits
$tools dimension preview deviceXY
$tools dimension edit nativeRelationship
$tools dimension apply existingOr0 specification referenceBool annotationWorldXY
$tools dimension annotation_start nativeRelationship deviceXY
$tools dimension annotation_move deviceXY
$tools dimension annotation_commit
$tools dimension annotation_reset nativeRelationship
$tools dimension draw canvas nativeGeometry formattedText color ?options?
$tools relationState
$tools dimension cancel
```

Preview returns state with references, native specification, annotation, geometry,
status and explicit error. Unsupported/physically inadmissible proposals clear old
geometry instead of leaving a stale preview. `edit` rejects reference dimensions
until the user explicitly switches to driving. Annotation movement previews the
native geometry and commits only on release; cancel mutates nothing. The same
advanced Run admission/begin/committed/rollback hooks own mutation orchestration;
no private Undo stack is introduced. Consumers submit accepted native changes to
P017 History and own scientific restoration if their adoption hook fails.

The default embedded Host routes these tools through its existing input dispatch,
draws standard badges/measurements, and supports annotation selection/positioning.
External renderers use present/draw with their own labels/visibility policy.

The default Host draws a new dimension's native projected proposal before commit,
using the same shared dimension primitives. Its owned transient preview/marker
items are replaced on redraw. Existing annotation drags substitute projected
geometry for the committed annotation and preserve its reference/driving style.
Neither preview updates a native relationship; Escape discards it.
Every proposal redraw obtains its current projection from the existing native
specification and world annotation. View changes do not reuse old device points.

## Lifecycle and mutation boundary

`$host event key Escape` cancels both the Advanced proposal/editor and the basic
Host interaction scope. A staged dimension or annotation is not a C geometry drag.
Every actual apply/manage/annotation commit uses the shared `Run` admission and
source-generation checks and rejects while `targetsMutable` is false. No timer
commits an abandoned proposal, and an unchanged annotation produces `changed 0`.

Host reassociation cancels the old proposal before replacing the scene/context.
Host destruction disposes the Advanced controller and its editor/layout callback;
consumer scientific geometry remains owned by the consumer. An externally closed
scene is rejected on mutation, and relationship presentation returns empty when
the native context is no longer live. The consumer must detach/dispose its Host
when closing its own scene or Document; the tools do not acquire scene ownership.

History is explicit: independent consumers use optional Host `advanced` hooks to
capture/adopt an accepted change through P017 services. Workbench keeps its domain
snapshots and logical adoption outside CORE and therefore does not record History
again in those hooks. Cancel, preview, selection and redraw never create History.

## Embedded configurable editor

```tcl
set editor [$tools dimension editor_create widgetPath options]
pack $editor -in hostChosenPanel -fill x
$tools dimension editor_value ?newText?
$tools dimension editor_update {message text title text value text}
$tools dimension editor_commit ?referenceBool0?
$tools dimension dispose
```

The editor is one child frame created through UI_FIELD_API_v1 components; it never
creates a toplevel. The consumer packs/grids/places it. Optional canvas and
anchor_device options place an overlay within that existing Canvas. Default width
is280. Owned idle layout recalculates its requested height when messages/reference
controls change, fixing the old fixed-height clipping. All pending layout work is
cancelled on disposal; no polling or background Tk work is added.

Options:

- specification, existing(default0), annotation(world XY), value(initial display
  text), title, message, width, reference_only and focus(default1).
- native_unit/display_unit plus absolute(default0): default numeric and explicit
  `number unit` input uses existing Unit Registry affine plans; absolute enables
  affine offset for position-like parameters. No unknown units are inferred.
- parse_command(specification,text)→{value expression}: optional scientific owner
  parser for coordinate snapshots, physical admission and established Parameter
  scopes. CORE does not evaluate a consumer's formula in a different scope.
- commit_command(event)→receipt: optional domain adoption route; otherwise the
  shared native dimension apply runs through normal advanced hooks.
- accepted_command(event), cancel_command(reason), guard_command()→boolean:
  bounded owning-thread lifecycle hooks, never worker calls.
- canvas and anchor_device are optional; omit them for a caller-owned external
  panel layout.

Commit event fields: native specification/existing, expression, reference and
annotation; accepted adds receipt. Source guards run before parsing/mutation.
Driving conflicts retain the editor and offer the existing native reference
fallback where applicable. Escape closes/cancels without scientific mutation.
No History step is generated by the editor itself, harmless selection or repaint.

Workbench supplies only its unit/source/parameter parser, logical relationship
adoption, UI labels and P017 History orchestration. The shared native input,
proposal, editor, annotation and marker code is used by the independent consumer
without loading Workbench runtime files.
