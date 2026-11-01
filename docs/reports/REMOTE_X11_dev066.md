# GX-TXT 0.9.8.10-dev-066 — remote X11 usability

Delivered from immutable published dev-065. Workbench 2.11.1 contains the GUI
corrections; the existing scientific Native2D/Parameter/numerical sources and binaries are
byte-identical to dev-065. Curve Fit 0.3.10 adds pre-map shared placement and
reserves result/status/residual rows before the expanding plot;
Session Generator packages are unchanged. No canonical user Session or previous published release was modified.

## Corrections

The Workbench canvas is a real child of its persistent viewport frame. Shared
CORE ViewportHost resolves the actual geometry owner; callers resolve panels
through its additive host-only widget lookup. Render, input, selection, overlays
and controls use that canvas consistently. Feedback/readout labels and the
residual canvas have real matching Tk parents. Chrome is visible while idle,
without a hover repaint. Layout watches its owning frame rather than using
native toplevel Configure traffic as an invalidation feedback loop.

Native construction evaluates tentative previews and falls back to the valid
placed prefix if a trailing segment is degenerate. Each noncommitting placement
refreshes that preview immediately. Native geometry remains the authority; no
scientific evaluator, topology, schema or parameter store was duplicated.
The dev-065 authoritative tangent/measurement separation is preserved unchanged.
The source recovery reference for unpublished dev-058 was read before implementation:
its Tk ownership, panel lookup and preview findings were adapted to dev-065
without restoring obsolete files or repeating already present scientific fixes.

Shared UI placement sets the X11 USPosition hint to prevent automatic native
placement from overriding the requested position, reserves room for native
decorations/taskbars and clamps
ordinary mapped toplevels to the screen. Workbench and Curve Fit request placement before mapping; Workbench starts at +20+20; the main
window uses 1280x840 subject to the screen allowance. Its Page selector exposes
complete names for all sixteen notebook pages by pointer and keyboard. Existing
reflow, scrollbars, menus and fixed publication controls remain available.

A normal Session journey revealed a dev-065 lifecycle defect: defaults reset
forgot loaded public APIs while their Tcl wrappers remained installed. Later
activation failed on duplicate rename targets. CORE now preserves the existing
interpreter-lifetime activation cache through configuration/Session resets.
There is no new loader, API signature, ownership authority or hot-reload claim.
The existing host/admin loader remains outside Script Bridge exposure.

## Actual validation

Linux Tcl/Tk was displayed on Windows pc-giux via inherited remote X11
`DISPLAY=192.168.1.111:0`, HC-Consult/VcXsrv. Screen 1920x1080; native working area
1920x1040. This is the available direct remote TCP display; an SSH-tunnel
transport and a Windows-native framework executable were not separately tested.
Actions used real native pointer and XTEST keyboard events; captures used actual
Windows client pixels with exact-title, foreground and bounds checks. XGetImage
backing stores are not acceptance evidence. Ordinary remote latency is accepted;
no comparison with local Xorg performance or burst-fluidity threshold applies.

| Surface | Actual checks |
|---|---|
| Workbench | Idle icons/footer; placed Spline prefix and coincident cursor; Enter; Line, Circle, Rectangle, Arc and Bezier creation; exact Spline arm drag; automatic three-branch Path; list Duplicate/Undo/Redo; 8 mm parameter dimension; pan, wheel zoom, Fit all, grid; palette scroll/collapse and comparison controls |
| Session | All five views; create/evaluate/delete and cycle diagnostic; configuration save/export/load; canonical Workspace Parameters action; save/close/reopen seven retained objects and the dimension; GUI-created Session; portable export/import and correct Session ownership |
| Cross-window parameters | Workspace `span=session.base*2`; Session base 4→5 drives 8→10 mm; deletion while Workspace is closed is rejected; restoring base=4 recalculates 8 mm on reopen |
| Other main components | All sixteen pages opened/captured; Modules/Plots action scrollbars and Graph Import chooser; Dataset browser activation glyph and namespace dialog; Script Library editor; real Dataset Curve Fit load, preview and accepted CORE fit |
| Existing Sessions | A private copy of the dev-065 validation Session opens its saved branched Path/external Circle, constraints and 12 mm named-parameter dimension; the original 3.2 MiB Session hashes remain unchanged |

GUI04 provides the initial construction/editing journeys. GUI05 repeats configuration/Session/import actions after the CORE
activation fix, plus source-bound preview and live parameter journeys. GUI07 checks the main pages and legacy Session. Fresh GUI08 binds the final runtime including explicit user-position
hints and the pre-map Curve Fit placement with reserved diagnostics, and repeats Curve Fit/Script Library
interaction with visible result/status/residual rows and a rendered plot. The final application/controller error log is
empty, actual rendered captures were inspected, and final processes closed
normally. Runtime source binding covers 1442 files, SHA-256
`8d1113d46c7dd982e505cb2d591b272613c71508288afc3530af1fa0cef67281`. Three Native2D adapters remain identical:
`07ffba798ac7d5306529b963365be9752765201e6588b56587e8fad091d5794a`.

The focused real-API lifecycle regression fails on immutable published dev-065
with duplicate wrapper rename (exit 1) and passes on dev-066 across repeated
defaults/catalog resets. Native scientific trees and binaries were compared
byte-for-byte. No unrelated full CTest, Python/Octave, Native3D, or every-plugin
campaign was repeated for this GUI/lifecycle change.

## Evidence boundaries and retained failures

Baseline native capture shows a blank idle viewport strip and a footer obscured
by the Windows taskbar. GUI01/02 and the failed GUI03 start remain diagnostic.
Early harness corrections include entry replacement, combo Up/Down navigation,
postcommand menu enumeration, exact row IDs/labels, modal acknowledgment and
variable directory-dialog confirmation counts and waiting for asynchronous
Script Library mapping on the remote display and using ttk Treeview Down keys
rather than an unsupported End binding. A 7 ms unpaced drag did not edit
an arm; the normal paced gesture did and was visually checked. That failed
attempt remains `04a-drag-diagnostic.png`, not a performance acceptance gate.

GUI04 exposed a real API reload failure after defaults reset; its later
state-only/import checks are excluded despite earlier PASS labels. The failure
capture `api-reload-failure.png` is retained. Fresh GUI05 adds ownership/activation
checks and repeats the affected workflows on the corrected source. GUI05 Curve Fit rendered correctly but its bottom overlapped the taskbar after
automatic native placement. GUI08 repeats the fit with explicit user placement
and reserved result/status/residual rows, and checks actual client bounds
against the working area. GUI06 had verified placement but still hid diagnostic
rows; GUI07 reserved them but left the plot below its rendering threshold.
GUI08 reduces filter/residual visible-row counts (lists still scroll) and
verifies the rendered plot alongside diagnostics; earlier captures stay excluded. An empty log
never overrides an observed GUI failure. Report coverage is the tested desktop,
normal interactions and listed components, not every screen size or every
installed scientific plugin. Manual user review and separately scoped future
work remain in the unfinished-only TODO.

## Delivery and reproduction

Framework archive/expanded pair:
`/home/giu/electronics-server/scripts/GXTXT/framework/{archives,expanded}/gxtxt_pipeline_v09810dev_066`.
Active `/home/giu/script-ag/current/gxtxt`; established alias
`/home/giu/ag-script/current`; matching restore archive under
`/home/giu/electronics-server/work-agent/restore-points`.
Workbench `viewer.curve_workbench_2.11.1.zip` and Curve Fit
`viewer.dataset_curve_fit_0.3.10.zip` have matching embedded/external
archives and expanded module bytes. All three ordered sections retain matching
archive/expanded names; unchanged Session Generators retain 56 pairs.
Final publication hashes and counts are in `_validation_dev066_publication.json`
and the authoritative `GXTXT_HANDOFF_v09810dev066.md`.

Version-scoped runners and arguments are in SCRIPT_CATALOG.md and
`validation/dev066/`. Start the normal main entry with an isolated XDG/Session
and a read-only observer; use the native helper for displayed pixels. Selected
reviewed captures and source/check receipts are under `docs/evidence/dev066`.
