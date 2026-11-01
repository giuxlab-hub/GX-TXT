# GX-TXT dev092 technical handoff — 2026-10-12

Incremental framework 0.9.8.10-dev-092 and Curve Workbench 2.15.0 implement the
accepted dev090 audit contracts G1–G7 and task workstreams A–G. Development uses
`_work_gxtxt_dev092_curve_local`; dev091 investigation files are untouched.
The immutable dev090 restore archive has SHA-256
`08c9e474faa3e23748ab73df90353e852c22d2d77c9b000ad643b81d3ae338c1`.

## Ownership and scientific behavior

Native2D C owns parent-scoped positive int64 constituent IDs, monotonic persisted
allocation, independent direction state, exact part rendering/picking and physical
arc-length marker placement. C POD geometry ABI is retained. Owned definition
imports validate geometry and all part state atomically. Clone/split/explode and
unannotated retarget rules are documented in `docs/api/NATIVE2D_PARTS_dev092.md`.
The Tcl adapter, public scoped Geometry API, managed resources and existing
Workbench Undo/Redo/Recipe/checkpoint mechanisms carry this state. Python and
Octave expose the additive contracts; Octave preserves imported IDs beyond
flintmax with exact integer scalar transport, while ordinary receipts retain their
existing double convention. No new Tcl rename chain or module-owned geometry store.

Unordered compounds have no global traversal. Branched/disconnected networks are
reviewed separate-part outputs; single ordered publication requires a valid chosen
continuous traversal. Nonshared boundary samples are retained, including native
near-but-distinct display vertices. Existing explicit uniform-parameter
materialization rejects ambiguous compositions and applies chosen directions.
Historical Dataset reconstruction replays its recorded original policy; an actual
dev090-published network Dataset was reconstructed and materialization verified.
Native unsupported solver families remain explicit; this release does not infer
new relationship equations for unordered compounds.

CORE owns shared popup workarea/monitor selection and native-menu paging, compact
six-section grid forms, viewport tool state, arrow painting and raster resources.
Workbench translates its existing controller state to button states, routes native
references for precise overlays and provides contextual per-part actions. Original
whole-composition selection remains available. New arrows on constituents are
hidden until explicit opt-in; inherited user appearance is preserved.

Generic managed raster import is discoverable from Workspace. The existing native
similarity transform supplies two-point physical calibration, compatible units,
scale/translation/rotation and percent opacity. Calibrated scale is read-only until
explicit reset/recalibration. Native calibration controls support reference
measurements; uncalibrated pixels cannot supply physical dimension references.
Reset retains raster and transform and obeys existing live-relationship safeguards.
The inline measurement editor now fits/focuses its fields; its curve-table
projection excludes image IDs without removing authoritative native image selection.

## Verification and preservation

`docs/evidence/dev092/TEST_REPORT.json` maps contracts/features to passing logs.
Normal and ASan/UBSan native builds each pass all 26 fixtures. Tcl contracts, real
Python/Octave Script Workspace consumers, historical reconstruction, Native3D
physical frame/exchange/bridge and Curve Fit scientific regressions pass.
Local GUI evidence covers normal 1280×840, maximized 1920-wide and 1100×700
Workbench, high-font compact grid, pressed tools/keyboard/Escape/tooltips, History
browse/latest/group expansion/explicit restart, exact constraint overlays, network
and unordered-compound arrows, independent drag/flip/Undo/Redo, seven separate
published Datasets with native part IDs/chosen directions and reconstruction.
Native long-menu pages are reached by mouse/keyboard, including a short parent
with a long cascade and all four corners. A second Viewer exercises the shared
grid and Dataset Browser exercises shared context positioning.

Image GUI tests cover import, show/hide, 0/50/100 opacity, zero-distance and
incompatible-unit rejection, reset/recalibration and a committed calibrated
reference dimension. Fresh-process reopen compares exact part state, image state
and History. Ordinary retained-line construction/handle edit/Undo/Redo/close/reopen
passes. CORE portable export validates with zero external dependencies, imports
into an isolated receiving Project and preserves exact curves/part state and the
calibrated managed image with its resource receipt.

All acceptance GUI runs use the guarded local Debian Xorg `:1` desktop with
`/run/user/1000/gdm/Xauthority` and verified private Eridania Session. The original
158-file Session inventory is checked at fixture reset and publication. No owner
GUI is closed/restarted. A separate old installation backup supports rollback.
All 100 other installed modules remain source/package byte-identical to dev090;
only Workbench receives a new package. Prior archives/expanded files and all
Session Generators are preserved. Installation identity and alias target are
checked. Generated Python bytecode additions in the old installation are retained
in its backup; they are not shipped as candidate source.

Test-environment incident: an older optional Curve Fit GUI regression accidentally
inherited the shell's remote DISPLAY. This violated the local-only instruction,
was reported, and is excluded from acceptance (`curve-fit.log`). No remote server
or desktop configuration was changed. Its scientific test was rerun without
DISPLAY; every reported GUI acceptance uses guarded local :1. Failed development
attempts and concurrent portable trials are also excluded; portable-final3 runs
after GUI writes finished.

## Delivery and manual acceptance

The publisher refuses collisions and adds matched archives/expanded pairs:
`framework/gxtxt_pipeline_v09810dev_092` and
`external_plugins/viewer.curve_workbench_2.15.0`. It also writes a matching restore
archive and atomically activates the tested source while retaining dev090 backup.
`_evidence_curve_local_dev092/publication.json` records final SHA-256 values and
parity checks. `docs/reports/DEV092_CHANGED_FILES.json` inventories changes.
Public APIs are documented in Native2D Parts, Native Geometry, UI Field and Viewport
Host documents; Workbench MANUAL/CHANGELOG describe the user workflow.

For manual acceptance, open a fresh owner-authorized private Session copy and
review History popup/restart warning, compact grid tabs and large font, pressed
tools, local constraint references, contextual arrows on simple/compound/network
paths, native arrow drag/flip and separate publication, then managed image
calibration/opacity/reference dimensions and save/reopen. Do not use the original
Session as an editable acceptance fixture. No unresolved implementation/API gap is
being handed off; owner manual acceptance remains pending.
