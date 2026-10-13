# Storage Auto and Dataset materialization extension v1

Introduced in GX-TXT 0.9.7.26 as an extension of Canonical Dataset API v2 and Dataset Publication API v2.

## Policy

Hard requirements include chunk and range reads, chunk and append writes, random access, hyperslabs, multidimensional objects, groups, and implicit axes. Preferences are compact numeric storage, human readability, fast sequential access, random access, and compression. Required capabilities remove unsuitable providers; preferences score the rest. Policy v1 uses the stable tie order CSV then HDF5 and has no size threshold. Explicit CSV or HDF5 requests pass the same validation.

Dataset Publication v2 records requested storage, effective provider, provider version, and selection reason. Dataset access callers use datasetAccessRequest with capabilities_required, characteristics_preferred, storage, and chunk_rows. If the active representation satisfies the request, CORE uses it directly. Otherwise CORE selects and materializes a representation. datasetAccessDiagnostics reports the decision, rejection reason, reuse, hashes, and compatibility mode.

## Identity and lifecycle

A materialization is another representation of the same Dataset ID and Variable IDs. Its storage_object_id is separate and is never registered as a scientific result. The SHA-256 key covers Dataset ID, actual and declared payload hashes, normalized Variable Schema v3 state, target provider and version, representation format version, policy version, and conversion parameters. Notes and presentation-only metadata are excluded.

Caches live in session/cache/dataset_materializations/cache-key. They are reproducible, independently deletable, and optional. CORE builds in a partial directory under a single-builder lock, validates and closes the provider, hashes the result, writes metadata, and atomically places the directory. Missing files, hash mismatch, invalid HDF5, schema mismatch, and provider, format, or policy version changes trigger regeneration. A copied session remains valid with or without its cache.

## Generic conversions

The initial generic path supports registered flat-table CSV to HDF5 acceleration and losslessly table-shaped HDF5 to CSV compatibility. It uses Table Stream API v3 and Publication v2 writers in bounded chunks. Uniform coordinates stay implicit in HDF5 only when Schema v3 declares them; CSV writes them explicitly. No numeric pattern inference is performed.

CSV uses UTF-8, comma separation, doubled quote escaping, and Tcl round-trip numeric formatting. It does not reduce floating precision. Rank greater than one, inconsistent dimensions or lengths, and grouped objects without an explicit flat view are rejected. datasetCompatibilityCsv returns the managed compatibility path and diagnostics.

Cache recreation is storage diagnostics, not a scientific provenance step.
