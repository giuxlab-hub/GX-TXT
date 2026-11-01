# source.mouser Remote Library Importer

Independent Plugin Install API v1 package. Install with the existing Plugin Manager, or the supplied atomic Bundle v1 with declared companions. No network or scientific import runs on installation or catalog discovery.

This official Search API connector provides read-through visual consultation: exact supplier identity, manufacturer/MPN, technical property tables, actual media/document links and source-suggested alternatives when supplied. Source images are previewed only in memory; original document links open explicitly. API responses are not saved into persistent Libraries. Independently user-entered technical records and user-selected downloaded files use the separate curated offline manual window and remain persistent, independent of any Session. Credentials belong only to existing protected Library Credential profiles, never Module Configuration.

Official Search API/OpenAPI: https://api.mouser.com/api/docs/V1,
POST `https://api.mouser.com/api/v1/search/partnumber` with
SearchByPartRequest and exact partSearchOptions. Protected UTF8 profile contains
the issued API key. Owner correction 2026-10-28 permits necessary documented
`apiKey` in the transient TLS query. Request URLs/keys never enter logs, errors,
fixtures, metadata or saved URLs; redirects are refused. No cart/orders API.
Only explicitly selected source images are fetched from declared Mouser hosts into transient memory for display; no API-content cache or Library file is written.

Offline shape fixtures cover 568-NAC3F-TRUE1-CG and 579-25CSM01E/MS. They validate
parser/identity and shared Electronics schema, not authenticated live responses.
SuggestedReplacement(s), when actually supplied, retains Mouser's native claim;
no LCSC class or engineering equivalence is inferred. API-specific access or
content conditions remain connector-local; offline user files are independent.
Live authenticated test: NOT VERIFIED (no credentials supplied).

The published Search API Terms section4 at
https://www.mouser.in/en/apiterms/ prohibits storing API-transmitted content.
Consequently this particular API channel currently declares read-through
consultation and does not enable persistent API-content Library import or asset
caching. A separate documented authorized channel requires its own reviewed
adapter contract; there is no user checkbox that invents such authorization.
The real connector, parser, lookup/preview, protected API-key method, ordinary
installation and independent manual/local-file persistent Library workflows are
implemented and remain available. This restriction does not apply to all Mouser
web/downloaded user materials by inference. Owner decision 2026-10-28 explicitly confirms this read-through-only API behavior and the separate offline persistent manual workflow. No actual API credentials or Mouser live content was used in author tests. The existing protected duplex transport uses in-memory pipes/buffers, drains messages and removes request state on completion/cancel/close; no response log/spool is written by that path.

Version1.0.1 declares the exact emitted record types for declarative Library view scopes: `electronics.component`, `electronics.supplier_listing`, `technical.document`, `technical.media`. Provider IDs refer to their installed domain schemas. These metadata changes do not alter normalization, credentials, HTTP or storage policy. Source discovery never makes a network request.
