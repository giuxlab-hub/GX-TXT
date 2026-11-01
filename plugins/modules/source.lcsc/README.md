# source.lcsc Remote Library Importer

Independent Plugin Install API v1 package. Install with the existing Plugin Manager, or the supplied atomic Bundle v1 with declared companions. No network or scientific import runs on installation or catalog discovery.

Persistent Libraries remain independent of Sessions. Look up a source, review the selected records, then explicitly Import into Library. Later select individual entries/resources and use Import selected to Session; existing Acquisition handlers own RAW, SHA, publication and Dataset registration. Missing/disabled providers leave saved immutable packages intact and report unavailable capability. Credentials belong only to the existing protected Library Credential profiles, never Module Configuration.

Official interface: https://www.lcsc.com/docs/openapi/index.html Item Details
`https://ips.lcsc.com/rest/wmsc2agent/product/info/{product_number}` and
https://www.lcsc.com/docs/ authentication/header/error contract. Protected UTF8
profile contains JSON `{"key":"issued key","secret":"issued secret"}`. The
adapter signs the documented key/nonce/secret/timestamp plaintext with SHA1;
secret is never transmitted, and authentication headers are never persisted.
Catalog discovery makes no network request. Exact C-number lookup only; no bulk
mirror/order API. Public docs contain inconsistent printed example digest; the
implemented documented algorithm is independently checked, LIVE signing remains
unverified without issued credentials. Actual returned technical field aliases
are strict explicit adapter mappings; unknown shape or mismatched SKU fails.

Four offline shape/identity fixtures cover C19190834, C46528106, C14663 and
C561794. They are fixture parser checks, not captured authenticated responses.
ESR frequency is retained only when explicit in the supplier source. Source
record attributes are retained, offer facts separated from physical identity,
photo/datasheet/drawing links and exact optional suggestion classes preserved.
No SPICE model, equivalence or native footprint is invented. Selected asset
retrieval is bounded to declared LCSC media hosts; other links remain external.
Live authenticated test: NOT VERIFIED (no credentials supplied).

Version1.0.1 declares the exact emitted record types for declarative Library view scopes: `electronics.component`, `electronics.supplier_listing`, `technical.document`, `technical.media`. Provider IDs refer to their installed domain schemas. These metadata changes do not alter normalization, credentials, HTTP or storage policy. Source discovery never makes a network request.
