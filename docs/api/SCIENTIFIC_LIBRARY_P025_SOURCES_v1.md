# Scientific Library P025 source and domain contracts

The public owner remains `::GX::ScientificLibraryManagerAPIv1`. The existing
intentional Python/Octave Script Bridge subset and its typed `result_json`
contracts remain unchanged. Declared capability, source permission and actual
runtime availability are distinct facts; a catalog row grants none of them.

## External and remote JSON sources

Install the data-only `library.reference.json_1.0.0.zip` provider through Plugin
Manager in a compatible complete P025 root. This is a client for explicitly
registered sources; no new server, registry or background mirror is installed.
The provider owns type `scientific.reference.json`. Its
[source schema and transport/cache contract](../../plugins/modules/library.reference.json/README.md)
defines all required source fields and permission flags.

Register a unique logical ID with `registerLibrary`, `mode external`,
`library_type scientific.reference.json`, `read_only 1`, an explicit admission
availability and `config.path /absolute/source.json`. Optional
`config.expected_sha256` pins that exact external document. For `mode remote`,
use `config.endpoint https://source.example/reference.json`; optional
`config.ca_file` supplies a trusted CA and `config.cache permitted` opts into
the source's cache policy. No credential, token or password belongs in those
fields. This provider does not implement remote authentication.

Registration, discovery and status do not probe network connectivity. A source
request returns the actual source ID/revision, document SHA, license and policy
reference. Every requested operation must be explicitly allowed by the source.
Export is a separate permission and returns JSON data, never a destination path.
Generic payloads stay typed and opaque; the provider performs no domain
validation, unit conversion, scientific ranking or numerical calculation.

Use the established asynchronous `libraryRequest content` route for network
work. Its managed request owns the 120000ms whole-process deadline and normal
cancellation/drain. Socket and body deadlines are narrower transport bounds;
the synchronous route has no universal DNS/header wall-time guarantee. HTTPS
verifies certificates and hostnames. Redirects and URL credentials/query/fragment
are refused. Plain HTTP is limited to an explicitly enabled literal loopback
fixture/service; it does not establish public-service transport acceptance.

The cache requires registration opt-in, positive source permission/TTL and
positive HTTP permission/TTL. Effective TTL is their minimum, capped at3600s.
Fresh data may be reused within that permission; changed source policy is seen
on revalidation. Expired data never substitutes for an unavailable source. ETag
304, no-store, corruption, policy withdrawal and source revision changes have
explicit behavior in the provider contract. Cache files are derived responses
outside canonical Sessions and library payload stores. They do not grant rights.

## Existing managed IR and NMR sources

The IR/NMR1.1.0 providers target the complete P025 shared adapter. Their base
package-version constraint alone does not certify an earlier dev111 patch.
Original package validation, immutable storage, `readLibrarySpectrum`, dedicated
Viewers, arrays, units, metadata and provenance retain their existing owners.

Normalized `libraryEntriesPage`, `getLibraryEntryInfo`, `searchLibraryEntries`
and `readLibraryEntry` now work for these managed types. Pages are sorted by
stable spectrum ID. Continuations bind the source content hash and exact query.
Search is literal case-insensitive metadata/ID substring search, without a
scientific match score. Source mutation and normalized export remain denied;
free-text license metadata is never interpreted as redistribution permission.

Full normalized reads through32768 samples return the original reader's exact
payload. Larger spectra fail with an explicit range instruction. Supply the
existing `provider_json` option with integer `start` and `count` (zero-based,
count0..32768, entirely within source bounds), for example:

```tcl
set options [dict create provider_json {{"start":0,"count":32768}}]
set result [::GX::ScientificLibraryManagerAPIv1::readLibraryEntry $library $entry $options]
```

The outer `metadata.read_range` records start/count/total. Original scientific
fields and source sample counts stay intact; X/Y contain exactly the requested
samples. No silent truncation, interpolation or resampling occurs. The existing
scientific reader still materializes one source spectrum before slicing: this
is a bounded response contract, not a bounded-reader-RSS claim. The existing
CORE node/byte limits remain enforced.

P025 validation uses actual bundled Cambridge24-entry NMR data, deterministic
IR data and explicit controlled external/TLS sources. These scopes do not
certify an arbitrary public/commercial endpoint, remote login protocol, new
external spectroscopy Viewer, other platform or owner installation. Consult the
independent P025 acceptance matrix for executed scopes and retained failures.
