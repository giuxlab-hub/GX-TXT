# GX-TXT dev-070 integrated delivery

This release implements the ten outcomes of the authoritative next-release task,
starting from the immutable published dev-069 archive. Workbench is 2.12.0, Curve
Fit 0.3.13 (shared Native adapter parity), PDF OCR 1.0.3, and Sketch acquisition 1.0.0.
Manual user acceptance remains pending.

## Real Spline regression and conversion

The exact supplied `test_per_agente2.gxtxt-workspace.zip` is an external read-only
fixture (SHA-256 `5b32868e08ba6d5ee4e95e551ef07a209f58c1c82511d5dc7eb4c980a90ac94d`).
The baseline API run reproduces its wrong local reference on dev-069. This is not
inferred from a simple newly constructed Path. Native's local policy previously
limited exact span refinement to unmapped standalone Splines. Removing that limit
and encoding the actual composite part/span fixes the authority used by picking,
selection storage, highlighting and editing. No parallel selection registry exists.

CORE exact extraction returns a two-knot retained Spline with the original explicit
cubic arms. Conversion replaces one chosen span by a retained Line, freezing all
unaffected spans' original arms. Transforms, traversal reversal and shared-node
origins are preserved. Existing constraint references are remapped and validated
before committing; failure restores geometry and rules. The logical object remains
inside its original Path. Workbench contributes one Undo/Redo transaction, captures
remapped dimension bindings and units, and saves through existing document services.

## Canonical Sketch and controlled editing

`geometry.sketch` is a versioned data dictionary, not a renamed Workspace or sampled
XY table. It carries exact Native definitions, logical identities, shared nodes,
constraints/dimensions, named formulas and units, and construction provenance.
CORE owns validation, extraction, parameter capture, reading, previews and canonical
file publication. The default acquisition handler integrates portable files; generic
Dataset preview and Open Dataset are contract-based, independent of producer.
Existing Registry, Metadata, Private Metadata, Unit Registry, Parameter Service,
Native renderer and publication rollback remain authoritative.

No-selection publication exports all eligible curves; genuine semantic selection
exports only its selected geometry. Shared subset nodes reuse existing coincidence
constraints. Relationships crossing the subset boundary are diagnosed instead of
silently dropped. Scientific vertices and breaks are converted only in the exported
representation, with units, source lineage and an explicit user report. The original
scientific bytes and Workspace source bindings remain unchanged. A Sketch opens
without restoring or requiring those sources.

An opened Sketch is a Workspace draft tied to its canonical identity/hash. Workspace
Save and explicit Commit remain distinct. Optimistic commits reject stale revisions.
Producer-authorized editing is stored in reserved private metadata and bound to one
Session location, Dataset ID, producer, contract, editor and hash revision. It grants
no general producer namespace access. Acquisition files are handled by the same
transaction. Producer ownership survives; last editor is recorded. A changed revision
consumes its prior grant. Injected registry failure verifies file/registry rollback.

## PDF and navigation

Current View and Entire Workspace exports use the existing Native presentation plan
and guarded camera lifecycle. PDFs contain vector linework/text plus reference raster
layers where applicable; they include scientific curves, coordinate/grid indications,
and visible dimensions/constraint annotations. Entire export fits off-screen content;
current export preserves the zoomed framing. Light interactive styles are adjusted
for white-paper contrast. Both publish ordinary `document.pdf`/`application/pdf`
Datasets through the existing file transaction.

The general reader opens through Dataset Preview without enabling PDF OCR. Its
shared canvas and Poppler renderer were extracted from the existing specialized
viewer; it is not another decoder. Page navigation, zoom rerendering, page/width
fitting, scrollbars and drag Pan are available, with identity/page status and errors.
Existing OCR selection/region/RPC/publication code continues using the shared canvas.
A real OCR rendering check also exposed a pre-existing Python 3.13 incompatibility:
Tk StringVar objects were used as dictionary keys for output defaults. Ordered pairs
now preserve that behavior without requiring hashable Tk variables.
Python Tk/Pillow, Poppler, ReportLab and DejaVu are available on the supported Debian
installation. Reader dependency checks provide a direct diagnosis before launch.

Middle-button Pan routes directly to existing Native view operations. It preserves
semantic selection, geometry, Undo and unfinished construction; the existing wheel
zoom is retained. It does not switch the active construction tool.

## Validation and evidence

Actual local XFCE/Xorg `:1`, giu, seat0/tty2, Remote=no, using native keyboard/mouse
input. The observation socket reads state and widget locations; it does not invoke
product controllers as substitutes for user input. Disposable private Sessions and
isolated XDG state protect canonical user data. Complete input logs remain in the
workspace; release evidence includes inspected screenshots, checks and source stamps.

- Real supplied multiply composed Path: multiple spans within/across Spline leaves,
  Ctrl/Shift, visible local highlights, whole mode, return to local, selective Modify
  conversion, exact Undo/Redo, fresh-process selection on restored converted Path.
- Whole and mixed local Spline/Line subset publication; scientific XY export with
  gap preservation, conversion report and unchanged source SHA/binding.
- Normal Dataset geometric preview/Open, all five original connection constraints,
  named formulas/units, geometry-only Sketch import, Save versus explicit Commit.
- Authorized foreign Dataset parameter/dimension edit and commit; a second identity
  rejects commit without canonical changes. Native/API injection checks rollback,
  revision invalidation and copied-grant rejection.
- Both PDF exports, zoomed framing versus off-screen-inclusive fit, canonical
  registration, camera restoration, and unchanged editable curves/source bindings.
- Imported independent two-page PDF and generated PDFs opened through normal
  Dataset navigation, with real page/zoom/Pan/fit operations and visual inspection.
- Middle Pan with selection and unfinished Spline, plus wheel zoom.
- Fresh original and imported Workspaces preserve exact definitions, valid constraints,
  source distinction, named parameters and Dataset draft bindings.
- Focused dev-069 Circle/Rectangle/control/list/window selection, straight segments,
  parallel constraints, Spline attachment/termination and cross-Path dimensions.
- 25 existing Native CTest fixtures, specialized PDF OCR API and local Tk/Poppler smoke, narrow public Tcl tests, actual Python and Octave
  Script Bridge extraction/conversion and Sketch publication/read operations.
- Fresh installed-runtime checks bind delivery to the same packaged source/adapters.

Evidence roots: `_evidence_dev070_gui04`, `_evidence_dev070_reopen04`,
`_evidence_dev070_final`, `_evidence_dev070_installed`; API `_evidence_dev070_api09`; Bridge
`_evidence_dev070_bridge04`; logs and publication receipts `_validation_dev070_*`.
`docs/reports/ACCEPTANCE_dev070.json` records checks and the complete changed-file list.
Validation runners and side effects are cataloged in `SCRIPT_CATALOG.md`.

Earlier attempts are diagnostic evidence, not successful acceptance: the API probe
first caught the real dev-069 span error; GUI inspection caught insufficient PDF
contrast and blank default-color Sketch preview, both corrected. Harness fixes
covered tab naming, hidden Fit controls, asynchronous completion and fixture receipt
unwrapping. Repeated Sketch opening also exposed a draft-name collision; unique draft names now preserve prior drafts. Canonical object/constraint IDs, geometric metadata and incoming provenance survive import/republish. The rejected foreign commit initially used a modal error; the final
menu uses the established non-modal notice. Final evidence verifies the corrected
behaviors. A passing assertion never supersedes a visible graphical failure.

## Limits and preservation

All requested functional areas are implemented. Native's supported primitive,
constraint and storage bounds still apply: 256 composite parts, 65536 defining
controls, and a 64 MB Sketch file limit. An incompatible constraint, unsupported
fragment/selection dependency or conversion exceeding those bounds fails explicitly.
Parameter-interval fragments on a converted Path must first be removed; their old
intervals cannot safely acquire new meanings after subdivision. Stale named semantic
references use Native's existing revision checks. External Session parameter values
are captured locally with original formulas in descriptions; exported Sketches do
not retain live dependencies on a foreign Session.

PDF linework is vector presentation tessellation, not analytic PDF Bézier rewriting;
editable retained geometry stays exact. Reference images remain raster. Physical
printing is separate scope. Reader consultation uses Poppler-supported PDFs and
does not implement password entry for encrypted PDFs. These yield explicit reader
errors. The validation is focused acceptance/regression, not a claim of exhaustive
coverage of every historical plugin or solver relationship.

Dev-069 archive/expanded contents, previous versioned releases/handoffs, restore
points and the user's original reproducer are preserved. New framework/plugin
archives and expanded trees match, as do installed/alias/restore copies and all three
Native adapters. Session Generators are unchanged. Authoritative handoff, current
continuity and unfinished-only TODO are synchronized after installed verification.
