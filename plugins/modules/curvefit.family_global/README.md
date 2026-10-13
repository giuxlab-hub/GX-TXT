# GX-TXT Curve Family Fitting

SPDX-License-Identifier: GPL-3.0-or-later

`curvefit.family_global` is a generic GX-TXT analysis module for fitting and validating parameterized mathematical models against `curve_family.table` datasets.

Plugin version: **6**  
Module API: **1**  
Graph Provider API: **1**

Fitting uses the runtime-discovered public `NUMERIC_API_v1` nonlinear solver with bounded fallback; global, domain and group residual summaries use its `residual_metrics` operation. All five graphs are persistent public `plot.dataset` variants. The module contains no private fitting solver or renderer.

## Operation modes

### `fit` (default)

Optimizes the model parameters through the public numerical-service workflow. The selected solver optimizes the registered model parameters using the semantic model bindings `x`, `family`, and `y`.

Saved Sessions without `operation_mode` are interpreted as `fit`.

Fit mode also builds a 2D convex hull in mathematical-model input space `(x, family)` and, when the hull is valid, writes the optional sidecar `fit_domain.csv`.

### `evaluate`

Uses frozen model parameters and never calls an optimizer. It computes predictions, residuals, metrics, training-domain classification, cache data and the normal graph-provider outputs.

Frozen parameters can come from:

- `parameter_source=manual` with `fixed_parameter_values` in `model.param_names` order;
- `parameter_source=csv` with `parameter_csv_path`.

The CSV parameter path uses the framework's `type=file` field and Browse control.

## Shared Parameter-Set API

CSV parameter sets are read through the shared helper:

```text
gxtxt_read_parameter_set()
```

The standard file remains compatible with:

```csv
parameter,value
mu,10.8
Kp,77.2
```

Parameter names, numeric values and optional `model_id` metadata are validated by the framework helper. The plugin no longer contains a private parameter-set parser.

## Shared Model-Domain API

The training-domain sidecar uses the public Model-Domain format:

```csv
# model_id=triode.koren_v1
# domain_kind=convex_hull
x,family
...
```

`x` and `family` are stable mathematical-model input roles, not dataset-specific column names. This is required so the same fitted surface can be evaluated on datasets whose canonical column names differ while the semantic model bindings remain the same.

The plugin uses the shared helpers:

```text
gxtxt_read_model_domain()
gxtxt_validate_model_domain()
gxtxt_classify_model_domain()
```

The domain is always defined and classified in mathematical-model input space. Measured `y` and `presentation_orientation` never participate in the in/out test.

When Evaluate uses a parameter CSV, the plugin automatically looks for `fit_domain.csv` in the same directory. If no sidecar exists, evaluation continues with `domain_role=unknown` and the summary reports that the training domain is unavailable.

An incompatible historical CurveFit domain file is not reinterpreted as a current Model-Domain file; it is ignored for classification with a warning, so frozen-parameter evaluation can still proceed safely.

`fit_domain.csv` is intentionally **not** listed in `[outputs].files`, because it is a conditional sidecar: Fit normally creates it, while Evaluate of an old parameter set may legitimately have no training domain. The public output contract does not declare this optional sidecar as a mandatory file.

## Domain roles and metrics

Evaluate assigns each point:

```text
in_domain
out_of_domain
unknown
```

`IN-DOMAIN` means interpolation within the convex hull of the training input region. It does not mean that a datum is correct. `OUT-OF-DOMAIN` means extrapolation outside that region. It does not mean that a datum is wrong.

Outputs include:

```text
fit_metrics_by_domain.csv
fit_metrics_by_family_domain.csv
```

`fit_metrics_by_family.csv` is also published for the standard family-level summary.

## Mathematical bindings vs presentation

The mathematical model always receives:

```text
model(theta, x, family)
```

`presentation_orientation` only changes plotting/grouping:

```text
x_by_family   -> horizontal=x,      group=family
family_by_x   -> horizontal=family, group=x
```

Domain classification is performed before this presentation transformation.

## Progress API v1

The plugin uses only the public GX-TXT progress helpers. It never manipulates Tcl/Tk widgets and never writes the structured protocol itself.

Analysis stages are:

```text
loading_data
validating_inputs
preparing_fit
optimizing                 (Fit only; indeterminate)
computing_predictions
computing_metrics
classifying_domain
building_render_cache
rendering_graphs
writing_outputs
completed
```

`optimizing` remains indeterminate because the current `lsqnonlin`/`fminsearch` workflow does not expose a reliable iteration counter without changing solver behavior. Graph rendering and output writing use determinate `current/total` progress.

Rerender uses only:

```text
loading_cache
rendering
completed
```

and never repeats fitting or scientific evaluation.

## Graphs

```text
curvefit.family.overlay
curvefit.family.residuals
curvefit.family.parity
curvefit.family.relative_residuals
curvefit.family.error_by_family
```

The first two graphs are enabled by default. Graph IDs and filenames follow the current descriptor. Standard graphics inheritance, standard legend handling and annotation capability remain descriptor-driven.

## Mandatory outputs

```text
fit_parameters.csv
fit_summary.txt
fit_predictions.csv
fit_metrics_by_family.csv
fit_metrics_by_domain.csv
fit_metrics_by_family_domain.csv
render_cache.mat
```

Conditional Fit/domain sidecar:

```text
fit_domain.csv
```

In Evaluate mode, `fit_predictions.csv` includes `domain_role`. Fit mode uses the standard prediction schema.

## Render cache and rerender

`render_cache.mat` contains the physical model inputs, measured/predicted values, residuals, metrics, operation mode, frozen parameters, presentation state and training-domain information required for cache-only rerender.

Rerender does not load the model and contains no call to `lsqnonlin`, `fminsearch` or the model function.

