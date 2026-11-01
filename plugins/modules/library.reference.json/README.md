# Scientific JSON Reference Source 1.0

This independently installable, read-only provider serves
`scientific.reference.json` through the existing Scientific Library Manager.
It accepts an external local JSON document or an HTTPS endpoint; no data is
bundled. Scientific payloads are returned as typed JSON values, without claiming
domain validation or performing numerical processing. IR/NMR scientific meaning
remains with their own providers. Credential profiles and remote authentication
are not supported by this provider.

Register with `library_type scientific.reference.json`, a unique logical
`library_id`, `mode external|remote`, `read_only 1` and `availability available`.
The latter is an explicit registration admission value, not a remote probe or
connectivity certificate: the manager marks its status as unprobed registration
metadata, and only an explicit content request performs transport. Discovery and
registration never contact a source. External config requires an absolute
`config.path`; optional `config.expected_sha256` pins the document. Remote config
requires `config.endpoint`, optionally `config.ca_file` for a trusted CA file and
`config.cache off|permitted` (default off). HTTPS validates the certificate and
hostname. All redirects, URL userinfo, query strings and fragments are refused.
No passwords, tokens or credentials belong in registration metadata. An explicit
`config.loopback_http 1` permits HTTP only for a literal loopback IP, for local
controlled services/testing; it does not disable HTTPS verification.

The exact source document is:

```json
{
  "schema": "gxtxt.scientific_reference_source.v1",
  "source_id": "published-source",
  "revision": "immutable-revision",
  "license": "source-provided license",
  "policy": {
    "policy_reference": "source:permission-revision",
    "operations": ["list_entries", "entry_info", "search_entries", "read_entry"],
    "cache_allowed": false,
    "cache_max_age_seconds": 0
  },
  "entries": [
    {"entry_id": "stable:entry/1", "metadata": {}, "provenance": {}, "payload": {}}
  ]
}
```

All top-level and entry fields shown are required. Policy operations are an
explicit subset of `list_entries`, `entry_info`, `search_entries`, `read_entry`,
`export_entry`; unknown operations fail. Policy cache fields default false/zero.
The provider never infers permission from free-text license/rights. The source
must grant `export_entry` separately; JSON is the only export format and returns
data rather than writing a destination. Consultation does not imply export.

Source order is retained. Pages have at most200 entries and a continuation bound
to the source identity/revision and exact query. Search is literal case-insensitive
text over entry IDs and compact metadata; no scientific scoring is invented.
Changing a source revision invalidates its old continuation. Returned provenance
preserves entry metadata and adds actual source ID/revision/license/policy and SHA-256 of the exact response bytes.

Source documents are at most8MiB/20000 entries/100000 JSON values/depth32.
Duplicate object keys, nonfinite JSON, duplicate stable IDs and malformed policies
fail. External reads require a regular nonsymlink final file and a stable read.
Network socket/handshake operations use5second timeouts. Body transfer uses
read1 (at most one receive) with each socket timeout reduced to the original
5second deadline's remaining time; a slow-drip body cannot renew that deadline.
DNS resolution and response-header parsing in the standard HTTP opener do not
have a certified end-to-end5second wall bound. Use the existing asynchronous
CORE `libraryRequest content ... callback` route for remote sources: its existing
120000ms managed-process deadline/cancellation owns the whole request, including
DNS/headers. Synchronous host calls retain their existing blocking semantics;
no separate alarm, worker manager or process owner is introduced. The existing
managed request also owns final envelope limits. HTTPS production-service, certificate infrastructure, hostile server and
remote authentication acceptance require their actual environments.

Caching is opt-in at registration **and** requires source `cache_allowed=true`,
a positive source TTL and an HTTP `Cache-Control: max-age` without no-store,
no-cache or private. Effective TTL is the smaller permission/HTTP TTL, at most3600s.
A SHA-bound whole response is stored in a private0700 per-provider cache directory
under XDG_CACHE_HOME;0600 files bind the entire registration identity. At most64
cache entries are created, with no background mirror/sweep. Fresh permitted data
may be reused until that explicit TTL; source policy changes are observed at the
next revalidation. Expired cache uses `If-None-Match` when a valid ETag exists.
304 revalidation still requires positive cache headers; no-store/policy withdrawal
removes the entry. Transport failure never returns expired data. Cache corruption
cannot authenticate a body: it is discarded and a full source request is made.
This cache is a permitted derivative, never a canonical scientific Dataset.
