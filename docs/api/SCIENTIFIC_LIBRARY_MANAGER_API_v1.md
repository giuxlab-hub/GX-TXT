# Scientific Library Manager API v1

CORE owns scientific-library registry, package integrity, provider dispatch,
normalized content and credentials. `library.reference.json` supports explicit
external JSON/HTTPS consultation with operation-scoped policy and optional cache.
Managed IR/NMR providers reuse immutable `.gxsrl` owners and bounded content reads.
See [source and domain contracts](SCIENTIFIC_LIBRARY_P025_SOURCES_v1.md).
Scientific Libraries is the primary management Viewer. The deprecated Reference
Library and Library Manager preserve saved open routes; specialized IR/NMR
Viewers retain scientific presentation ownership.

## Registry and storage

Managed package installation, `listInstalledLibraries`, IR/NMR entry access
and saved schema-1 registries use the same registry authority. `listInstalledLibraries` remains the managed-library view.
The manager is CORE loaded and does not depend on Analysis execution state.

`libraryRoot` returns the effective absolute GX-TXT Library Root. The persisted
configuration key remains `libraries.scientific_root`; callers should use the
public CORE method or `configurationGet`, not the internal environment handoff.

`listRegisteredLibraries` lists active managed, external and remote records.
`getLibraryInfo` accepts each mode and removed tombstones. Every public record
provides `library_id`, `library_type`, `display_name`, `provider_id`,
`provider_version`, `mode`, `version`, `state`, `availability`, `origin`,
`license`, `rights`, `read_only`, `authentication_required`,
`authentication_status`, and `provider_config` (JSON object). Historical
managed records receive compatible defaults on read. Managed payloads remain
under Library Root; external/remote registrations store metadata only.

`registerLibrary fields` accepts a Tcl dict with `library_id`, `library_type`,
`display_name`, `mode=external|remote`, optional `version`, `origin`, `license`,
`rights`, `read_only=0|1`, `availability`, `description`, and provider-owned
`config.<name>` fields. It returns the public record. `unregisterLibrary id`
marks an external/remote record removed and retains its ID as a tombstone.
Managed libraries continue to use `installLibrary` and `removeLibrary`.
Providers may declare `REGISTRATION_SCHEMA` in their Python entrypoint as a
mapping from mode to `{required: [...], optional: [...]}` and optionally
`validate_registration(mode, configuration)`. CORE checks keys and delegates
semantic validation; it does not interpret endpoint or local database formats.
Secret-like configuration keys are rejected. Operational access uses the provider content and credential contracts below.

Provider discovery in the Tcl host uses the loaded module catalog descriptors,
including independently installed provider-only plugins. A provider-only module
uses `kind=service`, `runner=service`, `selectable=0`, and a
`[library_type_provider]` descriptor. Legacy provider descriptors with
`kind=analysis`, `runner=service` stay loadable and are excluded from runnable
Analysis jobs. Direct standalone invocation of the Python helper retains its
bundled-descriptor fallback for compatibility.

GX-TXT manages scientific data libraries independently of the framework and executable plugins. CORE verifies the data-only package, stores its payload, tracks versions and checksums, and resolves an installed Library Type Provider. The provider validates scientific meaning and exposes entries. CORE contains no IR-specific parser.

## Public Tcl API

The namespace is `::GX::ScientificLibraryManagerAPIv1`. It is loaded with the framework.

| Operation | Result |
| --- | --- |
| `listLibraryTypes` | Library types served by installed providers. |
| `resolveLibraryProvider type` | Provider ID and version for a type; explicit error when absent. |
| `listInstalledLibraries` | Public registry records for installed libraries. |
| `getLibraryInfo id` | Registry record, including `removed` tombstones. |
| `queryCompatibleLibraries type` | Installed logical library IDs for a type. |
| `installLibrary package.zip` | Validate and install a new data package. |
| `updateLibrary id package.zip` | Validate a newer package with the same ID, provider, type and stable entries. |
| `removeLibrary id` | Remove managed payload and mark saved references stale. |
| `verifyLibrary id` | Recheck package and payload hashes and provider entry index. |
| `openLibrary id` | Resolve an installed logical ID without returning a storage path. |
| `listLibraryEntries id` | Provider-indexed stable entry IDs. |
| `openLibraryEntry id entry` | Validate an installed entry and open the provider-declared specialized Viewer with `library_id` and `entry_id` context. |
| `readLibrarySpectrum id entry` | Provider spectrum fields, arrays, metadata and provenance for supported one-dimensional spectra. |

`openLibrary`, entry access and verification reject removed IDs. The public registry contains origin, license, type, version, provider, state, hashes, timestamps and entry count. Current managed records may also return `managed_storage_location` as diagnostic information; consumers must use logical IDs and public access methods, not retain or open that location as an alternative storage contract. Internal `storage_ref`, `package_ref` and `entry_ids` are omitted from public records. An update cannot remove an existing stable entry ID.

A Library Type Provider may declare both `entry_viewer_module` and `entry_viewer_id` in its `[library_type_provider]` descriptor section. They are optional for types with no specialized Viewer. `resolveLibraryProvider` exposes these validated IDs, and `openLibraryEntry` uses the normal Viewer Provider API to open a selected entry. The manager checks that the library is installed and the entry belongs to it before dispatch. No Session is required for a library entry.

## Data package

The ZIP contains exactly `library.ini`, `SHA256SUMS.txt` and `payload/library.gxsrl`. The manifest declares library ID, type, version, provider requirement, format version, name, description, license and origin. `SHA256SUMS.txt` binds the payload bytes. The manager rejects extra paths, directories, links, oversized members, checksum mismatch, unsafe IDs and incompatible providers. It never executes content from a data package. Provider validation runs before the registry commit.

An independently distributed type is `spectroscopy.ir.reference`, served by the separately installable `library.spectroscopy.ir.reference` plugin. The IR provider validates the Scientific Reference Library database, IR spectral semantics, stable spectrum IDs and provenance. The Scientific Spectral Library viewer offers **Install library...** when its reference list is empty, then discovers the installed logical ID through this API. Existing user-authored reference libraries remain visible.

`spectroscopy.nmr.reference` provides a managed Cambridge 1-D NMR library. The unified `viewer.scientific_library_workspace` handles installation, entry search, version and provenance. The deprecated `viewer.reference_library` retains saved compatibility routes. Its selected-entry action calls `openLibraryEntry`, which routes to the provider-declared `viewer.nmr_reference`; NMR ppm/nucleus presentation stays in that specialized viewer. The current IR viewer continues to serve its established comparison and ranking workflow.

Install or update the provider through Plugin Install API v1, then install a data package through this manager. A library can be updated or removed without updating the framework, the provider, or the viewer. Removing a package leaves a tombstone so a saved ID reports a stale reference rather than resolving to different content.

The manager stores payloads and its registry below the effective Library Root returned by `libraryRoot`. The normal host supplies the configured `libraries.scientific_root`; without a configured root the helper falls back to `XDG_DATA_HOME/gxtxt_pipeline/scientific_libraries` (or the XDG default). Consumers use logical library IDs and public methods rather than constructing storage paths.

## Exact host signatures and return shapes

The public facade owner is `core/tcl/scientific_library_manager_api_v1.tcl`;
the delegated registry/package/provider implementation is CORE's
`core/python/scientific_library_manager.py`. Consumers call the facade, not
private helper functions or its internal wire format.

All commands below are in `::GX::ScientificLibraryManagerAPIv1`. The registry commands in this table have no optional Tcl arguments/defaults. IDs and type IDs are
strings matching `[A-Za-z0-9][A-Za-z0-9._-]*`, excluding `.` and `..`.

| Tcl signature | Exact facade result / context |
|---|---|
| `apiInfo` | dict: `api_name SCIENTIFIC_LIBRARY_MANAGER_API_v1`, `api_version 1`, `registry_version 1` |
| `libraryRoot` | effective absolute root string; diagnostic/configuration access, not a payload API |
| `listLibraryTypes` | list of installed provider type IDs |
| `resolveLibraryProvider libraryType` | dict of `library_type`, `provider_id`, `provider_version`, `entry_viewer_module`, `entry_viewer_id`, `library_viewer_module`, `library_viewer_id`; missing optional viewer fields are empty strings |
| `listInstalledLibraries` | list of public record dicts for installed **managed** records |
| `listRegisteredLibraries` | list of public record dicts for every installed mode; removed records excluded |
| `getLibraryInfo libraryId` | public record dict, including a removed tombstone; unknown ID errors |
| `queryCompatibleLibraries libraryType` | sorted ID list matching type and installed state, **all modes**; does not check operational external/remote access |
| `installLibrary packagePath` | public installed record; normalizes path and validates package/provider before commit |
| `updateLibrary libraryId packagePath` | public updated managed record; requires increasing version and preserved stable entries |
| `removeLibrary libraryId` | public removed managed record; provider deactivation and payload removal |
| `verifyLibrary libraryId` | public installed managed record plus `verified_at`; compares package/payload SHA and exact provider entry index |
| `openLibrary libraryId` | dict with only `library_id`, `library_type`, `version`, `provider_id`; no Viewer is opened |
| `listLibraryEntries libraryId` | managed record's ordered stable entry-ID list |
| `openLibraryEntry libraryId entryId` | result of public `viewerOpen` for provider's declared specialized Viewer, with `library_id`/`entry_id` context; requires managed entry membership and both viewer fields |
| `readLibrarySpectrum libraryId spectrumId` | spectrum dict described below; installed managed entry required |
| `registerLibrary fields` | public external/remote registration record; required/optional fields as above |
| `unregisterLibrary libraryId` | public external/remote removed tombstone; rejects managed mode |

Public Tcl record values are strings. In particular, `provider_config` is JSON
object **text**, not a nested Tcl dict. Boolean-like fields are `0`/`1` strings.
Managed records normally include package/payload SHA-256, format version,
installation/update UTC timestamps, entry count and the optional diagnostic
location. External/remote records need not contain managed hashes/location.
Consumers must not assume all modes have identical fields.

`readLibrarySpectrum` initializes `x` and `y` lists and `metadata` and
`provenance` dicts. It adds provider-supplied top-level fields and appends numeric
pair text parsed from the provider's spectrum output. The helper emits paired
samples using `zip(x, y)` and `.17g` formatting. This generic owner does not
declare axis units, sample semantics, nucleus/IR meaning, uncertainty, array
length consistency or calibration validation; use the selected provider's actual
spectrum fields and scientific contract. The result must not be called a
canonical Dataset or treated as a scientific validation receipt.

`registerLibrary` defaults version/origin/license/rights/description to empty
strings, read_only to `1`, availability to `unknown`, entry_count to `0`, and
authentication_required/status to `0`/`not_required`. A prior ID, even a removed
tombstone, cannot be registered again. A provider-owned registration schema and
validator check `config.*`; secret-like keys are rejected. Registration records
availability metadata; it does not authenticate, query or validate a remote
service's operational availability. Managed install has its distinct lifecycle.

## Limits, errors and language access

No Session is needed for registry or library-entry access. The host needs its
configured Python runtime and the installed provider when a type operation
requires it. Tcl wrapper errors retain the underlying error options with a
`Scientific Library Manager:` message prefix. Invalid IDs/fields, duplicate or
missing providers, removed/unknown entries, wrong mode, missing specialized
Viewer, checksum/index mismatch, incompatible update and invalid package are
explicit failures; there is no generic success/failure dict wrapper.

A package has exactly the three named ordinary-file members specified above;
each uncompressed member is limited to 500,000,000 bytes. The wrapper declares
no separate paged spectrum-read API or generic spectral sample bound. Operations
are synchronous host calls unless explicitly submitted using the additive
`libraryRequest` operation below; listInstalledLibraries/listRegisteredLibraries fetch
each record through the helper. Do not present them as asynchronous Job APIs.

This family is discoverable through the existing CORE API owner. It has no
automatic Python/Octave grant from this host surface. The reviewed Script subset
is specified below. Restricted C++ has the three
typed catalog methods described below. Do not call `gxtxt_api_call` with this family
solely because a catalog row exists. The Python helper is an implementation
owned by CORE, not a public consumer import or a replacement public service.
There is no generic C++ invoke; use existing reviewed typed capabilities only.

Read-only trusted-host discovery example (does not install or open a Viewer):

```tcl
set types [::GX::ScientificLibraryManagerAPIv1::listLibraryTypes]
foreach type $types {
    set provider [::GX::ScientificLibraryManagerAPIv1::resolveLibraryProvider $type]
    set ids [::GX::ScientificLibraryManagerAPIv1::queryCompatibleLibraries $type]
}
```

Runtime/provider availability and authentication remain explicit operation checks; discovery does not establish scientific access.

## Catalog, capability declarations and provider delegation

This contract reuses the same registry, package verifier, provider discovery,
ScriptJob/Resource owners and specialized Viewers. A registered
remote reference is not proof of connectivity or authentication. Existing
`openLibrary` remains an ID resolver; use the distinct `openLibraryViewer` for
normal registered-Viewer dispatch. IR's library Viewer and NMR's entry Viewer
remain the owners of scientific presentation.

| Host Tcl signature | Exact result and limits |
| --- | --- |
| `getProviderCapabilities libraryType` | Flat scalar dict with schema `gxtxt.library_capabilities.v1`, provider/type/version, `supported_modes`, declaration source, `capability.*`, `extra_actions`, `extra.ID.*` and `registration.MODE.required/optional`. Does not probe a library. |
| `getLibraryCapabilities libraryId` | Same declaration plus current record policy/status, effective `action.*` flags, `reason.*`, `library_id` and SHA256 of exact current registry bytes. Absent provider gives explicit unavailable status with inspection/refresh/unregistration availability; it is not an empty successful query. |
| `libraryCatalogPage ?options?` | Options dict: `mode all|managed|external|remote` (default all), `query` (default empty, at most1024 characters), `offset` (default0, nonnegative integer), `limit` (default100, 1–200), `library_type` (default empty; exact installed provider type). Mode/query/type filters apply together before pagination; unknown types error. Result: schema `gxtxt.library_catalog_page.v1`, registry SHA, mode/query/offset/limit/library_type, total/count and `records` list of public record dicts. Filters active installed records by ID/name/type/origin/provider; single registry read. Each public record is bounded to128KiB. No scientific entry search. |
| `openLibraryViewer libraryId ?context?` | Optional context dict accepts only `entry_id`. Current capability/policy checked; explicit entry must belong to the managed library. Prefer actual descriptor `library_viewer_module/id`; otherwise use declared entry Viewer and the first actual managed entry if no explicit entry supplied. Result dict: `status opened`, `dispatch_kind library_viewer|entry_viewer`, library/entry IDs and public `viewerOpen` result. Missing/unsupported/unavailable/auth-blocked actions error. |
| `invokeLibraryAction libraryId actionId ?parameters?` | Only a currently declared, enabled provider extra-action ID; defaults empty dict. At most32 safe parameter keys, each value at most4096 characters. Calls the provider's fixed `library_action` hook, returns at most128 scalar fields/128KiB plus actual library/action/provider IDs. No arbitrary function name. |
| `libraryRequest operation arguments callback` | Returns the existing ScriptJob asynchronous request ID. Callback receives common `ok` plus `result` or `error` response. Fixed operations listed below; `arguments` is the operation's positional list, not shell text. |

`apiInfo` retains version1/registry1 and additionally advertises the capability
schema, exact host operation list and `script_exposure intentional_subset` with
the separate finite `script_operations` list. Technical capabilities do not grant
additional script operations.

`libraryRequest` accepts `catalog_page`, `library_capabilities`,
`provider_capabilities`, `library_action`, `info`, `entries`, `verify`, `install`,
`update`, `remove`, `register`, `unregister`, `provider`, `types`, `open`, `content`.
`catalog_page` positional arguments are mode/query/offset/limit and an optional fifth exact library type; the four-argument form remains valid;
`library_capabilities`, info/entries/verify/remove/unregister/open take one ID;
provider/provider_capabilities take one type; install takes package path; update
takes ID/path; register takes alternating public field/value pairs;
library_action takes ID/action then alternating parameter/value pairs. Types
takes no arguments. Results use the same scalar/list decoders as synchronous
calls; catalog_page adds its records list. Timeout120s, output32MiB, process-group
and UI-lifetime ownership belong to existing ScriptJob. Cancel with its existing
request service. Cancellation is not a rollback of a committed administration
operation. Provider descriptors come from the current loaded module catalog and
are passed only to the helper child. This is an asynchronous host service, not a
new supervised scientific Job or a Script Bridge grant.

All synchronous helper invocations use the private fixed `--request-sync` entry
to the existing `--request` Tcl-dict stdin decoder/finite dispatcher and recursive Tcl
response envelope. The command argv contains only the configured Python runtime,
`-B`, the fixed CORE helper and `--request-sync`; catalog query text, IDs, paths,
provider arguments and descriptors are inert stdin data. Tcl `exec` control words
are not prohibited query text and must not become redirections/pipelines.
The complete request has a 1 MiB input bound, checked before dispatch and again
by the helper before Tcl-list parsing. Loaded catalog descriptors stay local to
that helper process; the synchronous facade does not modify host environment.
The finite private request dispatcher additionally accepts the existing
synchronous CLI operations `root`, `list`, `registered`, `compatible`, `spectrum`.
This does not extend `libraryRequest`'s advertised asynchronous operation list.
Both facades return the established inner information/list/spectrum/content
wire to the existing decoders; no new serializer or manager is introduced.
The sync entry inherits its caller's existing process group/session, preserving
managed/Job/wrapper cancellation and drain. Only the unchanged async `--request`
entry calls the existing request-process-group owner for its own group; mode is
a fixed private CLI selector, never a caller-controlled request field.

### Optional provider hooks and truthful status

The installed Library Type Provider's Python module may define the ordinary
dictionary `LIBRARY_CAPABILITIES`. Allowed boolean keys are `list_entries`,
`entry_info`, `search_entries`, `read_entry`, `add_entry`, `remove_entry`,
`export_entry`, `verify`, `mutable`, `read_only`, `remote`, `external`,
`offline_available`, `authentication_required`, `library_viewer`, `entry_viewer`.
`modes` is a nonempty list/tuple drawn from managed/external/remote. Unknown keys
or non-boolean flags fail discovery. Without the declaration, legacy managed
providers keep their actual entry enumeration, validate/verify and descriptor
Viewer capabilities; generic scientific read/search/mutation/export remain
false. Capability declarations do not create missing implementations.

`extra_actions` maps at most32 safe IDs to dictionaries containing a bounded
single-line `label` (1–160 characters), optional `modes` subset, and boolean
`requires_available`/`requires_authentication` (both default true). IDs cannot
shadow CORE actions. Operational execution requires the callable fixed hook
`library_action(record, action_id, parameters, framework_root)`. Its result is
bounded scalar information; scientific read/search/mutation contracts are not
invented by this hook. Parameters/IDs remain provider-owned semantics.

Optional `library_status(record, framework_root)` returns only known normalized
fields: `availability` (available/unavailable/unknown/temporarily_unavailable),
`read_only`, `authentication_required` (0/1/unknown), `authentication_status`,
`entry_count` (nonnegative integer/unknown) and optional `reason`. Report actual
known state; discovery itself does not initiate a remote probe. A registration's
read_only1 cannot be relaxed by a provider status response. Provider-supplied
authentication status is preserved; readiness requires authentication_required0
or status not_required/unlocked/authenticated. The registry remains unchanged.

Effective flat `status.*` is explicitly distinct from raw registry metadata.
Legacy external/remote registration defaults count0/auth0/not_required are not
observations: count/auth become unknown unless an actual declaration/status hook
supplies knowledge. `status_source` identifies registration_metadata_not_probed,
provider_status or provider_unavailable. Unsupported modes, temporary absence,
missing provider, removed records and authentication failures produce explicit
disabled action reasons; no empty-success fallback. Verify and existing managed
entry enumeration remain managed-only. Inspection and unregister can remain
available when scientific opening is disabled.

When a registered provider is unavailable, capabilities still report the actual
`mode`, `registry_state` and registry fingerprint. Inspection and external/remote
unregistration remain enabled for installed records. Removed tombstones keep both
actions disabled with `Library was removed` reasons, matching provider-present
policy; refresh remains available and public `getLibraryInfo` can still inspect
the retained tombstone. Capability discovery does not change the registry.

### Restricted C++ Viewer and declarative GUI Host

The reviewed SDK exposes `Host.catalog_refresh(unsigned form)`,
`Host.catalog_inspect(unsigned form)` and
`Host.catalog_action(unsigned form, const char* action)`. `form` is the actual
component ordinal of a declared section with
`catalog_owner scientific_libraries`. The project requires manager API v1 and
explicit compatible profile grants; refresh requires libraryCatalogPage, inspect
requires getLibraryCapabilities. Every catalog requires both, plus
listLibraryEntries when entries are declared and getProviderCapabilities for
registration controls. Each finite action requires its exact manager operation:
open/entry_open→openLibraryViewer, verify→verifyLibrary, install→installLibrary,
update→updateLibrary, remove→removeLibrary, register_external/register_remote→
registerLibrary, unregister→unregisterLibrary, extra_action→invokeLibraryAction.
Entry search requires searchLibraryEntries; next/previous require libraryEntriesPage;
entry_info requires getLibraryEntryInfo. Declared entry-search forms require all three grants.
No generic invoke, Tcl callback, registry/path access or provider import is given
to the author. `refresh` uses catalog_refresh; it is not a catalog_action string.

The GUI Host owns the existing lists/tables/shared forms and request lifetime.
Section properties: required catalog_records(list), catalog_mode(choice or
combobox), catalog_filter(entry or field), catalog_info(table with2columns),
catalog_capabilities(table with4columns), catalog_log(log), catalog_status and
catalog_count(label/status), catalog_actions(dictionary of finite action→declared
command handler). Optional catalog_entries(list), catalog_extra_action(choice/
combobox), catalog_page(entry/field, positive integer) enable managed entries,
declared provider actions and100-record pages. Mode values are the public mode
strings; filter text remains a registry filter. Shared tables are read-only;
legacy ID-only entry consultation shows at most1000 IDs with explicit shown/total count.
A form declaring catalog_entry_filter(entry/field), catalog_entry_info(table)
and catalog_entry_count(status/label) uses normalized provider search/info.
Empty query lists entries; nonempty query is an explicit JSON string sent to
search_entries. Pages contain at most100 records and preserve provider continuation
identity and original query across next/previous. Entry selection displays exact
metadata/provenance/result_json through entry_info. Errors remain errors rather
than successful empty pages. Optional catalog_type(choice/combobox) selects an
exact type before pagination; catalog_providers(table) displays installed type
capability declarations and registration schemas. No scientific mutation is implied. Raw facts are labeled registry.*; operational
status facts retain status.*. Capability table action rows use actual action
gates; a Viewer row also requires that specific Viewer kind to be declared (NMR
Open's first-entry fallback does not declare a library-level Viewer). Non-action
property rows show `N/A` with the actual mode/availability explanation rather
than inventing a false disabled action. Read-only/authentication rows show their
effective known state; unsupported generic capabilities remain explicit.

Host Tcl calls are `viewerGuiDesignCatalogRefresh window form`,
`viewerGuiDesignCatalogInspect window form`,
`viewerGuiDesignCatalogAction window form action` and
`viewerGuiDesignCatalogDescribe window form`. Describe returns presentation-only
state, rows/current selection/capabilities/requests/page with owner identification;
it is not a registry authority. Read requests coalesce; late generation/Session
responses are discarded. An active administration operation blocks interfering
refresh/actions until its actual result. Window disposal cancels owned requests.
Response ownership is checked before changing presentation state: the live
Session, process-local catalog `lifetime`, active request generation and stage
must still match. Reopening the same window path creates a fresh lifetime even
if its generation counter repeats. A stale or duplicate completion preserves the
entire successor state, including its request, pending read and `last_action`.
The owning canceled read may hand off to the latest coalesced pending read;
disposal invalidates the catalog before canceling requests so it cannot restart
pending work. `generation` tracks requested reads; `active_generation` identifies
the dispatched request. These identities are transient presentation metadata,
not registry or scientific identities.
The presentation state retains `last_action` with schema
`gxtxt.library_catalog_action.v1`, actual operation/requested library/returned
library ID, request generation, common `ok` and exact manager result or error.
Automatic list/capability refresh preserves it. Activity keeps correlated action
results/errors (bounded65536characters, with an explicit older-activity omission
notice) instead of replacing a Verify receipt with capability metadata. This is
per-window RAM: closing it releases the presentation, and it is not a durable
scientific Job or an additional canonical log store.
Registration uses ordinary UI Field forms and provider-declared non-secret
configuration fields; unsupported operational modes are labeled registration-only.
Opening delegates to the registered domain Viewer through the same manager.

## Normalized content operations

The API-owned Tcl and Python manager owns provider dispatch, normalized results,
policy and integrity. The reviewed Script subset reuses this same owner.

### Exact public host signatures

All methods belong to `::GX::ScientificLibraryManagerAPIv1`. `options` defaults
to an empty Tcl dict. Provider-owned structured input is **explicit JSON text**;
CORE never guesses whether a Tcl string is a dict, number, boolean or null.

| Tcl signature | Result |
| --- | --- |
| `libraryEntriesPage libraryId ?options?` | Normalized entry page with provider ordering/stable IDs and optional continuation/known total. |
| `getLibraryEntryInfo libraryId entryId ?options?` | Compact entry information/metadata/provenance. |
| `searchLibraryEntries libraryId queryJson ?options?` | Provider-defined search query expressed as JSON; normalized entry page. |
| `readLibraryEntry libraryId entryId ?options?` | Provider scientific payload/contract, metadata and provenance. |
| `exportLibraryEntry libraryId entryId format ?options?` | Explicit data-return export: media type, utf-8/base64 encoding and data. No destination path. |
| `addLibraryEntry libraryId entryJson ?options?` | Add to an existing mutable library; provider-assigned/validated stable ID and mutation receipt. |
| `removeLibraryEntry libraryId entryId ?options?` | Remove one entry from an existing mutable library; not containing-library administration. |

Every method accepts `provider_json` in options, containing a JSON object of
provider-owned options. Pages/search additionally accept `limit` (default100,
1–200 decimal integer) and `continuation` (bounded opaque provider token).
Unknown common options reject. Query JSON may be a string or another provider-
accepted JSON value; add-entry JSON must decode to an object. For example a Tcl
JSON string query is `{"benzene"}`; a provider option object in a Tcl options dict
requires its literal braces, e.g. `{provider_json {{"mode":"exact"}}}`.

Existing discovery remains authoritative: `listRegisteredLibraries` returns all
active public records, `queryCompatibleLibraries` filters by type, and
`libraryCatalogPage` supplies bounded mode/text-filtered public records. Those
results, entry pages and search results are already structured data-return
exports; callers persist permitted derivatives through existing public artifact/
publication/export APIs. No duplicate library-discovery service or unrestricted
filesystem writer is introduced.

### Result shapes and lossless JSON typing

Common result fields are schema, actual library_id/library_type/provider_id/
provider_version/mode and observed `retrieved_at`. Scientific source timestamps,
remote revision/ETag/hash/license and upstream source identity are preserved only
when supplied in provenance, never fabricated from the registry. Provider
provenance cannot conflict with authoritative CORE identity fields.

Schemas are `gxtxt.library_entry_page.v1` (records/count, optional continuation/
total), `gxtxt.library_entry_info.v1` (entry_id, compact metadata/provenance,
optional content_contract), `gxtxt.library_entry.v1` (entry_id/payload plus optional
metadata/provenance), `gxtxt.library_entry_export.v1` (entry_id/media_type/encoding/
data/provenance), and `gxtxt.library_entry_mutation.v1` (entry_id/action, optional
revision/transaction_id/provenance). Unknown totals/revisions stay absent.
Entry IDs/tokens preserve Unicode and punctuation; they are not filesystem paths
and do not use the CORE library-ID grammar. Records are library source content,
not already published canonical Session Datasets.

Every public result additionally includes `result_json`: JSON text of the full
normalized result **excluding the sidecar itself**. It is authoritative for JSON
null versus empty string, boolean versus integer, nested container types and
exact integer text. Convenience Tcl dict/list fields use the existing recursive
`tcl_result` conversion, where None appears empty and boolean appears0/1; callers
needing typed interpretation use result_json with their normal JSON reader.
The sidecar is response metadata, not another storage or authority path. No new
serializer is introduced; standard-library JSON plus existing tcl_result are
used deliberately.

Limits:1MiB parameters/full host request envelope; pages at most200 records;
opaque IDs/tokens at most4096characters; internal normalized content at most16MiB,
100000nodes/depth32. The **final serialized/base64 C wire**, including the sidecar,
is capped at24MiB so the existing32MiB managed-response envelope remains bounded.
A result may hit the final wire bound before the normalized-content bound.
Oversized data rejects with a clear error; it is never silently truncated.

### Provider contract, policy and integrity

The installed trusted provider implements fixed named hooks
`list_entries`, `entry_info`, `search_entries`, `read_entry`, `export_entry`,
`add_entry`, `remove_entry`, each `(record, parameters, framework_root)`. The
existing capability vocabulary gates them, but a positive flag without a
callable hook yields unsupported_operation. Provider owns scientific search,
entry validation, ordering/paging, payload/units and atomic source transactions.
Normalized return fields match the result shapes above; pages return compact
records, read returns payload, export returns data rather than a file path.

Required fixed hook
`library_content_policy(record, operation, parameters, framework_root)` returns
`{allowed: bool, reason?: str, policy_reference?: str}`. A literal positive
boolean is required. Missing policy denies; malformed policy errors; operation-
scoped denial is policy_restricted. CORE does not interpret free-text license or
rights to grant access. Provider owns source/license terms, per-entry and exact-
format permission. Consultation does not imply export/redistribution permission.
No CORE cache/bulk mirror or automatic retry is added. This is not a DRM claim:
authorized hosts remain bound by source terms when receiving consultation data.

Mutation requires explicit registry read_only0, mutable/write capabilities,
provider read_only=false, an actually observed writable status from existing
library_status, and affirmative operation policy. Current managed versioned
packages remain immutable regardless of provider flags. Saved provider/type IDs
are validated before selection; a corrupt empty provider ID cannot rebind the
current type provider via a legacy optional-ID fallback. Provider inputs are
copied; a hook cannot mutate CORE's in-memory registration or requested identity.

Managed content reads reuse existing package/payload SHA, provider scientific
validation and exact stable-entry index verification inside the existing local
registry lock, before and after the content hook. Detected postflight changes
discard unreturned data. External/remote requests do not hold that lock across
provider work. Hash/lock checks serialize ordinary manager actions; they do not
claim cryptographic signatures or atomic defense against unrelated malicious
replace-and-restore writes. Legacy list/spectrum/lifecycle semantics remain
unchanged; dedicated IR/NMR providers and managers are not rewritten.

### Errors and asynchronous use

Normalized codes: unsupported_operation, library_not_found, entry_not_found,
read_only, authentication_required, credentials_locked, authentication_failed,
rate_limited, temporarily_unavailable, provider_unavailable,
invalid_provider_configuration, integrity_failure, policy_restricted,
provider_failure, invalid_request, invalid_provider_response. A failed search
never returns a successful empty page. Explicit provider errors use the single
`{error: {code, message, retry_after_seconds?, provider_code?}}` result; safe bounded
messages/details are provider-author obligations. Unknown exceptions become a
safe generic provider_failure rather than leaking raw exception text.

Synchronous errors preserve Tcl catch with errorcode
`{GXTXT SCIENTIFIC_LIBRARY_MANAGER CODE}` and custom `-library_error` structured
detail. Asynchronous content errors retain common ok0/error/category and add
error_code/error_details. Existing ScriptJob timeout/cancellation/process errors
retain that owner's common error behavior. Any error after dispatching mutation,
including a later registry failure, conservatively carries
`mutation_outcome unknown`. Neither failure nor cancellation proves rollback;
providers own commit disposition, and no automatic retry is performed.

`libraryRequest content arguments callback` uses the existing managed request
owner. `arguments` is a3-item Tcl list: libraryId, finite operation, parameter dict.
Operations: list_entries, entry_info, search_entries, read_entry, export_entry,
add_entry, remove_entry. Fixed parameter fields: entry_id, format, limit,
continuation, query_json, entry_json, options_json. The *_json fields are explicit
JSON text (options_json must be an object). They map to provider parameters query,
entry and options. No arbitrary method/function name or eval input is accepted.
Common example:

```tcl
set args [list $libraryId read_entry [dict create entry_id $entryId]]
::GX::ScientificLibraryManagerAPIv1::libraryRequest content $args $callback
```

The direct helper CLI `python3 -B scientific_library_manager.py content` still
reads that same3-item Tcl list from stdin. Host synchronous and managed calls use
the same decoder with fixed `--request-sync` or async `--request` and those
arguments as data. Successful and failed content use a
single C/base64 record containing the finite recursive Tcl response schema;
CLI failure exits nonzero, while managed-worker transport carries the result to
the facade's decoder. No provider payload is required in argv. All old F/L/M/P/D
wire and old public method signatures remain unchanged. `listLibraryEntries`
remains the accepted managed-only ID-list route; use libraryEntriesPage for the
new normalized all-mode operation. Existing --request operations still decode
through their old paths.

## Python and GNU Octave Bridge subset

The API-owned `core/script_bindings/scientific_library_manager.py` provides
closed projections and finite operation grants through the common Bridge.

Both languages use `gxtxt_api_call("SCIENTIFIC_LIBRARY_MANAGER_API_v1", operation,
args)` with positional list/cell arguments. The exact callable surface is:

| Operation | Arguments | Existing host owner |
|---|---|---|
| api_info | none | apiInfo, safe subset projection |
| effective_root | none | libraryRoot, read-only root query |
| list_types | none | listLibraryTypes |
| list_libraries | none | listRegisteredLibraries, safe public records |
| list_installed_libraries | none | listInstalledLibraries, managed-only records |
| library_info | library_id | getLibraryInfo, safe public fields |
| compatible_libraries | library_type | queryCompatibleLibraries |
| legacy_entries | library_id | listLibraryEntries, managed-only compatibility |
| provider_capabilities | library_type | getProviderCapabilities, closed fields |
| library_capabilities | library_id | getLibraryCapabilities, closed fields/status |
| catalog_page | optional options map | libraryCatalogPage |
| entries_page | library_id, optional paging map | libraryEntriesPage |
| entry_info | library_id, entry_id | getLibraryEntryInfo |
| search_entries | library_id, query_json, optional paging map | searchLibraryEntries |
| read_entry | library_id, entry_id | readLibraryEntry |
| export_entry | library_id, entry_id, format | exportLibraryEntry, data-return only |
| add_entry | library_id, entry_json | addLibraryEntry, existing mutable library |
| remove_entry | library_id, entry_id | removeLibraryEntry, existing mutable library |

`paging` accepts only `limit`1–200 and bounded opaque `continuation`.
The Script `catalog_page` options also accept `library_type`: empty selects all
types; a nonempty value must name an installed provider type (at most128
characters). The same existing manager applies mode/query/type filters before
pagination and returns the effective `library_type`. This is read-only discovery,
not a provider option or administrative grant.
`catalog_page` accepts only mode(all/managed/external/remote), query<=1024
characters, nonnegative integer offset, limit1–200 and this exact type filter. Every other argument
is a string. query_json and entry_json are explicit JSON **text**, retaining the
provider's scientific meaning and the accepted1MiB complete-input bound.
Finite integral Octave paging numbers normalize to exact integers; logical,
fractional, nonfinite or out-of-range limits reject before provider dispatch.

No operation forwards provider_json/options_json, destination, configuration,
credential-profile data or arbitrary action names. Export supplies no destination
or options: its result has the existing provider media_type, utf-8/base64 encoding
and data contract. The provider's named format and explicit owner policy/license,
authentication and integrity checks remain authoritative. Capability flags and
free-text license/rights do not authorize a call. Mutation affects an entry in an
already-mutable library only; managed versioned packages remain immutable.
Scripts may retain public lists/results through their normal framework-owned run
output/artifact/Dataset services; this family adds no host file writer.

All seven content operations return exactly `{schema, result_json}`. The existing
accepted result_json is authoritative for JSON null versus empty text, boolean
versus number, nested values and exact int64/uint64 text. Python may use json.loads;
Octave may use jsondecode for convenient values, but its native numeric conversion
does not replace the authoritative JSON when an exact large integer is needed.
No new serializer/null sentinel or shared transport type guess is introduced.
Final ordinary typed Bridge JSON frames are bounded to24MiB, without truncation,
in addition to existing manager input/result/wire bounds.

api_info validates the existing host identity/version/schema, then returns only
api_name/version/registry_version/capability_schema, intentional_subset exposure,
fixed CORE provider identity, exact script aliases, and capabilities
library_discovery/public_status/explicit_json_results/data_return_export/
conditional_entry_mutation/restricted_credential_runtime. It never returns the
unrestricted host operations.

Library info/catalog records admit only library_id/library_type/provider_id/
provider_version/display_name/version/mode/state/read_only/availability/
authentication_required/authentication_status/entry_count/description/license/
rights/installed_at/updated_at/sha256 when actually present. Configuration,
managed/package storage locations, implementation paths and profile fields are
excluded. effective_root is the deliberately approved read-only path query.

The Script capability projection admits only the fields below. Optional absent
fields remain absent; selected malformed values reject. Provider free-text status
reasons, implementation paths and arbitrary capability keys are excluded.

| Fields | Exact Script value |
| --- | --- |
| `capability_schema` | String `gxtxt.library_capabilities.v1`. |
| `library_type`, `library_id`, `provider_id`, `provider_version` | Text, at most4096 UTF8 bytes each. |
| `supported_modes` | Nonempty list of unique strings from `managed`, `external`, `remote`. |
| `mode` | String `managed`, `external` or `remote`. |
| `registry_state` | String `installed`, `removed` or `unknown`. |
| `declaration_source` | String `provider_declaration` or `legacy_managed_contract`. |
| `status_source` | String `registration_metadata_not_probed`, `provider_status` or `provider_unavailable`. |
| `capability.NAME` | Boolean, for exactly the sixteen names below. |
| `status.availability` | Library projection only: string `available`, `unavailable`, `unknown` or `temporarily_unavailable`. |
| `status.read_only`, `status.authentication_required` | Library projection only: string `0`, `1` or `unknown`; these status tokens remain distinct from capability booleans. |
| `status.authentication_status` | Library projection only: string `not_required`, `unknown`, `locked`, `unlocked`, `authenticated`, `failed` or `authentication_failed`. |
| `status.entry_count` | Library projection only: exact nonnegative decimal text, or string `unknown`. |
| `reason.inspect`, `reason.refresh` | Library projection only: inspect is empty text or `Library was removed`; refresh is empty text. |

The sixteen `capability.NAME` suffixes are `list_entries`, `entry_info`,
`search_entries`, `read_entry`, `add_entry`, `remove_entry`, `export_entry`,
`verify`, `mutable`, `read_only`, `remote`, `external`, `offline_available`,
`authentication_required`, `library_viewer` and `entry_viewer`. A technical
host/Viewer capability does not grant a Script operation. These fixed projection
rules belong to the existing Scientific Library Script binding, alongside the
finite aliases documented above; consumers do not import its implementation.

Normalized content failures raise `GXTXT:ScientificLibrary:<code>` with a bounded
JSON error message containing code/message and available retry_after_seconds,
provider_code or mutation_outcome. The finite normalized content codes above apply.
Input schema/arity failures use existing InvalidArguments; unregistered methods
use UnknownOperation. Failed search remains an error. A mutation whose result
cannot be returned reports mutation_outcome unknown: reconcile provider state
before retrying; no automatic retry or rollback is claimed.

The complete current host `apiInfo` declaration enumerates37 host operations,
plus `apiInfo` itself. The Script aliases above are its intentional subset; the
host discovery list is not an additional grant. Its
seven credential operations are `credentialStatus`, `credentialLock`,
`credentialProfileAdmin`, `bindLibraryCredentialProfile`, `credentialPrepare`,
`credentialSubmit` and `credentialFinish`; their access rules are documented below.
The thirteen host/module-only methods are resolveLibraryProvider, installLibrary,
updateLibrary, removeLibrary, verifyLibrary, openLibrary, openLibraryEntry,
readLibrarySpectrum, registerLibrary, unregisterLibrary, openLibraryViewer,
invokeLibraryAction and libraryRequest. Domain spectral workflows retain their
existing dedicated Reference Library bindings. Whole-library/provider/root/
credential administration is excluded. Explicit credential_status, credential_unlock
and credential_lock use the protected credential contract below.

## Protected credentials

The Script aliases credential_status, credential_unlock and credential_lock
reuse the existing native credential owner. Profile administration and the
CORE-only prepare/submit/finish routes are not ordinary Script grants.
credential_unlock(library_id, unlock_credential, lifetime_seconds=300) returns
one synchronous final result. Lifetime must be an integer from1 through900:
Python `30` or Octave `int64(30)`. Booleans, logicals, null, double-valued Octave
`30`, zero and out-of-range values reject. Omission uses integer300.

The binding calls credentialPrepare unlock with exact nonsecret identity and
lifetime, captures the operation reference, calls native credentialSubmit directly,
lets the complete Tcl invocation return to Python, then calls nonsecret
credentialFinish with that captured reference. No Tcl catch/uplevel wrapper surrounds
protected Submit. Reply references cannot retarget cleanup. Failed/malformed Submit
invokes exact-owner quarantine and Finish; failed Finish or final typed validation
quarantines that captured operation. There is no automatic resubmission.

Python arguments/request/memory remain; no Python/Tcl zeroization, arbitrary observer
or diagnostic-erasure guarantee is made. The binding raises fixed BridgeErrors outside
caught handlers and does not forward raw exception context, cause or traceback.
Runtime fields are library_id, configured(bool|null), authentication_required(bool|null),
authentication_status, expires_in_seconds(integer0..900), cleanup_pending(bool).
States are not_required/unconfigured/locked/unlocked/failed/unavailable/unknown/revoking.
Authoritative result_json preserves null/bool/integer types. Python receives None;
Octave receives [] for null and must retain result_json for exact null identity.
The lifetime is a CORE grant, not proof of successful remote authentication.

### Trusted-host credential signatures and lifetime

These commands use the same `::GX::ScientificLibraryManagerAPIv1` owner. Profile
administration, binding and Prepare/Submit/Finish are CORE host operations; they
have no Script phase, operation-reference, administration or callback alias.

| Host signature | Current contract |
| --- | --- |
| `credentialStatus libraryId` | Final `gxtxt.library_credential_response.v1` envelope with closed status fields and authoritative `result_json`. |
| `credentialLock libraryId` | Revokes that library's existing owned contexts; `revoking` with `cleanup_pending=true` is distinct from completed drain. |
| `credentialPrepare operation metadata` | Operations `unlock`, `profile_create`, `profile_replace`; reserves one nonsecret operation and returns schema `gxtxt.library_credential_operation.v1`, `ok=1`, `operation_ref` and `state=prepared`, or a fixed failure envelope. |
| `credentialSubmit operationRef unlockCredential ?providerSecret?` | Direct native invocation: one protected value for unlock, two for create/replace. Successful `state=submitted` means channel acceptance, not authentication or durable commit. |
| `credentialFinish operationRef ?callback?` | Receives/validates the final result only after the complete protected Submit invocation returns. The optional bounded callback selects managed asynchronous completion; pending is not completion. |
| `credentialProfileAdmin list` | Nonsecret profile inventory. |
| `credentialProfileAdmin inspect profileId` | Nonsecret profile metadata/revision. |
| `credentialProfileAdmin inspect_binding libraryId` | Current nonsecret binding and library-record CAS revision. |
| `credentialProfileAdmin delete profileId expectedRevision` | Exact expected-profile-revision delete; stale CAS refuses. |
| `bindLibraryCredentialProfile libraryId profileId expectedLibraryRevision expectedProfileRevision` | Exact library/profile CAS binding. Unbind uses empty `profileId` and profile revision `none`. |

Prepare metadata is exactly `library_id lifetime_seconds` for unlock, with
canonical integer lifetime1..900 (callers resolve default300). For profile create/
replace it is exactly `profile_id expected_revision provider_id`: create requires
revision `absent`, replace requires the exact64-character lowercase SHA256 revision.
An operation reference contains exactly `context_id`, `generation`, `operation_id`;
the generation is32 lowercase hex characters. It conveys no path, secret or
independent authority. Completion and failure cleanup retain the original captured
reference rather than a reply-selected target.

The caller prepares and prearms its nonsecret completion/cleanup before reading
protected input. Submit runs directly, without a Tcl catch/uplevel wrapper or
yield/modal validation around that invocation. Receive/decode/cleanup occurs after
its complete return. Secret-bearing Tcl `credentialUnlock` and profile-admin
create/replace forms return fixed unavailable responses; use the admitted native
sequence rather than those convenience forms.

The existing credential owner bounds complete protected arguments to32768 UTF8
bytes, the credential/admin subset to16384 bytes, and the encoded frame including
newline and pending bytes to65536. Envelope overhead can refuse a legal-sized
individual field. Unlock credentials admit12..1024 UTF8 bytes and provider secrets
1..4096 UTF8 bytes. The complete encrypted profile record is bounded to16384
bytes, so JSON escaping can reject otherwise admitted individual secret text.
No truncation or alternate serializer is used. Nonprofile1MiB
input remains supported. Encrypted ProfileStore support is loaded lazily for
protected operations. Profile-bound content fails locked before provider import;
authorized synchronous/asynchronous calls share the same owned private runtime.
Each request rechecks library, provider/source and profile identities. Provider
readiness and source policy remain necessary after successful decryption; a grant
does not establish remote authentication. Provider-private secret use stays inside
the scoped callback. The existing TTL and managed process/drain owners control
retirement, with no zeroization or hostile-provider sandbox guarantee.

Failed durable administration/binding may have committed: mutation_outcome unknown
requires read-only inspect/inspect_binding reconciliation with original expected
revisions, without automatic retry or rollback.

### Offline manual candidate selection (P028 revision 2, additive)

Host `domainRequest manual_candidates` accepts `{record_type,text}` with literal TSV
(256KiB UTF-8, header plus1–20 rows). `candidate_id` is required and distinct;
other columns are installed schema field names, optional `label`/`source_id`.
Non-string typed fields use JSON scalar/array/object syntax. No lookup or writes.

`manual_prepare` / `manual_import` additionally accept destination `library_id`,
optional `expected_version`, and optional `suggestions` dictionary. Its `include`
boolean defaults false. If true, specify `text` (or structured `candidates`),
`selected_ids`, provider-declared `relation_type`, `source_id`, `assertion_kind`
(`user` or `source`), and literal `evidence`. Structured rows contain
`candidate_id`, `fields`, optional `label`, `source_id`, `original_text`.
Only relations explicitly declaring `manual_suggestion: true` and compatible
source/target types are offered/admitted. Existing source connectors are unchanged.
No validated equivalence assertion or recursive selection is produced.

Preview returns `expected_version` and `selected_suggestions`, with exact candidate
entries and new/reused status. No persistent write occurs. Stable candidate IDs
are hashes of record type, source identity and literal candidate key. Existing
exact typed records are reused; conflicting content under the same key is refused.
Candidates and primary directed edges commit through one existing immutable Library
transaction. Destination version comparison occurs again inside the registry lock.
A reviewed stale primary revision/hash or destination version is refused. The
original primary fields/resources/provenance remain unchanged when only links are
added. Every target pins actual Library/Entry/revision/content SHA, preserves source
assertion/evidence/original paste, and declares compatibility unverified.

The import receipt retains `entries` and zero `session_datasets_created`, and adds
`primary_entry_id` plus `selected_suggestions` candidate/entry/status rows. A duplicate
selection reuses existing entries/edges. Browser Cancel/review performs no commit;
only explicit Save writes. Session acquisition remains a separate action. No
network, credentials, automated API caching or supplier-specific CORE UI is involved.

Manual suggestion previews are bounded to2MiB of selected candidate/edge data
(including retained original input); reduce the paste or checked subset if needed.
Quoted TSV and multiline/CRLF original rows are retained exactly. An explicit
changed original paste is retained as `provenance.original_text` and creates a new
revision even when typed fields match; absent paste preserves prior provenance
when only suggestion links are added. Candidate inspectors and selected-review
fields show full typed identity values and source assertions, with no JSON editor
required for the normal scalar component workflow.


## Unified Viewer presentation bridge

The existing `viewer.scientific_library_workspace/scientific_library_workspace`
uses three Builder-declared `library_browser` components in one group: `records`,
`sources`, and `manual`. Existing catalog/administration remains in the same
Viewer. `VIEWER_GUI_HOST_API_v1` owns component admission and finite page focus.
This trusted presentation bridge is not a Script data or arbitrary GUI factory API.

After constructing all declared page frames, the GUI Host calls
`::GX::LibraryBrowser::mountPages window group pages statusCommand` once. `pages`
is exactly records/sources/manual mapped to existing empty native frames owned
by that Viewer. The host derives the status command; authored callback strings
are not accepted. The result is a controller bound to the existing Viewer lifetime.
`focusPage controller page` selects the declaring native page and its normal input.
`canClose controller` returns a strict boolean after reviewing an unsaved draft;
it does not destroy the Viewer or mutate a Workspace. Forced parent destruction
retains captured PDF retirement callbacks until reader processes are drained and
resource leases can be released. Draft values and credentials are not captured
as Workspace interface values.

The formerly internal `LibraryBrowser::open ?parent?` compatibility route opens
or focuses the existing Viewer through its normal provider identity and the
public Host page-focus operation. It creates no standalone Browser top-level.
A legacy module without declared embedded pages receives an explicit upgrade
error; there is no fallback parallel workspace. All data operations retain the
existing manager, graph, source, Resource and Acquisition APIs described above.


The Records page makes acquisition selection explicit: **Import selected records**
uses only the current left-list selection; **Import displayed record** uses the
exact currently displayed reference after Follow/Back/Forward. **Import selected
related entries** reviews a bounded selected subset (1..100 rows), resolves the
other endpoint of incoming/outgoing assertions, and deduplicates identical pinned
Library entries. Stale, missing, external and canonical-Dataset edges are refused
for this Library-entry import action; they are not automatically downloaded or
converted. Every chosen Library entry still receives the existing representation
and compatible Acquisition Handler review before a separate Session/Namespace
confirmation. Cancelling review publishes nothing. **Edit displayed record**
also follows the visibly displayed identity, rather than an earlier list row.

### Declarative Library view scopes (P028 continuation)

The host-only `describeScope parametersJson` operation delegates to the existing
`domainRequest scope_describe`. Parameters are `{"scope": {...}}`; the scope may
also be omitted. Its result has schema `gxtxt.library_scope.v1`, canonical `scope`,
`restricted`, `eligible_record_types`, scoped domain `catalog`, eligible connector
`connectors`, registered remote `sources` (at most100), `source_total`,
`source_limit`, and bounded identity-availability `diagnostics`. Discovery does
not connect to a provider. Provider IDs identify actual domain-schema providers,
not Library Type Providers or a particular Viewer. Any compatible Viewer can use
this data contract.

Optional `scope` is accepted by existing domain operations `schemas`,
`connectors`, `search`, `resolve_external_id`, `detail`, `related`, `stage`,
`manual_candidates`, `manual_prepare`, and `manual_import`. Content operations
accept it inside their existing `options` object (`options_json` on the Tcl
facade); `importSourceSelection` accepts a top-level `scope`. Empty or absent
scope preserves unfiltered operation. Explicit null, unknown dimensions,
duplicate IDs and malformed values are rejected.

Supported dimensions are `library_types`, `record_types`, `library_ids`,
`provider_ids`, and `source_ids`. Each is a JSON list of at most64 distinct literal
IDs, ORed within the dimension and ANDed across dimensions. Empty lists are
removed, keys/values sorted, and canonical UTF8 JSON limited to32768bytes.
Non-source IDs use the existing safe-ID grammar
`^[A-Za-z0-9][A-Za-z0-9._-]*$`. Source IDs are exact nonempty Unicode strings of
at most512characters without CR/LF/NUL. They match entry
`provenance.source_id`; Source choices match exact connector IDs. Labels,
registered Library IDs, supplier names, substrings and inferred equivalence are
not substituted for source identities.

Cross-Library search and qualified external-ID resolution apply predicates in
the existing disposable index before counts, offsets and limits. Pinned detail,
resource staging and manual saves validate the same scope. Related assertions
remain visible with exact target identities and evidence, including
`scope_status=outside_scope`/`scope_reason` when the other endpoint cannot establish
the scope; opening or importing that content is refused. These are presentation
selectors, not access grants or security policy.

Source declarations may provide finite `record_types` in addition to
`library_types`. A record/provider-restricted view offers only connectors with an
actual matching declaration; a third provider sharing a Library type does not
inherit another connector's supported schemas. Upstream search/suggestions are
external identities awaiting explicit inspection: their paging remains honestly
upstream identity paging. Typed preview entries/media are filtered before their
public count/selection, and selected records/destinations are checked again before
existing explicit Library publication. No fetch-all scan infers scientific types.
The unchanged Mouser API channel remains transient consultation only.

The embedded controller accepts optional trailing scope on
`LibraryBrowser::mountPages window group pages statusCommand ?scope?`; existing
four-argument callers retain default unfiltered operation. All page state shares
one canonical scope. Successful pinned navigation alone advances Back/Forward;
failed or outside-scope reads preserve current display/history. External anchors
resolve only through scoped local exact-identity candidates, with no implicit
remote fetch. Canonical Dataset anchors with record/provider/type-only selectors
use their declared target type as presentation context and the existing
`datasetViewerOpenReference` as actual exact Session/SHA admission. Library-ID or
source-ID restrictions cannot be established for such a Dataset anchor and leave
it unavailable. This does not reinterpret scientific Dataset types or provenance.

Representation review displays full Library/entry/revision/content pins and
original resource hashes; the next review displays the actual staged bytes SHA,
MIME, content contract and recognized compatible handlers. The final existing
Session/Namespace form retains each chosen handler and all exact pins, explaining
independent per-entry outcomes. Related rows include exact other-end identities,
direction, attribution, resolution and view-scope status. Review data is transient
UI state; the same Acquisition dispatcher remains the only publication owner.

Related-table target columns are anchor-neutral: `target_kind`,
`target_container`, `target_id`, `revision`, and `target_sha256`. Their values are
respectively Library ID/entry ID/content SHA for a Library entry, exact Session
path/Dataset ID/payload SHA for a canonical Dataset, and source ID/external ID
for an external entity (unknown SHA remains blank). The anchor kind labels the
meaning; a Dataset or source identity is never presented as a Library ID.
A bounded caption displays selector counts, while an explicit read-only inline
scope view retains every literal ID and availability diagnostic. Scoped typed
source previews retain `source_record_sha256` from their original primary record
before filtering, preserving the existing source-change review pin even when the
primary scientific record type is outside the view.

An embedded Browser retains its provider-backed draft editors. If the loaded
Manager's admitted provider set, enabled state, descriptor identity or version
changes while it is open, further Browser operations clearly request an explicit
Viewer reopen to load current schemas/connectors. Editors and unsaved literal
values remain intact; normal close review still lets the user retain or discard
the draft. The Browser neither silently rebuilds a dirty form nor substitutes
unrestricted types. This is cache invalidation using the existing Manager
provider admission, not another provider registry or a permission check.

Native Manual schema/template selection checks that provider snapshot before
changing draft widgets or rows. Because a combobox updates its displayed value
before its callback, refusal restores the last accepted schema and template as
well as retaining every field. Re-selecting the same accepted schema/template is
idempotent. Deliberate internal initialization for Edit and explicit Cancel uses a
separate reset argument; ordinary selector callbacks cannot request it. A pending
technical-row form also checks the provider context before committing parent rows;
the existing UI Field form displays a refusal while retaining its unsaved input.
