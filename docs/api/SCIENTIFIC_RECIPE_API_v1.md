# Scientific Recipe API v1

CORE owns inert `gxtxt.scientific_recipe.v1` data, source/API/plugin validation,
rolling recording, controlled replay proposals and Python export. Both Workbench
controllers register owner adapters. No recipe is evaluated as Tcl, or contains
renderer handles or private framework/Session paths.

Each accepted semantic step records public API/version, underlying geometry API,
operation, parameters, logical targets/results, units and an exact scientific
state patch. Retained Native2D definitions remain mathematical definitions;
complete bulk Native2D and Native3D geometry uses content-addressed Interactive
Document resources. Replay resolves captured results through public geometry and
resource authorities. It does not rerun a version-dependent fitting or Boolean
algorithm; original parameters and producer provenance remain inspectable.
An accepted drag records one action, rather than pointer-motion callbacks.

The rolling window has at most128 steps and8MiB of structured recipe data. When
older steps expire, their patches advance the base checkpoint, retaining the
complete current replay state. The action transport also has an8MiB limit;
oversized base64 proposals reject explicitly before mutation. Owned resources
remain Session-scoped: move/copy the Session through normal persistence, rather
than expecting a script alone to supply missing scientific inputs.

Public Tcl entry points are `scientificRecipeInspect(encoded)`,
`scientificRecipeValidate(encoded)`, `scientificRecipeGeometryState(encoded,
stepCount=-1)`, `scientificRecipeProposal(encoded)`,
`scientificRecipeCapture(owner, context)`,
`scientificRecipeReplay(owner, context, encoded)` and
`scientificRecipeExportPython(encoded, destination)`. Python and Octave expose
Inspect, Validate and Proposal through provider `scientific_recipe`.
GeometryState resolves the base plus ordered patches after full validation.

Validation checks required APIs, enabled exact plugin versions, current Dataset
fingerprints, units, logical identities, resource hashes, complete retained
geometry and group references. Invalid input stops before authoritative mutation.
Replay belongs to its declared Workbench; the extension host verifies document
revision and commits one Undo action. Native3D uses a staged candidate scene.
There is no implicit Dataset publication.

**Scientific Recipe Recorder…** displays operations/API/targets/results/units,
validates, replays and exports **Python script** through atomic file publication
and the native Save dialog. Generated source uses only public
`SCIENTIFIC_RECIPE_API_v1.proposal` and
`WORKBENCH_EXTENSION_API_v1.return_result`. Script Workspace validates and stages
the proposal without mutating an unrelated GUI document. Builder profile W
packages the identical source; invocation in the owning Workbench applies one
transaction. Source bytes and SHA remain unchanged.

## Explicit History rebase (dev094)

`scientificRecipeRebase(record, current_snapshot, context)` is a pure host operation
on the same CORE authority. Context requires `owner`, `document_id` and
`retention=complete|rolling`. It preserves record metadata, validates owner/document
preconditions and the registered host's complete current scientific snapshot,
then returns `base=current_snapshot, steps={}` within the existing 8 MiB ceiling.
It never alters the caller's record, appends automatically, deletes recovery data,
raises limits or changes complete-retention append behavior. Registered future
owners can use the same operation without importing another Workbench.

The caller captures live scientific state and commits the returned candidate via
Session Workspace/Interactive Document, with recovery checkpointing kept separate.
Curve Workbench offers explicit Workspace → Clear History with confirmation and
portable-backup navigation. Precommit failure preserves old live/saved History;
a postcommit recovery warning reports the committed reset accurately. Undo/Redo
restart empty; current scientific records, resources, parameters and notes survive.

## Shared Workspace History host adapter (dev096)

`scientificHistoryCreate(owner, snapshot)`, `scientificHistoryAppend(owner,
record, snapshot, description)`, `scientificHistoryNavigate(owner, record,
index)`, `scientificHistoryBranch(owner, record, index)`, and
`scientificHistoryState(record, index=-1)` use the same immutable Recipe base
and patches. A record has a persisted cursor, complete retention, meaningful
timestamps/descriptions and the existing 8 MiB/4096-step bounds. Its registered
Recipe host validates inert scientific snapshots and resource references.
Rebase also resets a present cursor to zero. Geometry/arrays remain resource
references where required; no second History persistence store is introduced.

`scientificHistoryViewerAttach` takes capture/restore/commit/guard callbacks.
`scientificHistoryViewerState(window)` returns the inert currently displayed
checkpoint, including the browse cursor when browsing. Hosts use it to restore
bound form controls before a guarded edit, so cancelling a branch preserves the
visible values and accepting it can apply the captured new user choice.
The host commit uses Session Workspace/Interactive Document transactions.
`scientificHistoryViewerChanged` commits one semantic operation, rolling back
live state on precommit failure. Navigation separates durable Undo/Redo from
read-only browsing. `PrepareEdit` requires confirmed branching after Undo;
`ViewerClear` guards latest state and offers protected portable backup before
calling Recipe Rebase. Export/publication side effects are outside local Undo.
The common `ViewerStrip` presents a compact Description/History selector and
timeline, with Previous/Next/Return to latest/explicit restart context actions.
This adapter is used only by History-capable hosts; Interactive Curve Builder
must not attach it.

`scientificHistoryStripFields` and `scientificHistoryStripValidate` supply the
typed `visible`, `mode` (`Description` / `History`) and `grouped` preferences to
the host's existing Configuration contribution. `scientificHistoryViewerStrip`
accepts an optional configuration ID and pack-layout arguments; it subscribes to
that authority and releases the subscription when the owning Viewer closes.
`scientificHistoryViewerStripSet` / `Toggle` use the current Session token and
persist through Configuration rather than adding a history snapshot or private
settings file. Hiding the strip preserves the complete History record.

`scientificHistoryGroupedEntries` groups consecutive equal descriptions and
operations at most 60 seconds apart for presentation only; indices and all
individual patches remain intact. `scientificHistoryViewerDetails` exposes full
read-only status text or each individual timed operation. The shared strip
adjusts its common height to the current font/control metrics, retains horizontal
timeline scrolling and exposes context actions through the existing configurable
Viewer command catalog. These are host GUI services, not Script Bridge commands.
