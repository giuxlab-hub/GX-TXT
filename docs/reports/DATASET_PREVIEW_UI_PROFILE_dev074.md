# Dataset Preview, explicit filters and CORE profile — dev073

Status: validated focused corrective release; manual acceptance pending.

Dev073 was published after its focused tests, then a final compatibility audit
found an omitted empty-text category in profiles marked complete. It remains
immutable. Dev074 corrects exact text inventories and labels empty text without
changing source values. Profile revision 2 rejects older derived inventories;
normal scientific commits and explicit Build regenerate them. Focused tests compare
persistent results with the original Graph Series scan, including empty strings,
verify revision invalidation/rebuild and unchanged canonical bytes. This is the
concrete reason for the additional version in the same authorized task. Derived only from
immutable GX-TXT 0.9.8.10-dev-072 (archive SHA-256
`5f08d4a0cd71ed50dc072f05bc22c0ab7cf1a421a7556286934d1ffa3d0bc08e`).
The interrupted candidate was not read or reused. Dev074 continues this run’s
verified fresh-baseline candidate; published dev073 archive/source/handoff stay unchanged. Project/Session redesign is outside scope.

## Behavior

The existing active inspection Dataset is the sole selection authority. Dataset
header duplicates are hidden, automatic visible Preview synchronization uses catalog
notifications and effective identity, and the navigator Refresh forces resynchronization.
Epoch/identity/visibility checks reject obsolete asynchronous completions. Clear keeps
inspection information and survives refresh, tab changes and identity-preserving rename
until explicit Render or new activation. Notes/schema drafts remain protected.

Copy, Table pages and Clear are glyph actions in a draggable overlay with a grip,
fixed to the viewport across scrolling, rerendering and Dataset changes. Unsupported
Table pages/Pending operations are disabled with explanations. Variables Help is last.
One contextual navigator Edit retains existing Notes, Metadata and Temporal Set flows,
including Save/Cancel/Back, validation and activation locks. Existing legacy single-file
input is activated with its navigator glyph; generic Pending detection is automatic,
while the legacy single-input detected-CSV action remains available when meaningful.

Family/Group, Trace and Replicate controls appear only for genuine schema variables;
labels show stable Variable IDs and units. Independent exact filters intersect. Explicit
multi-family selection produces separate curves, at most 16. All rows is the unfiltered
single-series default; All members is available only for complete inventories. Existing
Curve Source/Native2D keep source order, row identity, missing gaps and units.
**There is no Sylvania rendering fix:** its unfiltered 540 rows correctly remain one
continuous source series. No automatic splitting or Dataset-specific renderer exists.

Embedded mesh/structure Preview retains the existing CORE Native3D worker while visible,
uses actual viewport framing and existing fit/preset/navigate/cube pick/click APIs.
The cube uses 80 px and 40 px margin; full Viewer retains 128 px and 16 px. Zoom +,
Zoom − and Fit All sit above it. Tab/Session/Dataset/Clear/close cancel owned workers,
images and timers. The Native2D and Native3D kernels are byte-identical to dev072;
only the Tcl Native3D adapter was rebuilt for Preview presentation and diagnostic receipt
fields. On this server embedded Preview Auto uses existing Software rendering for
readable cube colors; explicit policies and full Viewer retain their prior behavior.

Expanded History constraint groups expose individual immutable constraint identities.
Inspect/select is read-only. Edit/remove require an explicit confirmed restart to an
editable retained step, then use existing CORE constraint editing/removal, dependencies,
solver and Undo/Redo. Cancel preserves saved past/future. The complete old Workbench
manual is retained and extended. Workbench is packaged as 2.13.1; other modules and
Session Generators are unchanged.

## Persistent CORE Scientific Profile

Metadata API v1, Variable Schema v3, Catalog v1 and graphSeriesDistinctValues were
inspected. The latter had only an in-memory cache, so a minimal CORE profile was added
in reserved existing Metadata `_gxtxt.framework.scientific_profile`. Stable Variable
IDs, actual encountered distinct values, completeness/truncation, registered Dataset
content hashes and existing Graph Series scientific schema identity are exposed through
public read-only Read/Discover operations; explicit Build is the controlled persistence
operation. No second database, sidecar or fingerprint authority is introduced.

Relevant normal canonical registry commits regenerate profiles inside existing backup/
transaction handling. Scientific schema rollback includes metadata. Preview filter discovery consults
persistent values first and Graph Series reuses complete matching inventories. Plotting
still reads requested XY rows through existing Curve Source. Old
Datasets have a bounded once-per-Session/identity legacy Discover cache and explicit
Build for cross-process persistence. Ordinary consultation does not write canonical data.
Stale profiles expose no usable values; canonical content/schema changes regenerate.

Bounds: 100,000 total scanned rows, 32 scanned variables, 1,024 distinct values per
variable, 1,024 bytes per value and 2 MiB retained value bytes. Compatible dimensions
share Table Stream scans; independent dimensions use their own bounded access. Unknown
or over-budget sources remain explicitly incomplete, with reasons. No All members claim
is enabled for an incomplete inventory. This is a categorical profile, not an index.

Implementation limitations: profile eligibility is enabled rank-one grouping/category
Variables supported by existing row filters; scalar and multidimensional category
inventories are outside this focused extension. Declared numeric source codes are
included and tested. Profiles are built with a bounded pass inside commit after
normal source processing, rather than a streaming accumulator; large sources can remain
incomplete. Legacy discovery is read-only and lasts a Session process; explicit Build is
needed to persist older Datasets across processes or cache eviction (32 identities). Registered identity and existing payload
integrity checks remain authoritative; unauthorized external file edits are not silently
normalized. Full/explicit Hardware cube colors on this NVD9 server remain a known issue.
STEP normalized-unit exposure and broader codec/provider coverage remain in TODO.

## Evidence and preservation

Focused API checks verify 540-row unfiltered behavior, exact selected row IDs/order,
independent filters, gaps, units, unchanged scientific data and public receipts. Persistent
profile tests verify normal synthetic publication, reopen/Graph reuse with zero scientific
Table Stream calls, canonical replacement, scientific schema changes, new-process
persistence, stale-value rejection, legacy one-time discovery, incomplete budgets,
independent HDF5 categories and injected registry/schema/metadata transaction rollback.
Existing focused Native2D/Sketch/CORE failure-injection suites are retained and run.

Actual local XFCE/Xorg keyboard/mouse evidence covers clean page/laptop/desktop layouts,
filters, floating actions, Clear/force refresh, draft/save/cancel flows, media/Pending,
Temporal Sets, rename/move notifications, full scientific Viewer, Native camera/cube,
rapid switching and resource cleanup, old Workspace construction and historical
constraint inspect/restart/edit/remove/Undo/Redo/persistence. A copy of the real Session
provides Sylvania, curve.replicate.traces and CCD GLY evidence. Original scientific Session bytes and
Workspace ZIP inventories are protected and rechecked. A separately running remote
GX-TXT process changed original Workspace/recovery/report-cache files during validation;
these external changes are recorded in reference-live-audit.json and left untouched.
The local tests open only the private copy. Screenshots receive direct visual
review; controller errors and tested-source stamp are checked before publication.

See `docs/reports/ACCEPTANCE_dev074.json`, `docs/reports/CHANGED_FILES_dev074.txt`,
`docs/evidence/dev074/`, `docs/DATASET_PREVIEW_CONTROLS_dev073.md`, and
`docs/api/DATASET_SCIENTIFIC_PROFILE_API_v1.md` for receipts, source/API contracts,
visual review, retained limitations and changed files. The release publisher verifies
paired archives/expanded contents, active runtime/alias, restore archive and plugin ZIP
parity while preserving historical releases. Stop for manual acceptance; no next phase.
