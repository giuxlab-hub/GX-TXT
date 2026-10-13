# GX-TXT Scientific Spectrum Import API v1

CORE namespace: `::GX::SpectrumImportAPIv1`. `parseCsv path options` and `parseJcamp path options` return validated generic Spectrum dictionaries. `importOneToLibrary libraryId format path options` and `importBatchToLibrary libraryId jobs` store references; batch reports each file independently. `::GX::SpectrumSessionAPIv1::importExperimental session datasetId format path options` uses the **same parser** but publishes a normal `spectrum.scientific` Session Dataset with stable `spectral_x` and `spectral_y` variable IDs, leaving the source file unchanged.

CSV requires explicit `spectrum_id`, `display_name`, `spectrum_kind`, `x_quantity`, `x_unit`, `y_quantity`, `y_representation`, `y_unit`, `x_column` and `y_column`. Set `header=1` and header names or `header=0` and 1-based column indices. Set `delimiter` to `,`, `;` or `tab` (or `auto` for detection). Ambiguous scientific meanings are **never** inferred from magnitude. Metadata and provenance are optional Tcl dictionaries. X may be ascending or descending and irregular, but must be strictly monotonic; duplicates/non-finite values fail.

JCAMP-DX supports whitespace-delimited AFFN XYDATA, signed-packed AFFN XYDATA as in the real OpenSpecy/PNNL nitrocellulose example, and numeric XYPOINTS/PEAK TABLE. It preserves XFACTOR/YFACTOR, explicit headers, source metadata and the detected numerical encoding; signed-packed rows are checked against the declared X grid. Compressed SQZ/DIF/DUP and multi-block files are rejected explicitly in v1, rather than being misparsed. An unsupported unit also fails and requires a controlled conversion or user-provided documented mapping. This is a scoped importer, not a claim of full JCAMP conformance.

Example:

```tcl
set options [dict create spectrum_id exp-1 display_name {Measured IR} spectrum_kind IR \
    x_quantity wavenumber x_unit cm^-1 y_quantity absorbance \
    y_representation absorbance y_unit 1 x_column wavenumber y_column absorbance delimiter ,]
set result [::GX::SpectrumSessionAPIv1::importExperimental $session exp.ir csv /path/to/exp.csv $options]
```
