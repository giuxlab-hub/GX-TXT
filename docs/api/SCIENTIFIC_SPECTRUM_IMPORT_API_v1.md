# GX-TXT Scientific Spectrum Import API v1

CORE namespace: `::GX::SpectrumImportAPIv1`. `parseCsv path options` and `parseJcamp path options` return validated generic Spectrum dictionaries. `importOneToLibrary libraryId format path options` and `importBatchToLibrary libraryId jobs` store references; batch reports each file independently. `::GX::SpectrumSessionAPIv1::importExperimental session datasetId format path options` uses the **same parser** but publishes a normal `spectrum.scientific` Session Dataset with stable `spectral_x` and `spectral_y` variable IDs, leaving the source file unchanged.

CSV requires explicit `spectrum_id`, `display_name`, `spectrum_kind`, `x_quantity`, `x_unit`, `y_quantity`, `y_representation`, `y_unit`, `x_column` and `y_column`. Set `header=1` and header names or `header=0` and 1-based column indices. Set `delimiter` to `,`, `;` or `tab` (or `auto` for detection). Ambiguous scientific meanings are **never** inferred from magnitude. Metadata and provenance are optional Tcl dictionaries. X may be ascending or descending and irregular, but must be strictly monotonic; duplicates/non-finite values fail.

JCAMP-DX supports whitespace-delimited AFFN XYDATA, signed-packed AFFN XYDATA as in the real OpenSpecy/PNNL nitrocellulose example, and numeric XYPOINTS/PEAK TABLE. It preserves XFACTOR/YFACTOR, explicit headers, source metadata and the detected numerical encoding. For `(X++(Y..Y))`, the physical grid is `FIRSTX + i*(LASTX-FIRSTX)/(NPOINTS-1)`; FIRSTX/LASTX are already physical coordinates and DELTAX is nominal. Both AFFN row styles check scaled row anchors against the grid using the existing rounding tolerance `max(abs(step)/2,0.02)` in declared X units; compact metadata records the policy, step, anchor count and maximum discrepancy. Original rounded anchors remain in the SHA-pinned RAW. This decodes the declared format; it does not resample explicit XYPOINTS/PEAK TABLE pairs or sort data. Explicit pairs retain table XFACTOR/YFACTOR scaling and order. The physical wavelength unit aliases MICROMETERS/UM and NANOMETERS/NM map to `um` and `nm` without coordinate conversion. See the [JCAMP-DX 1988 specification](https://iupac.org/wp-content/uploads/2021/08/JCAMP-DX_IR_1988.pdf), sections 5.1.1, 6.2.3, 6.2.5, 6.3.2 and 6.4.2. Compressed SQZ/DIF/DUP and multi-block files are rejected explicitly in v1, rather than being misparsed. An unsupported unit also fails and requires a controlled conversion or user-provided documented mapping. This is a scoped importer, not a claim of full JCAMP conformance.

Native Acquisition producers can reuse this exact parser through additive,
explicitly admitted `ACQUISITION_HANDLER_PLUGIN_API_v1` operations:

```cpp
auto parsed = host.scientific_spectrum_parse(source_index, "jcamp", options);
auto page = host.scientific_spectrum_read(token.c_str(), offset, 2048);
```

Both return typed `gx::AcquisitionValue` objects. Parse returns `parse_token`,
`row_count`, `source_index`, `source_sha256`, `parser_sha256`, `fields`, `metadata`
and `provenance`. Read returns `offset`, `row_count`, `total_rows`, `eof` and two
equal-length numeric arrays `x`/`y`, in original decoded order. EOF reads at
`offset == total_rows` are empty. Unknown or foreign tokens refuse. The token is
valid only within the actual admitted request and grants no publication rights.

Before returning a token, CORE also delegates to the existing
`SpectrumImportAPIv1::parse` / `SpectrumAPIv1::create` value authority through a
fixed host-only `validateSource` projection over that same admitted source. This
preserves genuine finite, strictly monotonic 1D spectrum semantics and the
existing scientific value hash; duplicate/nonmonotonic X refuses without sorting
or altering source points. The source is independently SHA-checked before and
after this validation, then rechecked under the original SourceGrant. `fields`
also contains `sample_count`, `spectrum_hash`, `source_hash`, `x_ordering`, `x_min`
and `x_max`; `value_qualification` is `SCIENTIFIC_SPECTRUM_API_v1_VALIDATED`.
This qualifies a scientific value, not a canonical Dataset or publication.
An unavailable value owner explicitly refuses. The additional read/parse uses
the same maintained scientific owners; no validator or normalization engine is
copied into a module. Normal Acquisition and the public Development Test both
use the same projection, with host-captured source paths never sent to workers.

The format is exactly `csv` or `jcamp`. Options are the existing scalar text
fields `spectrum_id`, `display_name`, `spectrum_kind`, `entity_id`, `x_quantity`,
`x_unit`, `y_quantity`, `y_representation`, `y_unit`, `x_column`, `y_column`,
`header`, `delimiter`, plus bounded `metadata`/`provenance` text maps. CSV still
requires explicit scientific meanings and columns. CORE binds source identity
to the granted source index and request, computes SHA-256 of the exact bytes,
and refuses attempts to replace source provenance or original `jcamp.*` headers.
No filename, source path, executable, helper or parser selection is accepted.

Limits are 32 MiB per source, four parses and one million total samples per
request, 48 KiB metadata/options and 2048 rows per page. The existing SourceGrant
phase read budgets remain effective, so a large inspection may explicitly
refuse before import. Each exchange retains actual admission, cancellation,
Session and source identity checks. Normal Test/import completion rechecks full
reviewed source SHA-256 and pinned CORE decoder/bridge hashes before canonical
handoff. The worker receives neither source paths nor source FDs. These bounded
source-data pages are distinct from prepared output bytes, which remain under
the existing local typed-buffer policy. Helpers receive no new source grant.
The producer maps decoded values into its ordinary prepared outputs; normal
schema, contract, RAW retention and atomic publication owners remain in charge.
No Reference Library is populated by parsing.

Example:

```tcl
set options [dict create spectrum_id exp-1 display_name {Measured IR} spectrum_kind IR \
    x_quantity wavenumber x_unit cm^-1 y_quantity absorbance \
    y_representation absorbance y_unit 1 x_column wavenumber y_column absorbance delimiter ,]
set result [::GX::SpectrumSessionAPIv1::importExperimental $session exp.ir csv /path/to/exp.csv $options]
```
