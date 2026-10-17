# SESSION_WORKSPACE_API_v1

A workspace is a provider-registered Interactive Document. CORE owns its ID,
generation/revision, unique user-visible name, transactions and managed paths.
The existing Document registry supplies listing; `workspace_metadata` in its
payload carries name, preview and note associations. No private viewer registry
or second identity/path authority exists. Legacy Curve Workbench documents are
listed and promoted in place without changing ID or geometry.

`gxtxt_api_call("SESSION_WORKSPACE_API_v1", operation, arguments)` works in Python
and Octave through the common registration/transport. Arguments are positional:

| Operation | Arguments | Result |
|---|---|---|
| list | none | workspace metadata records |
| get / validate | workspace_id | metadata plus `payload_utf8` / validation receipt |
| create | provider_id, name, payload_utf8 | new workspace receipt |
| update | workspace_id, payload_utf8 | updated workspace; associations retained |
| rename | workspace_id, name | same stable identity and new unique name |
| delete | workspace_id | existing Document lifecycle deletion, note cleanup |
| note_read / note_write | workspace_id / workspace_id, text | UTF-8 note receipt |
| preview_set | workspace_id, resource | same-owner verified image receipt association |
| export | workspace_id | managed `gxtxt.workspace.zip` resource |
| import | managed_package_resource, new_name | newly committed workspace receipt |
| resource_copy_tree | workspace_id, payload_utf8 | serialized payload with all nested resources copied to this owner |

The provider payload is serialized UTF-8 Tcl dictionary data, never executable
code. Curve Workbench schema is `gxtxt.curve_workbench.workspace` version `2.0`;
its version-2 logical payload retains the published schema. Payloads are bounded
to 16 MiB; large scientific values use managed resources. Providers register
schema, version, ordinary validation, optional deep validation and GUI opening
callbacks. These host callbacks and GUI opening are intentionally not bridged.

Portable packaging uses the existing Portable Resource format/integrity helper.
It includes provider identity, payload, recursively owned raster/geometry
resources, preview and UTF-8 note. Import checks provider/schema, names and every
resource/note hash before committing. Resources are remapped to a new Document
owner/generation; nested resource metadata is remapped too. Private staging
Documents are not exposed as workspaces and are removed if import fails. ID/name
collisions never replace existing data; choose an explicit new name.

Session → Workspaces lists every registered provider, showing name/type/provider
and preview. Open dispatches to the provider. Export/import file dialogs are
trusted host UI; scripts use the same package service with managed receipts.
When no Session is open, the Session tab shows an empty Workspace area. Its
asynchronous view refresh does not call the Session-required Interactive
Document API until a Session exists.

See [MANAGED_RESOURCE_API_v1](MANAGED_RESOURCE_API_v1.md) and
[NOTE_DOCUMENT_API_v1](NOTE_DOCUMENT_API_v1.md). Genuine Python/Octave fixtures:
`validation/dev056/bridge.py`, `bridge.m`, executed by `bridge.tcl`.

<a id="integrated-dev-065-extension"></a>
## Parameters and retained networks

See [CORE Parameter Service](CORE_PARAMETER_SERVICE_v1.md) for automatic Workspace contexts and descriptor Workspace actions, and [Native2D Geometry API](NATIVE_2D_GEOMETRY_API_v1.md) for exact topology/reference/constraint semantics.

<a id="lightweight-provider-discovery-and-viewer-menus-dev094"></a>
## Lightweight provider discovery and viewer menus

Installed modules may declare `[workspaces] ids=provider_id` and
`[workspace.provider_id] entrypoint=api/workspace_provider.tcl`, `type`, `schema`,
`version`, `validate` and `open`. `sessionWorkspaceProviderDiscover module_id`
loads that module-owned schema contribution and calls the existing provider
registry; it does not load a numerical engine or open a Viewer. The entrypoint
must remain inside the installed module root. Disabled/missing providers are
not listed and cannot open; their documents remain untouched and available
again after enabling/installing the provider.

Curve Viewer and Dataset Curve Fit register their existing schema/version1.0
and2.0 documents, respectively. Legacy compatible documents are listed and
promotable with the same ID. Both accept `workspace_id=new` plus `workspace_name`,
or an exact existing Workspace ID. Explicit opening never chooses by Dataset.
One top-level switches by saving and closing the previous document; sources and
accepted fits cannot merge across Workspaces. Generation/revision/lifetime
checks reject stale saves. Metadata-only note/name updates are reconciled.

`sessionWorkspaceViewerMenu menu provider callbacks parent` is a generic GUI
adapter in this API. Callback prefixes `current`, `save`, `close`, and `open`
connect a host to New/Open/Save/Duplicate/Rename/Manager/Close/Delete actions.
Duplicate uses the official export/import path to remap managed resources;
Delete confirms and preserves source/published Datasets. Notes, previews and
portable packaging stay with the existing CORE manager and Document/Resource
APIs. No additional registry or private project format is created.
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

<a id="compatible-provider-schema-versions-dev094"></a>
## Compatible provider schema versions

A lightweight descriptor provider may declare `accepted_versions=1.0;2.0`.
Without it, only the existing `version` is accepted. CORE checks format/owner and
the accepted version before invoking the module-owned inert payload validator.
New documents use the provider's current version. Curve Fit advertises existing
v1/v2 compatibility; its authoritative restore suppresses autosave until complete,
and a subsequent save promotes a v1 document to v2 on the same ID.

<a id="shared-os-title-projection-dev096"></a>
## Shared OS title projection

`sessionWorkspaceViewerTitle window base_title current_callback ?draft_callback?`
subscribes a Viewer window to the existing Workspace GUI lifecycle. The current
callback returns its actual Workspace ID. The title retains Viewer type/mode and
shows `Workspace: <authoritative name>` immediately and after Workspace changes,
including Manager rename. A truly unsaved draft is explicitly marked unsaved;
stale Session ownership shows None. Destroy releases the projection. This holds
callbacks and widget paths only; it does not change Document identity, revision,
generation or scientific contents. `sessionWorkspaceViewerTitlesRefresh` supports
immediate host updates during a local transition; normal owner mutations use the
existing idle notification. No provider-specific CORE branches are added.

The Managed Resource API supports typed numeric writes. Scientific
providers can retain large result arrays in their own Workspace payload through
`MANAGED_RESOURCE_API_v1/write_numeric`, then read bounded typed pages after the
producing Job exits. Document identity/generation and portable-package resource
collection are unchanged; the provider retains the returned reference explicitly.


Resource rebinding on package import preserves every untouched subtree
exactly. Parsing a scientific label, formula or statistical receipt as Tcl data
does not authorize reserialization. Only resource references and their containing
structures change when ownership is assigned to the imported Document. This
preserves CORE interpretation validation and frozen model-state hashes.

`::GX::managedResourceCopyTree document payload` uses the same recursive collector
and remapper as portable Workspaces. It copies each content hash once through
managed bounded readers/writers, verifies unchanged bytes and preserves untouched
text exactly. The caller commits the returned payload; uncommitted copies remain
collectible managed resources. The existing owner and its payload are unchanged.

The Script binding uses `sessionWorkspaceResourceCopyTreeUtf8` to encode the
result before it crosses Tcl/Python. This preserves original text even when Tcl
also caches a list representation; Python tuple conversion must not normalize
scientific text. The public Script result is an ordinary Unicode string.
