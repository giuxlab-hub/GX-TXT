# dev-056 implementation audit

Baseline: published GX-TXT 0.9.8.10-dev-055, frozen receipt in the development workspace. No implementation is inherited from the previous working tree.

| Capability | Classification | Existing authority and extension |
|---|---|---|
| Fit, zoom, pan, bounds, coordinate mapping, tolerance | Existing C/Tcl, scoped gap | gx2d view APIs; expose owned scoped operations without another view store |
| Background, grid, aspect, portable views | Existing, needs presentation | Native presentation/view_state; Settings and shared controls consume it |
| Polyline, vertex/segment references, closure | Existing, needs discoverability | retained polyline, interaction references and construction APIs; preserve independent Line |
| Spline tangents | Missing retained CORE semantics | existing Catmull-Rom cubic kernel; compatible optional knot-relative overrides, same evaluator/bounds/derivatives |
| Symmetry construction | Missing atomic orchestration in CORE | existing reflection matrix and persistent solver relationships; supported families only |
| Reference images | Missing portable CORE geometry/state | Native similarity transforms/calibration, existing Document resources for raster ownership |
| Viewport chrome/panels/icons | Host/UI-only | sibling widgets over geometry canvas; shared semantic layout, no geometry identities |
| Context menus | Shared host composition + Native targets | existing interaction pick/references/compatibility; viewer policies supply domain actions |
| Notes | Existing editor, needs generic managed document contract | dataset_notes GX-Markup renderer/editor; reuse View/Edit and UTF-8 storage |
| Session workspaces | Existing Document persistence, missing generic workspace metadata/provider service | extend Interactive Document payload/registry lifecycle; no second identity/path store |
| Preview | Existing scene snapshots/render data, missing bounded preview contract | Native transforms and shared scene rendering; omit chrome/transient state |
| SB-014 | Existing resource writers sufficient as destination authority | Document-owned immutable resources addressed by receipts, bounded writes; never script-supplied host paths |

Audited gx2d.h/c, retained/interaction/construction/solver/units/CAD/identity/collection/view implementation and Tcl adapters; native2d_geometry scoped dispatch and Python binding; shared host/presentation; Dataset Notes; Session persistence, portable resources and explorer; Workbench serialization, lifecycle and CAD interaction; Curve Fit shared-adapter dependency. The Python provider discovery supplies Octave through the common bridge transport; new registrations must be exercised in both real processes.

Small geometry edits and Tk presentation remain serial; no new worker pool. Raster work must be bounded/cached. Existing solver limits and scientific/unit semantics remain authoritative.

Actual dev-055 package contains an older unfinished TODO, contrary to continuity's missing-file claim. The authoritative compito/task scope supersedes that older content; final gates must check current bytes, not presence alone.

Connected-Line conversion was evaluated and is deliberately not added. The existing Lines can belong to Coincident/Fixed/dimensional graphs, persistent fragments, groups, captured ordinal selection sets and Dataset provenance. A new ordered polyline can copy positions, but preserving or explicitly migrating every existing reference would require a new topology transaction beyond this frozen interaction cycle. Keeping independent Line and prominent retained Segmented curve avoids ambiguous branches/units and destructive replacement. No conversion API is advertised. Existing Mirror remains available: real X11 verifies target selection, editable axis endpoints, numeric form initialized from the picked axis, separate copies and one Undo/Redo.
