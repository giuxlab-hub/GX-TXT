# GX-TXT Scientific Reference Library API v1

CORE namespace: `::GX::ReferenceLibraryAPIv1`. Persistent references are user-owned and independent of Sessions. A library is a SQLite `.gxsrl` file under `$XDG_DATA_HOME/gxtxt_pipeline/scientific_reference_libraries` (fallback `$HOME/.local/share/...`), with indexed metadata, entity and spectrum IDs, and native IEEE-754 float64 X/Y payloads. Each library has a content hash; each spectrum has a scientific-data hash and a payload hash. The portable `.gxsrl.zip` includes a SHA-256 manifest.

Call `apiInfo`, `root`, `listLibraries`, `libraryInfo`, `validateLibrary`, `createLibrary`, `upsertEntity`, `listEntities`, `entityInfo`, `addSpectrum`, `listSpectra`, `spectrumInfo`, `readSpectrum`, `search`, `exportLibrary`, or `importLibrary`. The API returns Tcl dictionaries or stable ID lists. `addSpectrum` accepts a `::GX::SpectrumAPIv1::create` result and validates it before storage. The generic model does not require chemical fields; entity metadata may contain compound name, synonyms, CAS, formula, InChIKey, phase and other source-specific identifiers where actually known.

For historical reproducibility, `forkLibraryVersion sourceId newId newVersion` creates a new user-owned version without changing the source. `updateReference sourceId newId newVersion spectrum` replaces one existing Spectrum in a new version; `removeUserReference sourceId newId newVersion spectrumId` removes one Spectrum from a new version and only accepts a user-owned source; `updateLibrary sourceId newId newVersion info` applies controlled library metadata changes in a new version. The old library remains available with its original content hash. `removeLibrary libraryId` applies only to user-owned libraries and moves the file into a recoverable `removed/` directory rather than deleting it. All new-version target IDs must be distinct and absent. Avoid repointing historical analysis results at a new library ID.

Example:

```tcl
set api ::GX::ReferenceLibraryAPIv1
${api}::createLibrary [dict create library_id my-ir name {My measured references} version 1.0.0 owner user license {user-owned}]
${api}::upsertEntity my-ir sample-a [dict create display_name {Sample A} phase solid]
set spectrum [::GX::SpectrumAPIv1::create [dict create \
    spectrum_id sample-a-atr entity_id sample-a display_name {Sample A ATR} spectrum_kind IR \
    x_quantity wavenumber x_unit cm^-1 y_quantity absorbance y_representation absorbance y_unit 1 \
    x {4000 3500 1800 400} y {0.01 0.1 0.7 0.05} \
    metadata [dict create method ATR] provenance [dict create source {my instrument}]]]
${api}::addSpectrum my-ir $spectrum
${api}::validateLibrary my-ir
```

`createLibrary`, `addSpectrum` and `importLibrary` refuse duplicate library/spectrum IDs. Export/import refuse existing destinations and verify integrity. A source update should be built as a new versioned library in staging and validated before switching consumers; see `REFERENCE_DATABASE_UPDATE.md`. Direct SQLite edits are unsupported. Source-license obligations remain with the library owner.

## Full-library IR candidate prescreen (0.9.7.94)

`bulkRank libraryId processedSpectrum options` scans a validated `.gxsrl` through CORE's read-only, NumPy-backed matcher. `processedSpectrum` is a dictionary with strictly ascending, finite `x` and `y` lists already processed by IR Analysis. Options include `experimental_representation`, `range_min`, `range_max`, `normalization`, `step`, `method`, `fingerprint_min`, `fingerprint_max`, `fingerprint_weight`, and positive `limit`. The result gives `scanned`, `skipped`, and ordered candidate dictionaries with `spectrum_id`, `match_score`, `full_spectrum_score` and `fingerprint_score`.

This is a **candidate prescreen** for the simple no-baseline, no-smoothing, no-derivative IR path. IR Analysis 1.0.5 invokes it only for libraries with more than 100 spectra, then recomputes at least 30 shortlisted references using the existing public reference and numerical APIs. Other processing modes and small libraries use the original matching path. The shortlist is approximate; the final scores are exact for shortlisted candidates, but a global top-N guarantee is not asserted for every input. A same-trace 9,537-spectrum benchmark tests performance and retrieval, not independent identification accuracy. Library files and scientific payloads remain read-only during ranking.


P035 additive managed read interoperability (version1)

`managedValidateLibrary`, `managedLibraryInfo`, `managedListSpectra`,
`managedReadSpectrum`, `managedEntityInfo` and `managedBulkRank` take the same
logical identities/scientific arguments as their existing flat-root counterparts.
They consult only normally registered installed managed Libraries whose provider
explicitly declares `MANAGED_REFERENCE_READ_API=1`. Existing flat-root methods,
writers and saved-data compatibility remain unchanged; no alias/copy/import or
fallback to an unregistered path is performed by the managed methods.

Scientific Library Manager remains the location/registry/provider/credential/
read-policy/integrity owner. It holds its normal registry lock, verifies payload
and original package before/after each complete read/rank and rechecks the exact
registration. The existing Reference owner reads the selected immutable payload
with SQLite read-only/query-only access. No storage path is returned. Large
managed spectra require the existing bounded Manager range-read interface;
`managedReadSpectrum` caps complete reads at32768 samples. There is no new Script
Bridge or restricted native grant: native producers still use their separately
admitted scientific public host operation.

`managedLibraryInfo.version` is the actual managed package version;
`scientific_version` retains the payload's original scientific-data version.
`content_hash` remains the real scientific content hash, with separate
`managed_payload_sha256`/`managed_package_sha256`; these meanings are never
substituted. Managed bulk ranking invokes the unchanged existing CORE numerical
algorithm and result protocol, with the same full scanned/skipped counts. This
is source resolution/admission, not a second ranking engine.
