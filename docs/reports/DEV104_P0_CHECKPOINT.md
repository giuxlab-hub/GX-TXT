# GX-TXT dev104 — P0 engineering checkpoint

This is an isolated development checkpoint, **not an accepted dev104 release**.
The active and officially deposited framework remains **0.9.8.10-dev-103**.
The two P0 corrections have bounded engineering evidence. The user subsequently
reported that the exact empty-Viewer failure has stopped appearing. Its trigger
remains unconfirmed and no exact-failure repair is claimed. A/B/C may proceed
with that qualification; all three and canonical delivery remain required.

## Verified predecessor and preservation

- Official dev103 archive SHA-256:
  `c13ff6b8170eb76efa4fb724137238646efc7766a752862fc7f8ddbe2aa85745`.
- All 14,346 declared expanded/active files matched before development.
- Isolated checkout: `_work_gxtxt_dev104`, branch `dev104`.
- Actual Debian desktop: local Xorg `:1`, Tk 8.6. Tests use isolated
  configuration/resources and agent-owned copied or synthetic Sessions.
- Final preservation audit matched all 14,346 active dev103 files and all 189
  protected candidate Plot Dataset/Digitalizer files. Neither protected module
  was changed. BUG6/BUG7 were not reopened.
- No canonical framework/module package, restore point, active installation,
  release pointer or official handoff has been changed.

## Candidate changes and actual evidence

**Configuration → Modules:** the accepted dev103 page reproduced the empty
Services tab despite 98 existing catalog records. The browser was created as an
older sibling of the new notebook and subsequently geometry-managed inside
its page; the newer notebook obscured it. The candidate constructs the browser
as a real child of `kinds.services`, and updates the existing editor references.
It retains the existing registry, Configuration authority and Plugin Manager.

Actual GUI tests passed catalog search/selection/details, private module package
installation 1.0 → update 2.0 with visible version change, configuration saving,
draft retention across both subtabs at 1280×840 and 850×600, fresh-process
configuration/version reopening, documentation, Services provider activation,
Analysis activation and separate persistent Viewer presentation policy. Invalid
and nonexistent packages left the registry unchanged. Managed test modules were
uninstalled through the existing public owner. Bundled/unmanaged packages retain
the existing API restriction against Plugin Manager updates; no updater was invented.

**Help:** the shared Documentation Browser adapter reuses an existing Help menu,
places it last, and adds only missing Manual/About actions. Legacy native
menubutton rows and grid-managed toolbars retain their geometry owners. The
shared UI Field/Menu helpers add a trailing control without a second command
registry. About reads the current installed descriptor.

The real catalog run recorded **19 PASS, 9 NOT TESTED, 1 CUSTOM UNCHANGED and
1 EXCLUDED FROZEN**. The nine untested shared-Help paths returned an external
backend, a structured non-window result or no normal Tk window; their complete
context-specific Help behavior is not claimed verified. The inventory retains
every consumer's actual status. Curve Fitter screenshots show the duplicate
Help row before correction and the existing single menu row afterward.

**Separately reproduced History defect:** an existing Worksheet/Fitter window
can outlive its Session token. Normal Viewer launch can reuse that window
without creating/opening a Workspace. Selecting Description/History then called
the scientific editing guard and raised:

```text
Session changed; reopen this Workspace
_scientificHistoryGuard
scientificHistoryViewerStripSet
_scientificHistoryStripSwitch .scientific_worksheet
(command bound to event)
```

The candidate makes strip selection presentation-only. Stale windows display
their retained timeline locally and cannot write preferences into another
Session. Scientific Undo/Redo, restoration, branching and edits retain the
original guards. Actual pointer/keyboard transitions and scientific guard
refusals passed for Worksheet, Curve Fitter, Curve Viewer and Replicate.
Curve Workbench and Scientific Image Inspector were independently exercised
before/after without modifying their module sources. Inspector evidence covers
loading an actual image and its populated initial timeline; no successful new
annotation-creation claim is made from the attempted control gesture.

**Huge error-dialog geometry:** the genuine native Tk error dialog measured
3046×1361 pixels on a 1920×1080 screen. Its `wm grid` contract uses character
units; the shared pixel fitter incorrectly resized it. The candidate leaves
gridded windows under their native geometry owner. A named intentional error
fixture produced a genuine 376×284 Details dialog with reachable controls.
That controlled geometry test is separate from scientific or empty-Viewer
failure reproduction.

## Transient failure qualification — user update

The user clarified that the reported failure occurs when opening a Viewer
normally **without an active Workspace or History**, and does not occur with
an active populated Workspace. On official dev103, fresh private empty Sessions
were tested with the default Worksheet and Curve Fitter launch paths: both had
an empty Workspace ID and zero retained steps, and both completed actual pointer
and keyboard Description → History → Description transitions without an error.
The native-dialog run independently confirmed the empty Worksheet result.

**The reported empty-Viewer failure is NOT REPRODUCED locally.** The separately
reproduced stale-Session traceback must not be represented as proof of that
exact trigger. The user then reported: ‘The bug isn’t happening; it has stopped
appearing—I don’t know what to tell you.’ No further traceback is available.
Default drafts, saved baseline-only Workspaces and normal reopening after Close
were additionally exercised for Worksheet and Fitter on both dev103 and the
candidate: all pointer/keyboard transitions passed with no unexpected errors.
The old native menu Save/Close commands were invoked programmatically in that
extra lifecycle test; menu-opening gesture coverage is not claimed from it.
Read-only Tcl inspection of the running application was refused by X display
security. No forwarded-display test or change to display security was performed.

## Source ownership and retained failures

Product changes are confined to:

- `app/gui/configuration_modules.tcl` and `configuration_module_editor.tcl`:
  existing Modules page geometry and editor paths.
- `app/gui/documentation_module_window.tcl`: shared Help attachment/metadata.
- `core/tcl/scientific_recipe_history.tcl`: strip presentation semantics.
- `core/tcl/ui_field_api_v1.tcl`: existing layout and native grid-size ownership.
- `core/tcl/ui_menu_api_v1.tcl`: existing menu-row trailing action support.
- Existing public GUI API documentation.

No new Tcl rename wrappers were added. The first candidate incorrectly packed
Help into Workbench's grid toolbar; the failed receipt is retained, and the
corrected shared layout passed a fresh process. Early focus/chooser automation
failures and a live-reload test that reset the History adapter dictionary are
retained and excluded from acceptance. Replicate's legitimate refusal to reopen
a stale Workspace was also recorded; the corrected test exercised the existing
window's strip while retaining that refusal.

## Required work still unfinished

1. Retain the unconfirmed transient empty-Viewer trigger and explicit Help
   consumer coverage limits; investigate only if evidence recurs.
2. Complete **all** of A: visual two-window Viewer Interface Builder, public
   CORE component contracts, imports/round trips, analyzers and finite real-GUI
   recording/replay batteries from the full authoritative component mandate.
3. Complete **all** of B: Project and Project-local Session namespaces,
   transactional membership, hierarchy/search/drag-and-drop, keyboard access,
   portability and scientific no-move/no-loss acceptance.
4. Complete **all** of C: redesigned existing Print/PDF Studio, real assembled
   pages, cache-backed scientific browser, typed composition/export and bounded
   asynchronous CUPS discovery/capabilities/submission with real hang tests.
5. After successful acceptance, perform the already authorized complete
   canonical dev104 delivery: archive/expanded equality, changed module pairs,
   restore/evidence/checksums, active installation/alias, complete dev103
   rollback, installed acceptance, handoff/pointers and unfinished-only TODO.

The fourth parked historical-backlog workstream remains excluded. No unrelated
unfinished item was removed from the existing TODO.

## Evidence and repeatability

Reusable scripts and exact scope/side effects are registered in
`SCRIPT_CATALOG.md`, under **Dev104 isolated implementation and acceptance**.
Evidence is in `_private_dev104` and the bounded public checkpoint
`_evidence_dev104_p0_checkpoint_01/CHECKPOINT.json`. The checkpoint includes
before/after screenshots, the actual native traceback, per-consumer statuses,
negative receipts, source diff and SHA inventory; it excludes Session payloads,
configuration trees and credentials. It is not a release archive or activation
receipt.
