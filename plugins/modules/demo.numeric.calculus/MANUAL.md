# Numerical Calculus Demo — `demo.numeric.calculus`

## 1. Module overview

Plugin ID:

```text
demo.numeric.calculus
```

Version:

```text
1.0.0
```

`demo.numeric.calculus` is an independently installable GX-TXT analysis module. It demonstrates the public Dataset-aware calculus operations provided by `math.numeric` / `NUMERIC_API_v1`:

```text
dataset_grid_info
dataset_differentiate
dataset_integrate
dataset_cumulative_integrate
```

The module does not contain private differentiation or integration algorithms. Numerical work is delegated to the public numerical service. The module adds Dataset binding, analytical-reference comparison, diagnostics, Publication API output, automatic graphs, rerender support and a reproducible tutorial workflow.

The complete scientific chain is:

```text
GX-TXT Numerical Examples
        ↓
Mathematics → Calculus
        ↓
normal independent GX-TXT Session
        ↓
raw/calculus.csv
        ↓
normal Acquisition import
        ↓
calculus.source
        ↓
Analysis Source + stable variable bindings
        ↓
NUMERIC_API_v1
        ├─ dataset_grid_info
        ├─ dataset_differentiate
        ├─ dataset_integrate
        └─ dataset_cumulative_integrate
        ↓
analytical-reference diagnostics
        ↓
Dataset Publication API v2
        ↓
demo.numeric.calculus.result
        ↓
Graph Provider API v1
        ↓
five automatic PNG graphs
```

## 2. GX-TXT requirement

Reference and minimum framework version:

```text
GX-TXT 0.9.7.72
```

The package manifest declares:

```text
framework_min=0.9.7.72
```

The plugin is external. Installation must not modify or repackage GX-TXT itself.

Required bundled CORE service:

```text
math.numeric
```

Required public numerical API:

```text
NUMERIC_API_v1
```

GX-TXT 0.9.7.72 advertises the capabilities used by this module:

```text
integration
cumulative_integration
differentiation
dataset_calculus
grid_analysis
dataset_variables
dataset_selection
```

## 3. Canonical Session Generator

GX-TXT 0.9.7.72 already includes the required generator.

Exact identity:

```text
Library:   GX-TXT Numerical Examples
Category:  Mathematics
Generator: Calculus
```

Stable generator information:

```text
generator_id = calculus
version      = 1.0.0
```

The generator descriptor states that it produces:

```text
raw/calculus.csv
metadata/ground_truth.txt
```

GX-TXT also records normal generator provenance in the generated Session as:

```text
metadata/session_generator.ini
```

The generated Session is the interface between the Session Generator Library and this plugin. The plugin never reads files from the installed generator library.

## 4. Creating the example Session

Use the actual GX-TXT 0.9.7.72 GUI labels.

1. Click `New Session`.
2. Click `Generate Session...`.
3. In the expanded `Session Generator Library` browser select:

```text
GX-TXT Numerical Examples
→ Mathematics
→ Calculus
```

4. The generator suggests the Session name:

```text
calculus-example
```

The name may be changed by the user.

5. Click `Generate Session`.

GX-TXT creates and opens a normal independent Session. The generator creates:

```text
raw/calculus.csv
metadata/ground_truth.txt
```

and GX-TXT writes:

```text
metadata/session_generator.ini
```

A validation generation of GX-TXT 0.9.7.72 produced `raw/calculus.csv` with SHA-256:

```text
f853906c45145a269084b80691597ce9b584cea79924d9e15a704b1c33d57fd8
```

## 5. Importing the scientific Dataset

The Session Generator creates scientific source files; creation of the canonical Dataset remains a normal Acquisition operation.

Open the `Acquisition` tab and use `Multi-CSV canonical dataset import (v0.8.2)`:

1. Enable `Use batch table`.
2. Click `+ Add CSV`.
3. Select the generated Session file `raw/calculus.csv`.
4. Set `Dataset ID` to:

```text
calculus.source
```

5. Set `Contract` to:

```text
table.generic
```

6. Leave `Delimiter` as `auto`.
7. Set `Header` to `1`.
8. Click `Variables`.
9. Keep all four columns:

```text
x
f
df_dx
F
```

10. Suggested semantic roles for this demonstration are:

| Variable | Unit | Semantic role |
| --- | --- | --- |
| `x` | empty | `independent` |
| `f` | empty | `measured` |
| `df_dx` | empty | `reference` |
| `F` | empty | `reference` |

The canonical generator does not define physical units, so no physical unit should be invented during import.

11. Click `Import enabled pending into current session`.

A fresh validation import created four stable Dataset variable IDs in column order. The plugin does not depend on those literal IDs; it resolves the actual selected variables through the public Analysis Source runtime and Dataset Variable Schema metadata.

## 6. Scientific dataset and analytical reference

The generated CSV contains 81 uniformly spaced samples:

```text
x = -2.0 ... +2.0
step = 0.05
```

The analytical function is:

```text
f(x) = x^3 - 2x
```

The exact derivative is:

```text
df/dx = 3x^2 - 2
```

The analytical antiderivative stored by the generator is:

```text
F(x) = x^4/4 - x^2
```

At the first canonical sample:

```text
F(-2) = 0
```

Therefore the complete generated `F` column is already aligned with a cumulative integral beginning at the first sample. When an optional Dataset Selection starts later than `-2`, the plugin subtracts the first selected `F` value before comparison so that the analytical and numerical cumulative integrals share the same zero origin.

The numerical derivative and integrals are computed only from the bound `x` and `f` variables. The `df_dx` and `F` variables are used only as analytical references.

## 7. Mathematical background

### 7.1 Numerical differentiation

GX-TXT 0.9.7.72 reports the `dataset_differentiate` method as:

```text
centered_secant_with_endpoint_secants
```

and the implementation kernel as:

```text
octave.gradient
```

Interior samples use centered secant behavior while the two endpoints use one-sided secants. The endpoint error is therefore expected to be visibly larger than the interior error for this cubic example.

For uniform spacing `h = 0.05`, centered differentiation of the cubic term has an exact interior truncation error of:

```text
h^2 = 0.0025
```

for this function. The endpoint one-sided secants have a substantially larger first-order contribution. The module reports whole-range and interior diagnostics separately rather than hiding this behavior.

### 7.2 Definite integration

`dataset_integrate` reports:

```text
method = trapezoidal
kernel = octave.trapz
```

For the complete canonical interval `[-2,+2]`, `f(x)` is odd and the interval is symmetric. The analytical definite integral is therefore:

```text
0
```

The module computes the exact reference for any current range as:

```text
F(x_end) - F(x_start)
```

so the same logic remains valid when an X-range Dataset Selection is used.

### 7.3 Cumulative integration

`dataset_cumulative_integrate` reports:

```text
method = cumulative_trapezoidal
```

The public API returns an aligned cumulative vector beginning at zero at the first selected sample. The module compares it with:

```text
F_selected(x) - F_selected(x_start)
```

This prevents an arbitrary antiderivative constant from being mistaken for integration error.

## 8. Plugin installation and discovery

Release package:

```text
demo.numeric.calculus_1.0.0.zip
```

Install through the normal GX-TXT GUI:

```text
Modules
→ Install plugin...
→ select demo.numeric.calculus_1.0.0.zip
```

After installation, remain in `Modules` and locate:

```text
Numerical Calculus Demo
```

Stable module ID:

```text
demo.numeric.calculus
```

Enable it with the normal `Enable` action. No custom installer and no framework source modification are required.

## 9. Running the plugin

Open the Session containing `calculus.source`.

1. In `Modules`, enable `Numerical Calculus Demo`.
2. Open the `Analysis` tab.
3. In `Numerical Calculus Demo (demo.numeric.calculus)`, enable `Run / recalculate now`.
4. In `Calculation configuration`, leave `Data selection (optional X interval)` empty for the canonical full-range demonstration.
5. Leave `Output Dataset ID` as:

```text
demo.numeric.calculus.result
```

6. In `Dataset sources (Analysis Source Map API v1)`, set source `primary` to:

```text
calculus.source
```

7. In `Input variable bindings`, bind:

```text
Independent X variable      → primary.x
Function Y variable         → primary.f
Exact derivative variable   → primary.df_dx
Exact antiderivative variable → primary.F
```

8. Run:

```text
PHASE 2 - RUN SELECTED ANALYSES
```

A successful run publishes the derived Dataset, writes metrics/report/cache files, and renders all enabled module-owned graphs automatically.

## 10. Numerical processing chain and public APIs

The actual numerical processing path is:

```text
calculus.source
→ Analysis Source Map API v1
→ stable variable_id resolution
→ Table Stream API v3
→ optional Dataset Selection API v1 x_range
→ NUMERIC_API_v1 dataset_grid_info
→ NUMERIC_API_v1 dataset_differentiate
→ NUMERIC_API_v1 dataset_integrate
→ NUMERIC_API_v1 dataset_cumulative_integrate
→ analytical-reference comparison
→ Dataset Publication API v2
→ demo.numeric.calculus.result
→ Graph Provider API v1
→ shared graphics layer
→ five PNG artifacts
```

Only the following public APIs are used by the implementation:

```text
Standard Module API v1
Analysis Source Map API v1
Dataset Variable Schema API v3 runtime metadata bridge
Table Stream API v3
Dataset Selection API v1
NUMERIC_API_v1
Dataset Publication API v2
Progress API v1
Graph Provider API v1 / shared graphics helpers
```

`PLOT_DATASET_API_v1` is used by the integration test to confirm that the published Dataset remains available to `plot.dataset` for user-defined graphs.

## 11. Error diagnostics and expected canonical behavior

For differentiation:

```text
error = derivative_numeric - derivative_exact
RMSE  = sqrt(mean(error^2))
MAE   = mean(abs(error))
max absolute error = max(abs(error))
```

The module additionally reports:

```text
endpoint maximum absolute error
interior RMSE
```

For cumulative integration:

```text
error = integral_numeric - integral_exact
```

with RMSE, MAE and maximum absolute error.

For definite integration:

```text
error = numerical complete-range integral - exact complete-range integral
```

For the canonical full 81-sample Dataset, an independent mathematical oracle gives the expected differentiation diagnostics for the public method:

```text
RMSE                  ≈ 0.0468127673309877
MAE                   ≈ 0.00978395061728388
maximum absolute error = 0.2975
interior RMSE          = 0.0025
```

The larger whole-range error is dominated by the two one-sided endpoint secants. This is expected behavior, not hidden or discarded.

For cumulative trapezoidal integration on this cubic/uniform-grid example, the exact truncation-error relation is:

```text
error(x_i) = h^2/12 × [f'(x_i) - f'(x_0)]
```

with `h = 0.05`. The corresponding full-range diagnostics are approximately:

```text
RMSE                  ≈ 0.00181443682435714
MAE                   ≈ 0.00164583333333328
maximum absolute error = 0.0025
```

The complete symmetric definite integral should be roundoff-close to zero. The integration test uses `1e-12` as the complete-range zero tolerance; this is a conservative roundoff allowance for 80 trapezoidal panels with values of order unity, not a general-purpose integration-accuracy claim.

The module reports the actual values returned by `NUMERIC_API_v1`; it does not replace them with these expected values.

## 12. Derived Dataset

Default Dataset ID:

```text
demo.numeric.calculus.result
```

Contract:

```text
table.generic
```

Published variables:

```text
x
function
derivative_exact
derivative_numeric
derivative_error
absolute_derivative_error
integral_exact
integral_numeric
integral_error
absolute_integral_error
```

`integral_exact` is the analytical antiderivative shifted to zero at the first selected sample. This makes it directly comparable with the public cumulative-integral result for both the full Dataset and X-range selections.

Publication uses Dataset Publication API v2 with an extendible `sample` dimension and one aligned multivariable append. Publication starts only after the numerical output structure and X alignment have been validated.

Provenance includes:

```text
source Dataset
source stable variable IDs
plugin version
reported differentiation method
reported definite integration method
reported cumulative integration method
Dataset Selection ID when used
```

## 13. Automatic graphs

Automatic rendering is a required part of the plugin. The default Run produces five module-owned Graph Provider artifacts.

### 13.1 Source function

Graph ID:

```text
demo.numeric.calculus.function
```

Artifact:

```text
01_function.png
```

Series: bound source `f(x)`.

Purpose: establish the function being differentiated and integrated.

### 13.2 Exact versus numerical derivative

Graph ID:

```text
demo.numeric.calculus.derivative
```

Artifact:

```text
02_derivative_comparison.png
```

Series:

```text
Exact derivative
Numerical derivative
```

Purpose: show global agreement and make endpoint behavior visible.

### 13.3 Derivative error

Graph ID:

```text
demo.numeric.calculus.derivative_error
```

Artifact:

```text
03_derivative_error.png
```

Series:

```text
derivative_numeric - derivative_exact
```

A zero-error reference line is included.

### 13.4 Exact versus numerical cumulative integral

Graph ID:

```text
demo.numeric.calculus.integral
```

Artifact:

```text
04_integral_comparison.png
```

Series:

```text
Exact cumulative integral
Numerical cumulative integral
```

### 13.5 Cumulative integration error

Graph ID:

```text
demo.numeric.calculus.integral_error
```

Artifact:

```text
05_integral_error.png
```

Series:

```text
integral_numeric - integral_exact
```

A zero-error reference line is included.

When graph labels are left at `auto`, labels use the actual bound source variable names and units. Because the canonical generated Dataset has no physical units, the default plots do not invent them.

## 14. Dataset Selection behavior

The module exposes:

```text
Data selection (optional X interval)
```

using the public Dataset Selection API v1 with selection type:

```text
x_range
```

When a Selection is active:

- `dataset_grid_info`, differentiation, definite integration and cumulative integration receive the same public Selection structure;
- analytical `df_dx` and `F` references are restricted with the public selection mask over the same X range;
- the cumulative analytical reference is shifted to zero at the first selected sample;
- the derived Dataset contains only the selected samples;
- metrics and graphs describe the selected interval.

The plugin does not implement an independent private row-selection system.

## 15. Metadata behavior

The generated Session includes:

```text
metadata/ground_truth.txt
```

but generic CSV import in the current workflow does not automatically promote that sidecar into Dataset Metadata.

This does not reduce the current plugin functionality. The analytical reference information needed for all calculations is already present as normal Dataset variables:

```text
df_dx
F
```

Therefore version 1.0.0:

- does not read `metadata/ground_truth.txt`;
- does not parse generator-library files;
- does not require a metadata importer;
- works completely when no generator metadata have been imported into Dataset Metadata.

When a future generic metadata importer exposes additional scientific metadata through a public GX-TXT Dataset Metadata API, a later plugin version may use those values additively for richer provenance, displayed analytical expressions or additional consistency checks. Such metadata must remain optional: absence of imported metadata must not prevent numerical processing, publication or graph generation.

## 16. Rerender and `plot.dataset`

A successful analysis writes:

```text
render_cache.mat
```

The module's rerender entry point reads this cache and can regenerate enabled Graph Provider PNG files without repeating differentiation, integration or Dataset publication.

The published `demo.numeric.calculus.result` Dataset is a normal canonical GX-TXT Dataset and remains usable by `plot.dataset`. The integration test creates an additional `plot.dataset` graph from `derivative_exact` and `derivative_numeric` to verify this interoperability.

## 17. Reproducibility, troubleshooting and limitations

### Reproducibility

Canonical generator:

```text
Library:   GX-TXT Numerical Examples
Category:  Mathematics
Generator: Calculus
Version:   1.0.0
```

Canonical source CSV characteristics:

```text
81 samples
x = -2 ... +2
step = 0.05
f = x^3 - 2x
df_dx = 3x^2 - 2
F = x^4/4 - x^2
```

The generator is deterministic and contains no random input.

### Troubleshooting

**Plugin is not visible**

Use `Modules → Install plugin...`, select the ZIP, then confirm `Numerical Calculus Demo` appears in `Modules`.

**No source Dataset is available**

Generate the Calculus Session and import `raw/calculus.csv` through `Acquisition` first.

**A binding cannot be resolved**

Confirm that the selected `primary` Dataset contains all four imported variables and reselect the binding in `Input variable bindings`. The module requires stable variable IDs from the public runtime.

**Output Dataset ID collision**

The output Dataset ID must differ from the selected source Dataset ID. The default `demo.numeric.calculus.result` is appropriate when the source is `calculus.source`.

**Dataset Selection is rejected**

The module accepts only an `x_range` Selection belonging to the selected source Dataset and using the bound X variable.

**Graphs are missing after a successful numerical run**

Confirm that the five module graphs are enabled in the module graph controls and inspect the analysis log. Graph rendering uses the normal GX-TXT headless/shared graphics configuration.

**Rerender fails**

`render_cache.mat` must exist from a previous successful analysis. Rerender intentionally does not recalculate numerical results.

### Limitations

- The demo requires explicit analytical derivative and antiderivative reference variables for quantitative validation.
- Version 1.0.0 supports an optional X-range Dataset Selection, not rectangle selection.
- The plugin reports the algorithms supplied by GX-TXT 0.9.7.72; it does not provide alternate finite-difference or quadrature schemes.
- The canonical generator defines no physical units. Unit propagation becomes visible when the same module is run on a compatible Dataset that carries units.
- Imported generator metadata are optional and are not consumed by this release.

## 18. Package contents and validation performed

Package contents:

```text
plugin-package.ini
module.ini
README.md
MANUAL.md
CHANGELOG.md
LICENSE
runtime/demo_numeric_calculus.m
runtime/demo_numeric_calculus_main.m
runtime/demo_numeric_calculus_render.m
runtime/demo_numeric_calculus_rerender.m
runtime/demo_numeric_calculus_rerender_main.m
tests/README.md
tests/test_static.py
tests/test_publication_table.tcl
tests/test_framework_integration.tcl
```

The distributed tests cover:

```text
package descriptor validity
Plugin Install API installation
module discovery
canonical Calculus Session generation
source CSV hash and schema
normal Acquisition import
stable variable resolution
NUMERIC_API_v1 capability discovery
dataset_grid_info
dataset_differentiate
dataset_integrate
dataset_cumulative_integrate
analytical discretization checks
Dataset Publication API v2
published Dataset reopen/read-back
five automatic Graph Provider artifacts
cache-only rerender
plot.dataset compatibility
X-range Dataset Selection consistency
```

GNU Octave-dependent scientific checks require an installed numerical runtime.
Verification must distinguish executed tests from unavailable-runtime skips.
