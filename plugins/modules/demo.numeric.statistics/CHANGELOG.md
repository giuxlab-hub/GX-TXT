# Changelog

## 1.1.0 — GX-TXT 0.9.8.10-dev-097

- Uses the public CORE statistical interpretation API for scalar rows, statuses, units and reports.
- Preserves Dataset/statistic IDs and legacy metric keys; adds explicit status/reason/quantity columns and validated metadata to both Datasets.
- Reuses Numeric quartiles without a second computation and uses common typed transport for nonfinite values.
- Keeps relative weight units explicit and distinguishes singleton sample variance from population zero.

## 1.0.1 — GX-TXT 0.9.8.05

- Uses public plot.dataset variants and shared numerical reductions for summary views.

## 1.0.0

- Initial `demo.numeric.statistics` reference plugin.
- Added public Dataset descriptive and weighted statistics through `NUMERIC_API_v1`.
- Added explicit NaN/Inf policy and Dataset Selection support.
- Added long-form summary Dataset and graph/reuse series Dataset via Publication API v2.
- Added automatic mean/median graph and cache-only rerender.
- Added portable Statistics Session Generator package.
- Documented the current absence of standalone covariance/correlation operations in GX-TXT 0.9.7.82.
