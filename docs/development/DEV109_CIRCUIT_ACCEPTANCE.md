# dev109 Circuit Workbench correction — mandatory supplemental acceptance

Authority: user's urgent integrated Circuit correction of 2026-10-19, sections
1–16 and final directive. This adds requirements to the original 15-workstream
register. It does not replace any original criterion or the MAIN-owned P0
compiled Viewer lifecycle correction. MAIN277 accepts the CW editing/science requirements and current installed1.9.9 attachment. The original execution notes below remain historical; their OPEN statuses are superseded only by the exact current decision linked here. The complete15-workstream release and official deposition remain OPEN.

Current decision: `/srv/gxtxt/checkpoints/dev109/main_acceptance277/CIRCUIT.json`. It reconciles all33 functional checks, CW-01–CW-10,18 ordinary from-empty GUI steps, normal/narrow operation and12 handoff deliverables with original independent161/187, MAIN249 and current199 Help/metadata257. No completed campaign was repeated. Original failures and qualifications remain intact.

## Historical ownership and initial execution notes

Accountable Circuit specialist: `/root/author_circuit_interaction`, formally
assigned the new scope on 2026-10-19. Owns restricted Viewer integration, editing
controls, presentation, manuals, authentic GUI demonstration and same-author
regression. Uses official Interface Builder, C++ Development Workspace, project
grants and public APIs. MAIN `/root` alone changes CORE, shared Native2D Diagram,
electrical catalog/attributes/netlist, Builder, runtime, SDK and provider owners.
An inappropriate private implementation must be returned to its author.

Independent P0 installed-runtime QA: `/root/qa_document_readers`. Independent
Builder lifecycle QA: `/root/qa_cpp_debug_tree`. Full Circuit usability/science
independent QA and MAIN acceptance remain required after the author handoff;
those roles must be explicitly assigned before claiming their execution.
Icon/GUI contributors coordinate with the accountable Circuit specialist.

Verified runtime capacity is four active agents including MAIN, hence three
simultaneous subagents. The new Circuit author turn follows the current Test C
staging handoff; this scheduling does not suspend retained GUI tests or discard
other workstreams. No claim is made that an idle assigned author is executing.

The 156-file installed-runtime and 68-file Series input sets are currently held
by retained GUI tests. No edits to those files/packages until their owners
release them after real lifecycle/exit verification. Author-owned new staging,
source review and documentation outside those sets can proceed independently.

## Original registered defect and dependency matrix (historical statuses)

| ID | Mandatory behavior and verification | Authoritative owner / dependency | State |
|---|---|---|---|
| CW-01 | Native R→C→L→Voltage→Wire→Select→Probe→R; immediately use Canvas after each selection; first action, canonical kind, toolbar highlight and viewport tool agree; no retry, compiler/linker, unnecessary Busy or hidden wait | MAIN shared compiled dispatch/Builder/viewport; author tool bindings | OPEN |
| CW-02 | Start/end wire on existing segment; intentional T creates/reuses canonical junction with marker; accurate bends/picking/snapping; move/delete/Undo/Redo/save-reopen; generated ngspice netlist proves connectivity; ordinary crossing remains disconnected | MAIN Native2D electrical topology, hit testing, History/netlist | OPEN |
| CW-03 | Voltage Probe on wire middle resolves genuine same net at several locations and available Job/Dataset voltage; supported branch/device current only, precise contextual error otherwise; shared segment resolution for Net Label | MAIN electrical hit/net/observable and scientific result owners | OPEN |
| CW-04 | DC polarity, time-domain sine and pulse symbols follow canonical waveform; Properties redraw preserves ID/name/pins/polarity/properties/netlist; nonzero small-signal AC alone does not imply sine | MAIN electrical catalog and diagram presentation | OPEN |
| CW-05 | Electrical-only normalization: 1k→1000Ω, 4.7k→4700Ω, 470n→470nF, 1u→1µF, 10u→10µH, 1meg→1MΩ; canonical SI precision; decimal/scientific accepted; explicit m=milli/meg=mega; invalid input leaves document/History exact; readable engineering Properties/labels | MAIN electrical attribute/UI owners; no generic Numeric parser change | OPEN |
| CW-06 | Exactly one normal installed provider in Simulation & Modeling; none in Interface Tools; normal search/open; same provider/module/Session/Workspace identity; no duplicate launcher; do not name future magnetic simulator | MAIN official descriptors/catalog APIs; author package metadata | OPEN |
| CW-07 | Distinct circuit/schematic catalog icon versus Builder/Workspace/Curve/XY/3D/EM; actual dimensions/transparency/clarity/scaling/resources/packaging/installed catalog; provenance and licensing | Shared icon/resource/Builder facilities; author coordinates icon contributor | OPEN |
| CW-08 | Meaningful coherent Select/Move/Wire/Junction/Probe/Rotate/Delete/Undo/Redo/R/C/L/V/I/other device icons; Curve conventions for equivalents; all useful actions preserved; actual selected/hovered/disabled functionality agrees | Shared resources/Builder controls; author presentation | OPEN |
| CW-09 | Component stays visible and continuously follows native drag; accurate canonical final commit/one History; cancel/invalid recovery; selected differs from hovered; IDs/connectivity/Undo/Redo/save-reopen preserved | MAIN shared Native2D interaction/History; author integration | OPEN |
| CW-10 | Wire-mode available pins, hovered valid targets, endpoints, connected segments, intentional T attachment and completed connections visible and faithful to graph | MAIN shared Native2D hit/attachment presentation | OPEN |

For each failure the specialist must retain: expected/actual behavior; minimal
real-GUI reproduction; current public API and owner; missing/incorrect shared
capability; minimal proposed correction; exact source and actual screenshot
evidence. MAIN resolves genuine gaps in those owners, then the same author
retests the original failure before independent QA and MAIN acceptance.

## Mandatory installed GUI workflow

Every step below is OPEN. Start a genuinely new empty Session through normal
GX-TXT GUI. Run relevant checks at normal and narrow widths.

| Step | Required actual human-input evidence |
|---|---|
| 01 | Open installed Circuit through Simulation & Modeling; normal registration |
| 02 | Inspect actual category and new icon, search discovery, no duplicate |
| 03 | Native first-click placement of R1, C1, L1 and voltage source |
| 04 | Read-only canonical verification of actual electrical IDs and kinds |
| 05 | Native Properties R1=1k and C1=470n, exact SI values/readable labels |
| 06 | Native DC→sine→pulse Properties changes and corresponding actual symbols |
| 07 | Native held drag, intermediate visible movement and canonical final placement |
| 08 | Native component-pin wiring with visible genuine attachment targets |
| 09 | Native middle-of-wire branch with actual canonical junction |
| 10 | Read-only topology and actual generated ngspice node verification |
| 11 | Native ordinary crossing, canonical electrical disconnection verified |
| 12 | Native Voltage Probe middle-of-wire at several positions |
| 13 | Actual same-net resolution and genuinely available voltage observable |
| 14 | Local real ngspice analysis through ordinary GUI controls |
| 15 | Publish/inspect authentic canonical scientific Dataset and Plot |
| 16 | Native representative Undo/Redo preserving correct canonical state |
| 17 | Normal Session save, close and reopen |
| 18 | Exact preserved schematic/topology/values/results and normal lifetime |

No injected Diagram components, private Tk selection variables, preloaded
completed circuit, compensating second clicks, or Busy/Completed polling between
tool selection and Canvas input. Read-only API inspection verifies results.
Waiting for a genuine scientific Job is allowed. A screenshot alone cannot
establish input correctness. Preserve all failed input traces and screenshots.

## Genuine demonstration and delivery gates

Build at least one representative RC/RLC circuit from the empty Session using
normal GUI placement, Properties, wiring, branch, source and ground. Run genuine
simulation, publish canonical Dataset/Plot, save/reopen, and retain sufficient
screenshots and reproducible user steps. Preserve every released dev108 example;
successful reopening of those examples is not editor-usability evidence.

Required handoff, all OPEN: (1) dedicated identity/scope; (2) each original failure
reproduced; (3) shared CORE fix/file list; (4) Viewer fix/file list; (5) before/after
native evidence; (6) engineering/netlist checks; (7) immediate first-click proof;
(8) actual junction/Probe results; (9) installed category/icon; (10) from-empty
demonstration; (11) independent QA plus MAIN acceptance; (12) precise residual
BUG/GAP entries. Update Circuit manual, Native2D/Builder technical docs, API
contracts, architecture inventory and integrated acceptance ledger.

P0 A–E remain separate mandatory dependencies in
[DEV109_P0_COMPILED_VIEWER_RUNTIME.md](DEV109_P0_COMPILED_VIEWER_RUNTIME.md).
Distributed compiled binaries must be executed directly; no private Circuit
worker/event workaround. Scientific Jobs retain their existing asynchronous
owners. Missing/incompatible native binary is a precise error, never a rebuild.

## Evidence carried forward without enlarging its scope

Circuit 1.9.5 has prior authentic authored placement/drag/wire/History tests and
scientifically valid example Sessions. Its current source metadata already
declares Simulation & Modeling and a circuit resource. These are existing inputs,
not acceptance of this new complete workflow, installed category/icon, T-junction,
wire Probe, engineering notation or waveform presentation. The P0 ABI contract
loaded distributed Circuit/Library binaries and exercised 40 events with a
separately reviewed zero-compiler trace; that contract is not a GUI test.

No completed item is removed from the authoritative unfinished-only TODO until
its actual required acceptance is verified. Latest deposited dev108 TODO and
older register copy remain unchanged; zero items removed. All original 15 final
workstream gates remain OPEN. No final release, deployment or acceptance claimed.

## Current supplemental evidence and source corrections

Dedicated author `/root/author_circuit_interaction` completed native wave01 from
a genuinely empty Session. Category/icon/Search/normal launch and single-stream
R/C/L/V first-click placements passed. Literal1k Properties rejection and neutral
tool palette were genuinely reproduced and preserved. Normal close/Save/root
exit0, all164 input hashes and all3021 traced PIDs absent were recorded. The
original header-failure screenshot local bytes were overwritten by an old QA
capture helper; its explicit evidence-gap report is retained. Later evidence
uses exclusive phase names. Full8-tool sequence/full18 steps remain OPEN.

MAIN corrected the existing Diagram attribute/projector/viewport, shared command
presentation and Scientific Probe owners. Public contracts describe engineering
SI values, canonical waveform marks, intentional segment T-junctions, voltage
wire probing and declarative `diagram_tool` checked state. The original API
fixture retained32 passed checks before a QA points-page range failure; its
unexecuted continuation passed29 scoped checks including actual provider netlists,
disconnected crossings, intentional joins and low-counter identity preservation.
Independent review qualifies that raw waveform vectors were compared but not
retained separately. These synthetic API fixtures prove no native GUI authorship,
History, simulation or final acceptance. Original failures remain unchanged.

Repeated no-op junctions bypass History preparation; repeated existing-node
joining reuses canonical wires, with deterministic target ordering. Further
edge checks and the new same-author Builder package/installed GUI regression
remain pending. No private Circuit parser/graph/renderer/event worker was added.

## Subsequent installed and GUI evidence (still incomplete)

Normal Plugin Manager Update installed the official same-author1.9.6 package
`422fdd4b…`, including distributed native binary `e394d409…`;94 package files and
all foreign registry entries were independently verified. The loaded1.9.5 process
reported restart required honestly. All960 traced processes exited, with zero
compiler/linker invocations across8,962 execution attempts.

Fresh wave02 activated installed1.9.6 and created a genuinely new empty Session.
The unique Simulation & Modeling entry and circuit icon were inspected. Four
immediate R/C/L/V placements produced the correct canonical kinds; Wire's first
pin action and Select cancellation/selection also passed without local Job waits.
The seventh Probe selected correctly and left canonical source/History unchanged,
but its no-result explanation disappeared on release/redraw. MAIN viewed the
actual failure image. The eighth action and all dependent engineering/waveform/
drag/topology/science phases were not run.

Four GUI-authored components were normally saved; root/driver exited0, all4,127
traced PIDs were absent and all248 inputs remained exact. The failure and three
known QA errors remain preserved. MAIN corrected the shared viewport to retain
the same visible error and public `last_notice` through release/hover/redraw.
Focused retest must resume this saved Session, preserving the first-six results.
No full eight-tool,18-step, scientific Job/Dataset, Save/Reopen or narrow-window
acceptance is claimed. Independent report: `cw_native02/G1_PROBE_STOP_01.md`.


## MAIN277 integrated Circuit acceptance

Current official restricted package1.9.9 is normally installed in the isolated
MAIN dev109 tree (commit0155e25), SHA256
`16d5e4ac3aae1798cd2e968d488e321350ae17413900cb97ebd259f1c842b213`.
All94 distributed members match. Authored C++2d640a11, nativea65eaa03,
203 controls and historical tutorial resources preserve the tested scientific
and editing behavior. The same-author253 current guide23bba352 truthfully
records the accepted33 functional scopes and retains the full-release OPEN gate;
independent installed257 normal F1, genuine historical images and provider
contracts verify its actual attachment. No private Viewer workaround was added.

CORE corrections reside in the existing Native2D Diagram document/viewport,
electrical catalog and attribute normalization, Scientific Probe, declarative
command/GUI and compiled development/runtime owners. Their authoritative
contracts include the existing `native2DGeometryDiagram*` operations,
`NATIVE2D_VIEWPORT_HOST_v1`, `VIEWER_GUI_HOST_API_v1`,
`VIEWER_DEVELOPMENT_API_v1` and the existing electrical and Probe public
operations. `docs/architecture/AUTHORITY_CATALOG.yaml` records the
same owners and invariants: canonical segment joining, disconnected crossings,
authoritative tool state and genuine completed-Job voltage provenance. It creates
no second topology, parser, renderer, scientific store or execution service.

MAIN249 verifies the exact generated RLC deck, canonical engineering values,
4018 genuine scientific rows, shared local tool event path, original sources and
normal/narrow screenshots. MAIN277 links the separate P0 A–E acceptance159,
original before/after failures, independent current-source187 and all12 handoff
items. Original twenty atomic tool/Canvas pairs and full native trace prove zero
runtime compilation and immediate first actions. No new simulation was required
for the documentation/package tail. Original dev108 examples remain intact.

Only this completed supplemental CW obligation is removed from the unfinished
TODO. Full2/4/5/10/13/15, additive source-specific Preview acceptance, remaining
CORE verification and final separate tutorial/archive/checksum/restore/deposition
gates remain open. Accepted Circuit functionality is not a dev109 release claim.
