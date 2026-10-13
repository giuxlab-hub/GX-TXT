# Changelog

## 1.0.5

- Aligned the installed README correction with a unique development package version.

## 1.0.4 — GX-TXT 0.9.8.05

- Uses public plot.dataset variants for fit and residual views and public numerical fitting.

## 1.0.3

- Fixed Dataset-aware nonlinear fitting with imported canonical Datasets whose display/canonical variable names (for example `x` and `y`) differ from their stable `variable_id` values.
- The runtime now resolves Analysis Source bindings through `gxtxt_analysis_source_variable_meta()` and passes the resulting stable IDs to `NUMERIC_API_v1` and Table Stream API.
- Preserves canonical variable names separately for human-readable reports.
- Reference framework updated to GX-TXT 0.9.7.72.

## 1.0.3

- Fixed GX-TXT 0.9.7.72 variable binding GUI integration by adopting Analysis Source Map API v1.
- Replaced the legacy `config.dataset_id` selector with a required `primary` Dataset source.
- X/Y binding selectors now populate from the selected primary Dataset and expose values such as `primary.x` and `primary.y`.
- Runtime accepts qualified `primary.variable` bindings and resolves them to Dataset variables before calling NUMERIC_API_v1.
- No GX-TXT framework files are modified.

## 1.0.3

- Removed the hard-coded `demo.nonlinear.source` prerequisite.
- Added normal GX-TXT Dataset selection through the module configuration.
- Added normal X/Y variable bindings.
- Reads nonlinear-fit reference parameters directly from the generated Session.
- Publishes the derived fit as `demo.nonlinear.fit` through Publication API v2.
- Added automatic Graph Provider rendering and cache-only rerender.
- Added a complete `MANUAL.md` with the exact generated-Session import workflow.
- Improved diagnostics for wrong Sessions, missing bindings, and invalid data.

## 1.0.0

- Initial numerical integration demo.
- Required an exact pre-existing Dataset ID and an undocumented Tcl helper,
  which made the normal GUI workflow unclear.
