# Numerical Statistics Demo — Manual

Plugin ID: `demo.numeric.statistics`  
Plugin version: `1.0.1`  
Framework: current GX-TXT public scientific APIs  
License: GNU GPL v3 or later

## 1. Purpose

This plugin is a compact demonstration/reference consumer of GX-TXT's public numerical architecture. It demonstrates statistics on a Canonical Dataset through `math.numeric` / `NUMERIC_API_v1`, publishes reusable derived Datasets, writes a human-readable report and renders an automatic graph.

It is a demonstration, not a replacement for the independent production statistical analysis modules.

## 2. Public GX-TXT APIs used

The implementation uses only public framework paths relevant to the task:

- Standard Module API v1;
- Analysis Source Map API v1;
- Dataset Variable Schema API v3;
- Dataset Metadata API v1 when metadata are present;
- Dataset Selection API v1 for optional X-range filtering;
- Table Stream API v3 for bounded source inspection and graph-series preparation;
- `NUMERIC_API_v1` from `math.numeric` for all statistical calculations;
- Dataset Publication API v2 for both derived Datasets;
- Graph Provider / shared graphics helpers for automatic PNG output;
- Plugin Install API v1;
- Session Generator Library API v1.

No CORE code is modified by this plugin.

## 3. Statistical capabilities provided by NUMERIC_API

The public `math.numeric` API provides descriptive statistics, quantiles and weighted statistics, including Dataset-aware descriptive and weighted operations.

Descriptive statistics return:

- count of values used;
- minimum, maximum and range;
- sum and arithmetic mean;
- median, Q25, Q75 and IQR;
- population variance and standard deviation;
- sample variance and standard deviation;
- RMS.

Quantiles use **Hyndman-Fan type 7 linear interpolation**.

Weighted statistics return:

- finite-pair count before zero-weight removal;
- positive-weight count;
- sum of weights and effective sample size;
- minimum, maximum and range on positive-weight observations;
- weighted sum and mean;
- weighted empirical-CDF median, quartiles and IQR;
- population weighted variance/std;
- reliability-weight unbiased variance/std where defined;
- weighted RMS.

Standalone statistical covariance/correlation operations are not exposed by the current `NUMERIC_API_v1`. Covariance objects present in fitting and uncertainty-propagation APIs are different capabilities. This demo therefore has no covariance/correlation mode.

## 4. Session Generator

The package includes the portable Session Generator:

```text
Library:      GX-TXT Numerical Examples
Category:     Mathematics
Generator:    Statistics
generator_id: statistics
version:      1.0.0
```

Import `session_generators/gxtxt_numerical_examples_statistics_1.0.0.zip` with the Library Manager. The generated ordinary Session contains:

```text
raw/statistics_demo.csv
metadata/ground_truth.txt
```

The plugin never reads `ground_truth.txt` during analysis. That file exists only for human inspection and independent tests.

## 5. Source Dataset import

Import `raw/statistics_demo.csv` through the normal Acquisition / generic CSV workflow as a `table.generic` Canonical Dataset. A documented example Dataset ID is:

```text
statistics.source
```

Suggested variable semantics/units:

| CSV column | Unit | Suggested role |
| --- | --- | --- |
| `sample` | `1` | independent |
| `value_V` | `V` | measured |
| `weight` | `1` | weight |

Do not rely on the example's imported variable IDs. The module resolves stable IDs from Analysis Source / Variable Schema runtime data.

## 6. Configuration

The compact module configuration contains:

- **Value variable** — required;
- **Weight variable** — optional except in Weighted mode;
- **Data selection** — optional X-range Dataset Selection;
- **Statistics mode** — `descriptive` or `weighted`;
- **NaN / Inf policy** — `omit` or `error`;
- **Summary Dataset ID**.

Descriptive is the default mode.

## 7. Dataset Selection

If an X-range Dataset Selection is chosen, it is passed to the Dataset-aware numerical operation through the public Selection structure. The same public selection mask is used only to prepare matching counts and graph-series rows; the plugin does not implement a private filter language.

`Input count` in the report means rows remaining after the Dataset Selection and before the selected non-finite policy.

## 8. NaN / Inf policy

The public `math.numeric` default is `nonfinite=error`. This demo exposes the policy explicitly and defaults its example workflow to `omit` because the deterministic Statistics dataset contains three missing-value markers that the public CSV provider exposes numerically as `NaN`.

With `omit`:

- descriptive mode removes non-finite values;
- weighted mode removes pairs where either value or weight is non-finite;
- invalid data are never converted to zero.

The report states input, valid/used and excluded non-finite counts. In weighted mode it separately reports finite pairs, positive-weight observations and zero-weight observations.

With `error`, the public numerical operation rejects non-finite input and the plugin does not publish partial output.

## 9. Weight semantics

The Weight binding is an **explicit statistical weight**. It is not a measurement uncertainty.

A Dataset uncertainty column, if present in some other source, is not automatically reinterpreted as a weight. If a scientific workflow requires inverse-variance weights derived from uncertainty, that transformation must be explicit in the appropriate analysis workflow; this demo does not invent it.

Zero weights are discarded by the public weighted-statistics operation. Negative weights are errors. At least one positive weight is required.

Weighted quantiles use the public `weighted empirical CDF inverse` definition.

## 10. Variance and standard-deviation conventions

Descriptive mode reports both conventions returned by `NUMERIC_API_v1`:

- population variance/std: divisor `n`;
- sample variance/std: divisor `n-1`, undefined (`NaN`) for a single observation.

Weighted mode reports:

- population weighted variance/std;
- reliability-weight unbiased variance/std where mathematically defined.

The plugin does not choose an alternative convention.

## 11. Units

Minimum, maximum, range, sum, mean, median, standard deviation, RMS and quantiles retain the Value variable unit.

Variance is published/reported with the squared-unit expression, for example `V^2`. GX-TXT's Unit Registry parser supports simple powers; no false unchanged `V` metadata is assigned to variance.

Counts and effective sample size are dimensionless. Weighted sum carries `value*weight` units when the Weight variable itself is not dimensionless. Correlation is not produced because no public correlation operation is exposed in this framework version.

## 12. Derived Datasets

### Summary Dataset

Default ID:

```text
demo.numeric.statistics.result
```

Schema:

| Variable | Type | Meaning |
| --- | --- | --- |
| `statistic` | string | Stable statistic name |
| `value` | float64 | Computed numeric value |
| `unit` | string | Per-statistic scientific unit |
| `definition` | string | Definition/convention note |

A long-form schema is used because different statistics have different units. The numeric `value` column therefore does not falsely claim one common unit; the per-row `unit` field carries the correct unit.

### Graph/reuse series Dataset

Default ID:

```text
demo.numeric.statistics.result.series
```

It contains the observations actually included by the public operation, a sequential included-observation index, constant mean and median reference series, and explicit weights in weighted mode. It is suitable for normal downstream Dataset consumers, including `plot.dataset`.

## 13. Provenance

Publication records include:

- producer module and version;
- source Dataset ID;
- source Value variable ID;
- Weight variable ID in weighted mode;
- Selection ID when used;
- numerical mode;
- explicit non-finite policy;
- public numerical API identity.

The source Dataset is never modified.

## 14. Report

`statistics_report.txt` contains:

- plugin ID/version;
- source Dataset and stable variable IDs;
- selected variables and units;
- Selection identity or Full Dataset;
- exact public numerical operation;
- input/valid/excluded counts;
- weighted counts/configuration when applicable;
- variance/std convention;
- quantile convention;
- computed statistics and units;
- Dataset Metadata availability;
- published Dataset IDs;
- graph output;
- the documented absence of standalone covariance/correlation operations.

`statistics_metrics.ini` provides a compact machine-readable run summary.

## 15. Automatic graph

`01_statistics_values.png` plots observations actually used by the selected public operation and overlays its mean and median. Weighted mode labels the reference lines as weighted mean/median.

The graph is module-owned but uses GX-TXT shared graphics/Graph Provider infrastructure. Rerender uses only `render_cache.mat`; it does not recalculate statistics.

## 16. Save/reopen

Module settings use the normal Standard Module manifest path. The test suite verifies persistence of mode, non-finite policy, output Dataset ID, binding configuration and Selection ID through manifest write/reload.

Published Datasets are ordinary registered Canonical Datasets and remain addressable after Session reopen according to normal GX-TXT Dataset persistence.

## 17. Tests

The package contains:

```text
tests/test_static.py
tests/test_framework_integration.tcl
```

Coverage includes deterministic generator data, normal/constant/signed/single-value/non-finite numerical semantics, explicit weighted behavior, package installation, generator import, Canonical Dataset import, stable variable resolution, API capability discovery, Selection persistence and real Octave execution when available.

Runtime-dependent checks are reported as `SKIP` when GNU Octave is absent; no PASS is fabricated.

Numerical and GUI checks require the configured GNU Octave and Tk runtime.

## 18. Known limitations

- No standalone covariance/correlation mode because GX-TXT 0.9.7.82 does not expose those public statistical operations.
- No regression; that belongs to `demo.numeric.regression`.
- No histogram is generated because this demo does not require a new graph type or any patch to `plot.dataset`.
- Only normal X-range Dataset Selection is supported by the descriptor for this reference demo.
