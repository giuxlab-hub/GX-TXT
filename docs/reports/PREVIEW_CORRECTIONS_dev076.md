# GX-TXT 0.9.8.10-dev-076 — focused corrective handoff

Status: implemented and focused verification complete; publication receipt and archive
SHA are recorded in the versioned workspace handoff. Manual acceptance remains pending.
Stop after delivery. Baseline is the published **dev075**, independently checked against
archive SHA-256 `27935ff63b4d8e7f869e80b265a2cc3aa85e4709689153d8d5f30b8b6539a659`,
the expanded tree and every internal manifest entry before the candidate was created.
No intermediate worktree or dev073 sources served as the baseline.

## Confirmed regressions and actual consumers

**Profile suspicion confirmed.** On dev075, `_profileStep` reconstructs categorical
`variables` from descriptive `summaries`, even when those summaries have partial coverage
or have hit a distinct-value limit. A request for two rows and one retained value changes
an existing complete four-value member inventory into a one-value incomplete inventory.
`scientificDatasetFilterDimensions` trusts the current record and exposes the reduced
choices. `scientificDatasetFilterControls` can consequently drop selected absent members
and disables "All members as separate curves". `graphSeriesDistinctValues` instead falls
back to a full source stream: its final values remain correct when the source is readable,
but the persistent no-scan inventory is lost. Baseline evidence records one fallback scan.
`datasetProfileDistinct` also hides the prior complete inventory behind the partial sample.

Existing affected consumers are Dataset Preview, the CORE Scientific Dataset Viewer, and
the shared Graph Series editor (`graphSeriesEditorValueChoices`) offered through existing
Graph Series/plot modules, including the `plot.dataset` path. `curve.replicate_analysis`
also declares Graph Series API access. The read-only Script Bridge distinct operation
calls the same additive profile getter. None requires a plugin migration.

Dev076 preserves identity-validated complete categorical entries and lets the distinct
getter use them when a descriptive sample is incomplete. `datasetProfileVariable` still
reports partial measured coverage. Complete membership never certifies complete statistics.
Replacement/schema identity changes continue to invalidate old profiles. CSV and HDF5
fixtures check partial row coverage and full coverage with a smaller distinct budget,
unchanged canonical source hashes, and zero Graph Series fallback scans. A real Preview
filter dialog and the existing Graph Series value chooser retain all three GUI fixture
members following partial profiling.

**Multiview suspicion confirmed.** Dev075 `_multiviewReadable` calls revision-strict
`_multiviewRequire`; its catch destroys the entire host. A genuine isolated Native3D
render sent before an owner commit, delivered after the revision increments and before
`ModelChanged`, reproduces that destruction. This is distinct from dev075's already tested
case where ModelChanged is called before the stale frame arrives.

Dev076 validates Session/document generation independently of revision in the response
handler. A pending owner revision rejects the response, clears obsolete queued work,
records `stale_rejected` / `model_refresh_required`, and retains the host and its stored
revision. READY records worker readiness without scheduling an obsolete render. Epoch
checks still reject frames following explicit ModelChanged. Stale picks cannot change
selection. Explicit owner regeneration still updates both Native views; real Session
expiry still destroys the host and its workers/scenes.

No shipped dev075 plugin/viewer directly invokes Scientific Multiview Host; it is an
optional CORE API advertised through Workbench Extension discovery. The focused test
uses the real API, real worker, an unchanged Curve Workbench source and an independent
Tk owner. Existing full Native3D viewers use their own established viewer path. Their
independent operation and worker ownership are also verified.

## Preview reuse and invalidation

A single active Preview is retained in its existing widgets. Notebook tab/page changes
unmap those widgets without incrementing the preview epoch or disposing resources.
A valid return keeps the photo/text, scroll position, axis/filter selections, action
state, Native3D camera and the existing embedded viewer/worker. The cache fast path
skips `datasetPreviewActionsState`'s scientific table-support probe; action state is
already correct for that identity. Toolbar placement remains responsive.

The rendering signature contains the established Session/Dataset source stamp
(canonical registry identity, scientific schema, file stat and metadata), selected
X/Y variables, equality filters and separate-curve mode, Preview settings and Native3D
graphics/resource policy. Pending/single-file signatures additionally retain their
existing acquisition configuration and channel mapping identity. Generation freezes
the signature after controls reconcile defaults. Responsive-read reentry is guarded
so the same active build cannot restart itself. A consumed catalog drain callback
becomes a no-op, preventing a background error observed during real replacement and
responsive Preview regeneration.

Returning after a source, schema, metadata, selection, filter or option change regenerates
when Preview is visible. While hidden, a one-second identity/options watcher releases
obsolete resources without starting scientific work. Dataset changes discard the single
old cache; a Session change cannot revive it. Explicit Refresh always regenerates a
non-cleared Preview; Clear immediately closes the embedded worker, deletes photos and
media temporary files, preserves filters and retains its existing Session/Dataset clear
identity. Refresh respects Clear; explicit Render restores the visualization.

Native2D scientific previews remain derived PNGs: the existing renderer destroys its
transient scientific scene in `finally`; the cache retains only the display photo.
Native3D keeps its actual owned viewer/scene/worker and camera. A same-size remap does
not send a render request; a real viewport size change does. Hidden valid worker and
media-thumbnail completions are retained. Hidden initial worker readiness is deferred
until mapping. Clear/Session expiry release the embedded worker while an independently
opened existing full viewer remains isolated.

## Focused evidence and compatibility

Real authenticated local Xorg `:1` with the existing GDM Xauthority and actual xdotool
mouse input exercises the complete existing Tk application. Scientific Preview counters
before/after unchanged inner-tab return are **1 1 1 2 2 0 → 1 1 1 2 2 0**, respectively:
filtered renders, Curve Source opens, table-page probes, stream chunks, range reads and
hyperslab reads. Outer-page return likewise adds zero calls. Photo identity and text
scroll position are unchanged. Native3D return preserves exact worker/photo/camera and
adds zero render requests. HDF5 array-plane return performs no new hyperslab read;
binary thumbnails finish while hidden and return without another conversion process.

Focused checks cover Refresh/Clear, filter/variable/options changes, schema edits,
canonical replacement, obsolete filter reconciliation, reentry, real viewport resizing,
hidden completion/startup, independent full viewer ownership and hidden Session cleanup.
Delayed Multiview replies are rejected, explicit owner refresh works, and owned Native2D
scenes/Native3D processes are released. The inherited dev073 **validation-only** profile
fixture checks replacement, schema identity, empty categorical values and no-scan reopen;
its historical deployment scripts are never executed. Headless discovery remains Tk-free.

All **3,227** existing CORE Tcl procedure signatures are unchanged; two internal cache
helpers are additive. Existing plugin packages, script bindings, Native2D/Native3D kernels
and binaries, Geometry Exchange, external plugins and Session Generators retain baseline
bytes. The release verifier permits only the five focused CORE/GUI source files, version
and documentation changes. All other baseline files are verified unchanged. No exhaustive
GUI suite or full SEM viewer implementation is part of this task.

Evidence is frozen under `docs/evidence/dev076/`; fixtures and version-pinned incremental
publisher are under `validation/preview_dev076/`, with arguments and side effects in
`SCRIPT_CATALOG.md`. Numbered historical releases and all original scientific data are
preserved. The archive, expanded tree, restore archive, active runtime and alias are
independently verified after publication; all three deposit sections retain paired sets.

## Real limits and remaining acceptance

The cache is one active in-memory Preview, not a multi-Dataset history or persistent
Session cache. Metadata/schema/stat checks perform small authority I/O; they do not read
scientific samples. External file changes use the existing identity/stat checks instead
of fully hashing every source on every tab change. Hidden invalidation is bounded to one
second; explicit Refresh/Clear is immediate. Binary conversion temporary files retain
the existing five-minute expiry while already loaded display pixels remain reusable.
Multiview regeneration remains explicitly owner-supplied and synchronous during owner
preparation; pending revision is not permission to interact with the new model.

Manual acceptance of dev076 remains open. Prior bounded CORE v1 limits and separately
scoped work remain in the unfinished-only `GX-TXT_REMAINING_WORK_TODO.md`. Completed
corrections and cache implementation are not listed as future tasks.
