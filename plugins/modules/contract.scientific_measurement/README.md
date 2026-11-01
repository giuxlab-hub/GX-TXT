# Ranked Scientific Measurement Contract

This installable service declares `measurement.numeric_array` through the
existing Contract Registry and `count` / `count/s` through the existing Unit
Registry. It adds no parser, publication engine, Dataset reader, renderer or
Library ingestion path. Declaration alone is not scientific validation.

The contract represents genuine typed real measurement arrays: images or
detector planes, frame sequences and other ranked measurements whose semantics
do not establish a more specific existing contract. Variables retain their exact
dtype, rank, shape, dimension IDs and column-major canonical order. Coordinate
variables retain their own dimension lengths and explicit association to the
signal. Frame axes remain independently addressable; a rank-three stack is never
flattened into unrelated tabular rows. Existing canonical schema, storage and
Publication owners validate those structures.

Producers must preserve source identity and SHA, original instrument labels,
calibration coefficients/policy, observed units, coordinate roles, frame/ROI/bin
information and any known correction/normalization. Unknown physical units or
time bases remain unknown, with a source pixel (`px`) or explicit frame index
where appropriate. Retain raw timestamps as source ticks when no time unit was
declared. A physical calibration requires explicit reviewed quantity and unit;
a grating/blaze label is not an axis unit. Arbitrary vendor header bytes are not
scientific Markdown metadata.

`count` describes an instrument count; `count/s` describes an instrument-declared
rate. Both are opaque units: they establish no photon calibration, dimensionless
ratio, absolute intensity, exposure time or automatic count/rate conversion.
Background correction is distinct provenance, never inferred from the unit.
The existing `px` unit belongs to CORE and is not redeclared here.

There is deliberately no parent `table.generic`, `image.raster`,
`spectrum.scientific` or NMR contract. Typed detector arrays are not opaque PNG
resources, and detector coordinates do not prove spectral calibration. Genuine
one-dimensional spectra continue using `spectrum.scientific`; genuine existing
time-series/families/NMR retain their established contracts. Consumers opt into
this contract explicitly and read through canonical numeric APIs. Scientific
plane display uses the existing canonical hyperslab and Native2D owner.
