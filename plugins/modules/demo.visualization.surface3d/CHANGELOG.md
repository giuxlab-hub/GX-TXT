# Changelog

## 1.0.3

- Replaced three private 3D figures with persistent public Plot.dataset variants.
- Kept the canonical source Dataset as the graphics source and removed full grid
  matrices from the rerender cache.
- Uses the shared plot window for viewpoint, color, axes and export controls.

## 1.0.2

- Fixed an Octave syntax error in the `contour3` rendering path: the `contour_levels` expression was missing one closing parenthesis.
- Added a static delimiter regression over all distributed Octave `.m` files so this class of packaging-time syntax error is detected even when GNU Octave is unavailable.
- Kept the scientific Dataset handling, Analysis Source resolution, Session Generator, and Graph Provider behavior unchanged.

## 1.0.1

- Fixed Analysis Source binding resolution: canonical/display names are now resolved to stable Dataset `variable_id` values before Table Stream API v3 is opened.
- Added explicit diagnostics when the runtime does not expose stable variable IDs.
- Updated Render Cache version matching for 1.0.1.
- Raised the minimum framework requirement to GX-TXT 0.9.7.77, the current stable large-data transport baseline used for validation.

## 1.0.0

- Initial external release for GX-TXT 0.9.7.75 or later.
- Added stable X/Y/Z Analysis Source bindings.
- Added exact rectangular-grid validation with explicit rejection of missing, duplicate, scattered, or non-finite XYZ data.
- Added descriptive summary calculations through NUMERIC_API_v1.
- Added automatic Graph Provider outputs for GX-TXT Plot 3D API v2 `surface`, `mesh`, and `contour3`.
- Added Render Cache API v1 cache-only rerender support for viewpoint, colormap, colorbar, axis and other presentation-only changes.
- Added deterministic `surface3d_thermal_field` Session Generator and reference truth.
