# Native Workspace API v1

## Plot v4 presentation snapshots (P031)

The existing typed `plot_spec` adapter accepts the optional
`GXTXT_NATIVE_GRAPH_PRESENTATION_v1` projection returned by Plot v4 `loadSpec`.
Normal Viewer binding, Workspace Save, native readback and cold restoration retain
the complete projection, including explicit output dimensions, captions, units,
Level Scale and per-panel overrides. A missing projection keeps the existing
PlotSpec v2 contract unchanged. Restoring a saved projection does not replace
scientific payloads or write global/module plotting defaults.

The projection's graphics, legend, layout and plot configuration bags contain
literal source settings, encoded as explicit text fields. Empty, `auto`,
`inherit`, numeric-looking and list-looking settings are not guessed from their
Tcl representation or cache type. Axes and panel overrides retain nested declared
Level Scale records and panel-name arrays as structured values. Scientific
samples remain in their existing Dataset authorities and typed source bindings.
Wrong projection schemas, unknown root fields, forged nested kinds and invalid
Level Scale declarations refuse before a native Workspace write. The same
existing native C++ store, generation/revision checks and Viewer codecs apply;
no additional Workspace engine or renderer is introduced.

The C++ entry point is `core/workspace/workspace_v1.hpp`, namespace
`gx::workspace::v1`. `Store` owns one Session database, its native object model,
name/provider/owner indexes, validation and persistence worker. A `Value` has an
explicit `Kind`: null, text, boolean, signed integer, finite real, object, array
or managed resource reference. Text is never implicitly parsed. Scientific
arrays and geometry should use managed resource references; the existing
resource owner retains the bytes and lifecycle.

`core/workspace/viewer_workspace_v1.hpp` supplies the host-injected
`ViewerWorkspace` facade. With no hooks its typed state/properties are the
editor model. Optional `ViewerHooks` capture, validate, restore and committed
callbacks execute on the caller's owning thread. Hooked editors signal draft
edits with `changed()`. Open and Close take an explicit `DirtyDecision`; Cancel
retains the draft and identity. Save can accept asynchronously or wait for
durability. Hosts must flush before discarding their service/lifecycle context.

Register a `Schema` with provider, owner, schema ID/version and required typed
state fields. Registering a different contract over an existing provider fails.
Creation requires a registered schema. Save checks the complete expected
`Identity` (ID, generation and accepted revision), validates the typed graph,
and atomically accepts an immutable native snapshot. Concurrent stale writes
raise `Error` with code `CONFLICT`. An unchanged Save retains its revision.

`create`, `save`, `rename`, `notes` and `erase` return `Receipt`. `accepted`
means the native RAM state owns the change; `pending` means its revision is
not yet durable. `durable_revision` advances only after a successful SQLite
transaction with synchronous FULL. `status` reads metadata without reading or
hashing state. `flush` waits for the captured accepted revision; `flush_all`
waits for all pending work. A timeout retains accepted state and does not
report durable success. A storage failure retains accepted state, sets failure
status and refuses further writes. Explicit `close` drains accepted work,
checkpoints the WAL and releases the exclusive Session writer lock; it throws
on failure. Destruction drains the worker but cannot report errors to callers,
so lifecycle owners must call `close` explicitly.

`query` returns metadata only, ordered by name with optional provider, owner,
name prefix, offset and bounded limit. `get` returns a typed native snapshot.
`metadata` avoids copying state. `rename` changes only the name; `notes` changes
only bounded UTF-8 note text. `erase` requires an explicit true confirmation
and the exact expected identity. Resource deletion is a coordinated lifecycle
responsibility of the existing managed resource authority; native deletion
does not blindly remove scientific blobs.

The Session database contract is `user_version=1`: `workspaces` owns identity,
schema, name and notes; `values_v1` stores individual typed graph nodes with
parent, key/order and scalar columns. No field stores an opaque Tcl payload.
The worker writes changed nodes only, inside the same metadata transaction.
SQLite WAL recovery owns interrupted transaction handling. Opening rejects an
unknown database contract; it performs no legacy Workspace conversion.

Metadata `sha256` identifies the native `GXWorkspaceNative.v1` typed content
encoding, including schema, state, properties, provenance and optional object
field ordering. It does not identify a Tcl string serialization. Metadata-only
Rename/notes operations advance the revision without changing this content
digest. Typed content is hashed at a changed acceptance boundary and checked on
explicit cold Open; metadata query/status never hashes state. Cold bodies and
named archive graphs are loaded on demand by the SQLite owning worker. A corrupt
body rejects that Open without preventing metadata recognition or access to
other valid objects.

The owning-thread Tcl transport is `::GX::workspaceNative`, supplied by
`core/workspace/libgxtxt_workspace.so`. It is an adapter to this native domain,
not a callback worker. Operations:

| Operation | Arguments after operation | Result |
|---|---|---|
| open | database_path | opaque store handle |
| register | store provider owner schema version required_fields | registered |
| create | store provider name typed_state typed_properties typed_provenance | receipt |
| metadata / get | store workspace_id | metadata / typed snapshot |
| properties | store workspace_id | typed properties, without copying scientific state to Tcl |
| notes_get | store workspace_id | note text without copying scientific state |
| query | store ?provider owner name_prefix offset limit? | metadata list |
| save | store id generation revision typed_state typed_properties | receipt |
| save_properties | store id generation revision typed_properties | receipt; native scientific state preserved |
| rename / notes | store id generation revision text | receipt |
| delete | store id generation revision confirmed | receipt |
| status / flush | store id | receipt |
| flush_all / close | store | durable / closed |
| resource_owner_generation | store id | retained managed owner generation |
| register_resource_owner | store id generation | registered scientific identity |
| retired_owner_generation | store id | native retired generation; scientific registrations excluded |
| retained_references | store ?exclude_workspace? | typed retained references after a durable barrier |
| json_decode / json_encode / json_encode_lexical | explicit_JSON / typed_value (no store argument) | typed graph / JSON client transport |
| history_save | store id generation revision name typed_record typed_auxiliary typed_context | receipt with archive_id |
| history_list / history_get | store id ?archive_id? | typed metadata list / full archive |
| history_rename | store id generation revision archive_id name | receipt |
| history_delete | store id generation revision archive_id confirmed | receipt |

Every transport value is exactly `{kind data}`; objects contain a dictionary of
typed values and arrays contain a list of typed values. Kinds use `null`,
`text`, `bool`, `int`, `real`, `object`, `array`, `resource`. Null data is empty.
A resource contains typed `document_id`, `owner_generation`, `sha256` and
`size_bytes`, plus its other managed descriptor fields. This explicit transport
preserves the distinction between scientific text and structured state.
The Tcl transport retains each declared numeric/boolean scalar's original
spelling as a native scalar annotation alongside its actual integer/real value.
Both are persisted and covered by the content digest. This preserves existing
scientific receipt and P017 snapshot byte contracts (`1` versus `1.0`, for
example) without storing serialized containers. Projection checks that the
annotation still denotes the canonical native scalar. C++ values without an
annotation use their ordinary canonical numeric representation.
Finite real graph nodes retain exact IEEE bits in their otherwise unused
integer column as well as an SQL REAL projection, preserving signed zero.
Recovery checks that the numeric projection agrees with those bits.
Metadata exposes `has_notes` and `has_preview` without copying/decoding the body
through the GUI transport. Store startup loads metadata and archive summaries;
it does not materialize scientific bodies or complete archive graphs. A first
properties request loads and verifies the containing native graph once; later
property reads do not copy scientific state through Tcl. Notes remain bounded
metadata. Name-ordered provider/owner indexes support prefix seeking and stop at
the requested page without sorting all matches. Rename/notes jobs carry only
metadata, and ordinary metadata persistence leaves scientific nodes untouched.
Session note editing uses the native note transaction; a preview is a typed
managed resource property. Neither action writes obsolete Workspace files.

Named archives retain the complete native History record (initial state, operations and
cursor), auxiliary state, context, provenance, source owner and schema identity.
They have separate typed graphs; ordinary state Save never serializes or copies
them. Archive operations advance the Workspace revision in the same transaction.
Deleting/clearing active scientific state does not remove archives. Restore into
the active native History timeline belongs to the coordinated History adapter, which must
validate scientific sources and dirty-state decisions before changing that sole
active engine. This storage API does not implement another active History engine.

The native worker verifies newly retained managed resource descriptors against
stable native owner generations, actual content hashes and byte sizes, then
synchronizes their bytes and managed directories before committing the Workspace.
Retired resource owners retain their native generation after Workspace deletion.
Scientific owners outside this Store register their identity through
`register_resource_owner` on each Store lifetime. The trusted Session adapter
obtains the generation from the existing managed-resource owner or retirement
marker, never from the submitted descriptor alone. Re-registration with another
generation or a conflicting native identity fails. This identity-only admission
does not create a Workspace or copy an external owner's scientific state. The
reference graph retains its declared owner/generation across reopen; the owning
host must re-admit external identities before accepting a new transaction.
Large resource bytes are streamed, never copied into graph records. A failed
resource check leaves the previous durable Workspace untouched and marks the
accepted transaction failed/pending. A later caller must resolve the error;
failure does not certify a durable save.

Resource collection obtains native reference descriptors from state, properties,
provenance and every named archive, including archive auxiliary/context. This
explicit retention boundary drains pending writes before reading compact
`retention_roots`/`retention_pins` indexes; failure aborts collection. Pins commit
atomically with their active or archive graph, include conservative mixed-use
cache/scientific policy, and verify their own digest and source content hash.
They allow collection without opening complete cold archive workflows. A native
pre-index development database fails collection with `RETENTION` until explicit
validated Opens populate each missing derived root; no obsolete Workspace is
converted. It does not copy complete Workspace bodies into Tcl or infer resource
types from ordinary scientific strings. Native retired generation authority also
keeps managed reads valid after direct native owner deletion. The existing
managed-resource collector still protects Dataset, scientific Document and P017
references through their original owners.

`json_decode` is a new-client transport for owners whose existing interfaces
already declare JSON types. It builds native nodes for objects, ordered arrays,
strings, booleans, signed 64-bit integers, finite reals and null. Duplicate keys,
malformed escapes/surrogates, out-of-range scalars and excessive depth/size reject.
JSON strings are never inspected as Tcl. JSON negative integer zero projects as
the equivalent Tcl real spelling `-0.0`, preserving its IEEE sign. JSON output
escapes text and retains typed integer/real distinctions; managed resource kinds
require the explicit typed API rather than losing their identity through JSON.
`json_encode_lexical` additionally preserves valid original numeric JSON
spellings. Curve Digitizer uses the compact UTF-8 projection for its separate
configuration SHA and managed scientific configuration resource; its native
content hash and generation/revision remain distinct. No obsolete Workspace
file is parsed or converted through this transport.

`nativeWorkspaceProperties`, `nativeWorkspaceSetProperties` and
`nativeWorkspaceSetProperty` expose property transactions in the Session adapter.
The Parameter service uses explicit typed definition/binding properties and held
receipts; it no longer rewrites a decoded scientific body through the old Document
writer. Native property mutation still hashes changed native content and persists
through the same worker/transaction authority.

Existing separate desktop clients use the additive weak host transport in
`workspace_external_host_v1.tcl` and `gxtxt_workspace_rpc_v1.py`. Each connection
is bound to its current Session and process incarnation. All UI callbacks execute
in that desktop's original Tk thread; the input thread only queues lines. Session
leave reviews every desktop before disposal, then drains native persistence and
closes the reviewed windows. Cancel preserves the Session and draft. Busy or lost
connections return a bounded error, never implicit approval. These adapters hold
no authoritative saved model or parallel database.

Builder's automatic declarative provider and the public compiled
[Viewer Workspace SDK](VIEWER_WORKSPACE_SDK_v1.md) use this authority. The
remaining direct writers are tracked in `docs/development/DEV111-P024/`.
The Script Bridge exposes `NATIVE_WORKSPACE_API_v1` through
`core/script_bindings/native_workspace.py`, shared by Python and Octave. A node
is `{kind: "text", value: "001"}`, `{kind: "real", value: "-0.0"}`,
`{kind: "object", value: {field: NODE}}`, `{kind: "array", value: [NODE]}`,
or the corresponding resource/null node. Scalar annotations retain original
spellings; text is never decoded as Tcl. Query/Get/properties, checked Save,
Async Save, metadata mutations, explicit Delete, barriers and named archive
storage are exposed. Typed Create/Save pass the installed provider's existing
semantic validation and type-preserving projection before native acceptance.
Save expects held `id`, `generation`, `revision`; asynchronous acceptance is not
reported as durable. Delete uses the resource-safe high-level lifecycle.

`resource_copy_tree` accepts an explicit typed graph and adopts only resource
nodes into the named native owner, recursively including resource metadata.
Every other scalar and ordered collection remains unchanged. The former
serialized-Tcl tree walker is retired. The Fitter-to-Workbench client explicitly
encodes its accepted-result shape before adopting resources.

## Native transport and coordinated Restore

`duplicate(expected, name)` atomically copies all typed graphs, notes, archives
and compact retention pins into a new identity. Immutable resource references
retain their original identities; `lineage(id)` records exact source receipts.

`capsule_export(expected, newPath)`, `capsule_import(path, name)` and
`capsule_inspect(path)` implement bounded native binary graph interchange.
Capsules preserve kinds, scalar annotations, IEEE bits and field order. Native
import validates active/archive hashes and contracts, then publishes the new
Workspace, archive graphs, lineage, retention pins and missing immutable owner
tombstones in one SQLite transaction. The Session facade performs installed
provider semantic/source checks and immutable byte adoption first. ZIP helpers
handle only files, sizes, paths and SHA-256. Old Tcl payload packages are denied.
See [Session Workspace](SESSION_WORKSPACE_API_v1.md) for transport limits and
whole-Session owner-lock/checkpoint behavior.

`transition_prepare(expected, typedIntent)` persists a bounded coordination
intent before replacing active P017 History. `transition_commit(token, expected,
state, properties)` accepts the target Workspace and atomically marks the intent
committed with its durable transaction. `transition_list()` returns verified
pending intents; `transition_finish(token)` removes a resolved intent. Pending
intents prohibit ordinary writes. The owning Tcl adapter uses P017's existing
complete-record replace/flush and recovers prepared intents to the old record,
committed intents to the target record. Session/owner/path/generation guards
precede recovery. These internal coordinator operations are trusted host APIs;
they are not exposed as unrestricted Script Bridge commands. No new History
journal or execution engine is introduced.
