# Integrated Dataset, CORE viewers and History — dev072

Release: GX-TXT 0.9.8.10-dev-072, derived from immutable published dev-070 and its
version-specific handoff. Delivery is for manual acceptance; stop after delivery.
This report follows `GXTXT_NEXT_DATASET_CORE_VIEWERS_HISTORY_INTEGRATED_TASK.md`.
Google Drive, Windows, ZIP optimization and a further feature phase are outside scope.

## Corrective publication and provenance

Dev071 was published, then its installed GUI check caught a small Tk selector
listvariable residue after scientific-window close. Streams, jobs and Native scenes
were already released, but widget destruction recreated the numeric/member lists.
Dev072 destroys widgets before clearing their state. Fresh-process and installed
checks require an empty per-window state after close for both CORE viewers.
Dev071 archive, expanded tree, restore point and packages remain immutable; it was
not manually accepted and is superseded for this delivery. Dev072 reuses its five
compatibility packages byte-for-byte. No additional feature development occurred.
Full integrated evidence and contract matrix are retained from dev071; the correction
has its own source-bound validation and installed receipt. The final changed-file
inventory is measured against the original dev070 base.

## Architecture and delivered changes

CORE retains the Dataset Registry, Publication, Schema v3, Metadata, Namespace,
Dataset Access/Table Stream/Curve Source, Transform, Session/Document lifetime,
Parameter Service, Scientific Recipe, Native2D and Native3D authorities. No new
Dataset registry, scientific file format, parallel history database or viewer
plugin was introduced. `datasetViewerDescribe` resolves canonical identity and
capability; `datasetViewerOpen` opens CORE read-only scientific/mesh/media readers,
or the existing guarded Sketch editing workflow. Python Script Bridge exposes the
read-only descriptor. Existing two-argument Curve Source calls remain valid; an
optional progress callback supports cooperative unknown-row-count opening.

The Dataset page contains Variables, Metadata, Notes, Temporal Sets, Variables Help
and Preview. The former Preview widgets and their commands are reused inside it.
Refresh, Save Schema, namespace manager and Open icons sit above the navigator.
Current is an action indicator, independent of explicit Dataset activation. Preview
controls wrap to remain reachable. Canonical table pages preserve exact source-row
numbers; choosing/highlighting a navigator row alone does not activate a Dataset.

`base` is the effective fallback; old `current` paths project read-only to `base`.
Explicit legacy migration creates and validates a portable Session backup first,
then commits metadata/catalog changes atomically. Migration failure restores bytes
and in-memory state. Pending items cannot be moved into canonical namespaces;
canonical Datasets cannot be moved into Pending. Generic acquisition and modular
publication both enforce the producer's assigned namespace independently of Current.
Replacement preserves omitted registry history, notes, provenance and source fields.

Scientific Preview renders actual canonical values to Native PNG with units,
explicit axes/member selection where ambiguous, gaps and source identities. The
CORE Scientific Viewer provides Pan/zoom/Fit, cursor source-row readout, canonical
pagination, multiple compatible-unit Y variables, independently selected family
members, exact bounded multidimensional planes and schema/provenance. Families
never connect across member boundaries. Planes use declared coordinate variables
(including descending ppm), otherwise labelled storage indices. Nonfinite cells
remain explicit. Canonical source bytes are never rewritten by consultation.

The CORE Mesh Viewer loads STL, OBJ, STEP, VTP, VTU and VTI through the established
Native3D/VTK/OCCT backend. It provides Fit, six standard views, isometric view,
orbit/Pan/zoom, surface/wire/edges/points representations, point/cell scalar arrays,
colormaps, field isosurfaces and actual bounds/counts/array summaries. A restricted
CORE worker accepts read-only rendering/navigation commands. Existing plugin API
entry points remain compatibility adapters. Molecular/crystal decoders now live in
CORE with compatibility wrappers; XYZ/CIF and CUBE density consultation were rendered.
Workers, temporary renders, streams and timers are released on close or Session/revision
invalidity. The full contract matrix identifies direct and shared-path evidence.

PDF consultation uses existing Poppler/shared canvas infrastructure. Fit uses the
active page's actual dimensions and rotation. The render cache is bounded to eight
files/64 MiB and cleared on close. Raster consultation implements Fit/zoom/Pan.
Text/code is read-only and never executed. Audio displays a timed min/max envelope
of the explicitly selected stream's first channel, respecting declared raw PCM
metadata; amplitude is labelled normalized PCM, with no invented physical calibration.
External media-reader processes are tracked through pipes, not un-reaped PID polling.

Notes retains the existing scientific text editor (search, markup, undo and preview),
Metadata its full existing controls, and Temporal Sets its original forms. They edit
inside their sections; Save/Cancel returns safely. Section switching preserves input.
Dataset/Session identity is locked while an editor owns a draft. Variables Help is
an integrated English guide with 24 navigable topics and examples.

Workbench History uses the existing Scientific Recipe stored in the Workspace. The
original bottom strip has Description/History modes at its existing footprint,
auto-grouping and expansion, selected-state indication, future dimming and a hide
setting. Browsing reconstructs exact geometry/topology, constraints/dimensions and
named parameter values through a read-only Parameter Service context. It does not
truncate or overwrite saved Workspace state. Editing resumes only at Latest or after
explicit confirmed restart. Restart is rollback-safe and rejects divergence in shared
Session parameters. Existing constraint dependency checks and Undo/Redo remain active.
History retains up to 4096 steps/8 MiB and explicitly rejects overflow instead of
silently rebasing away old operations. Persistence beyond legacy short limits is tested.

Sketch import now restores prior geometry, registry, parameters and binding after
late reconstruction errors. Canonical commit and subsequent draft-save outcomes are
reported separately; a failed draft save does not pretend the canonical commit failed.
Export records source Dataset lineage through converted scientific curves and nested
provenance. A scrollable report lists scope, included geometry, conversions, sources,
omissions and dependencies. Whole-object gap splitting is not misreported as a subset.
Opening another Sketch protects dirty work with Save/Discard/Cancel. Existing PDF
framing, producer-authorized canonical commit and independent Workspace Save remain.

The supplied dev068 Spline defect was visibly reproduced. Native presentation now
evaluates retained definitions adaptively in device space; stored compatibility sample
arrays no longer define the rendered shape. Exact definitions, topology and canonical
files are unchanged. Span-origin remapping uses a linear first-index map instead of
repeated searches. The identical rebuilt Native2D adapter is shipped in CORE,
Workbench and Curve Fit.

## Measured Native results

For the original three retained curves at the tested viewport, maximum distances to
2049 exact reference samples were 0.322, 0.283 and 0.319 pixels. Display counts were
23, 21 and 283 against stored compatibility counts of 257 each. This is adaptive
presentation, not refitting or replacement of canonical geometry. Tolerance begins at
0.35 pixels, with explicit bounded complexity safeguards documented in the API report.

Connected two-part span-plan benchmark, same node-map checksum in both versions:

| Defining controls | dev070 | dev071 |
|---|---:|---:|
| 8,000 | 14.938 ms | 2.880 ms |
| 16,000 | 53.124 ms | 5.392 ms |
| 32,000 | 183.995 ms | 11.298 ms |
| 60,000 | 608.933 ms | 21.068 ms |

These local timings establish the remapping improvement, not a universal GUI latency
claim. 25 existing Native CTests pass, alongside retained-display and focused Tcl tests.

## Validation and evidence

Normal local Debian XFCE/Xorg :1, giu, seat0, Remote=no. GUI runners send actual
mouse/keyboard input; the observation socket reads state only. Tests use copied or
synthetic private Sessions. Original user archives and published predecessors are
hash-checked. Failed diagnostic attempts are retained but are not counted as passes.

| Requested journey | Direct evidence |
|---|---|
| Legacy current projection, base and backed-up migration | gui14 legacy checks and backup; transactions migration rollback/restore |
| Current base/pending/custom, moves, Pending rejection, producer namespace | gui10 namespace; gui14 Pending success/duplicate failure |
| Icons, Current actions, embedded Preview and toolbar | gui10 Current; final3 controls, table rows 101/201; final toolbar screenshot |
| Scientific PNG, plot, units/gaps/row identities | gui07/gui10 and final science; API page/PNG/source-row checks |
| Families and arrays | final six-trace family and exact 24×32 physical-coordinate plane |
| STL/OBJ/STEP/VTP/VTU/VTI, camera/modes/lifecycle | gui10 six-format real render/mode/close journey |
| Structural and scalar fields | gui14 XYZ/CIF/CUBE, VTI isosurface; direct screenshot review |
| Ordinary PDF, raster/audio/text | gui12 real reader navigation/Fit/zoom/Pan/close; PDF cache API |
| Sketch existing-work prompt/export/PDF/Pan | gui14 successful checks, corrected button-input continuation; full report review |
| Notes/Metadata/Temporal Save/Cancel/return | gui07 save; gui11 Temporal save/cancel; final3 Notes/Metadata cancel/identity |
| Variables Help navigation | gui07 and final3 index navigation |
| History grouping/restart/hide | gui11 actual creation, browse, future preservation, restart Cancel/confirm |
| Long History/parameters/dimensions | 170 actual edits, exact historical 12/92/182 values, reopen; fresh-process GUI |
| Import/commit/metadata/migration rollback | transactions04 injected late parameter import, postcommit draft save, file placement, registry commit, metadata failures and retry |
| Prior Workspace and Spline regression | original dev068 before/after screenshots; retained exact-distance check; regression final; fresh-process GUI |
| Public API and language compatibility | API release; Python and Octave Script Bridge; 25 Native CTests |
| Cancellation/source lifetime | forced unknown-count provider cancellation releases all resources; real Session-switch viewer close; canonical SHA audit |

The bundled `ACCEPTANCE_dev072.json` contains successful check labels, exact changed-file
inventory and evidence pointers. Publication and installed-runtime receipts bind the
archive, expanded tree, active runtime, alias and restore point to identical bytes.
The contract matrix is exhaustive for the installed registry; shared-path coverage
is explicitly distinguished from directly opened formats and codecs.

## Verified bounds and genuinely unresolved limitations

- Initial filtered Transform plan preparation remains synchronous in the established
  CORE backend. Scientific display streaming and unknown-count passes have cooperative
  cancellation, but very large family filters can delay input before those stages.
  A cancellable Transform planning API is still needed for a strict end-to-end latency
  guarantee. No unmeasured large-file responsiveness claim is made.
- The existing Native3D orientation cube renders dark with unreadable face labels on
  this local backend. Axes, six named standard-view buttons and Iso remain usable.
  This backend contrast defect remains open; it is not certified as visually correct.
- STEP is normalized by OCCT, but the public Native3D result does not expose reliable
  source/normalized units. The viewer states this limitation and invents no unit.
  Other absent mesh units remain explicitly undeclared.
- Scientific consultation uses explicit 2D projections for `curve3d.table`, not a new
  ordered 3D trajectory renderer. Overlays admit 16 compatible-unit traces and 1024
  enumerated family members. Exact array planes admit two nonsingleton dimensions
  and 16384 cells. Table/plane access preserves canonical information beyond a plot.
- Structure consultation uses the first molecular conformer and a fixed CUBE density
  midplane, with atoms/bonds/cell and details where available. It does not implement
  trajectory playback, arbitrary density-plane controls or chemistry editing.
- Raw PCM and selected audio-stream metadata are wired through to ffmpeg; WAV is the
  directly exercised GUI codec. PDB/SDF, all Pillow formats, acquisition providers and
  audio codecs were not each rerun. Matrix aliases are not independent parser tests.
- Image budgets are 64M source/32M display pixels. Audio intervals are at most 300 s
  and 128 MiB decoded PCM. Text displays at most 256 KiB with a truncation notice.
  PDF password entry and physical printing remain outside the existing reader scope.
- Older already-rebased histories cannot recover previously deleted steps. Shared
  Session parameter divergence prevents restart rather than silently overwriting other
  documents. Existing Native relationships and 256-part/65536-control limits remain.
- Display/picking compatibility samples remain separate from exact retained geometry.
  Adaptive rendering has bounded tolerance escalation under pathological complexity;
  it is not an unlimited-pixel-accuracy promise for arbitrary maximum-size composites.

## Delivery and maintenance

Framework version 0.9.8.10-dev-072. Changed compatibility packages only:
Workbench 2.13.0, Curve Fit 0.3.14, viewer.engine_3d 0.1.4,
viewer.crystal_structure 1.0.1 and acq.molecule_structure 1.0.1.
PDF OCR and Sketch acquisition retain their existing packages. No Session Generator
changed. Server framework/external_plugins/session_generators archive/expanded pairs
remain synchronized. Previous releases, handoffs and original fixtures remain immutable.

See the versioned handoff for exact archive SHA and locations. User/API docs and the
English guide accompany this report. The unfinished-only TODO retains manual acceptance,
the explicitly unresolved backend issues and separately scoped future work.
