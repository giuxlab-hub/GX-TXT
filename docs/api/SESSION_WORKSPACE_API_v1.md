# SESSION_WORKSPACE_API_v1

SPDX-License-Identifier: GPL-3.0-or-later

Session Workspace is the provider and GUI facade over
[NATIVE_WORKSPACE_API_v1](NATIVE_WORKSPACE_API_v1.md). C++ owns the typed model,
identity, indexed query, revision checks, transactions and persistence. A Tcl
`payload` returned to an existing host is a temporary provider projection. It
is never a second saved model or an opaque SQLite payload.

## Providers and state

Installed `[workspaces]` declarations must specify
`native_contract=NATIVE_WORKSPACE_API_v1`, an in-module declaration entrypoint, owner,
schema/version, explicit native encoder/decoder, required field kinds and the
existing semantic validator. Admission checks the contract before loading the
provider. Missing, disabled, incompatible and obsolete providers cannot read or
write scientific bodies. Metadata recognition and confirmed safe deletion remain
available. Old Workspace conversion, promotion and fallback writers are denied.
Scientific Documents which are separate geometry, result or immutable source
owners retain their own APIs; declaring their formats does not make them
Workspaces. Provider declarations identify each supported owner and schema.

A state uses explicit object/array/scalar/resource kinds. Labels, formulas, JSON
text fields and source signatures remain text. Numeric annotations, ordered
fields, signed zero and frozen scientific receipts retain their declared
contracts. Large arrays and geometry remain in managed resources. State,
properties and provenance together are bounded by the native 16 MiB contract.

## Host operations

| Tcl operation | Contract |
|---|---|
| `sessionWorkspaceCreate provider name payload ?async? ?typedProperties?` | Validate the provider projection and create a new native identity. |
| `sessionWorkspaceGet id` | Explicit Open/read, returning the existing provider projection and typed properties. |
| `sessionWorkspaceMetadata id` | Metadata only, including compatibility/native flags. |
| `sessionWorkspaceList` | Session metadata inventory; no scientific-body reads. |
| `sessionWorkspaceUpdate id payload expected ?async? ?typedProperties?` | Held `id`, `generation`, `revision` required; stale updates fail. |
| `sessionWorkspaceRename id name` | Metadata transaction, stable identity and unique name. |
| `sessionWorkspaceDelete id confirmed expected` | Explicit confirmation and held identity, managed-resource-safe lifecycle. |
| `nativeWorkspaceSaveAs id name` | New identity, same exact state/properties/provenance, notes and all named archives. |
| `sessionWorkspacePreviewSet id reference` | Verified typed resource property; returns metadata. |
| `noteDocumentRead/Write` | Native notes transaction; existing editor receipt checks remain. |
| `sessionWorkspaceExport id` | New managed native Workspace ZIP resource. |
| `sessionWorkspaceImport resource ?name?` | Validated native package, new identity; never overwrites an existing Workspace. |
| `managedResourceCopyTree id typedGraph` | Explicit resource-node adoption; other text and structure remain unchanged. |

Create/Save may accept asynchronously. An accepted revision is not durable until
its flush receipt says so. Close, Session leave and application exit review dirty
hosts, preserve everything on Cancel, and drain Workspace and native History writers before
closing. Save/Discard/Cancel callbacks execute in the original GUI thread.
Notes/name/archive notifications rebase only matching held identity stamps.

## Script Bridge

Python and Octave can use the registered `NATIVE_WORKSPACE_API_v1` typed-node
contract. Objects carry field maps, arrays carry ordered node lists, scalars
carry explicit kinds and original spellings. Save takes the held identity;
Delete takes confirmation and the held identity. Semantic provider validation
precedes Create/Save acceptance. The existing Session bridge retains provider
UTF-8 projections for existing callers, but its Update and Delete also require
held receipts and use the same native authority. Its serialized Tcl resource
copy operation is retired; use the typed native operation.

## Save As, resources and portability

Save As copies native graph nodes transactionally without serializing scientific
state through Tcl. Managed blob identities remain immutable: their original
owner/generation/hash/size are retained. The new Workspace records its exact
source receipt and ancestor lineage. Archives retain their original graphs and
hashes; lineage permits their explicit Open in the new Workspace. Source Delete
and GC preserve every resource still referenced by the copy or its archives.

Single-Workspace packages contain `workspace.native`, an explicit native binary
typed capsule, a file SHA-256 manifest and immutable managed blobs. C++ verifies
native grammar, node/depth/byte bounds, graphs, content hashes, archives and
lineage. Capsules permit up to 256 archives within a 256 MiB aggregate native
file; packages permit up to 10,000 files and 2 GiB of uncompressed bytes.
Python verifies ZIP paths, duplicates, member types, size limits and
byte hashes; it never parses scientific state. Import verifies the installed
provider and its semantic projection, resource generations and existing byte
collisions before native publication. Missing immutable resource owners become
native tombstones in the same transaction as the new Workspace, archives,
lineage and retention pins. Failed import exposes no partial Workspace; newly
copied unreferenced immutable blobs may remain for explicit collection. Old Tcl
payload ZIPs are unsupported. Packages are integrity receipts, not authentication.

Whole-Session portable export drains/checkpoints the native database and History
owners and holds owner locks while copying. WAL/SHM/lock files are transient;
a direct helper cannot export an undrained WAL. Foreign active writers cause a
clear refusal. Import preserves the database/resources and uses the existing
History transport to rebind physical Session ownership without altering scientific
steps or auxiliary state. Experiment Duplicate retains its distinct preparation
policy and intentionally omits scientific Workspaces/results.

## GUI adapter and named History

`sessionWorkspaceViewerMenu menu provider callbacks parent` attaches the shared
New/Open/Save/Save As/Rename/Close/Delete/Notes/Preview/Import/Export manager.
Required prefixes are `current`, `save`, `close`, `open`; optional prefixes are
`dirty`, `prepare`, `discard`, `review`, `rename`, `metadata_advanced`, `new`.
The host stores weak widgets and Session/window incarnation tokens only.
Naming forms and selected rows retain generation/revision guards. New opens an
unsaved provider draft; only its established Save path allocates a Workspace.
The optional `new` prefix presents provider-specific creation fields after common
Host admission, replacing the generic naming form. Its existing owner must retain
dirty-state review and Cancel behavior before closing or replacing a live view.
It owns presentation only; native identity and persistence stay with Save.

`sessionWorkspaceBuild`, `sessionWorkspaceDialog` and
`sessionWorkspaceViewerAction` share that guarded host. `errorMode=propagate`
returns the original Tcl error for structured clients. A Viewer-scoped manager
restricts provider selection/import. `sessionWorkspaceViewerTitle` projects the
native name and unsaved status without owning state.

History menus offer Save History As and Named History. The latter
browses/inspects complete workflows and exposes Restore, Rename and confirmed
Delete. Active Clear leaves archives intact. Restore reviews dirty work, checks
provider/schema/lineage/channel and scientific source/resource identities, then
uses the existing native History replace/flush operation. A native typed coordination
intent is durable before History replacement; its committed phase is atomic with
the target Workspace transaction. Recovery restores old History for a prepared
intent or target History for a committed intent before normal native writes.
This adds no History engine or ordinary-Save archive replay.
