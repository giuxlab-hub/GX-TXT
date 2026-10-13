# demo.numeric.interpolation

External GX-TXT reference plugin demonstrating Dataset-native interpolation and
resampling through the public `math.numeric` `NUMERIC_API_v1` service.

- Plugin ID: `demo.numeric.interpolation`
- Plugin version: `1.0.4`
- Framework: compatible public `NUMERIC_API_v1` and Dataset/Graph Provider contracts
- Canonical Session Generator Library: `GX-TXT Numerical Examples`
- Canonical generator: `Interpolation`

The complete scientific and GUI workflow is documented in [`MANUAL.md`](MANUAL.md).
The public manual documents the scientific workflow and environment requirements.

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
