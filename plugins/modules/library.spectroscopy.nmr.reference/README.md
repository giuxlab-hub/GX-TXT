# NMR Reference Library Type Provider

This provider validates managed `spectroscopy.nmr.reference` packages and exposes measured 1-D entries through the existing Scientific Library Manager. The included Cambridge package contains 24 real ¹H and ¹³C references from the University of Cambridge Apollo deposit, DOI 10.17863/CAM.130157, under CC BY 4.0. Each entry retains its original JCAMP-DX SHA-256 and processing details. The untouched source ZIP is preserved in Task 005 validation sources; the package stores a derived 1-D spectral representation.

Install `data/cambridge_co2_nmr_1d_1.0.0.zip` using the Scientific Reference Library viewer. The specialized NMR viewer owns chemical-shift presentation; the generic library browser shows library and entry metadata without NMR-specific fields.


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
