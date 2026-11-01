# Scientific Library Domains / Sources API v1 (P028)

The existing Scientific Library Manager remains the sole registry, immutable
package installer, provider admission and protected credential owner. These are
additive host operations in `::GX::ScientificLibraryManagerAPIv1`; they do not
extend the Script Bridge grant. Library population creates no Session Datasets.

`getDomainSchemas` returns the installed versioned domain catalog.
`listSourceConnectors` returns connector declarations without network requests.
`searchAcrossLibraries parametersJson`, `relatedEntries parametersJson`,
`importLibraryRecords parametersJson` and `domainRequest operation parametersJson`
accept explicit JSON objects so numbers, booleans and nested domain values retain
their types. Every result includes authoritative `result_json` and a recursive
Tcl dict projection. Async `libraryRequest domain {operation parametersJson}
callback` uses existing ScriptJob process, deadline, cancellation and UI lifetime.

Finite domain operations:

| Operation | Parameters | Result |
| --- | --- | --- |
| schemas | `{}` | qualified record/relationship schemas and provider version/SHA |
| connectors | `{}` | connector IDs, versions, supported Library types, authentication |
| search | query text, record_type, offset≥0, limit 1–100 | exact Library/Entry/revision/SHA, label, type |
| related | reference, direction incoming/outgoing/both, relation_type, source_id, offset, limit≤100 | typed assertions, evidence/why_related, resolution |
| detail | reference | exact typed fields/provenance and resource descriptors, bytes omitted |
| import | library_id, library_type, entries, display_name, expected_version | immutable Library transaction receipt; zero Session Datasets |
| import_bundle | bundle, selected_ids, destinations (type→Library ID) | per-Library commits with explicit completed/failed/partial receipt |
| manual_prepare | record_type, fields, source_id, label, entry_id, pasted_text, attachments, previous, raw_fields | schema-validated draft; no persistence |
| manual_import | manual_prepare fields plus library_id | actual immutable import receipt |
| stage | reference, resource_index (-1 structured record), output_dir | exact bytes in an existing host Resource Management allocation |

A reference pins `library_id`, `entry_id` and, for saved selections/edges,
`revision` and `content_sha256`. A changed/tombstoned/missing entry is never
silently rebound. A cross-Library relation includes a qualified relation type,
typed target anchor (`library_entry`, `canonical_dataset` or
`external_source_entity`), source identity, assertion kind (source/user/derived),
retrieval/as-of information and evidence. Library targets require exact Entry
revision and content hash; Dataset anchors require Session/Dataset/revision.
External references retain their qualified unresolved identity. No identity or
engineering equivalence is inferred from matching names or scalar properties.

Domain plugins declare `[library_domain_provider] api_version=1,
schema=relative.json`; schema `gxtxt.library_domain.v1` declares qualified
record_types, fields/type/required/enum, library_type, relationship from_types and
to_types. Display labels, paste-field mapping, content_contract and resource MIME
contract mappings are domain declarations. Unknown schemas/types and mismatched
relations fail. Several unrelated domains coexist with no Browser changes.

Each typed Library Type plugin uses existing `[library_type_provider]` and the
fixed normalized content hooks. Its payload is `gxtxt.library_records.v1` with
immutable entries, exact SHA and source provenance. All writes create a data-only
Scientific Library ZIP and invoke existing installLibrary/updateLibrary. Earlier
version payloads/packages remain retained. Explicit edits pin previous content
SHA, append previous entry history and increment Entry revision. Existing P027
managed spectral packages remain untouched. The SQLite relations index is a
derived, fingerprinted cache; immutable packages and the existing registry remain
authoritative. Search indexes metadata, never a second scientific store.

Sources declare `[library_source_connector] api_version=1,
entrypoint=api/connector.py, library_types=...,
authentication=none|protected_opaque_utf8`. Connector IDs identify service
adapters; multiple connectors can use one domain Library Type. Register a normal
remote Library with nonsecret `config.connector` set to an installed compatible
connector. Search/read use existing normalized content requests; only explicit
`importSourceSelection sourceLibrary parametersJson` persists reviewed entries.
Parameters: entry_id, selected_ids (1–100), destinations, optional
expected_source_sha256, download_assets and selected_alternatives (≤10 actual
source suggestions, no recursive fetch). Async operation is `source_import`.
Every Library commit has its own receipt; the multi-Library batch is not falsely
advertised as one atomic operation. Actual selected original files may be saved;
failed/missing files stay explicit external links. No trace or PDF is fabricated.

Credentials use existing protected profiles, opaque UTF8 accessor and fixed
provider authentication scope. Stage A works with no open Session. Configuration,
Library/profile generation and context lifetime/revocation still apply. Ordinary
module fields never accept secrets. Owner correction 2026-10-28 explicitly allows
necessary API key methods required by official providers, including transient TLS
query authentication. No secret/query URL is logged, retained in error text,
receipts, metadata, fixtures or saved source URLs; redirects are refused.

`domainApiInfo` describes `SCIENTIFIC_LIBRARY_DOMAINS_API_v1` as an additive
Manager-owned host contract. `resolveExternalId parametersJson` matches exact
qualified source_id/external_id/record_type and returns bounded pinned local
candidates; it never fuzzy-matches labels, contacts a service or rewrites an edge.
The Browser requires review before following an external identity candidate and
provides Back/Forward, source/type/direction filters and relation pagination.
Canonical Dataset anchors retain their exact Session/Dataset/revision reference;
opening that reference currently uses the named Session's existing Dataset
Browser, not implicit copying or revision retargeting.

A type may declare compatible `library_types`, a safe relative scientific
`validator` in its Domain provider, and explicit compatible prior schema SHAs.
Saved Entry domain-schema pins are checked on read. Unknown/incompatible provider
versions remain unavailable with original immutable packages preserved. The
index reports unavailable Libraries separately and still searches unrelated
available domains. `library.molecular.structures` is a dedicated installable
Structure Library Type; its Domain validator reuses existing `molecule_io` for
source SDF atom/bond/coordinate admission. Historical typed structure records in
`chemistry.records` remain an explicitly declared compatible storage type.

Domain field descriptors may declare labels, fixed editor kinds, choice values,
structured table columns and bounded manual templates. The generic manual form
uses these declarations for identity fields, editable original/numeric/unit/test
condition rows and local-file review. No vendor/source-ID branches or source API
calls are needed to construct, preview, cancel or save a manual record.

P028 continuation adds optional literal `scope` to the existing query, pinned
read/stage and manual operations, plus `scope_describe`. The exact five-axis
normalization, domain-provider/source identity meanings, pre-count paging,
source-preview and outside-link behavior are documented in
`SCIENTIFIC_LIBRARY_MANAGER_API_v1.md` under Declarative Library view scopes.
These selectors are reusable by arbitrary Viewer identities and new declared
domains; they do not create a registry, writer, scientific parser or access grant.

## Literal representation-dependent content contract (P033 additive)

A record definition may optionally declare `content_contract_by_field` with
exact keys `field`, `default`, `values`. `field` names its declared string enum
(1–32 distinct nonempty tokens, each at most128 characters); `default` is one
of those tokens. `values` maps every enum token, and no others, to a literal
Contract Registry ID (at most128 characters) or empty string. This is a fixed
data lookup, not a condition/expression, callback or contract registration.
The declared default must match the original fixed `content_contract` if present.
Provider discovery rejects malformed selectors. Unknown saved selector values
and an explicit entry contract contradicting the selection refuse. An absent
historical entry `content_contract` remains absent and valid.

`manual_prepare` uses the same selector: nonempty selection adds that contract;
empty selection omits the entry field. Definitions without this optional
vocabulary keep their prior fixed-contract behavior. Unknown future Dataset
contract identities are preserved as explicit metadata, never converted to
other known contracts or admitted as scientific values by this mechanism.

For example, `domain.scientific_spectra`1.1.0 retains the SAME
`scientific.spectrum` type: optional `representation` defaults to
`numeric_source`, selecting `spectrum.scientific`; explicit `description_only`
selects empty. Its numeric wrapper requires the old CSV/JCAMP fields and delegates
the unchanged scientific validator. Description-only metadata has no scientific
payload-validation claim, parser result or implicit Dataset. Seven distinct
provider-declared scalar/complex/ND/spatial/frame/temporal/general measurement
record types use the versioned `gxtxt.library_measurement_description.v1` object.
They preserve observed dtype/rank/shape/dimension/coordinate/component/unit/source
identity with bounded structural checks, without parsing or converting numbers.
The historical Library Type/storage ID, immutable records and original schema
SHA compatibility are preserved. See the provider README for exact fields.

Provider-declared `scientific.describes_dataset` and
`scientific.related_measurement` relations reuse existing typed anchors/evidence.
Exact canonical Session/Dataset/payload revision/SHA/contract pins are metadata
assertions; explicit Follow still uses the existing Dataset Viewer admission.
An unavailable target stays unresolved, and a relationship is not scientific
equivalence. This extension creates no Registry, source connector, ingestion
workflow, auto-population, Dataset writer or binary attachment promise.

Compatibility: CORE `domainApiInfo` advertises `literal_content_contract_selector_v1` for the additive literal selector. Description-only records require that P033 feature; the provider explicitly refuses their admission on earlier CORE code rather than accepting a misleading fixed numeric content contract. Existing numeric_source CSV/JCAMP entries retain the original validator and behavior. Schema discovery alone is not proof that an older host can admit every new representation.


P035 additive read-only normalized metadata projection

A non-typed managed provider may declare one `normalized_projection` per owned
Library type in its existing domain schema. Version 1 contains exactly
`api_version:1`, `fields` (1–32 field-name → literal dictionary-key paths),
`label_path` and `source_id_path`. Every path starts at `metadata`, has 1–8 literal
keys and is never evaluated. Declared field types are validated without coercion.
This consultation-only schema has no acquisition content contract, resource
mapping, scientific validator or executable adapter. Existing typed schemas and
source/manual import formats retain their original contracts.

CORE consumes only the existing Manager-normalized `list_entries`/`entry_info`
metadata; no arrays or storage paths enter the Browser. The Manager verifies the
immutable managed payload/package before and after the bounded snapshot, with
normal credential/capability/policy admission on each page, registry lock and
identity recheck. Totals, unique IDs, continuation progress, complete verified
entry-index parity, 100000 entries and 64 MiB metadata are enforced. Errors leave
an explicit unavailable-Library diagnostic, never a partial successful Library.
The existing disposable graph index is the only derived store.

Projected entries pin real Library/version, payload/package SHA, domain schema
SHA and exact metadata content SHA. Source provenance/rights remain attributed;
missing retrieval time is explicitly `not_recorded`, never replaced by the
installation or content-call time. Identical immutable packages preserve portable
entry pins across installations. No relations, canonical Dataset, scientific
arrays or acquisition representation are manufactured. Manual entry/edit/import
refuses projected schemas; the Browser omits them from writable schema choices.
Normal Manager package update/removal owns their lifecycle. Search, exact scoped
inspection and relation queries reuse the existing domain operations and guards;
this addition grants no Script/native mutation or filesystem capability.
