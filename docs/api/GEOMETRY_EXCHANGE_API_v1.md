# CORE Geometry Exchange API v1 — dev075

Exact, explicit copies between independent Interactive Documents. No Dataset is
published. Existing Native2D, Workspace, parameter, unit and document APIs retain
their contracts. This is optional; existing modules need no migration.

## Public Tcl contract

All commands are in `::GX`. Discovery is source-safe and headless. Geometry work
loads the established Native2D adapter, without loading Tk or the source GUI.

| Command | Contract |
| --- | --- |
| `geometryExchangeApiInfo` | Version, limits and supported operations. |
| `geometryExchangeSourceRegister module provider commandPrefix` | Optional trusted owner adapter; returns a saved canonical `sketch` and `groups` from document metadata passed to it. Registration requires its existing module context or an explicit CORE/user operation. The callback must be pure/read-only. |
| `geometryExchangeExport document sketch selectedIds ?options?` | `sketch` may be `{}` to use CORE's saved source snapshot. A supplied complete snapshot must match saved whole-object definitions/units. Saved metadata, provenance, constraints and parameters prevail. Returns checksum-bound descriptor with exact definitions. |
| `geometryExchangeInspect descriptor` | Validates format, bounds, SHA, Session lifetime, source owner/generation/revision/payload SHA, saved definitions and captured parameter dependencies. |
| `geometryExchangeImport destination descriptor ?options?` | Stages a new destination-owned Native scene, allocates new local IDs, validates dependencies, prepares an owner-compatible payload, then commits once. Returns `source_to_destination`, `object_tokens`, `group_tokens`, `groups`, canonical `sketch`, `revision`, and `scene_token`. |
| `geometryExchangeRestore document sketch ?groups?` | Reconstructs already committed destination geometry/constraints/groups in a fresh scene; returns new runtime handles for persisted local IDs. Its source may have been deleted. |

The serialization language is the existing `gxtxt.geometry.sketch` version 1.0.
Native's supported exact families include line, circle/arc, quadratic/cubic Bezier,
spline, path/compound, point, construction line and their retained controls and
local matrices. Unknown definitions are rejected; no display polyline is substituted.
Native IDs/worker pointers never appear in portable exchange content. Runtime
handles exist only in the import/restore receipt, outside its persisted `sketch`.

CORE reads canonical Sketch payloads directly. Its additive saved-Workbench adapter
reads `gxtxt.curve_workbench.workspace` version 2 retained definitions, constraints,
parameters and groups without instantiating that plugin. Other owners register a
pure source adapter. The built-in Workbench adapter deliberately declines a mixed
snapshot containing bulk/Dataset-backed curves; it cannot certify those payloads
as bounded retained definitions. Whole-object inventory and dependency closure are
required; segment/fragment export belongs to existing selection/extraction APIs.

## Dependencies, parameters and physical coordinates

Export options are `dependencies strict|closure`, `groups` (object-ID sets), and
`frame {name source_world orientation xy_right_handed ?calibration_source ...?}`.
Every touching constraint/group must be closed over; `strict` reports its missing
IDs, `closure` adds their exact definitions. Saved source groups cannot be removed
or changed by hints. Canonical local formulas and captured Session values use the
existing parameter evaluator. Unsupported references fail validation.

Import options are `target_unit`, `transform`, `payload_command`, `cancel_command`.
All source X/Y units must be declared, equal and convertible through Unit Registry.
Mixed source units require prior owner normalization. Unit rescale goes through
Native's existing operation, including dimension values/tolerances. Expression-driven
constraints require owner parameter normalization before changing units; otherwise
conversion is rejected instead of silently changing formula meaning. Named parameters
retain their declared units and scope; they are not destination owner capabilities.

A transform requires `matrix {a b c d tx ty}`, `source_frame`, `target_frame`,
`calibration_source` and `unit` matching the destination. Only a finite, rigid,
orientation-preserving placement is supported. Non-identity frame placement with
constraints is currently rejected. A calibration label is an explicit caller
attestation, not independent metrological certification. Actual raster calibration
uses Native2D `image_calibrate` / `image_map`; raw pixels never become lengths by
inference. Imported primitives receive a readable default blue presentation;
scientific controls remain exact. Source appearance/chrome is not editing authority.

## Commit, cancellation and owner adaptation

`payload_command beforeDocument importReceipt` is a trusted local command prefix,
not serialized executable content. It prepares a compatible payload **without
committing or modifying the source/destination**. CORE verifies both authorities
again and checkpoints the staged scene exactly once. Failure/cancellation disposes
that entire scene and leaves the existing document and live scenes unchanged.
`cancel_command` is polled between object/constraint operations and before commit;
a true return gives `{GX GEOMETRY EXCHANGE CANCELLED}`. It may service its own UI
cancellation flag; import itself is a bounded synchronous operation.

For an explicitly created `core.geometry_exchange` document, omitting the payload
adapter appends a copy receipt to `payload.exchanges`. Other document formats require
an owner payload adapter. The new scene contains the imported selection; a caller
restores/combines its complete document through its own model adapter. After a
successful revision change, old document scene handles are stale by the established
Native API. Close obsolete scenes and rebind views; do not treat them as another
scientific authority. Persistence contains local IDs, exact controls, relations,
groups, declared units and source lineage, not runtime handles.

## Example

```tcl
set descriptor [::GX::geometryExchangeExport $source {} {line1 bezier1} \
    {dependencies closure}]
::GX::geometryExchangeInspect $descriptor
set result [::GX::geometryExchangeImport $target $descriptor {target_unit mm}]
set lineCopy [dict get $result source_to_destination line1]
# Target owner edits and checkpoints its own model using its existing permissions.
set reopened [::GX::geometryExchangeRestore $target [dict get $result sketch] \
    [dict get $result groups]]
```

## Supported boundary

Same active Session/lifetime only; source revision must still be current at import.
4 MiB descriptor, 32 MiB document payload (checked before reading), 1024 objects, 4096 constraints, 1024 parameters. A descriptor
checksum provides integrity, not cross-installation authenticity. There is no
inter-Session exchange, remap-to-existing-target policy, nested group language,
unbounded streaming, general constraint-frame transformation
or new solver. These return explicit errors or require an owner adapter, never a
claimed lossless approximation. Export/import descriptors are dictionary data,
never `source`/`eval`; unknown executable/path fields are not part of the contract.

Focused fixtures: `validation/core_foundation_dev075/geometry.tcl` and the real
Workbench→independent SEM-like host in `multiview.tcl`.

## Dev088 bounded resource transport

`::GX::geometryExchangeExportResource document selectedIds ?options?` captures the
saved owner snapshot and writes a managed `gxtxt.geometry.exchange.v1` resource in
1 MiB chunks. Callers supply identities, not a giant inline definition dictionary.
`geometryExchangeImportResource destination resource ?options?` verifies resource
SHA/owner, reads bounded chunks with cancellation, and invokes the existing atomic
owner import. Existing dependency/unit/transform/owner callbacks remain authoritative.

Both inline and resource routes now allow16,384 whole retained objects (and groups),
64 MiB serialized transport; the final destination Document remains capped at32 MiB.
Native construction is still a bounded in-memory snapshot, not unbounded streaming.
Source revision/generation/SHA and same-Session lifetime must match until commit.
Committed copies restore without consulting their source; whole-Session portability
uses Session Portable. Cross-Session *live exchange descriptors* remain unsupported.
Logical IDs, definitions, units, attributes, constraints, source identity and exactness
are preserved under the existing supported conversion policy. Document origin is in
the source receipt; copy lineage records source origin and receiving installation.
The independent1,100-object fixture tests successful transport, cancel, stale source
and unchanged destination after both failures. No new public API family was created.
