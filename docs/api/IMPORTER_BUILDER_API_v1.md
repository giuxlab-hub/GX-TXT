# Importer Builder API v1

The existing CSV recipe editor persists `importers/<id>.ini` under the user's
GX-TXT configuration directory. Stable IDs, versions, filename matching, parser
settings, ordered column mappings, declared units, numeric scale/offset and
filename/header metadata remain portable INI data. This mode is distinct from
Acquisition plugin source-project authoring; it does not compile a plugin.

File contains New, Save, Duplicate, Import, Export, Remove and Close. Edit exposes
mapping add/edit/remove/reorder with a native table and retained advanced syntax
`column | Variable | unit | scale | offset`. Run contains bounded Preview, complete
parser Test and Cancel. View reloads the inventory; invalid definitions remain on
disk and their paths/errors appear in diagnostics. Changed drafts use
Save/Discard/Cancel on New, selection, Export, Import and Close. A stale Save or
Remove retains the draft and explains the conflict.

## Existing calls and additive CAS

`importerBuilderDefaults`, `Validate(definition)`, `Read(path)`, `Get(id)`,
`Reload()`, `Write(definition,path)`, `Save`, `Duplicate(id,newId)`,
`Export(id,path)`, `Import(path)`, `Remove` and `Test` remain callable. Tcl signatures:

```tcl
importerBuilderDescribe id
importerBuilderSave definition ?expected_sha256?
importerBuilderRemove id ?expected_sha256?
importerBuilderSnapshot definition ?source?
importerBuilderEffectiveSnapshot definition source
```

`Describe` returns `definition`, `file_sha256` and `contract_state`. Pass its file
SHA to Save/Remove. Pass `absent` for a new identity; collisions refuse. The GUI
always supplies this CAS value. Omitting it retains legacy last-write behavior;
it is not a stale-write guarantee. Mutation uses an exclusive per-target lock,
checks the supplied SHA and checks it again before replacing prepared Save data.
Unknown mapping keys refuse rather than disappearing on an INI roundtrip.
Read rejects links/hardlinks, files over1MiB, invalid UTF-8, malformed/duplicate or
unknown INI fields/sections and inconsistent mapping counts. Reload exposes
`::GX::importerBuilderDiagnostics` rather than silently deleting bad inventory.

Syntactically valid unavailable contracts remain Read/Edit/Save/Import-INI/Export data, with
`UNKNOWN_UNAVAILABLE`. Recipe INI Import also preserves this data. Scientific
Test/data execution refuses unavailable contracts or contracts not compatible
with `table.generic`; no known replacement is invented. Contract
compatibility uses the existing registry. Unit text remains explicitly declared;
there is no inferred source unit or implicit unit conversion. Numeric mapping
coefficients must be finite; an overflow from finite input refuses. Existing
scientific NaN/Inf payload policy is retained separately.

## Immutable definition and effective source receipts

`Snapshot` returns schema `gxtxt.importer_builder_request.v1`, full normalized
`definition`, `definition_json`/`config_json`, `definition_sha256`/`config_sha256`,
`science_json`/`science_sha256`, actual bundled `parser_sha256`, Python `codec` and
`contract_state`. Full hashes include all normalized fields. The science hash
excludes **only** cosmetic `name`/`description`; identity/version and every parser,
contract, mapping, encoding and metadata rule remain included. JSON is canonical
UTF-8, sorted and compact; these are content hashes, not mutable ID/version claims.
Supplying `source` also captures device/inode/size/nanosecond timestamps without a
full source read.

Python codec lookup and strict incremental decoding apply to source Preview,
header metadata and the same bundled canonicalizer. Unsupported or non-text
codecs refuse. Invalid bytes inside the bounded prefix refuse; only an incomplete
valid trailing character at its byte boundary is deferred. `EffectiveSnapshot`
reads at most64KiB, returns bounded `header_text` (at most32768 characters), source
identity, `prefix_sha256`, `digest_scope=prefix`, `header_complete`, resolved
`effective_delimiter` and `effective_config_json`/`effective_config_sha256`.
Original `definition.delimiter=auto` stays unchanged. Automatic selection reuses
the parser's first-physical-line count policy; an oversized incomplete first line
requires an explicit delimiter. Filename/header regex semantics stay Tcl's.
`importerBuilderMetadata` delegates to this decoder;
`importerBuilderMetadataFromText definition source header` applies the same rules
to an already captured header.

These inert receipts are available to the existing Acquisition authority for
request-admission and publication provenance. The CSV editor/Test itself neither
stages RAW nor publishes a Dataset. Actual Acquisition must pin the admitted
packet, source and effective settings through its existing transaction; this
frontend batch alone does not establish that integration.

## Managed Preview and complete parser Test

```tcl
set token [importerBuilderRequest preview $definition $sample done progress]
# Or operation test. progress is optional.
# done receives: token response (ok/result or ok/error).
# progress receives: token event (phase, rows and available byte progress).
importerBuilderRequestInspect $token
importerBuilderCancel $token
```

At admission the request freezes normalized definition/config/parser SHA and source
identity. A changed source or parser refuses. Preview reads at most65536 source
bytes, exposes at most30 physical source lines and parses at most12 canonical
rows with the **same** canonicalizer. Incomplete last physical lines do not become
successful scientific rows. The result is `PREVIEW`, not complete validation;
truncation or inability to complete a bounded parse is explicit. Its digest is
only `prefix_sha256`; `source_sha256` is empty.

Test streams the full source SHA, reuses the same open inode and validates all
parser rows/mappings/decoding/finite coefficients, rechecking source identity.
Only a64KiB canonical display sample is retained while the rest is discarded.
Its `PASS` means **CSV parser validation**, not full scientific Contract/Variable
Schema or publication acceptance: those remain the actual Module/Session owners.
No test Session or canonical Dataset is fabricated. The complete result includes
full `source_sha256`, `digest_scope=full`, parser rows/kinds, original/effective
configuration hashes and bounded samples. Metadata capture uses the captured
source path/header, never later edits of the UI.

The fixed CORE worker uses existing ScriptJobAsync, process-group cancellation and
Resource Management temporary allocations; authored command strings are not
accepted. Requests have1MiB control,4MiB response,512MiB address-space/600CPU-second
worker bounds,1hour managed timeout, bounded
progress records. At most8 active or not-yet-released requests are admitted;
completed records retain at most16 full packets/results after successful cleanup.
Cancellation and failed/obsolete windows retain cleanup
ownership until worker completion. Inspect reports allocating/running or terminal
completed/failed/cancelled, immutable packet, response and asynchronous cleanup
receipt. `importerBuilderRequestForget(token)` succeeds only for a terminal
request whose allocation is absent or successfully cleaned. Pending/recoverable
cleanup cannot be forgotten. The explicit `cleanup_failed` state keeps its original terminal status.
Cleanup failure keeps a compact resource identity
and bounded diagnostic, drops full source/config/result payloads and occupies an
unreleased slot; `importerBuilderRequestRetryCleanup(token)` retries that same
Resource Management allocation. It is transient interpreter state, not another job or Dataset store.
Legacy `importerBuilderTest(definition,sample)` waits on this same managed path;
the GUI exclusively uses the asynchronous interface.

Recipe/source identity transitions (New, selected recipe, Duplicate, Import,
Remove, source chooser **or direct source-entry edits**) retire the pending
request token/generation. Obsolete callbacks cannot fill the new context.
Draft-only edits within the same identity retain a clearly labeled captured
recipe ID/source basename and `STALE_DRAFT` result; they never become a new
scientific read silently.

## Responsive bounded inventory

`importerBuilderReloadAsync(callback,?progressCallback?)` uses the same callback,
Inspect/Cancel/Forget/cleanup interface. It captures the inventory root inode and
four fixed source-owner SHA pins (CSV API, fixed Python worker, fixed Tcl inventory
helper, existing INI owner). Those pins/root identity are checked before and after
reading. The fixed Python envelope invokes only the trusted
`core/tcl/importer_builder_inventory_request.tcl` entrypoint in its existing managed
process/group. That helper reuses actual Read/Describe/parseIni. There is no second
INI parser or authored command input.

Enumeration reads at most64 recipes and considers256 directory entries, with one
bounded overflow lookahead. Receipt data has a2MiB aggregate limit. Truncation is
explicit in `result.truncated` and a visible diagnostic; remaining files are not
read and no total omitted count is invented. Results contain captured definition
and file-SHA receipts plus malformed/overflow diagnostics. The GUI performs Reload
asynchronously and selects these captured receipts without Python forks per click;
CAS still refuses if a file changes later. A newer draft arriving during explicit
Reload remains in the editor. Legacy synchronous `importerBuilderReload()` remains
for compatibility; it is not used by the GUI inventory/selection path.

RAW bytes, normal generic-CSV batch routing, publication/rollback, Contract Registry,
Variable Schema, Session/Group authority and the ordinary Module writer remain
with their existing owners. No new script filesystem/publication capability is
granted by these host-side functions.
