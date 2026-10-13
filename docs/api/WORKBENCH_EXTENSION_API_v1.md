# Workbench Extension API v1

One descriptor/discovery authority covers exporter, importer, tool, operation,
measurement, geometry_generator, transform, validator, repair, analysis and
utility actions. Module descriptors declare `[extensions] api_version=1` and
action IDs, plus each `[extension.ID]` category, compatible `workbenches`,
selection kinds, `mutates`, public API/command, required APIs and parameter IDs.
Parameter sections use the shared UI Field types, defaults and validation.
Plugins do not supply arbitrary Tk widgets.

List/Describe discover enabled installed providers. Invoke receives logical
Workbench identity/version, document ID/revision, selection, active object/group,
plane, units and parameters. Unknown context fields and parameters are rejected.
CORE adds a snapshot of effective plugin configuration and validates document
ownership/revision and required APIs before invoking the provider.

Mutating hosts register Begin/Apply/Commit/Rollback callbacks. A provider returns
a structured successful result; the host validates/applies it and commits once.
Failure rolls back the host transaction. CORE owns revision-before/after and
producer/config/parameter provenance in the receipt. A Workbench must supply
its transaction/history adapter before mutating actions are permitted.

Exporters receive the renderer-neutral presentation snapshot. Export validates
the declared format and atomically creates a user-selected output file, rejecting
collisions. The receipt reports bytes, SHA-256, format and display policy. No
private Session path, native pointer or window handle enters action context.

The shared exporter dialog discovers formats and typed parameter fields from
descriptors. `export.native2d_presentation` supplies PNG and true vector SVG.

## Research scripts and mutating Curve Workbench actions

Script Module Builder profile `W` produces ordinary hashed Python/Octave module packages with the same extension descriptors and public registration used by other providers. Script/bundle bytes remain unchanged. The installed action runs through CORE packaged Script Execution. It calls `script_context` (no arguments) to read immutable logical context with typed scalar parameters/config and `return_result` (one struct) to return `status=ok`, `operations`, optional `warnings` and `provenance`. Both share `WORKBENCH_EXTENSION_API_v1`, provider `workbench_extension`. Context requires a host-issued invocation. ReturnResult also stages validated research/recipe proposals in Script Workspace without applying them to a GUI document. Results are bounded to8MiB and stored by CORE as inert execution-owned data.

Curve Workbench **Extensions…** discovers enabled compatible actions and uses shared parameter fields. Each invocation refreshes document revision and selection. Its host transaction accepts up to 256 operations: `affine` (`target_ids`, six-number `matrix`), `create_sketch` (`name`, retained `definition`, optional `display_samples`, `working_unit`), `create_points` (`name`, exact XY `points`, optional `working_unit`), `replace_points` (one logical target, exact `points`), `delete` (`target_ids`) and `identity` (`target_ids`, optional `name`/namespaced `attributes`). Explicit point inputs are limited to 65536. Locked/large Dataset geometry rejects mutation; Convert to Native supplies an explicit editable range.

The host validates operation/field/lifetime/ownership/Native constraints, tracks actual created/modified/deleted IDs and commits one history action. Failed multi-operation proposals restore the full prior geometry/presentation and history. Plugin version, action, script hash/language/execution ID, normalized parameters/config and API identity persist in the record provenance. A failure after the authoritative document revision changed is reported as a committed action with a warning, avoiding a false rollback. Disabled or checksum-invalid modules cannot invoke.

Read-only actions do not enter a mutating transaction. Action selection kinds must match the logical context. Public action context contains no Native IDs, native pointers/window handles or private Session path.

Both Workbenches also accept `replay_recipe` with an encoded, fully validated
Scientific Recipe API proposal. Native3D registers a transactional host and shared
Extensions chooser: `box`/`cylinder` accept name and native parameters;
`translate`/`rotate`/`scale` accept logical target IDs and parameters; `identity`
accepts names/attributes; `delete` accepts target IDs. Complete geometry is staged
in a separate scene before mutation, then committed once. Locked/missing targets
reject; grouped targets require an explicit group operation. A failure restores
original Native ownership, complete geometry, presentation and history.


## TASK-9 dev-052 final behavior

`workbenchExtensionExport` validates optional provider sidecars (`suffix`, `bytes`) and atomically publishes the main geometry plus all sidecars with normal File Publication. Sidecar names are unique and suffixes restricted; the receipt reports published files rather than raw payload bytes. `export.native3d_geometry` is the official provider for complete STEP/STL/VTP and explicit canonical Dataset publication. It receives a host-issued document/revision/owned-resource snapshot, stages an independent Native scene, excludes nonregular roles and validates owner revision before publication. Scripts use scoped Native `export_resource` plus Dataset Publication, with no raw filesystem destination authority.
