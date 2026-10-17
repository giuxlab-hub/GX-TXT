# demo.numeric.interpolation

External GX-TXT reference plugin demonstrating Dataset-native interpolation and
resampling through the public `math.numeric` `NUMERIC_API_v1` service.

- Plugin ID: `demo.numeric.interpolation`
- Plugin version: `1.1.0`
- Reference framework: GX-TXT `0.9.8.10-dev-097`
- Canonical Session Generator Library: `GX-TXT Numerical Examples`
- Canonical generator: `Interpolation`

The complete scientific and GUI workflow is documented in [`MANUAL.md`](MANUAL.md).
Development and final acceptance evidence are recorded in the integrated framework validation records.

This plugin is an independent package. It does not modify GX-TXT CORE and does
not read files from the installed Session Generator Library.

## Derived Dataset publication

The module declares an extensible `sample` dimension and publishes all stored result columns through a single aligned Dataset Publication API v2 `append` operation. This follows the public CSV provider contract for complete multi-variable tables.

SPDX-License-Identifier: GPL-3.0-or-later


## Automatic graphs

The module declares two normal GX-TXT Graph Provider outputs and renders them after successful analysis:

- `Interpolation curves` → `01_interpolation_curves.png`;
- `Interpolation errors` → `02_interpolation_errors.png`.

Both graphs use the shared GX-TXT graphics layer and support normal GX-TXT rerendering from `render_cache.mat`. The published Dataset remains fully available to `plot.dataset` for additional user-defined plots.


Version 1.1.0 uses CORE `STATISTICAL_RESULT_SEMANTICS_API_v1` to interpret and
report existing pointwise errors. The result metadata records physical units,
applicability and comparison/subset identities. These descriptive errors do not
establish regression parameter uncertainty or sampling-inference claims.
Failed reference validation leaves an existing successful output Dataset and render cache unchanged.
