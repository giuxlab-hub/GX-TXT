# Scientific Library Source Connector API v1

`::GX::ScientificLibraryManagerAPIv1::sourceApiInfo` describes this additive
source contract; the existing Scientific Library Manager remains its sole
registry, request, credential and persistent Library transaction authority.

An independent ordinary module declares `[library_source_connector]` with
`api_version=1`, a safe relative Python `entrypoint`, compatible `library_types`,
`authentication=none|protected_opaque_utf8` and optional
`persistence=persistent|read_through`. The module exports fixed `CONNECTOR_ID`,
`search(query, limit)` and `read(entry_id, options)` hooks. Discovery imports no
remote content and makes no network requests. Multiple sources can share one
Library Type without registering duplicate Type providers.

Use `listSourceConnectors`; register a normal remote Library via `registerLibrary`
with nonsecret `config.connector`; use existing `searchLibraryEntries` and
`readLibraryEntry`. The fixed normalized read payload is a versioned source
bundle of typed entries, actual resource descriptors and source suggestions.
Connector/version, original source record SHA, exact upstream IDs, retrieval time
and normalization provenance are preserved. Unknown/changing identity/shape,
authentication, rate and missing content states fail honestly.

`importSourceSelection sourceLibrary parametersJson` is a separate explicit
Stage A transaction. It selects entries, source-bound review SHA, destinations,
optional selected source assets and at most10 reviewed actual source-suggested
alternatives. No recursive suggestions, automatic Dataset or implicit all-record
import. Result reports each Library commit and any failed/partial batch.

Read-through sources return `persistent_import_available=false` and a technical
reason; the generic Manager/Browser refuses only that channel's persistent
import. The source Inspector still shows typed actual fields and source media,
document and alternative references. Optional
`transient_asset_entry_id` in read options returns selected actual PNG/JPEG bytes
as bounded `preview_assets` with `availability=transient_memory`; the Browser
creates a temporary in-memory image and releases it on close. Actual document
links open only by user action. No API response or preview asset is written into
a Library, cache, log or staging file by this path.

The official Mouser Search API currently uses that read-through contract,
confirmed by owner decision 2026-10-28. Independent manual technical records and
user-obtained local files use the curated offline domain form, separate from API
responses and requiring no vendor credentials/network. Source conditions never
become a Library-wide gate or user legal attestation.

Existing protected profile/accessor/scope and ephemeral duplex request owners
handle credentials. Official API key authentication, including necessary
transient HTTPS query methods, is explicitly authorized by the owner's corrected
mandate. Keys never enter ordinary configuration, source metadata, diagnostics,
fixtures or stored URLs. Redirects and undeclared/nonpublic hosts are refused;
responses, timeouts and explicit request intervals are bounded. Protected duplex
transport uses in-memory pipes/buffers and consumes/removes request state on
completion/cancel/close. Connector code does not independently log/store requests.

Current modules: `source.pubchem`, `source.lcsc`, `source.mouser`. LCSC/Mouser live
authenticated integration remains NOT VERIFIED without issued credentials; real
adapters/packages/UI and deterministic fixture tests are provided. A fixture
never proves actual service availability.
