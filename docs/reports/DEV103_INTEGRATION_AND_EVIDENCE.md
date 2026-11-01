# GX-TXT dev103 implementation and acceptance

This release derives from the exact official dev102 archive SHA-256
`48630fae9171721ee164d390a0139b5dbaabc1a70dcb059b0a0338c690abdded`.
Development took place in a separate Git checkout; the active predecessor remains
unchanged until the cataloged final atomic activation. Source/module manifests,
package versions and the final immutable artifact ledger identify all changes.

## Authoritative inputs and exact user Session

The complete development/delivery mandate, mandatory Section 8 and all referenced
technical specifications were read. Specification SHA receipts accompany the
release. Before coding or GUI testing, the COMPLETE real 2D21 Session was copied
to an owner-private fixture and every entry verified: 298 entries, 32,580,876 file
bytes. Source-before, source-after and copied inventory were identical. Only the
small associated Project metadata was copied; its storage_path was narrowly
relinked. Scientific Dataset/Variable, Project and Experiment IDs and provenance
were retained. Unknown creator/date declarations remain unknown. Final original
Session inventory and original project.ini SHA are checked again after acceptance.
No scientific GUI or publication uses the authoritative original.

## A — remote execution

CORE Scientific Execution dispatches local/automatic/explicit node destinations
through existing Configuration and Script Job APIs. The Debian HTTPS agent
requires CA/hostname-verified mutual TLS and certificate-to-logical-Session grants.
Only enumerated public owner operations are available. It accepts no client
program, command, executable path or shell. Credential paths remain account-local;
keys are private and excluded from evidence/delivery. A JSON administrator config
maps logical Sessions to local directories. Providers and effective tools/policy
are discovered from the actual node host.

The node uses the SAME existing durable Job Supervisor and process guardian,
provider allowlist, resources, queue/concurrency and scientific Publication. There
is no second scheduler. Bounded SHA-verified staging deduplicates managed inputs,
retaining local Document generation/revision, resource SHA and source lineage.
Durable scoped nonce receipts prevent duplicate retry; uncertain admission refuses
reexecution pending reconciliation. Status/log/output/cancel/reconnect retain the
original node/Session/Job identity. Explicit FreezeResource captures a verified
terminal output into a chosen local Document; ImportResults publishes on the node.

Actual mTLS client, agent and Supervisor run as separate Linux processes over
localhost, as specifically requested by the user; this is not a second physical
machine test. Campaign20 runs real registered ngspice, compares its waveform with
an independent RC analytic solution, verifies exact staging/idempotency, local
Document rejection, local execution override, generic Script Job observation,
server publication, immutable output freeze, cancellation and agent restart.
Actual registered Python AND Octave Jobs consume redacted node capabilities and
exact Dataset ranges. Negative cases cover absent certificate, denied Session,
wrong node, unknown operation, stale revision and corrupt binary block.

## B — remote canonical Datasets

The existing canonical registry stores a qualified remote location adapter;
scientific IDs are unchanged and no second Dataset registry is created. Existing
metadata/schema, canonical handles, Table Stream, bounded row/range and hyperslab
APIs use framed raw typed binary blocks with SHA integrity. Exact uint64/int64,
UTF-8 strings, booleans, missing/NaN/Inf, units and dimensions survive transport.
A million-row source is consulted with a seven-row transfer below 8192 bytes.
Normal reads never download the full scientific file. Read handles bind the
original revision; offline is unavailable, and genuine metadata invalidation
requires explicit catalog refresh. Explicit local import publishes through the
existing authority, preserving exact rank-2 integer cells.

## C and D — responsive live Preview and disposable cache

Postcommit Dataset Catalog notification schedules standard preparation through
managed Script Jobs. Publication never depends on Preview success. Worker reads,
raster/Quality decoding, curve/filter preparation and polling run outside Tk.
The loading shell, genuine progress/cancellation, Session lifetime, source and
callback generation guards remain in CORE. No source work runs on Show/Hide.
Digitalizer uses retained Native2D/Plot v4 XY objects and a substantial resizable
pane, native Fit/Zoom/Pan, calibrated source overlay, original/verified processed
image and Quality/source identity. Visibility preferences do not invalidate the
scientific Plot source guard or reset the current camera.

The explicitly synthetic load fixture contains 60,000 canonical rows, 30,000
unique raster points, 20 curves and two calibration realizations. This is a
performance case, never user measurements. The recorded heavy GUI campaign11
measured a 373 ms cold request return, 188681 ms full managed preparation, 7458
25 ms heartbeat samples and 944 ms maximum gap. One hundred visibility changes
took 12.927 ms total with zero Dataset/CurveSource reader calls, native rebuilds
or scientific Jobs; native identity/axes were unchanged. The final campaign12
passes the final feature path after the Session-origin key update: 307 ms cold
request, 190206 ms worker preparation, 7522 heartbeat samples, 917 ms maximum gap
and 12.47 ms for 100 retained visibility changes. Custom Render/restoration also pass. Worker duration is reported honestly and is
not represented as instantaneous preparation.

Session cache keys bind Session origin, scientific identity/content/schema,
coordinate/calibration context, exact render options, renderer/native binary
hashes and media policy. Entries/artifacts are SHA verified, bounded, symlink
refusing, disposable and resource-managed. Standard cache and last successful
custom Render are distinct. Changed controls leave the last successful frame,
show a previous-settings status and require explicit Render. Exact axes, filters,
curves/calibration/grouping/ordering choices persist through existing Preview
Configuration. Cancel/failure never overwrites the last successful frame.

Actual contracts cover postcommit/hit/no Job, replacement, coordinate change,
damaged representation and PNG, safe clear/regenerate, Session switch/admission
cancel and reopening. Real GUI covers custom axes/render persistence, cache
manager and Files hiding ONLY the derived subtree. Canonical SHA values remain
unchanged. Image/PDF/audio, bounded exact array planes and installed Native3D
standard frames use existing owners/codecs; an independent PNG check verifies
all six finite source palette levels. Open Dataset keeps actual resizable Native3D
consultation. Unsupported media/geometry report actual limits. Remote preparation
runs on the authoritative node; client transfer contains bounded model/derivatives,
with authoritative verification before declaring a cached remote frame current.

## E — catalog and module policy

All 30 actual installed Viewer providers declare distinct authored scientific
SVG masters, directly rasterized 192px PNG, short titles and semantic groups.
Normal artwork is 64px, with original-resolution HiDPI rendering. No emoji,
character placeholders or repeated bundled icons. Real catalog15 evidence covers
all tiles, compact scrolling and HiDPI clam layout, manager disable/Open refusal,
fresh-process persistence, dependency rejection and re-enable. Every tile opened
successfully, including actual mapped external Digitalizer/PDF OCR/Table Extractor
windows and a real imported synthetic NMR prerequisite. These are opening tests,
not claims of scientific acceptance for every Viewer algorithm.

Presentation enablement is an existing Configuration flag projected by Viewer
Provider; Analysis Run membership and required scientific services remain
independent. Installed script editors therefore remain launchable even when their
Analysis Run flag is off. Existing Workspaces survive presentation disablement.
The sweep exposed and repaired Section Profile's Destroy quoting and Surface
Fitter's authenticated command owner. Logical command catalog aliases now declare
the actual installed module owner through the existing Viewer Commands API.

## F — real 2D21 Replicate and reusable CORE GUI FIRST

The REAL installed predecessor Curve Workbench was opened and loaded with the
copied 2D21 source BEFORE product changes. Its toolbar/menus, scrollable inspector,
live canvas, source dialog, Description/History, Workspace/context/Help and resize
architecture were directly inspected and photographed. A shared public host probe
passed before Replicate was rebuilt. CORE UI Field/Viewer Commands/manifest
extensions were implemented FIRST. Replicate then consumes those shared facilities.

| Capability | Existing public owner |
|---|---|
| Window, regions, inspector, splitter, scrolling | UI_FIELD_API_v1 |
| Ordered toolbar, shortcuts, selection enablement | Configuration / Viewer Commands |
| Menus/context composition | VIEWER_GUI_HOST_API_v1 over CORE menu services |
| Dialog placement, sizing, focus, map/unmap grabs | UI_FIELD_API_v1 |
| Description/History and undo/redo | Scientific Recipe History |
| Create/save/open/close and unique default names | SESSION_WORKSPACE_API_v1 |
| Current rendered Help | Documentation Browser |
| Original/aligned/consensus/spread graphics | PLOT_DATASET_API_v4 / Native2D |

Curve Workbench genuinely reuses the shared source-dialog owner, and Worksheet
independently reuses the contained selector. No Replicate-only toolbar, scheduler,
renderer, History/Workspace manager or GUI framework was added. Finite source
review checks no new Tcl rename wrappers; unrelated inherited wrappers are retained.

Exact source Dataset `dig_2D21_Sylvania_during_conduction_1`, SHA-256
`79964c50b792114e43daf1e592044a88a350f547a2e4eded092725590968cb01`,
uses x/y in V/mA and genuine curve IDs
`4ffe3ddb-d112-45ad-bed6-262ec43d3159`,
`983211ac-df4c-4748-b03e-f06fee02f891`,
`b1092585-29e2-40ea-9d14-83020c771e3a` (27/43/60 points).
Y(X) explicitly orders by x, since raw acquisition order is not monotone.
These are distinct digitized point sets from ONE source image/calibration, not
independent physical experiments. The result is descriptive consensus/sample
spread; no shared-factor covariance or confidence/prediction interval is claimed.
Independent NumPy interpolation/mean/median agree exactly, and sample SD/SEM
maximum error is 1.734723475976807e-18 on the 200-point grid.

Actual GUI events exercise scientific selectors/editor, frame/calibration IDs,
source removal/Undo/Redo, Analyze and genuine Cancel, native visibility/navigation,
context, resize/map lifecycle, results/Graph publication and Workspace save/reopen.
Additional fresh-process checks exercise Description, History Details, current Help,
source editor size and ten repeated modal map/unmap/focus/grab cycles. No new
scientific Job is created by reopening saved presentation. Side-by-side screenshots
use the SAME copied Session/Dataset, matching window dimensions/theme/scaling and
330/300px inspector proportions. Workbench displays the full eleven source curves,
including the three selected Replicate observations; its recorded point-index order
is distinct from the explicitly sorted Y(X) analysis. This difference is documented,
not concealed as equivalent statistical processing.

The predecessor's ordinary Workspace reopen failed with the genuine prepare
callback arity error; the public lifecycle callback signature is repaired. The
reported exact `grab failed: window not viewable` was reproduced by deliberately
withdrawing the actual native ttk popdown before its global grab. That is a
controlled lifecycle reproduction, NOT an ordinary user action observed on this
Xorg server. Ordinary clicking/map/close attempts did not reproduce the original
trigger. Replicate now uses contained mapped selectors and CORE deferred mapped
focus/grab checks; those races and unmap releases pass actual GUI verification.
A fresh shared source dialog also fixes the global mapper freezing its provisional
200×200 size before children negotiate their layout. Failed exploratory/harness
attempts remain in bounded evidence and are never counted as PASS.

## Delivery and limits

All 31 changed/new modules receive packages, checksums and matching expanded
copies. The official framework, source commit, complete changed-file/owner ledgers,
archive/expanded parity, restore framework plus two evidence ZIPs, actual installed
catalog/native GUI, complete dev102 rollback, alias, identity preservation and
current handoffs are verified by separate delivery receipts. No Windows tests or
porting are performed. Previously accepted scientific evidence is retained; unrelated
scientific campaigns are not needlessly repeated. The unfinished-only TODO keeps
advanced covariance/intervals, missing independent original package, exact historical
signed source and other unrelated debts. A cached PNG is never substituted for
the separate retained Digitalizer performance acceptance.
