# Scientific Spectrum paged value validation v1

The existing `SCIENTIFIC_SPECTRUM_API_v1` owner additionally exposes the trusted
host operation `::GX::SpectrumAPIv1::validatePages fields count readerPrefix`.
`fields` contains `spectrum_kind`, `x_quantity`, `x_unit`, `y_quantity`,
`y_representation`, `y_unit`. `count` is an exact integer from 2 through 536870912;
the admitting source/storage owner normally imposes a smaller byte/count limit.
The trusted reader receives `offset count`, at most 4096 samples per call, and
returns exactly `{x X_values y Y_values}` with that many actual samples.
This callback is not a Script Bridge, native SDK or arbitrary filesystem grant.

`create` and `validatePages` share the same finite-value and strict-monotonic-X
implementation and numerical hash writer. A duplicate or reversal across page
boundaries refuses. The result contains `sample_count`, `spectrum_hash`,
`x_ordering`, `x_min`, `x_max`, without retaining whole X/Y arrays. Hash semantics
remain the original six semantic lines and normalized binary64 values formatted
at 17 significant digits. This numerical hash is distinct from exact typed
payload SHA-256 and does not replace its integrity authority.

Generic Acquisition prepared publications requesting `spectrum.scientific` must
declare those six fields plus `spectral_x_variable_id` and
`spectral_y_variable_id` in `definition.structured_metadata`. The IDs must select
different real rank-one arrays of equal length on the same dimension. X has
`coordinate_role=coordinate`; Y explicitly references X in
`coordinate_variable_ids`; units exactly match the two actual Variable schemas.
Existing dtype, shape, staging and producer-capability checks still apply.

CORE qualifies the sealed buffers through this shared owner before Publication,
checks their exact SHA before/after, and retains those pins for publication.
The existing typed decoder supplies actual promoted float32 values for scientific
hashing. Its optional `formatFloating=0` mode avoids decimal presentation rounding;
the previous default float32/float64 textual formatting is unchanged. Integer
payload bytes remain exact; the Scientific Spectrum value/hash retains its
existing binary64 numeric semantics.

The definition receives the five result fields and
`spectrum_value_validation=SCIENTIFIC_SPECTRUM_API_v1_VALIDATED`; conflicting
producer-supplied values refuse. This describes qualification at publication
time, not a transferable capability or a replacement for current canonical
payload/schema/metadata revision checks. RAW, module and calibration provenance
retain their existing Acquisition owners. No vendor-specific branch, parser,
coordinate conversion, interpolation, Dataset writer or cache API is introduced.
Other contracts continue through their existing validators unchanged.

Qualification failure precedes any scientific publication. Later sealed-buffer
failure uses the existing Dataset Authority outer transaction to roll back all
outputs in the batch. Full native/vendor, cold Session and real-GUI acceptance
remain separate from synthetic author verification of this host interface.
