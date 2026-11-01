# GX-TXT dev-059 — consolidation, exact composition and Dataset organization

This completes the same unpublished candidate based on manually accepted local
Linux dev-057. It does not restart from dev057 or use dev058 product changes.
The current authoritative user task and permanent rules define the scope.
The earlier straight-only curved Join blocker is resolved in Native2D.

## Architecture and behavior

The architecture was mapped before refactoring. Workbench capture/restore,
render ordering, persistence/close, pointer dispatch, UI construction/open and
semantic selection now have explicit owners. The final audit records 34 sources,
605 definitions, 575 loaded procedures and 88 rename wrappers, down from 199.
Remaining wrappers preserve feature compatibility; this cycle does not claim
that every legacy layer was removed. The 16 ms draw coalescer, deferred view
persistence, scientific authorities and document/recovery lifecycle are preserved.

A shared command registry drives creation, bulk object operations, menus,
contexts and configurable shortcuts. Pictographic Select and transform/pivot
icons expose their modes on right-click. Ctrl adds and Shift subtracts, including
transform-mode picks; rectangle and polygon selection are tested. Empty-canvas
context, persistent creation, visible tool status, text-focus protection, bulk
Delete/duplicate/reverse/visibility/locking and graphical pivot placement work
through normal GUI controls. Configuring and restoring shortcuts is persistent
through the existing Configuration authority.

Native2D owns exact heterogeneous `composite_path` and `compound` definitions,
constituent orientation, connectivity, transforms, evaluation, sampling, copy
adoption, Split and Separate. The Tcl/Bridge public Geometry v1 interface is
extended compatibly. No viewer geometry engine or sample-backed substitute for
retained definitions was added. Rectangle/Spline works as Compound; Line/Arc/
Spline works as an endpoint-connected Path. Sources are preserved. Compound
publication uses reviewed separate outputs; Path publication uses exact straight
vertices and explicit curved sampling. Mixed Dataset selection offers reviewed
retained promotion and keeps the original Dataset. A GUI-discovered active-object
handoff defect was fixed by rebinding the existing point-selection scene before
conversion/history capture.

Native fixes include scientific tangent independence from display interpolation,
point/segment semantic-reference identity, interior Path-segment tangency with
Circle/Arc, and exact drag-origin offsets for constrained defining handles.
Resource collection prunes numeric payloads without skipping escaped receipts
or private metadata references, fixing close/save with many saved workspaces.

Dataset private fields remain in the existing metadata INI. CORE-issued module
contexts control private owner prefixes; ordinary metadata filters reserved keys
and preserves them on replacement. Module publication has an automatically
assigned namespace, rejects requested overrides, and checks replacement placement
again at writer finalization. Bound Tcl and Python/Octave writes enforce ownership.
User/admin namespace movement and current import placement use existing Metadata,
Catalog and Session authorities. The browser projects existing Dataset selection.
Portable ZIP import preserves private metadata, places the imported Dataset in
the target current namespace and correctly rebinds notes when its ID changes.
See `DATASET_API_AUDIT_dev059.md` for the operation-by-operation interface audit.

## Acceptance and evidence

The decisive acceptance path is the normal GDM-authenticated local Linux desktop:
XFCE, local Xorg `:1`, giu, seat0/tty2, Remote=no. GX-TXT and Tk render on that
server. Actual X11 mouse/keyboard input operates visible product controls;
read-only observations locate handles and check state. No SSH forwarding,
192.168.1.111:0 or VcXsrv is used. Earlier local VNC evidence is supplementary.
Screenshots were inspected explicitly; the final evidence index records the
selected successful runs and excludes earlier failed/incomplete runs.

Coverage includes successive creation for all 11 exposed tools; object-list and
canvas multi-selection; all geometric selection modes; bulk/context/shortcut
workflows; custom pivot/translation/rotation and history; exact curved Join,
Rectangle/Spline Compound, Split/Separate, reviewed publication, mixed Dataset
promotion and reopening. Thirty constraint scenarios cover the exposed directional,
connection, shape, fixing and dimensional families, including Line/Arc and interior
Path-segment/Arc tangency, Bézier Tangent and Curvature/G2. Each positive editable
case changes defining geometry while retaining a valid solved relationship, then
checks exact Undo/Redo and reopen. Fixed resists edits; conflicting Horizontal is
rejected without changing geometry; Unfix and its history are exercised.

Dataset GUI acceptance covers hierarchical selection, move/current namespace,
ordinary private-field filtering, metadata/notes, ZIP export/import, renamed import
note ownership, rename/delete and source preservation. A repeated lifecycle found
the note-path defect; its earlier incomplete run is not used as final acceptance.

Supplementary evidence: 25/25 Native CTests, 25/25 address/undefined-behavior
sanitizer CTests, 9 state and 11 persistence differential cases against dev057,
30 pointer scenarios with the explicit new object-list-refresh delta, 51 namespace
checks, 23 private metadata checks, 24 composition-publication checks, 18 Dataset
lifecycle checks and 5 managed-resource checks. Actual Python and Octave Bridge
journeys cover private metadata, namespace placement, transforms and exact
composition/publication/resource roundtrips. All five Curve Fit models, filters,
selection, residuals and accepted CSV export pass; its Tcl source differs from
published dev057 only in version identity. The registration inventory covers
66 public API entries with explicit script/host policy.

## Defined limits and delivery boundary

Compound has no invented global traversal or Boolean-union semantics. Separate
creates exact editable constituent copies; nested composition control references
are not exposed. Heterogeneous Path Split is at a constituent junction. Curved
Dataset publication is an explicit finite parameter sample, not an assertion that
those samples are the exact retained primitive. Composition bounds are 256 finite
leaves and 65536 defining controls. Constraint validation covers the documented
workflows, not every possible overconstrained sketch. Fully trusted in-process
Tcl is not an OS sandbox. C Native consumers rebuild with the matching extended
header; all shipped adapters are rebuilt together. Existing Tcl/script contracts
and legacy Session definitions remain supported.

No requested dev059 capability is intentionally left unfinished. Separate future
work remains in the unfinished-only TODO. Release byte parity, package hashes,
immutable predecessor verification and the actual publication paths are recorded
in the publication receipt and versioned handoff. Stop after handoff for manual
user review; agent acceptance does not substitute for that review.
