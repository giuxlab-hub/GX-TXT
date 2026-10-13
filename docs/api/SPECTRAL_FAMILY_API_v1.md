# Spectral Family API v1

`spectrum.family` is a CORE Dataset contract for a parameterized collection of complete measured spectra. It is distinct from `spectrum.scientific` (one spectrum), `spectrum.table` (the existing FFT type), and a calibration table. The implementation is `core/tcl/spectral_family_api_v1.tcl` and is available whenever the framework loads.

## Calls

- `::GX::SpectralFamilyAPIv1::create parameterQuantity parameterUnit members` validates at least two member dictionaries. Each member has a unique `member_id`, finite `parameter_value`, public Spectrum API v1 `spectrum`, and optional `source_dataset_id`.
- `::GX::SpectralFamilyAPIv1::publishSession session datasetId family` writes a canonical long table with `member_id`, `parameter_value`, `spectral_x` and `spectral_y` through Dataset Publication API v2. Every original Spectrum Dataset can remain separately addressable.
- `::GX::SpectralFamilyAPIv1::readSession session datasetId` reopens complete member curves, preserving order and checking monotonic spectral coordinates.
- `::GX::SpectralFamilyAPIv1::responseAt family x` returns a public `math.numeric` linear interpolation for every member, rejecting extrapolation.

All members must share spectrum kind, coordinate quantity/unit and ordinate quantity/representation/unit. Members can use distinct monotonic grids; interpolation occurs per member. The API does not fit a calibration, infer concentrations, or alter originals. It currently materializes complete curves in memory when reopened, so very large families need a later streaming path and measured performance work.
