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

## TeX project profile (dev109 integration)

The existing Document family provides a `tex_project` profile through
`core/tcl/interactive_document_tex_v1.tcl`. Its canonical project is a Session
Workspace with schema `gxtxt.tex_project.v1`; source, assets, diagnostics and PDF
bytes use existing managed document resources. This profile is still undergoing
functional integration and does not certify the LaTeX Viewer's installed GUI.

| Public Tcl operation | Arguments | Result or effect |
| --- | --- | --- |
| `interactiveDocumentTeXApiInfo` | none | Profile operations and bounds. |
| `interactiveDocumentTeXRegister` | `module provider viewer` | Registers the existing Workspace provider and normal Viewer open route. |
| `interactiveDocumentTeXCreate` | `provider name` | Creates an empty article Workspace; no generated article or compilation. |
| `interactiveDocumentTeXRead` | `document` | Reads and validates the current Workspace and resource references. |
| `interactiveDocumentTeXReadSource` | `document` | Reads the saved managed source in bounded chunks and verifies exact UTF-8 and its Document ownership; empty for an unsaved article. Missing unrelated old assets do not prevent source reading or repair. |
| `interactiveDocumentTeXSave` | `document source assets ?history={}?` | Saves UTF-8 source and explicit asset references; increments the source revision when either changes. Returns the existing current canonical article Workspace receipt. |
| `interactiveDocumentTeXImportAsset` | `document name path` | Imports one asset as a managed resource; returns its reference for explicit Save. |
| `interactiveDocumentTeXBuild` | `document callback ?engine=pdflatex? ?ownerWindow={}?` | Starts one managed native build, also accepting `xelatex` or `lualatex`; optional live owning Viewer. Immediate return: `{status running request REQUEST source_revision N inputs MANIFEST}`. |
| `interactiveDocumentTeXStatus` | `document` | Reads the current canonical article and projects its real pending build/current PDF state; fields below. |
| `interactiveDocumentTeXCancel` | `document ?expectedGeneration={}?` | No pending request returns `{status idle}`. For a pending request, a supplied generation must match its original owner; returns `{status cancelling|awaiting_completion request REQUEST}`. It does not assert a terminal cancelled build. |
| `interactiveDocumentTeXExport` | `document kind destination ?policy=create_only? ?includeAssets=0?` | Publishes `source` `.tex` or current-revision `pdf` `.pdf`; returns the existing File Publication bundle receipt. |

Build resolves the configured `latexmk`, `pdflatex`, `xelatex` or `lualatex`
runtime through the Runtime owner. The worker stages an immutable source/assets
manifest in an existing Resource Management allocation. Native bibliography and
auxiliary passes supply actual convergence and diagnostics; the worker does not
implement a TeX parser or substitute a PDF generator. Full native transcripts
remain retained diagnostics. Source is limited to16 MiB, explicit assets to4095
and total staged input to256 MiB. Asset names are normalized relative names;
`main.tex` is the source, and `.gxtxt-build` is reserved for generated output.

Build subscribes to the existing Document lifecycle. Session change, deletion or
owner replacement cancels its current managed request. An optional owning Viewer
also cancels on destruction; its dead window receives no completion callback.
The facade unsubscribes and releases its retained allocation on actual completion.
An explicit cancellation is recorded as cancelled, distinct from failure or a
stale result rejected by the source/lifetime checks. No new Job scheduler is
introduced. This lifecycle source still requires actual facade/GUI tests.

With includeAssets1, export includes all associated resources at their exact
relative names beside the selected source/PDF filename, through one existing
File Publication bundle. Nested directories use that owner's explicit
create_parents option. All output paths and replacement/create-only policy are
preflighted together; duplicate destinations or any writer failure cannot leave
a partial file bundle. Original managed source/assets are never moved or altered.

Native invocation disables shell escape. Lua retains `--nosocket`; it does not
use the `--safer` flag rejected by the installed standard font loader. Generated
font caches live inside the same managed build output. Input access follows TeX
Live's ordinary `openin_any=a` policy so the native font loader can read installed
Unicode tables through kpathsea; output retains `openout_any=p` and the managed
`TEXMFOUTPUT`. Source/assets are independently SHA-checked before and after the
build. These checks attest the staged inputs; they do not claim that a native
TeX distribution never reads its own package files.

Completion must still match the original Session lifetime, Workspace generation,
source revision and complete input manifest. A stale completion is rejected
without replacing the current source. An unsuccessful build retains diagnostics
and the prior good PDF, while export requires a good PDF matching the current
source/assets revision. Export uses File Publication's normal destination policy.
Building does not publish a scientific Dataset implicitly.

Native BibTeX runs from the existing managed output directory with the actual
auxiliary basename; BIBINPUTS/BSTINPUTS retain the staged project root and native
distribution defaults. Subsequent TeX passes restore the staged source working
directory. Each process receipt records its actual working directory. Native
`Missing character:` lines remain warnings without guessed file/line links.
Use an engine-appropriate preamble/font for Unicode; a completed PDF with a
missing-glyph warning does not establish faithful text rendering.

`interactiveDocumentTeXStatus document` projects the existing pending request,
saved source revision and PDF state (`unbuilt`, `stale`, `current` or
`unavailable`). `interactiveDocumentTeXCancel document ?expectedGeneration?`
permits cancellation after source edits but rejects a different Document
generation. No second Job store is introduced. API discovery now includes this
Interactive Document owner and its existing TeX profile/manual through the normal
CORE catalog. Shared Builder integration is described in
[GUI Host](VIEWER_GUI_HOST_API_v1.md#declared-tex-article-form-dev109).

Status always includes `status` (`idle`, or `running`/`cancelling` for its actual
pending request), integer `source_revision`, `last_build` and `pdf_status`.
A retained good PDF adds `compiled_source_revision`; invalid resources add
`pdf_message` and `pdf_status unavailable`. A PDF resource owned by another
Workspace is unavailable even when its source revision and input hashes match.
A live request additionally reports `request`,
`build_source_revision` and `owner_generation`, checked against the original
Session token and current Document generation. PDF states are `unbuilt`, `stale`,
`current` or `unavailable`; a ready old PDF is not a current-source export permit.
Revision/generation values are identities/counters, not times or scientific
units. Source/asset limits are byte counts; native diagnostic lines are one-based.

These TeX-profile entrypoints are trusted Tcl host contracts in the existing
Interactive Document family. No Python/Octave TeX-profile binding or generic C++
Document invocation is registered. Restricted C++ uses the specific declared
GUI Host `tex_command` plan; it does not receive canonical article bytes or
resource paths through this method. API discovery exposes the profile beneath
`INTERACTIVE_DOCUMENT_API_v1` and points to this existing manual; it is not a new
API family or proof of full installed editor acceptance.

### Declared schema transitions and duplication policy (dev109)

An actual format/version change through `interactiveDocumentUpdate` refreshes
an automatically derived registration policy only when the saved receipt
exactly matches the prior owner/schema/generation and derived classification.
This covers normal Workspace import from its temporary staging schema into
the final registered schema. Explicit or unproved overrides require an
owner-reviewed transition and are refused before writing the payload.
Same-schema updates retain the policy; an unchanged payload remains a no-op.
Generation and original creation provenance remain unchanged. Existing older
metadata is not retrospectively rewritten. This correction does not invent
source-document lineage for historical duplicates.
