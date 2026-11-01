# IR Reference Library Type Provider

SPDX-License-Identifier: GPL-3.0-or-later

This independently installable GX-TXT module registers the
`spectroscopy.ir.reference` Scientific Library type. CORE owns package
integrity, managed storage, the registry and install/update/remove lifecycle.
This provider validates IR spectral meaning, checks stable spectrum IDs, and
exposes reference spectra. It contains no bundled library data.

Install the provider through Plugin Install API v1. Install compatible data
packages separately through the Scientific Library Manager. The IR Viewer
consults references through its shared Browser; installation and maintenance
remain Manager responsibilities.


Version1.1.0 targets the complete DEV111-P025 framework, including its shared
normalized-content adapter. The base-version package constraint alone does not
establish patch compatibility; do not overlay this package on an older dev111
root that lacks the P025 adapter.

P025 version1.1.0 adds normalized managed consultation through Scientific Library
Manager `libraryEntriesPage`, `getLibraryEntryInfo`, `searchLibraryEntries` and
`readLibraryEntry`. The original scientific validator and spectrum reader retain
all numerical/units/metadata/provenance semantics. Pages are bounded and sorted
by stable spectrum ID, with continuation bound to content hash and exact query.
Search is literal case-insensitive SQLite substring search over IDs/compact
metadata, not scientific ranking. The `read_entry.payload` is the complete legacy
`read_spectrum` result (tuple arrays become JSON lists in the existing CORE wire).
The shared adapter resolves true managed storage through the existing manager,
uses read-only SQLite and creates no aliases, conversion or source cache.

The source remains immutable; external/remote specialized spectroscopy access is
not added by this adapter. Explicit policy permits consultation; free-text license
metadata never creates export/redistribution permission. Normalized export and
mutation stay unavailable. Existing specialized Viewers, managed package admission,
activation and legacy spectrum access remain unchanged.

Normalized reads are bounded by the existing CORE transport. Full reads through
32768 samples retain the complete legacy payload. Larger spectra require explicit
provider options `start` and `count` (zero-based, count0..32768, within the source).
The returned outer `metadata.read_range` records start/count/total; original
scientific fields including source sample_count stay unchanged, and X/Y contain
exact requested source samples. No default read silently truncates a spectrum.
Reassemble adjacent explicit ranges when full large-array consultation is needed;
no general Table Stream, canonical Dataset or scientific engine policy changes.

Version1.2.0 selects the genuine Builder/C++ `viewer.ir_spectroscopy` provider
for normal managed Library opening. Its compiled compatible package must be
installed and enabled; otherwise normal capability discovery reports the
unavailable action explicitly. Library/Entry identities pass through the
reviewed shared read-only context, with exact current scope/revision/SHA checks.
No numerical adapter, Library payload, Registry schema, legacy data reader or
scientific provenance is rewritten by this routing change. Historical archives
remain immutable.

P035 shared Browser consultation uses the declared read-only normalized metadata
projection in `domain_schema.json`. CORE Manager owns package/payload verification,
paging and content admission. The Browser pins real Library/version/payload/schema
and entry SHA identities without copying arrays, manufacturing relations, or
turning the metadata projection into an acquisition/import format. Missing source-retrieval time is explicitly `not_recorded`; no installation or
content-call timestamp is substituted or used to change portable entry pins.

`MANAGED_REFERENCE_READ_API=1` explicitly admits read-only interoperability
with existing CORE Reference methods through the Scientific Library Manager.
No module receives a managed storage path or mutation grant.
