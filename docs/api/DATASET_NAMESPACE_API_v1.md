# Dataset Namespace API v1

Organizational namespaces group canonical Datasets within a Session. They are
not filesystem paths, Dataset IDs or separate stores. CORE enforces module write
placement while allowing reads across namespaces.
The stable Dataset ID and existing Dataset Publication/Metadata/Catalog APIs
remain authoritative.

`datasetNamespaceNormalize value` trims surrounding whitespace and empty slash
components, and returns1–32 slash-separated components. Components contain
letters/digits, underscores, hyphens and dots; `.` and `..` are forbidden.
The maximum total length is512 characters. Case is preserved and significant.

Tcl functions in `::GX`:

- `datasetNamespaceGet session datasetId`: explicit namespace, or the Session's
  current namespace when no private field exists. Old Datasets are not rewritten.
- `datasetNamespaceSet session datasetId namespace`: user/admin host operation;
  writes only `_gxtxt.framework.dataset_namespace` in the existing Dataset
  Metadata resource. ID, payload, schema, source bindings and provenance remain.
- `datasetNamespaceCurrentGet ?session?`: current namespace; default `current`.
- `datasetNamespaceCurrentSet session namespace`: user/admin host operation changing the open Session's
  current namespace through Session Persistence. Writes to another Session are
  rejected. Missing-field Dataset display follows this current value.
- `datasetNamespaceCreate session namespace`: user/admin host operation creating
  an empty namespace through the existing Session Manifest. Existing namespaces
  are idempotent; no Dataset or alternate namespace registry is created.
- `datasetNamespaceList ?session?`: occupied namespaces, current namespace and
  explicitly created empty namespaces, and their ancestors; no parallel
  namespace catalog is maintained.
- `datasetNamespaceForModule moduleId`: assigned `module/<moduleId>`, with
  reversible UTF-8 hex fallback for an identity requiring encoding.

The current namespace and explicit empty namespaces persist in the existing
Session Manifest under `[dataset_organization] current_namespace`,
`namespace_count` and `[dataset_namespace.N] name`. Catalog snapshots expose
`current_namespace` and each Dataset's `namespace`. Both Dataset moves and
current-namespace changes notify existing catalog subscribers; empty namespace
creation also notifies browser subscribers.

Publication v2 series/writers and file publication automatically use the module's
assigned namespace. A caller-supplied `dataset_namespace` is rejected, including
one matching the assignment: modules do not choose output placement. A module
cannot replace an output which the user has moved outside its assigned namespace.
Streaming writers recheck placement before finalization. Old outputs without an
explicit namespace remain replaceable by their recorded producer and acquire the
assigned namespace on publication. Namespace metadata participates in publication
rollback even when the caller supplied no ordinary metadata.

Host imports through legacy acquisition registration pin the Session's current
namespace when first committed. Later current-namespace changes leave that import
in place. Existing Datasets with no namespace continue to follow the current
namespace for display. Module publication, including publication by an acquisition
module, always uses its assigned module namespace.

Python/Octave use `DATASET_NAMESPACE_API_v1` operations `get`, `list`,
`current_get`, and `module_default`. Arguments follow the Tcl
operations with the Session supplied by the trusted Bridge host. Module identity
comes from runtime context. There is no caller-supplied owner override or namespace
mutation operation. `create`, `set` and `current_set` are intentionally
host-only user/admin operations; module scripts cannot choose output placement.
User/admin namespace changes are exposed in the Dataset browser and manager.

The Dataset browser is a catalog projection. Its row highlight is only a browse
state. The small row glyph or explicit context-menu action activates a Dataset
through the existing inspection choice; row clicks and context-menu opening do
not. Preview's historical choice variable is an alias of that choice, not a
second Dataset selection authority. Namespace and Dataset context menus create
empty namespaces and move Datasets. The pictographic manager presents hierarchy,
membership, current namespace, move and drag/drop using these same API calls.
Ordinary Metadata UI/text export hides all reserved private fields.

Portable Dataset ZIP import preserves private module fields but assigns the target
Session current namespace. User/admin move/current/import operations reject a
bound module context. Ordinary metadata, schema, notes, rename and deletion also
enforce module placement when invoked from a bound Tcl module context. Host UI
operations remain user/admin actions. In-process trusted Tcl is not an OS sandbox.

## dev071 compatibility and migration

Missing/empty organizational metadata has the deterministic `base` fallback,
independent of Current. A legacy leading `current` path component projects to
`base` without a read-time source rewrite. New registrations with a known producer,
including legacy acquisition registration, receive `module/<producer>`; anonymous
registrations receive `base`. Pending is never a canonical destination. An explicit
user package import uses Current unless Current is Pending, in which case it uses
base. File/structured publication still validates producer ownership and namespace;
a user move does not grant the producer permission to write in the new namespace.

`datasetNamespaceMigrationPlan ?session?` describes legacy Dataset and Manifest
fields. `datasetNamespaceMigrate session newBackupArchive` is a host/admin operation:
create and validate a new portable backup outside the Session, then migrate in a
catalog transaction. Errors restore registry, affected metadata and Manifest bytes,
plus in-memory settings. Restore through Portable Session Import into a new directory.
The existing private metadata authority remains the only writer of namespace keys.
