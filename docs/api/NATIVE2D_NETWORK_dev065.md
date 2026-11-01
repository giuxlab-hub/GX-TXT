# Retained sketch networks — dev-065

A user-facing Path is one retained `composite_path` with exact flat constituent
definitions and a canonical node map. It need not be a degree-two chain. Supported
leaves include Line, Polyline/segmented Path, Arc, Spline, quadratic/cubic Bézier,
and compatible circle/ellipse/rectangle controls. Points/construction lines are
not curve leaves. Existing practical bounds are 256 flat leaves and 65536 controls;
constraint solving has a separate bounded 1024-parameter / 4096-residual budget.
Over-budget operations fail, rather than truncating geometry.

`gx2d_composition_create(...,ordered=2,...)` / Tcl `composition_create ... 2 tolerance`
collects connected exact constituents into a network. `nodes` stores, for every
flattened defining-control ordinal, its first canonical equivalent ordinal.
Construction establishes equivalence; later coordinate equality does not weld
unrelated points. Validation checks canonical IDs, shared positions and connected
constituents. Serialization, cloning, rollback and resources own/preserve the node
array. Old dev-063 ordered chains without `nodes` retain their original semantics.
Network display breaks between exact constituents, avoiding false straight bridges.
A branch has no unique global traversal or enclosed area: the existing whole-object
parameter follows storage order; use exact part queries for scientific traversal.
Separate is available but unnecessary for editing controls, splines or constraints.
Split at a part boundary remaps each side's node IDs and rejects disconnected sides.

The CORE attached-construction authority establishes explicit connections when a
retained defining point is clicked. The host's `native2DConnectedObjects` expands
the full active coincidence component, then requests CORE composition. Network node
connectivity is recognized even without redundant coincidence rules.
`gx2d_composition_retarget` / `composition_retarget scene target source_ids`
retargets all source constraint endpoints, including external relationships, into
the new Path without changing rule identities. Source deletion is the caller's
subsequent adoption step; failures roll back the existing authority. This raw scene
adoption helper is host-only; scoped Bridge composition/constraint/resource APIs
already expose reusable network operations without raw scene ownership bypass.

Control references use existing flattened control ordinals. Segment references
encode leaf and local segment as `GX2D_SEGMENT_INDEX + leaf*65536 + segment`;
65535 selects a complete curved leaf. Public interaction picking, reference,
compatibility and application APIs resolve exact borrowed leaves and map results
back to stable root references. Two segments in one Path, a Path and an external
object, or constituents in two Paths use the same existing constraint authority.
Points, curves and segments still obey geometric compatibility; membership itself
is not a refusal reason. Unsupported/conflicting relationships return diagnostics.
Spline tangent query/edit resolves the exact leaf and retains one root object.

Native component solving collects leaf variables and adds each shared-node equality
as a residual. Intermediate candidates validate leaf geometry; final adoption also
validates topology. All incident controls move in one transaction. The public
`gx2d_constraint_values` / `interaction_constraint_values scene {id value ...}`
updates a dimension batch across components atomically, restoring rules and exact
retained geometry if any component fails. Parameter consumers use this operation.
The three delivered Tcl native adapters are byte-identical.

## Functional interaction reference

Reviewed Autodesk's current [sketch constraints documentation](https://help.autodesk.com/cloudhelp/ENU/Fusion-Sketch/files/SKT-CONSTRAINTS.htm)
and [parameters documentation](https://help.autodesk.com/view/fusion360/ENU/?contextId=SLD-MODIFY-PARAMETERS)
on 2026-10-09. They describe individual geometric targets, compatible relationships,
and expressions driving design dimensions. GX-TXT adapts selection-before-action,
contextual commands and inspectable relations, without copying Fusion's appearance.
Existing Native2D capabilities include horizontal/vertical, coincidence, tangent,
equal size, parallel/perpendicular, fix, midpoint, concentric, collinear, symmetry
and supported curvature relations. Availability is computed from exact selection;
Fusion's wider expression/type system is not claimed as GX-TXT functionality.
