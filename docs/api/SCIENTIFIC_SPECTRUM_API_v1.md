# Scientific Spectrum API v1

SPDX-License-Identifier: GPL-3.0-or-later

CORE owner `core/tcl/scientific_spectrum_api_v1.tcl`, namespace
`::GX::SpectrumAPIv1`, defines an inert one-dimensional `spectrum.scientific`
value. It does not import files, publish Datasets, convert units or validate a
domain-specific measurement by itself.

| Public signature | Required arguments / result |
|---|---|
| `apiInfo` | none; dict with api_name SCIENTIFIC_SPECTRUM_API_v1, api_version1, contract spectrum.scientific |
| `create fields` | required Tcl dict; returns normalized/derived Spectrum dict below |
| `validate spectrum` | required Spectrum dict; returns1 or raises an explicit mismatch/error |
| `axisInfo spectrum` | required validated Spectrum; returns sample_count, x_ordering, x_min, x_max, x_quantity, x_unit, y_quantity, y_representation, y_unit |

No optional positional arguments/defaults exist. `create` requires nonempty
spectrum_id, display_name, spectrum_kind, x_quantity, x_unit, y_quantity,
y_representation, y_unit, x and y. Use an explicit unit token such as `1` for
dimensionless data, not an empty unit field. x/y are Tcl lists of equal length,
at least2 samples, converted to finite Tcl doubles. X must be strictly increasing
or strictly decreasing, without duplicates or direction reversal; irregular
spacing is allowed. Y need not be monotonic. No resampling or reordering occurs.

Optional fields metadata and provenance default to empty Tcl dicts and are
checked as dicts. source_identity, source_hash and entity_id default to empty
strings. The result contains those fields, the eight required identity/meaning
strings, normalized x/y, contract spectrum.scientific, sample_count,
x_ordering ascending/descending, endpoint-derived x_min/x_max and spectrum_hash.
Unknown caller fields are not copied into the result.

The numerical SHA-256 hashes LF-separated spectrum_kind, x_quantity, x_unit,
y_quantity, y_representation and y_unit followed by each paired double formatted
with %.17g separated by a tab. Identity/name/provenance/metadata are excluded;
sample order is retained. This detects matching represented traces, not
equivalence under unit conversion, reversal or scientific preprocessing. Hashing
uses a temporary UTF-8 file which is removed by the owner; the value is not a
managed Session resource.

`validate` rebuilds the value and requires exact string equality for
sample_count, ordering, min/max and hash, plus the exact contract. It does not
prove source_hash against an external file, resolve an entity, validate the
meaning/unit strings in a Unit Registry or measure uncertainty. `axisInfo`
performs that same validation first. Units remain explicitly supplied scientific
labels; domain conventions and any controlled conversion belong to their owner.

Synthetic in-memory host example, not an executed scientific test:

```tcl
set s [::GX::SpectrumAPIv1::create [dict create \
    spectrum_id synthetic display_name {Synthetic trace} spectrum_kind example \
    x_quantity frequency x_unit Hz y_quantity amplitude y_representation linear \
    y_unit 1 x {1 2 4} y {0 1 0}]]
set axis [::GX::SpectrumAPIv1::axisInfo $s]
```

No Session/Tk is required for these value operations. The owner declares no
maximum sample count, streaming API or independent precision/coverage guarantee;
values are materialized lists and hashes. Errors identify missing fields,
malformed dict/list, nonfinite values, sample mismatch, duplicate/nonmonotonic
X, wrong contract or derived-field mismatch. There is no result-wrapper schema
for failure beyond the actual Tcl error.

This family has no registered Python/Octave Script Bridge operation or typed
C++ SDK method in the retained binding/current SDK scope. Catalog presence is
not language admission, and no generic C++ invoke exists. Import and normal
Session publication are separate
[Spectrum Import](SCIENTIFIC_SPECTRUM_IMPORT_API_v1.md) and
[Spectrum Session](SCIENTIFIC_SPECTRUM_SESSION_API_v1.md) contracts. Numerical
normalization/hash validation is not independent scientific validation.
