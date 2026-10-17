# Changelog

## 1.1.0

- Public CORE statistical-result interpretation and publication metadata.
- Numeric-owned mean uncertainty; explicit sampling assumptions and undefined/unavailable states.
- Existing scientific variable IDs and historical releases preserved.

## 1.0.0

- Added production grouped descriptive statistics for one grouping variable and one or more numeric value variables.
- Added explicit NaN/Inf value handling and missing/invalid grouping-value handling.
- Added optional Dataset Selection support for `x_range` selections.
- Added normalized grouped-result Dataset Publication with stable source identities and provenance.
- Added a grouped plot-support Dataset and persistent `plot.dataset` variants for mean ± SEM, median + IQR, and group observation count.
- Added compatible-unit grouping for automatic plots through the public Unit Registry.
- Added deterministic tests and a ready-to-run student Session Generator.
