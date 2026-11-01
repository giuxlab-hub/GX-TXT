# Curve Workbench comparison display contract

Owner: `viewer.curve_workbench`, public family `CURVE_WORKBENCH_API_v1`.


## Source-bound numerical comparison presentation

`comparisonDisplaySource w` returns a binding to the live enabled comparison's actual window/incarnation, Session token, Document identity/generation, explicit reference/target/method and unchanged comparison record. Source provenance is sampled at admission; cached editable geometry does not assert that its original canonical Dataset remains current.

`comparisonDisplayValidate binding record` returns `valid=1` only while the same owner, active definition, exact record/receipt, geometry fingerprints, coordinate signature, Document generation and referenced resources remain valid. Otherwise it reports a precise stale/closed/inactive condition. Neither operation evaluates geometry, saves a Workspace or publishes data. Both are trusted host APIs; Script Bridge and C++ SDK grants are unchanged.

The residual display uses public Plot v4 `comparisonModel` and its existing native widget. Numerical/statistical authority remains the original comparison receipt, including evaluation indices, maximum and sampling policy. Display points are derived comparison samples, never canonical Dataset row identities. Editable main geometry remains under Native2D. Closing or invalidating its owner retires the residual controller and child surface. A stale comparison requires the ordinary Compare action to refresh. Saving an authorized Workspace may rebind its presentation; display failure does not undo a committed scientific save.

The dev109 implementation is integrated separately from focused runtime/GUI acceptance; see `docs/development/plot_comparison418/IMPLEMENTATION.md` in the framework.

## DEV111-P017 History integration

Existing `undo w`, `redo w`, timeline navigation and scientific Recipe capture
entrypoints remain. They delegate History state/lifecycle to public CORE APIs.
`_history` is a scientific-domain adapter for affected records, not a History
store. The former private thirty-pair stacks and full Recipe recording wrappers
are removed; Undo/Redo move the native cursor without synthetic scientific edits.

The adapter supplies capture, restore, guard, commit, accepted/error, descriptive
row and domain context-action hooks. Owning-thread restoration distinguishes
browse/read-view, latest, Undo/Redo, explicit branch, recovery and rollback. CORE
schedules and invokes hooks and owns journal workers; no Tcl/Tk callback executes
on a worker. CORE auxiliary state persists presentation without scientific rows;
new operation metadata retains bounded pre-operation presentation for exact Undo.

Ordinary edits submit affected logical records plus scientific `@cad` metadata.
They do not materialize the accumulated History or project Interactive Documents.
`_saveExplicit`, Close, scientific Recipe export and strict extension revision
boundaries may export/project complete state and wait for durability. Saved
`cad_workspace scientific_recipe` remains compatible; `history_auxiliary` carries
CORE-owned presentation state. Legacy records gain required header fields only;
scientific step bytes and unknown metadata remain preserved. Recipe export
branches an exported value at the active cursor and retains live future Redo.

This change preserves existing scientific ownership, Dataset/source references,
Session generation checks, Native2D controllers, parameter formulas and manual
GUI layout. It introduces no further CAD algorithms or migration.
