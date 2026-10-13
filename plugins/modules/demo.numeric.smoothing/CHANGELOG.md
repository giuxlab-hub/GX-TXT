# Changelog

## 1.0.2 — GX-TXT 0.9.8.05

- Uses public plot.dataset variants and the shared numerical smoothing service.

## 1.0.1

- Added the corresponding portable Session Generator API v1 package.
- The generator imports into `GX-TXT Numerical Examples` as
  `Mathematics` → `Smoothing`.
- The generated ordinary Session contains deterministic
  `raw/smoothing_demo.csv`, scientific `metadata/ground_truth.txt`, and normal
  GX-TXT generator provenance.
- Updated the manual and integration tests to use the generated Session as the
  canonical demonstration source.
- No numerical smoothing algorithm or GX-TXT framework code was changed.

## 1.0.0

- Initial external release for GX-TXT 0.9.7.72.
- Added public `NUMERIC_API_v1` demonstrations for moving mean, moving median,
  Savitzky-Golay and local-polynomial smoothing.
- Added deterministic sensor-like demonstration data with a clean reference,
  seeded Gaussian noise and isolated measurement spikes.
- Added Dataset Publication API v2 output with reference, measured, smoothed and
  reference-error variables.
- Added RMSE, MAE, maximum absolute error, edge RMSE and interior RMSE
  diagnostics.
- Added four automatic module-owned Graph Provider outputs and cache-only
  rerender support.
