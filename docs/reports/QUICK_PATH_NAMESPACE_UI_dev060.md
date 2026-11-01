# GX-TXT 0.9.8.10-dev-060 — Path and namespace UI acceptance

The published dev-059 framework is the frozen predecessor. The dev-060 work
extends its existing Native2D, Dataset Metadata/Catalog/Namespace, Session
Persistence and Interactive Document authorities. No alternate geometry,
Dataset or namespace store was introduced.

The Session Workspace asynchronous refresh now treats an absent Session as an
empty state and does not request a Document Session token. The Session tab and
Workspace panel render without a Session or background error.

Curve Workbench 2.8.0 gives the shared Native2D arrow glyph to both Select
toolbar controls and removes the expanded textual Select control. Join (`j`)
now consumes a compatible selected chain into one top-level logical Path. The
existing Native2D composite retains deep exact leaves and their order/direction;
Workbench ancestry retains source definitions and provenance. Internal
coincidence constraints created by endpoint snapping become the Path's shared
junctions. A constraint referring also to an outside object blocks Join instead
of silently retargeting. The existing workspace snapshot authority restores
source geometry and those internal constraints on Undo; Redo restores the Path.
Separate creates exact editable copies and leaves the Path intact. Join does
not reinterpret a branch, gap or closed component as a single traversal;
Compound remains available for those topologies.

The Dataset browser now keeps row highlight distinct from the existing active
inspection choice. Only the small row glyph or an explicit context command
activates a Dataset. Namespace and Dataset context commands create empty
namespaces and move Datasets. The manager's tree exposes hierarchy and members;
its controls set the current namespace and move a Dataset, including by drag
and drop. Empty namespaces persist in the existing Session Manifest's Dataset
organization section. `datasetNamespaceCreate` is a host-only user/admin CORE
operation; Python/Octave `list` still reads the same authority. Dataset moves
preserve canonical IDs and the private/public metadata boundary.

## Decisive local GUI evidence

Validation ran on the normal giu XFCE desktop, GDM-authenticated seat0/tty2,
local Xorg `:1`, `Remote=no`. GX-TXT/Tk rendered on that Linux server. The
observer queried state and widget coordinates; construction, menu, drag, click,
save and reopen actions used actual local X11 input. No forwarded display,
VcXsrv or SSH X11 transport was used.

- `_evidence_dev060_local02/04-direct-window.png`: the empty Session tab and
  Workspace area, no background error.
- `_evidence_dev060_local02/06-dataset-initial.png` through
  `09-dragged-dataset.png`: highlight/right-click do not activate; glyph
  activation does; the manager shows hierarchy/membership and a real drag moves
  `measured059` without changing its Dataset ID or the active Dataset choice.
  The Dataset context also created and moved another Dataset to a new namespace.
- `_evidence_dev060_local03`: the same final executable code hosted a fresh
  real-GUI browser namespace-context creation of empty
  `analysis/from_browser060`; it appeared in the tree without activation or a
  background error.
- `_evidence_dev060_path06`: six inspected Tk-window screenshots and the actual
  input log. A connected Polyline, Spline and quadratic Bézier became one Path
  object with three exact Native2D leaves (`polyline`, `spline`,
  `quadratic_bezier`). Join removed only the two internal coincidence relations;
  Undo restored three exact sources and both relations; Redo returned one Path.
  Separate made three editable exact copies; Undo and Session save/reopen
  restored the single logical Path and exact leaf definitions. Both pictographic
  Select toolbar controls were visible. The result receipt is `PASS`.

The final GUI host's controller-error log is empty. Screenshots were inspected
as rendered Tk windows. Root captures that showed another desktop window over
the Tk client were excluded; the local pointer actions still reached the Tk
client and the window-ID captures show its rendered content.

## Supplementary validation and limits

The CORE namespace regression passed 56 checks, including empty namespace
Manifest persistence/reload and catalog notification. Registered Script Bridge
coverage passed for 66 APIs; the new host-only create policy is documented in
the existing Dataset Namespace v1 entry. The existing Native2D retained
composition implementation and matching adapter binaries are unchanged from
the published dev-059 release; the affected user workflow was accepted through
the real GUI. Prior dev-059 geometry and Dataset tests remain predecessor
evidence, not a substitute for the dev-060 GUI journey.

The Path has one truthful traversal and does not perform a Boolean union.
Nested constituent handles are edited through Separate. Curved finite Dataset
sampling does not replace exact retained geometry. A Join involving a constraint
to unselected geometry is rejected until the user revises that relationship.
Manual user review follows publication and handoff.
