# Complete integrated dev-065 delivery

Baseline: immutable published GX-TXT 0.9.8.10-dev-063. The candidate was copied from
its ordered expanded release. Neither dev-064 nor the earlier dev-065 draft is an
implementation or validation baseline. Scope is the complete
`GXTXT_DEV065_FULL_INTEGRATED_TASK.md`. All requested parts are implemented in this
release; none is assigned to a later cycle.

## Implementation and architectural decisions

- CORE Native2D retains branched Path networks as exact constituents plus shared
  canonical node identities. Editing a junction solves all incident geometry
  atomically. Automatic attached construction absorbs the connected component and
  retargets existing internal/external constraints without losing their identity.
- Exact internal control/segment/curve references feed the existing compatibility,
  solver, dimensional, spline-arm and constraint presentation authorities. Canvas
  right-click offers compatible actions and the existing inspector/removal workflow.
- The original ordered-chain invariant could not represent a multi-incident
  junction. Extending the retained definition with a node map was necessary;
  flattening samples or hiding private Workbench topology would lose editable
  geometry. The old no-node chain representation remains readable. This limitation
  was resolved in CORE; it does not leave a deferred part of the task.
- Portable C99 named-expression service; existing trusted module capabilities assign
  namespaces automatically. Host adapters own canonical Manifest/Workspace storage,
  metadata validation, rollback, subscriptions and persisted consumer bindings.
  Workbench presents the shared editor and maps expressions to CORE dimensional
  batches. Closed Workspace bindings protect parameter deletion; reopening performs
  dependent geometry recalculation. Modules cannot claim another owner or Session
  administration through the API.
- Workspace actions extend the existing descriptor/provider architecture. Parameters
  works from either Workbench or Session Workspaces Actions. Safe Python/Octave
  parameter read/evaluate operations expose no administration handles.
- Session views now use a dropdown in the existing large content area. Session,
  Import/Export, Configuration and Tools menus reuse existing operations. The
  unrelated framework Workspace-profile controls remain. Session Parameters uses
  the same CORE editor and canonical Manifest state.

Reusable capabilities live in CORE. Workbench additions are gesture/presentation,
provider dispatch and expression-to-constraint binding adapters. No separate
Session, Workspace, Dataset or geometry store was added. Current Autodesk Fusion
constraint/parameter documentation was reviewed; sources and adapted principles
are recorded in `docs/api/NATIVE2D_NETWORK_dev065.md`.

## Focused real GUI acceptance

Normal giu XFCE/Xorg desktop, DISPLAY :1, GDM-authenticated seat0/tty2, Remote=no.
Input uses actual X11 pointer/keyboard actions; the observer only reads state.
Final full journey: `_evidence_dev065_integrated_gui03`. Parameter lifecycle
follow-up: `_evidence_dev065_integrated_gui04`. Both controller-error logs are empty,
both processes closed normally, and final captures were explicitly inspected.

| Required case | Evidence / result |
| --- | --- |
| 1. Branched Path, one object | Line + Line + Spline automatically form one three-part retained Path; final continued Path is one four-part row. |
| 2. Shared junction movement | Real drag changes all three incident retained endpoint controls. |
| 3. Drawing connects automatically | New Line ends on the existing constrained junction; one four-part Path plus the external Circle remain. Existing dimension/tangent/parallel records survive. |
| 4. Internal Parallel | Ctrl-select two straight internal segments; Directions > Parallel commits and shows a badge. |
| 5. Internal Tangent | Select Spline portion and internal straight segment; Connections > Tangent commits. |
| 6. External Tangent | Internal Path straight segment and external Circle commit Tangent. |
| 7. Context constraints | Right-click internal segment; compatible menu exposes Fix/Distance/Horizontal/Vertical/Axis Angle. Horizontal commits from that menu. |
| 8. Spline arms | Interior knot exposes two arms; real arm drag sets the retained incoming tangent without Separate. |
| 9. Parameter dimension | Workspace `span = session.base * 2` drives an 8 mm dimension. |
| 10. Recalculation | Change to `session.base * 3`: geometry and dimension become 12 mm. Session base 4→5 subsequently makes it 15 mm. |
| 11. Session navigation | All five dropdown views selected through real input. |
| 12. Configuration menu | Export `.ini`, then load that file through the two dropdown entries. |
| 13. Moved Session actions | Session Open, Save configuration and information invoked; menu contains New/Delete; Import/Export and module Tools remain reachable. |
| 14. Session Parameters | Create `derived=base*2`, reject self-cycle visibly, delete it. Referenced base deletion while Workspace closed is rejected. |
| 15. Reopen Workspace | Save/close, invoke provider Parameters via Session Workspaces Actions. Formula, namespace/context and numeric dimension restore. After Session base changes while closed, geometry recalculates on reopen. |

The GUI04 follow-up covers only three changed parameter/persistence Tcl surfaces;
all network/native/UI interaction code is identical to GUI03. After GUI04, the only
product metadata change raises the two external packages' minimum framework to
dev-065. Source binding checks this explicit boundary rather than claiming all
runs used later packaging bytes.

Private diagnostic runs are retained but excluded from final acceptance. They
found and resolved a toolbar geometry-manager conflict and stale defining-point
presentation after parameter recalculation. An intermediate GUI02 process was
invalidated when its loaded native adapter file was overwritten during a build;
GUI03/04 started from final native bytes and closed normally. Harness read-query
mistakes, an expected recovery prompt, and an X11 activation timeout were followed
by corrected real-input steps; no private procedure was invoked to simulate a
successful gesture. Raw logs preserve those attempts. A saved utility-panel
visibility setting was explicitly changed through Settings for the final object
list capture.

## Focused native, C and API acceptance

`validation/dev065_integrated/` is cataloged and delivered. No broad unrelated
regression campaign ran.

- Native production adapter: three-way and 24-way topology; shared-node moves;
  internal Parallel/Perpendicular; internal Line–Spline Tangent; external Circle,
  Arc, Spline and another Path; Polyline and quadratic/cubic Bézier junctions;
  node serialization; malformed map rejection; atomic multiple-component dimension
  batches and rejected negative-value rollback. Log: API03 `network.log`.
- Standalone portable C test compiled with C99, AddressSanitizer and
  UndefinedBehaviorSanitizer: lifecycle, sorted identity, dependencies, Session
  references, power/unary precedence, cycles, invalid/domain/non-finite results,
  parser limits, deletion and recovery. Passed with no sanitizer findings.
- Host API03: 21 focused assertions covering formulas, cycles/rollback, dependency
  deletion, module auto identity, forged/foreign capability rejection, Session
  administration policy, Workspace save/reopen, action discovery/unknown action,
  Manifest reload and stale handles, generic persisted consumer bindings.
- Bridge02: genuine Script Workspace Python and Octave read/evaluate and denied
  administration; Python also round-trips a branched network through scoped geometry
  and resource APIs. Both execution receipts report PASS.

## Delivery and limits

Version: GX-TXT 0.9.8.10-dev-065. Workbench 2.11.0; Curve Fit 0.3.9 changes its shared
adapter/package version only. All three Native2D binaries match. Publication checks
embedded/external ZIP and expanded module bytes, framework archive/expanded/active/
alias/restore parity, and unchanged dev-063 archive, inventory and versioned handoff.
Session Generators are unchanged. Only disposable validation Sessions were edited.

Native geometry remains bounded by documented leaf/control/solver budgets.
Unsupported or conflicting relationships fail through Native2D. Formula units are
explicit consumer conventions; unit metadata is not dimensional algebra. Linux
binaries are delivered; Windows portability is provided by C99/CMake sources, not a
claimed Windows runtime test. User manual review follows delivery.

Documentation: `docs/api/CORE_PARAMETER_SERVICE_v1.md`,
`docs/api/NATIVE2D_NETWORK_dev065.md`, `docs/DEV065_USER_GUIDE.md`, Workbench MANUAL,
updated Workspace/action API pages and Script Bridge coverage policy. Machine-readable
acceptance is `docs/reports/ACCEPTANCE_dev065.json`. Publication receipts are in the
workspace under `_validation_dev065_integrated_*`; the authoritative versioned
handoff and CURRENT checkpoint are in `work-agent/compito`.
