## 1.1.2

- Open standalone runtime Session and inspect Dataset provenance through supported public APIs.

# Changelog

## 1.1.1 — GX-TXT 0.9.8.10-dev

- Aligned the module version after the GX-TXT 0.9.8.09 runtime correction; scientific behavior is unchanged in this stabilization block.

## 1.1.0
- Removed the module-private Octave renderer, rerenderer and render cache.
- Migrated family overlay, calibration/validation and residual graphics to persistent `plot.dataset` variants.
- Uses public `series_family_grouping` to render the canonical Spectral Family directly without per-curve data duplication.
- Preserved public NUMERIC_API use for regression, interpolation/resampling and peak detection.
- Publishes a derived blank-corrected family only when blank subtraction actually changes the scientific spectra.
- Added package/static/reference tests and explicit numeric-vs-analysis architecture documentation references.
