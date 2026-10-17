# GX-TXT Curve Family Fitting

SPDX-License-Identifier: GPL-3.0-or-later

`curvefit.family_global` fits and validates parameterized mathematical models against canonical `curve_family.table` Datasets.

Module version: **12**. Module API: **1**. Graph Provider API: **1**.

Fitting uses the runtime-advertised public `NUMERIC_API_v1` nonlinear solver with its explicit bounded fallback; global, domain and group residual summaries use its `residual_metrics` operation. All five graphs are persistent public Plot.dataset variants. CORE supplies statistical interpretation, Dataset transport and publication.

The public [Curve Family API](CURVE_FAMILY_API_v1.md) exposes callable-model
discovery, scientific Fit/Evaluate and durable result lookup to Tcl and both
Script Bridge languages. Canonical generic tables are accepted when their
explicit model Variable bindings meet the real aligned-row contract.

## Canonical inputs and source provenance

Normal Session runs read canonical CSV or HDF5 through CORE Table Stream v3.
The descriptor declares one required `primary` Analysis Source so the normal
launcher includes its stable Variable IDs, canonical names and physical units.
Existing Sessions without a source map retain their configured Dataset through
the framework's standard primary-source defaults.
Bindings resolve stable Variable IDs even when canonical names or display labels
change. A stale physical `dataset.path` is not used for Session Dataset access.
Standalone callers without a Session retain the public CORE CSV interface.

The model receives real physical `x`, `family`, and `y` values. The `family`
input is a mathematical coordinate; it does not silently become a categorical
member index. Joint missing/nonfinite rows are omitted in original source order.
The report and CORE provenance record total, used, omitted and missing counts,
the declared row policy, Variable IDs and source content/schema fingerprints.
Canonical text/complex inputs and 64-bit integers outside exact binary64 range
are refused. Publish an explicit scientifically meaningful conversion when
needed. The current materialized fitting input is bounded to one million rows.

Exact zero-based `uint64` source rows are retained in `render_cache.mat` and
the published `curvefit.family.result` Variable `source_row_ordinal`. Presentation
sorting and cache-only regrouping carry those identities with their rows.
Historical caches without row receipts remain readable and do not invent row
lineage. Legacy parameter and prediction CSV schemas remain compatible.
CORE identities are checked before/after ingestion and after model execution;
a changed scientific source is rejected before publication.

## Operation modes

### `fit` (default)

Optimizes the model parameters through the public numerical-service workflow. The selected solver optimizes the registered model parameters using the semantic model bindings `x`, `family`, and `y`.

Saved Sessions without `operation_mode` are interpreted as `fit`.

Fit mode also builds a 2D convex hull in mathematical-model input space `(x, family)` and, when the hull is valid, writes the optional sidecar `fit_domain.csv`.

### Shared, local and fixed parameters

`parameter_scopes` lists `shared`, `local` or `fixed`, separated by semicolons,
in the original mathematical model's parameter order. A single scope applies to
all parameters. The default `shared` preserves the existing global fit. `fixed`
retains one common constant; `local` allocates a separate parameter for each
distinct physical family value. The model still receives its original full
parameter vector and physical `x` and `family` inputs.

For example, `shared;local;fixed` for `slope;offset;family_coefficient` and family
values `-2;0.5;3` produces the joint parameter order
`slope;offset@family=-2;offset@family=0.5;offset@family=3;family_coefficient`.
Original model IDs remain in the versioned `gxtxt.family_parameters.v1` mapping.
Qualified local IDs explicitly identify their physical member. Members are sorted
numerically; locals allow at most 64 members and the joint model at most 128
parameter slots. An entirely shared model has no additional member-count limit.

Initial values and bounds default to the model declaration. Optional
`parameter_initial_values`, `parameter_lower_bounds`, `parameter_upper_bounds`
and `parameter_fixed_mask` use the expanded order above. Mask entries are 0/1;
equal bounds also fix a slot. This can fix an individual local parameter.
Fixed scope cannot be unset by the mask. All-fixed Fit evaluates the model without
optimization. Numeric computes one joint free-rank/DOF/covariance result; CORE
interprets it. Member rows do not represent independent fits or covariances.

The additive `curvefit.family.parameters` Dataset contains one row per local
member, or one `all_families` row with undefined `family_value` for a completely
shared model. In original parameter order, `p001_estimate`, `p001_role` and
`p001_scope` (then `p002_...`) carry values, free/fixed/frozen roles and declared
scopes. CORE provenance supplies the original IDs, expanded order and full joint
mapping. Declared physical parameter units come from optional model descriptor
`[parameters] units=...`; omitted or empty units remain unspecified.

### `evaluate`

Uses frozen model parameters and never calls an optimizer. It computes predictions, residuals, metrics, training-domain classification, cache data and the normal graph-provider outputs.

Frozen parameters can come from:

- `parameter_source=manual` with `fixed_parameter_values` in expanded parameter order;
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

Local-parameter CSVs include the mathematical `model_id` and versioned mapping
schema as comments, and use the qualified identities above. CSV replay restores
the complete saved member set: a subset of known members is allowed, while unseen
members or inconsistent local member sets are refused. A consumer expecting one
unqualified parameter vector rejects these files instead of selecting or averaging
a member. Shared-only CSVs retain the historical header and parameter identities.
Evaluate ignores solver and initial/bound configuration and labels published
parameter values `frozen`; these are not newly estimated quantities.

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

Individual graph descriptors default to off. The first two IDs remain the
descriptor's default selection list when graph selection uses that fallback.
Graph IDs and deterministic filenames are unchanged. Standard graphics
inheritance, legend handling and annotation capability are descriptor-driven.

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

New caches retain the full joint parameter mapping, values and actual model source
SHA-256. Cache-only regrouping republishes that state without changing the cache.
Historical caches without parameter state remain readable and do not create or
update `curvefit.family.parameters`; any previously published parameter Dataset
retains its own provenance. The actual model source is checked before/after model
execution, alongside the canonical Dataset identity check.

<a id="statistical-interpretation-module-7"></a>
## Statistical interpretation

All global, group and domain statistics consume `NUMERIC_API_v1` estimates and
`STATISTICAL_RESULT_SEMANTICS_API_v1` interpretation. `fit_statistics.tcldict`
records global training diagnostics (Fit) or frozen-parameter comparison
(Evaluate), plus compact group/domain tables. The three graph Datasets retain
the same validated records, including empty/constant subset states and units.
Historical CSV column names and numerical values remain compatible; subgroup
`r2` is explicitly the descriptive centered prediction score. No subgroup is
treated as a separately fitted model. Exported residuals remain predicted minus
observed. Parameter identities and physical model identity remain unchanged.

Units come from declared source-variable metadata, with the model response unit
as a fallback. Conflicting declared response units are rejected before fitting;
convert the canonical input explicitly. Parameter units that the
model does not declare remain unspecified. Training inference requires its
recorded model/noise/constraint assumptions; a solver result alone does not
establish valid confidence intervals.

Cached rerendering retains training evidence, reuses existing group estimates
when grouping is unchanged and computes only changed group comparisons through
Numeric. It writes `render_statistics.tcldict` for the current presentation and
preserves the numerical cache and fitting CSVs. Historical caches without
statistical records remain readable: their retained predictions get comparison
semantics, with training inference unavailable. No model or optimizer is loaded
by rerendering. Rows are chunked into bounded CORE tables when needed.
