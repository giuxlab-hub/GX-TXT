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
