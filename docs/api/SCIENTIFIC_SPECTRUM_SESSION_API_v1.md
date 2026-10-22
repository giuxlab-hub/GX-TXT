# Scientific Spectrum Session API v1

SPDX-License-Identifier: GPL-3.0-or-later

CORE owner `core/tcl/scientific_spectrum_session_api_v1.tcl`, namespace
`::GX::SpectrumSessionAPIv1`, publishes a validated generic experimental spectrum
through the established Dataset Publication owner.

| Public signature | Required arguments / result |
|---|---|
| `apiInfo` | none; dict with api_name SCIENTIFIC_SPECTRUM_SESSION_API_v1, api_version1 and contract spectrum.scientific |
| `publishExperimental session datasetId spectrum` | explicit Session directory, desired Dataset ID and validated Spectrum dict; Dataset Publication v2 Finalize receipt |
| `importExperimental session datasetId format path options` | explicit Session/ID, parser format/path and required options dict; parses via SpectrumImportAPIv1::parse then calls publishExperimental |

There are no optional positional defaults. `options` must be supplied even when
empty is appropriate for a particular parser. The Session argument is normalized
and must be an existing directory with a metadata subdirectory; it is not
implicitly selected from an arbitrary Viewer window. Underlying publication
retains its normal Session/ID/contract/admission checks.

## Exact publication shape

`publishExperimental` first validates the complete
[Scientific Spectrum](SCIENTIFIC_SPECTRUM_API_v1.md) value. It prepares a
spectrum.scientific Dataset owned by acq.spectrum, storage auto, producer1.0.0,
with source_identity and Spectrum provenance. It opens the standard writer,
declares extendible `spectral_point`, and writes:

| Stable Variable ID | Shape/type | Unit and role |
|---|---|---|
| spectral_x | float64, rank-one spectral_point coordinate | Spectrum x_unit, name x_quantity, semantic_role independent |
| spectral_y | float64 on the same dimension | Spectrum y_unit, name y_quantity, semantic_role measured, coordinate_variable_ids spectral_x |

The full x/y lists are appended together. Written count must equal sample_count;
the actual writer is finalized only after that check, otherwise aborted and the
original error propagated. No manual CSV/file or separate Dataset registry is
created by this facade. Storage selection, replacement/ID conflicts and the
Finalize receipt's fields remain Dataset Publication v2's contract.

Provenance retains source_identity, source_hash, spectrum_hash, spectrum_kind,
x_quantity, y_quantity, y_representation, metadata and provenance. Original source
file bytes are not modified by this parsing/publication path. Units and meaning
are explicitly supplied/parsed, not inferred from numerical magnitudes. The
Spectrum value validator does not itself verify an external source_hash,
measurement uncertainty, instrument calibration or domain correctness.

## Import, errors and exposure

`importExperimental` uses the same parser as library imports. Supported CSV/
scoped JCAMP variants, explicit column/unit/meaning options, unsupported encoding
and conversion errors belong to
[Scientific Spectrum Import](SCIENTIFIC_SPECTRUM_IMPORT_API_v1.md). It does not
make a reference-library entry or import an entire Library registry. The facade
declares no new parser defaults, streaming/sample bound or automatic unit
conversion. Full arrays are materialized before the writer append.

Malformed/invalid Spectrum, missing Session metadata directory, unsupported
format/parser input, invalid Dataset identity/schema/units, writer failure or
incomplete append produce the actual owner error. No generic success wrapper or
independent accuracy/uncertainty result is fabricated.

This host family has no registered Python/Octave Script Bridge operation and no
typed C++ SDK method in the retained/current reviewed scope. No generic C++
invoke exists. Authors use the actual public language bindings of their admitted
Dataset/Import services; catalog discovery alone grants no filesystem/Session
write capability. See [Dataset Publication](DATASET_PUBLICATION_API_v2.md) and
[Variable Schema](DATASET_VARIABLE_SCHEMA_API_v3.md). This reference is
source-backed documentation, not a new publication/science test.
