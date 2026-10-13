# GX-TXT Interactive Document API v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT 0.9.7.78

Interactive Document API v1 stores authoritative, module-owned UTF-8 scientific
state scoped to the currently open GX-TXT Session. It is intended for
interactive tools whose user-created document is not adequately represented by
Dataset metadata, Viewer presentation state, runtime cache or a render cache.

Examples include calibrated curve digitizations, durable scientific annotations
and other interactive documents where closing the UI must not discard the
scientific work.

## Authority model

Keep this distinction explicit:

```text
authoritative Interactive Document
        ↓
derived viewer/UI/runtime/cache
```

Deleting or rebuilding runtime/cache must not delete the Interactive Document.

The host-only `interactiveDocumentLifecycleSubscribe callback ?owner_window?
?document_id?` and `interactiveDocumentLifecycleUnsubscribe token` provide
committed owner-invalidation notifications. Delete receipts include the logical
Document ID, owner generation and Session lifetime. Delivery occurs at idle,
outside active Native callback/render transactions. A bounded 250 ms registry
watch also detects committed deletion by a Script Workspace child, replaced
owners and Session lifetime changes for live subscribed views. Widget owners
are weak references; subscriptions disappear when their views close.

Curve Workbench and 3D Workbench subscribe their owned views. Invalidation cancels
queued selection/gestures, waits for active cooperative operations to release
their owned state, closes the exact Native scene/renderer and removes observers
without writing the deleted or replacement Document. Normal Curve Workbench close
also releases retained Source tokens. Lifecycle errors report that deletion was
already committed rather than implying that the scientific owner survived.

The common **Interactive Documents** manager is available from both Workbenches.
It lists logical IDs, owners, revisions and formats, and offers explicit reviewed
deletion with Yes/No confirmation. A changed owner/revision or Session lifetime
invalidates the captured review and requires Refresh. Source Datasets and
published results remain intact. Published/external provenance references retain
their required resources under a read-only retired owner; unreferenced owned
resources and the deleted owner's recovery journal are removed.
Viewer scene/layer state remains a separate presentation mechanism.

## Scope and ownership

Every document belongs to:

- the current Session;
- a stable document ID such as `idoc_0001`;
- `module_id`;
- `provider_id`;
- an application-defined `format`;
- an application-defined `format_version`.

A Session must be open for every operation. Documents in another Session are
not visible through the current Session's API calls.

The public API does not expose internal filesystem paths. CORE may use internal
Session files to implement persistence, but modules must treat the returned
metadata and payload as the complete public contract.

Documents have a persistent opaque `generation` and automatic IDs use a durable
allocation counter. Resource references from a deleted generation cannot revive
when an explicit ID is reused. `interactiveDocumentSessionToken` identifies the
current process's Session lifetime: repeated assignment of the same live Session
preserves it, while leaving/returning or replacing the directory changes it.
Curve Source, Dataset Transform and resource handles use this common scope.

Deletion validates resource dependencies and cleanup targets before committing.
It removes the document payload, closes its active resource handles and removes
unreferenced blobs. Blobs referenced by committed Dataset metadata or other
documents remain readable under a retired resource owner, which is not listed as
an Interactive Document and cannot accept writes. Public resource collection can
remove released retired blobs and removes the owner after its last reference.
A failed registry commit rolls back retirement without discarding live handles.

## Public Tcl API

### Create

```tcl
::GX::interactiveDocumentCreate module_id provider_id format format_version payload ?document_id?
```

Creates one UTF-8 document. When `document_id` is omitted, CORE allocates the
next stable Session-local identity. Supplying an existing ID is an error.

Returns public metadata containing:

```text
id
module_id
provider_id
format
format_version
sha256
created_at
updated_at
```

### Exists

```tcl
::GX::interactiveDocumentExists document_id
```

Returns `1` if the document exists in the current Session, otherwise `0`.

### List

```tcl
::GX::interactiveDocumentList
::GX::interactiveDocumentList module_id provider_id
```

Lists public metadata. Filtering requires both owner fields. Internal storage
identities are never returned.

### Read

```tcl
::GX::interactiveDocumentRead document_id
```

Returns public metadata plus `payload`. CORE verifies the stored SHA-256 before
returning the payload. A missing or modified payload produces an explicit
error; it is never converted into an empty valid-looking document.

### Update

```tcl
::GX::interactiveDocumentUpdate document_id payload ?format? ?format_version?
```

Updates the authoritative payload while preserving document identity and
creation metadata. Optional non-empty format/version arguments replace the
corresponding metadata. CORE updates the payload SHA-256 and timestamp.

### Delete

```tcl
::GX::interactiveDocumentDelete document_id
```

Explicitly removes the document and its CORE-managed payload from the current
Session. Runtime reset does not call this operation.

### Opaque live-Session token

```tcl
::GX::interactiveDocumentSessionToken
```

Returns an opaque token for the currently open Session. It exists for adapters
that keep an external UI process alive and need to reject writes after the GX
process switches Sessions. The token is not scientific state and must not be
persisted as a document identity. It intentionally does not reveal the Session
path.

## UTF-8 and integrity

Payloads are UTF-8 structured text chosen by the owning module (for example
JSON). CORE stores and verifies a SHA-256 digest. The payload schema itself is
owned and versioned by the module through `format` and `format_version`.

CORE validates registry structure and reports explicit diagnostics for:

- invalid document/owner identities;
- unsupported registry version;
- missing registry fields;
- missing payload;
- invalid or mismatching SHA-256;
- unreadable/corrupt state.

An old Session with no Interactive Document registry is valid and simply has an
empty document list.

## Session persistence and isolation

Documents live with the Session and therefore survive normal Save/close/reopen
and GX-TXT restart. They do not depend on a running Viewer backend. Two Sessions
with identically named providers have independent document registries and
payloads.

Modules should store references and provenance rather than duplicating large
source data. For example an interactive image tool can store Dataset/artifact
identity and SHA-256 while leaving the original source under its established
GX-TXT ownership.

## Runtime and Module Reset

Interactive Documents are authoritative user state. Module Reset or other
runtime/cache cleanup may close/rebuild derived adapters and render state but
must not remove these documents. Deletion is explicit through
`interactiveDocumentDelete`.

## Viewer integration pattern

A Viewer Provider can combine both public APIs:

```text
Viewers discovery
→ no desktop activation
→ Open/Rerender
→ Viewer Provider activation_api
→ module public API activation
→ backend registration
→ Interactive Document read/create/update
→ backend-owned UI
```

The UI may use temporary bridge files or process IPC as runtime implementation
details, but authoritative scientific state must be committed through this API.

## Compatibility

Interactive Document API v1 is additive. Existing Sessions require no
migration. Existing Viewer scenes, Dataset resources and module runtime caches
keep their previous semantics.
