# GX-TXT 0.9.8.10-dev-095 technical handoff — 2026-10-12

SPDX-License-Identifier: GPL-3.0-or-later

This incremental stabilization implements both assigned workstreams from the
accepted 0.9.8.10-dev-094 package. Baseline archive SHA-256:
`b768dde274d2e606b3532b30cf52b9ab737f2fbb9901a347262a559c66d16f9b`.
Development and all scientific/GUI fixtures are isolated from the live installation
and original scientific Sessions. Tutorial script04 is excluded from execution,
modification, debugging and all acceptance/regression tests.

## Scientific diagnosis and resulting behavior

The user's verified Session copy contains `tutorial.large_signal_spectrum` with
32769 rows, X `v_frequency_hz` (Hz) and Y `v_welch_psd_v2_hz` (V^2/Hz).
The canonical full stream measures X 0..32768 and Y
`3.1605257955629954e-07 .. 0.36676684380444358`; every pair is finite.
The three principal peaks are 997 Hz / 0.36676684380444358,
4093 Hz / 0.044956383514306301 and 12011 Hz / 0.0081748597962238087.
These are measured source values, without normalization, smoothing or conversion.

On accepted dev094 the Preview inherited the calibrated `xy_equal` scene default.
Its actual Y viewport was `-11533.889663333654 .. 11534.25643049351`.
Full source and sampled bounds were already correct: equal-axis calibration
expanded the effective viewport using the frequency span. Scientific consultation
now explicitly uses independent axes (`aspect auto`), while calibrated Native2D
geometry defaults remain intact. The standalone scientific Viewer has an explicit
equal-aspect option. Fit recomputes a changed variable/filter/overlay selection;
pan, zoom and resize preserve current navigation.

The fixed standalone Y viewport is approximately
`-0.022005675612532284 .. 0.38877283546955543`; embedded Preview includes its own
small extra padding (approximately -0.0343..0.4011). The original 32769-row PSD
renders 3964 points and retains all three principal peaks with exact source row
and amplitude. Nineteen of the twenty largest local maxima survive the bounded
display; the omitted small noise maximum shares a bucket with a stronger extremum.
The existing ordered extrema sampler is unchanged. A bounded plot cannot promise
every arbitrary source maximum, and an exact scientific export uses full data.
Grid spacing follows the scientific viewport so dense 1 Hz grid lines cannot
obscure peaks. The Preview receipt reports actual view bounds and displayed count.

The larger-data guard exposed an existing 15.4-second async CSV ingestion step at
65536 rows. Curve Source now schedules its same complete ordered Native
accumulator in 4096-row chunks. Exact source rows, bounds and gaps are retained.
Missing-cell fixtures additionally required two small changes in their owning
adapters: Native numeric columns treat an empty coordinate as nonfinite; Transform
typed tuples retain numeric absence as null, and finite predicates/conversion
handle it without changing the source. The shared CORE native adapter is rebuilt;
its geometry kernel and C ABI are unchanged.

## Execution inspection and interaction

Script Jobs identifies each row by immutable submitted Script name, full qualified
registered ID, language, version/revision, state, launch/end/duration and Session.
The exact Job ID remains available and copyable. Launch time is recorded only
after successful guardian spawn; queued/cancelled jobs have no invented execution
time or exit code. Legacy missing fields are explicitly unavailable or projected
from the original immutable runtime, never today's Registry entry.

Double-click/Enter opens a resizable window bound to the exact Job ID and origin
Session. It shows frozen input aliases/Dataset IDs/revisions, Analysis Sources,
parameters, requested outputs versus publication receipts, submitted/snapshot SHA,
runtime/resources and actual process exit code. Failed and completed executions
cannot share another run's log. Archived Sessions without a journal entry use
their own retained metadata and snapshot, with missing/corrupt fields diagnosed.

The manager's lower pane is a labelled 16 KiB snapshot. Polling updates rows and
changed metadata without replacing unchanged text, selection, caret or scroll.
Details provide complete logs through 64 KiB pages, explicit Follow, full copy and
byte-exact Save. Mouse selection, Ctrl+C/Ctrl+A, context Copy, both scrollbars,
pane resizing and window focus transfers are supported. Manual inspection suspends
Follow; only an explicit action resumes it. Full clipboard transfer has a clearly
reported 32 MiB limit; pages and streamed Save provide access to larger logs.
Save rejects the origin scientific Session and linked/nonregular destinations.

Session Files captions add trustworthy immutable Script name/reference and
state/time while retaining the original run folder identity and path. Exact-run
double-click opens the same inspector. No historical file, run directory, source
snapshot or log is renamed or rewritten for presentation.

## Authorities, verification and evidence

The [API change report](DEV095_API_CHANGE_REPORT.md) maps every gap to its existing
owner. Public Script Job/Execution operations are additively extended for bounded
inspection/log pages/Session summaries, using the existing supervisor journal.
There is no new CORE authority, public API family, reader, sampler, plotting
engine, Job registry, transport or Tcl rename wrapper. Plugins, native geometry
kernel/ABI, numerical engines, Python execution bridge and guardian are unchanged.
Optional legacy provider binaries remain byte-identical to dev094; current Native
consumers load the rebuilt canonical shared CORE adapter through `native2DEnsure`.

Acceptance covers the full real PSD plus independent 1024/32769/524289-row spectra,
all known narrow peaks, negative/repeated X, missing/NaN/Inf pairs across chunk
boundaries, zero/constant/near-constant and ordinary signed signals, family filters,
empty views, exact int64 source preservation and explicit >2^53 display rejection.
Responsive async versus synchronous display results agree on points, source rows,
bounds and gaps for the compared fixtures through 32769 rows. The 524289-row GUI
records 133 heartbeats and a maximum 469 ms event-loop delay in candidate acceptance,
with a bounded displayed count and all three synthetic narrow peaks retained.
Scientific payloads are hashed before/after consultation.

Jobs fixtures exercise Python/Octave success, a real independent multiprocessing
PicklingError with exit code 1, distinct input bindings, immutable registry
revision/SHA after edits, queued cancellation, reopen, archived runs and long
Unicode logs. Adversarial inspector tests cover missing/empty/corrupt logs, UTF-8
page boundaries, invalid ranges, symlinks, hardlinks, FIFO and path traversal.
Actual local Debian Tk/Xorg `:1` tests use native mouse/keyboard actions and capture
PSD/Jobs screenshots at 1280x840 and other realistic sizes. Selection/copy across
polling, full-log byte equality, scrolling, Follow suspension and exact-run
Session Files navigation are checked.

The candidate suite passes 24 gates, produces 103 screenshots and checks 438
configuration coverage rows. The accepted dev094 configuration, History, Workspace, Publication, fitter,
classic fitting, family lifecycle, Curve Lab, Viewer and async Job regressions
remain in the complete suite. Fitter numerical output is byte-identical to the
accepted dev094 evidence. The rebuilt native suite passes all 26 tests and the
separate supervisor safety suite passes all 11 checks. All focused and preserved
regressions run again against a fresh extraction of the exact release archive
before activation. Test receipts identify framework paths and hash every log.

Included evidence is under `docs/reports/dev095_evidence/`: before screenshots,
candidate after screenshots/logs, full source audit, scientific/fitter result
receipts, native CTest XML and supervisor evidence. Final exact-package acceptance,
artifact parity and all-original preservation receipts are retained outside the
archive in workspace `_evidence_stabilization_dev095/{package-suite.json,
published.json}` to avoid circular archive hashes. The versioned workspace
handoff records the final archive SHA, installed/expanded/restore locations and
package evidence links. `DEV095_CHANGED_FILES.json` records before/after digests;
`SHA256SUMS` verifies every payload file.

## Delivery and preservation

The pinned reusable publisher is `validation/stabilization_dev095/release.py`,
registered with all validation entry points in `SCRIPT_CATALOG.md`. It gates
preparation, exact-package verification and activation, preserves the previous
active dev094 tree, and checks archive/expanded/active/restore/alias byte parity.
Original scientific Sessions, tutorial resources, installation identity, all
predecessor releases and the three ordered server sections are hash-audited.
Framework archives/expanded pairs gain dev095; external_plugins and
session_generators remain unchanged and paired. No historical deployment script
is run on this release. Restart the existing GUI to load the installed dev095;
existing computations are not terminated by activation.

No unrelated TODO is removed. Only the delivered release header is advanced;
the existing TODO had no separate pending entry for these two newly assigned
bugs. Windows Supervisor/tray, remote dispatch and other deferred work remain
untouched. This handoff closes the assigned stabilization scope.
