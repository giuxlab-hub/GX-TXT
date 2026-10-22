# Scientific Library Manager API v1

## Step 1 additive registry contract (dev-045)

This is an additive v1 extension. Existing managed package installation,
`listInstalledLibraries`, IR/NMR entry access, and saved schema-1 registries keep
their prior behavior. `listInstalledLibraries` remains the managed-library view.
The manager is CORE loaded and does not depend on Analysis execution state.

`libraryRoot` returns the effective absolute GX-TXT Library Root. The persisted
configuration key remains `libraries.scientific_root`; callers should use the
public CORE method or `configurationGet`, not the internal environment compatibility mechanism.

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
Secret-like configuration keys are rejected. Credential profiles and operational
access to external/remote entries are later-step work.

Provider discovery in the Tcl host uses the loaded module catalog descriptors,
including independently installed provider-only plugins. A provider-only module
uses `kind=service`, `runner=service`, `selectable=0`, and a
`[library_type_provider]` descriptor. Legacy provider descriptors with
`kind=analysis`, `runner=service` stay loadable and are excluded from runnable
Analysis jobs. Direct standalone invocation of the Python helper retains its
bundled-descriptor fallback for compatibility.

GX-TXT 0.9.8.06 manages scientific data libraries independently of the framework and executable plugins. CORE verifies the data-only package, stores its payload, tracks versions and checksums, and resolves an installed Library Type Provider. The provider validates scientific meaning and exposes entries. CORE contains no IR-specific parser.

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

The first independently distributed type is `spectroscopy.ir.reference`, served by the separately installable `library.spectroscopy.ir.reference` plugin. The IR provider validates the Scientific Reference Library database, IR spectral semantics, stable spectrum IDs and provenance. The Scientific Spectral Library viewer offers **Install library...** when its reference list is empty, then discovers the installed logical ID through this API. Existing user-authored reference libraries remain visible.

Task 006 adds `spectroscopy.nmr.reference` with a managed Cambridge 1-D NMR library. The generic `viewer.reference_library` handles installation, search, version and provenance. Its selected-entry action calls `openLibraryEntry`, which routes to the provider-declared `viewer.nmr_reference`; NMR ppm/nucleus presentation stays in that specialized viewer. The current IR viewer continues to serve its established comparison and ranking workflow.

Install or update the provider through Plugin Install API v1, then install a data package through this manager. A library can be updated or removed without updating the framework, the provider, or the viewer. Removing a package leaves a tombstone so a saved ID reports a stale reference rather than resolving to different content.

The manager stores payloads and its registry below the effective Library Root returned by `libraryRoot`. The normal host supplies the configured `libraries.scientific_root`; without a configured root the helper falls back to `XDG_DATA_HOME/gxtxt_pipeline/scientific_libraries` (or the XDG default). Consumers use logical library IDs and public methods rather than constructing storage paths.

## Exact host signatures and return shapes

The public facade owner is `core/tcl/scientific_library_manager_api_v1.tcl`;
the delegated registry/package/provider implementation is CORE's
`core/python/scientific_library_manager.py`. Consumers call the facade, not
private helper functions or its internal wire format.

All commands below are in `::GX::ScientificLibraryManagerAPIv1`. The original
Step1 commands in this table have no optional Tcl arguments/defaults. IDs and type IDs are
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
registered Python/Octave Script Bridge family. Restricted C++ has the three
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

These signatures describe the inspected implementation. Runtime/provider,
authentication and scientific acceptance are independent gates; later planned
Library steps are not implied by this reference.

## Step2 catalog, capability declarations and provider delegation (dev109)

This additive contract reuses the same registry, package verifier, provider
discovery, ScriptJob/Resource owners and specialized Viewers. It does not
implement progression Steps3–7: normalized scientific entry/search/mutation,
Script Bridge, credentials, network protocols or new domain parsers. A registered
remote reference is not proof of connectivity or authentication. Existing
`openLibrary` remains an ID resolver; use the distinct `openLibraryViewer` for
normal registered-Viewer dispatch. IR's library Viewer and NMR's entry Viewer
remain the owners of scientific presentation.

| Host Tcl signature | Exact result and limits |
| --- | --- |
| `getProviderCapabilities libraryType` | Flat scalar dict with schema `gxtxt.library_capabilities.v1`, provider/type/version, `supported_modes`, declaration source, `capability.*`, `extra_actions`, `extra.ID.*` and `registration.MODE.required/optional`. Does not probe a library. |
| `getLibraryCapabilities libraryId` | Same declaration plus current record policy/status, effective `action.*` flags, `reason.*`, `library_id` and SHA256 of exact current registry bytes. Absent provider gives explicit unavailable status with inspection/refresh/unregistration availability; it is not an empty successful query. |
| `libraryCatalogPage ?options?` | Options dict: `mode all|managed|external|remote` (default all), `query` (default empty, at most1024 characters), `offset` (default0, nonnegative integer), `limit` (default100, 1–200). Result: schema `gxtxt.library_catalog_page.v1`, registry SHA, mode/query/offset/limit, total/count and `records` list of public record dicts. Filters active installed records by ID/name/type/origin/provider; single registry read. Each public record is bounded to128KiB. No scientific entry search. |
| `openLibraryViewer libraryId ?context?` | Optional context dict accepts only `entry_id`. Current capability/policy checked; explicit entry must belong to the managed library. Prefer actual descriptor `library_viewer_module/id`; otherwise use declared entry Viewer and the first actual managed entry if no explicit entry supplied. Result dict: `status opened`, `dispatch_kind library_viewer|entry_viewer`, library/entry IDs and public `viewerOpen` result. Missing/unsupported/unavailable/auth-blocked actions error. |
| `invokeLibraryAction libraryId actionId ?parameters?` | Only a currently declared, enabled provider extra-action ID; defaults empty dict. At most32 safe parameter keys, each value at most4096 characters. Calls the provider's fixed `library_action` hook, returns at most128 scalar fields/128KiB plus actual library/action/provider IDs. No arbitrary function name. |
| `libraryRequest operation arguments callback` | Returns the existing ScriptJob asynchronous request ID. Callback receives common `ok` plus `result` or `error` response. Fixed operations listed below; `arguments` is the operation's positional list, not shell text. |

`apiInfo` retains version1/registry1 and additionally advertises the capability
schema, exact operation list and `script_exposure host_module_only`.

`libraryRequest` accepts `catalog_page`, `library_capabilities`,
`provider_capabilities`, `library_action`, `info`, `entries`, `verify`, `install`,
`update`, `remove`, `register`, `unregister`, `provider`, `types`, `open`.
`catalog_page` positional arguments are mode/query/offset/limit;
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
managed entry consultation shows at most1000 IDs with explicit shown/total count.
No search/mutation is implied. Raw facts are labeled registry.*; operational
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

## Step3 normalized content operations (dev110 candidate)

This additive v1 contract extends the existing Python/Tcl manager. MAIN's
independent proposal review accepted the bounded content/provider design; actual
release/milestone acceptance remains separate. Ordinary scripts remain excluded:
`apiInfo` continues `script_exposure host_module_only`. No Step4 binding,
credential facility, provider registry or scientific store is added.

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

New managed content reads reuse existing package/payload SHA, provider scientific
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

The helper's fixed CLI is `python3 -B scientific_library_manager.py content`,
reading that same3-item Tcl list from stdin. Successful and failed content use a
single C/base64 record containing the finite recursive Tcl response schema;
CLI failure exits nonzero, while managed-worker transport carries the result to
the facade's decoder. No provider payload is required in argv. All old F/L/M/P/D
wire and old public method signatures remain unchanged. `listLibraryEntries`
remains the accepted managed-only ID-list route; use libraryEntriesPage for the
new normalized all-mode operation. Existing --request operations still decode
through their old paths.

### Developer evidence and remaining acceptance

`validation/task210/library_step3/` records purpose/arguments/version/sideeffects
in CATALOG_ADDITION.md for MAIN's operational catalog. It installs a real
synthetic generic-science fixture through existing managed lifecycle, exercises
actual external mutable/read-only and controlled remote dispatch, and runs the
actual sync facade plus existing scriptJobAsync pipes/callbacks. Typed JSON
roundtrip, normalized failures, pre/post integrity, mutation ambiguity, legacy
wire and final response bounds are developer-checked. These checks do not prove
production remote service, domain IR/NMR, GUI or ordinary Script Bridge support.
MAIN retains integration and Step3 milestone acceptance. Steps4–7 remain ordered
unfinished work; no Step4 exposure or credential mechanism is inferred here.
