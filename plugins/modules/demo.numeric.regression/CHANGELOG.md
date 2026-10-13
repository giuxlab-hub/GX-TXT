# Changelog

## 1.0.1 — GX-TXT 0.9.8.05

- Completes the public plot.dataset graph path for all regression views.

## 1.0.0 - GX-TXT 0.9.8.05 integration

- Moved all six graphs to public persistent Plot.dataset variants.
- Published a coefficient Dataset for graphing and reduced the rerender cache to Dataset identities and display metadata.
- Fixed the rerender launcher to load CORE I/O APIs.

## 1.0.0

- Initial external `demo.numeric.regression` release for GX-TXT 0.9.7.72.
- Added Dataset-native OLS and WLS polynomial fitting through `dataset_polynomial_fit`.
- Added linear-regression and least-squares public-API consistency checks in linear mode.
- Added polynomial model evaluation, residual statistics and coefficient diagnostics.
- Added optional Dataset Metadata truth-coefficient support without metadata dependency.
- Added Dataset Publication API v2 result publication.
- Added six automatic Graph Provider outputs and cache-only rerender.
