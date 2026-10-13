# Curve Family Fitting — `curvefit.family_global`

GPL-3.0-or-later

This is a generic nonlinear curve-family fitting module. The 6BX7-GT is the first use case, not part of the module identity.

The module consumes a dataset with contract `curve_family.table`. It declares three required input roles:

- `x` — independent X;
- `family` — family/sweep variable;
- `y` — measured dependent quantity.

For `triode.koren_v1`, model preferences are `X_V`, `Vg_V`, `Y_mA`. These are defaults, not hard-coded requirements. The Analysis tab allows each role to be bound to any canonical dataset variable.

For the current `VG_X.csv`:

```text
X_V,Vg_V,Y_mA
```

all three bindings resolve automatically. If the user aliases `X_V` to `Va_V`, the binding can be set to `Va_V` and the canonical CSV is generated with that header.

The runtime configuration written into the session records the resolved bindings, selected model, solver and model parameters, making a run reproducible.


## Octave CLI entry point (v0.6.1)

`curvefit_family_global.m` is intentionally a minimal command-line launcher. It adds its own plugin runtime plus the shared `core/octave/*` directories to the Octave path and calls `curvefit_family_global_main(argv())`. Helper functions are subfunctions of the external function file rather than local functions declared after executable script statements. This avoids the direct-script startup failure `arg_value undefined` observed with Octave 9.4.0.

A successful fit must create all descriptor-declared outputs: `fit_parameters.csv`, `fit_summary.txt`, `fit_predictions.csv`, `render_cache.mat`, and `01_curve_family_fit.png`. The standard runner verifies this contract before reporting success.


## Standard legend editor

The plot `curvefit.family.overlay` declares `supports_legend=1` and `legend_editor=standard`. `legend_mode` in the module plot configuration selects the semantic content (`family_only`, `measured_and_fitted`, or `none`). Placement and visual formatting are handled separately by the common **Plots → Configure legend...** editor and by **Place legend by click**. These settings persist in Manifest Format 2 and apply identically to initial rendering and rerendering.

## Legend support

`curvefit.family_global` does not own a private legend-positioning implementation. Its plot descriptor declares the common legend capability and the renderer calls `gxtxt_plot_legend()`. The Plots-tab editor can therefore combine placement and layout independently, for example `below + row`, `below + wrapped (4 columns)`, `right + stacked`, or `manual + wrapped`. Under GNUplot the common renderer uses a dedicated legend axes so exported PNG placement is deterministic.


## Graph offerings (v0.7.2)

The module implements Graph Provider API v1 and currently offers:

- `curvefit.family.overlay` — measured points and fitted family curves; enabled by default;
- `curvefit.family.residuals` — residuals (`Y_fitted - Y_measured`) grouped by family.

Enable/disable these plots in Analysis under the module plot configuration. Graph selection is part of the experiment manifest and does not change the fitted parameters. Rerender uses `render_cache.mat`, so enabling the residual plot after a fit does not repeat the numerical optimization.

Plot DPI is a **global graphics setting**, not a fitting parameter. Legend font sizes can inherit the global `px`/`pt` unit or override it per plot.
