# Changelog

## 1.1.0 — GX-TXT 0.9.8.10-dev-097

- Publishes four CORE-interpreted pointwise error subsets with physical derivative/integral units.
- Uses public Numeric error reductions and CORE report formatting, retaining existing report and Dataset identities.
- Empty derivative interiors are undefined, with explicit status/reason fields rather than a zero error.

## 1.0.1 — GX-TXT 0.9.8.05

- Uses public plot.dataset variants and advertised numerical services for the calculus teaching graphs.

## 1.0.0

- Initial external `demo.numeric.calculus` release for GX-TXT 0.9.7.72.
- Uses public `NUMERIC_API_v1` Dataset operations `dataset_grid_info`, `dataset_differentiate`, `dataset_integrate` and `dataset_cumulative_integrate`.
- Uses the built-in `GX-TXT Numerical Examples → Mathematics → Calculus` Session Generator version 1.0.0.
- Resolves all selected inputs through Analysis Source and stable Dataset variable identities.
- Supports an optional public Dataset Selection `x_range` and applies the same selected range to numerical operations and analytical-reference comparison.
- Publishes a ten-variable `table.generic` derived Dataset through Dataset Publication API v2.
- Produces five automatic Graph Provider PNG artifacts and supports cache-only rerender.
- Keeps generator metadata optional: no direct metadata sidecar parser and no dependency on `metadata/ground_truth.txt`.
