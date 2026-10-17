# Numerical Interpolation Demo — Complete GX-TXT Plugin Manual

SPDX-License-Identifier: GPL-3.0-or-later

## 1. Module overview

**Plugin name:** Numerical Interpolation Demo  
**Plugin ID:** `demo.numeric.interpolation`  
**Plugin version:** `1.1.0`  
**Plugin type:** external GX-TXT analysis module  
**Runner:** `standard_octave`

The module is a reference implementation for interpolation and resampling through
the public GX-TXT numerical architecture. It consumes a canonical GX-TXT Dataset,
resolves the selected scientific variables through stable Dataset/Variable
identity, calls `math.numeric` through `NUMERIC_API_v1`, publishes one derived
Dataset, automatically renders two normal GX-TXT Graph Provider graphs, and
leaves the derived Dataset available to the protected `plot.dataset` service for
additional user-defined plots.

The demonstrated numerical methods are the methods actually advertised by
`math.numeric` in GX-TXT 0.9.7.71:

- `linear` interpolation;
- `cubic` interpolation;
- `spline` interpolation;
- `pchip` interpolation;
- explicit-grid resampling through `dataset_resample` using `linear` as a
  consistency check.

The plugin does not contain a private interpolation implementation. In
particular, the module does not call Octave `interp1`, `spline`, or `pchip`
directly. These algorithms remain inside the public `math.numeric` service.

The principal public GX-TXT interfaces exercised by the runtime are Standard
Module API v1, Analysis Source Map API v1 and its runtime metadata, Dataset
Variable Schema stable identities, Table Stream API v3, `NUMERIC_API_v1`, Plugin
Progress API v1, Dataset Publication API v2, Graph Provider API v1 and the
shared GX-TXT graphics layer. Plugin installation uses Plugin Install API v1.
The end-to-end compatibility test also exercises the separate public
`PLOT_DATASET_API_v1` service of `plot.dataset` against the published Dataset.

## 2. Required GX-TXT version

The required dev097 framework is:

```text
GX-TXT 0.9.8.10-dev-097
```

The package manifest declares `framework_min=0.9.8.10-dev-097`.

The plugin remains external. Installing it through the normal GX-TXT Plugin
Install workflow copies only the plugin package into the managed plugin area. No
GX-TXT source file, CORE module, `VERSION.txt`, or framework release archive is
modified or replaced by this package.

The runtime discovers protected service `math.numeric` through its advertised `NUMERIC_API_v1` version 1 descriptor and uses CORE `STATISTICAL_RESULT_SEMANTICS_API_v1` for interpretation.

## 3. Corresponding Session Generator

The canonical validation Session is produced by the existing GX-TXT 0.9.7.71
Session Generator Library:

```text
Library:
GX-TXT Numerical Examples

Category:
Mathematics

Generator:
Interpolation
```

These names were verified against the actual library and generator descriptors.
The generator ID is `interpolation`; the user-facing generator name is
`Interpolation`.

The intended relationship is:

```text
GX-TXT Numerical Examples
        ↓
Interpolation generator
        ↓
normal independent GX-TXT Session
        ↓
canonical Dataset imported in that Session
        ↓
demo.numeric.interpolation
        ↓
derived Dataset
        ↓
automatic module graphs + optional plot.dataset graphs
```

The plugin never reads the generator package or its installed files as scientific
input. The generated Session is the boundary between generation and analysis.

## 4. Creating the example Session

Use these GX-TXT 0.9.7.71 GUI labels:

```text
New Session
→ enter Session name in "Session name:"
→ Generate Session...
→ GX-TXT Numerical Examples
→ Mathematics
→ Interpolation
→ Generate Session
```

`<SESSION_NAME>` in this manual means the name selected by the user at runtime.
`<SESSION_DIRECTORY>` means the resulting Session directory selected/created
by GX-TXT for that runtime Session. Both are intentional procedural variables,
not unresolved implementation placeholders.

The verified generator creates these scientific files inside the independent
Session:

```text
raw/interpolation.csv
metadata/ground_truth.txt
```

The generated CSV has two headers:

```text
x,y
```

and ten sparse, non-uniform samples:

```text
x       y
0       0
0.35    0.377897807455
0.9     0.873326909627
1.4     1.12544972999
2.1     1.07320936665
2.9     0.529249329214
3.8    -0.231857890943
4.7    -0.529923257564
5.5    -0.15554032557
6.2     0.536910597183
```

The generator declares in `metadata/ground_truth.txt`:

```text
function=y=sin(x)+0.1*x
sampling=sparse nonuniform
noise=none
```

### 4.1 Canonicalize the generated CSV as a Dataset

A freshly generated Interpolation Session in GX-TXT 0.9.7.71 contains the RAW
CSV but does **not** initially contain a registered canonical Dataset. This was
verified by generating a fresh Session and reading its Dataset Registry through
GX-TXT.

Use the framework-owned generic CSV import in the same Session:

1. Open the `Acquisition` tab.
2. In `Multi-CSV canonical dataset import (v0.8.2)`, enable `Use batch table`.
3. Click `+ Add CSV` and select the generated Session file
   `<SESSION_DIRECTORY>/raw/interpolation.csv`.
4. Set `Dataset ID` to `interpolation.source` for the canonical tutorial and
   validation workflow.
5. Set `Contract` to `table.generic`.
6. Leave `Delimiter` as `auto`.
7. Set `Header` to `1`.
8. Click `Variables`. The verified variable table headings include `Use`,
   `CSV col`, `Original header`, `Canonical variable`, `Unit`, and
   `Semantic role`.
9. Keep canonical variable `x` and assign its `Semantic role` to `independent`.
10. Keep canonical variable `y` and assign its `Semantic role` to `measured`.
11. Click `Import enabled pending into current session`.

In the fresh validation Session this produced:

```text
Dataset ID: interpolation.source
Contract:   table.generic
x:          variable_id=v0001, canonical=x, role=independent, unit=empty
y:          variable_id=v0002, canonical=y, role=measured,    unit=empty
```

`v0001` and `v0002` are reported here because they were actually observed in the
fresh canonical validation Session. The plugin does **not** hard-code these IDs.
It resolves the stable IDs selected by the current Session runtime.

The generator defines no physical units for either variable, so the canonical
validation Dataset has empty unit fields. The plugin preserves those unit fields
rather than inventing units.

## 5. Scientific dataset

The canonical input Dataset used for package validation is:

```text
Dataset ID: interpolation.source
Contract: table.generic
Samples: 10
```

Scientific variables:

| Variable | Stable ID in fresh validation Session | Role | Unit | Meaning |
| --- | --- | --- | --- | --- |
| `x` | `v0001` | `independent` | empty | independent coordinate |
| `y` | `v0002` | `measured` | empty | sparse sample of the known function |

The analytical source is:

```text
y = sin(x) + 0.1*x
```

There is no noise. The X samples are strictly increasing but non-uniform:

```text
0, 0.35, 0.9, 1.4, 2.1, 2.9, 3.8, 4.7, 5.5, 6.2
```

The largest source interval is:

```text
h_max = 0.9
```

This dataset is suitable for validating interpolation because the sparse samples
are deterministic, the exact continuous reference function is known, and the
non-uniform grid exercises Dataset-aware interpolation rather than assuming a
uniform source step.

The generator serializes Y using Python `.12g`. The module therefore checks that
the canonical source values remain consistent with the analytical function
within a serialization tolerance derived from the reference magnitude.

## 6. Mathematical background

For source points \((x_i,y_i)\), interpolation constructs an approximation
\(p(x)\) that reproduces the source samples at their nodes:

```text
p(x_i) = y_i
```

The plugin evaluates all methods only inside the source interval; extrapolation
is explicitly set to `error`.

### 6.1 Linear interpolation

On one interval \([x_i,x_{i+1}]\), piecewise linear interpolation is

```text
p(x) = y_i + (y_(i+1)-y_i) * (x-x_i)/(x_(i+1)-x_i)
```

For a twice continuously differentiable reference function, the interval error
satisfies

```text
|f(x)-p(x)| <= h_i^2 * max|f''(x)| / 8
```

For the canonical function

```text
f(x)  = sin(x) + 0.1*x
f''(x) = -sin(x)
```

so `max|f''(x)| <= 1`. With `h_max = 0.9`, the conservative global bound used by
the plugin is therefore:

```text
h_max^2 / 8 = 0.10125
```

This is the scientifically justified dense-grid PASS/FAIL criterion for the
linear method. A small floating-point margin is added by the implementation.

### 6.2 Cubic, spline and PCHIP

GX-TXT 0.9.7.71 `NUMERIC_API_v1` publicly exposes interpolation methods named:

```text
cubic
spline
pchip
```

All three require at least three source points. The plugin uses the API method
names exactly as advertised.

The manual does not assign an arbitrary common approximation-error threshold to
these different higher-order constructions. For each method the module:

- verifies interpolation identity at the original source nodes;
- computes the actual dense-grid error against the analytical function;
- reports maximum absolute error;
- reports RMSE;
- reports mean absolute error.

The dense-grid diagnostics are scientific measurements, not a ranking of the
methods.

### 6.3 Resampling

The default target is a uniform grid of 201 points spanning `0` through `6.2`.
It is created through the public `uniform_grid` operation with `mode=count`.
The resulting step is:

```text
6.2 / (201 - 1) = 0.031
```

The plugin additionally invokes public `dataset_resample` with `method=linear`
on that same explicit target grid. Its result is compared with the linear
`dataset_interpolate` result. Because both public calls use the same documented
linear interpolation contract on the same target points, disagreement beyond a
small machine-roundoff envelope indicates an API/path inconsistency.

## 7. Plugin installation

The actual package filename produced for this release is:

```text
demo.numeric.interpolation_1.1.0.zip
```

Install it with the normal GX-TXT GUI workflow:

```text
Modules
→ Install plugin...
→ select demo.numeric.interpolation_1.1.0.zip
```

GX-TXT displays its normal Plugin Install confirmation after successful
installation.

The package is declarative and contains `plugin-package.ini`; it does not contain
or require a custom installer script.

### 7.1 Verify discovery

Remain in the `Modules` tab and locate the module whose stable ID is:

```text
demo.numeric.interpolation
```

Its displayed module name is:

```text
Numerical Interpolation Demo
```

The module is intentionally not enabled by default. Select it and use `Enable`.
The package depends on the protected CORE module `math.numeric`; normal module
dependency handling keeps that service available.

## 8. Running the plugin

Open the generated Session after `interpolation.source` has been imported as
described in Section 4.

### 8.1 Configure the analysis

1. In `Modules`, enable `Numerical Interpolation Demo`.
2. Open the `Analysis` tab.
3. In the module frame `Numerical Interpolation Demo (demo.numeric.interpolation)`,
   enable `Run / recalculate now`.
4. In `Calculation configuration`:
   - `Output Dataset ID` = `demo.numeric.interpolation.result`
   - `Uniform query point count` = `201`
5. In `Dataset sources (Analysis Source Map API v1)`, set source ID `primary` to
   Dataset ID `interpolation.source`.
6. In `Input variable bindings`:
   - `Independent X variable` → the `x` variable from source `primary`;
   - `Sampled Y variable` → the `y` variable from source `primary`.
7. Run the selected analysis using:

```text
PHASE 2 - RUN SELECTED ANALYSES
```

The module resolves the selected variables to stable `dataset_id + variable_id`
identities before numerical execution.

### 8.2 Expected module outputs

The module publishes the derived Dataset:

```text
demo.numeric.interpolation.result
```

and writes these declared analysis files:

```text
interpolation_metrics.ini
interpolation_report.txt
```

A recalculation may replace the same derived Dataset ID only through Publication
API v2 owned-replacement semantics and only when the existing Dataset is owned by
this module.

## 9. Numerical processing chain

The implemented runtime chain is:

```text
interpolation.source
→ Analysis Source Map API v1 runtime
→ stable variable resolution
→ Table Stream API v3
→ NUMERIC_API_v1 uniform_grid
→ NUMERIC_API_v1 dataset_interpolate
   ├─ linear
   ├─ cubic
   ├─ spline
   └─ pchip
→ NUMERIC_API_v1 dataset_resample (linear consistency path)
→ analytical reference y=sin(x)+0.1*x
→ error diagnostics / validation
→ Dataset Publication API v2
→ demo.numeric.interpolation.result
→ plot.dataset / PLOT_DATASET_API_v1
→ scientific PNG graph
```

The plugin does not read private Dataset cache/runtime files. Table Stream and
the Dataset-aware numerical API own canonical data access. Publication API v2
owns derived Dataset registration and physical storage selection.

The call to `dataset_grid_info` records source-grid diagnostics through the same
public numerical service.

## 10. Expected numerical result

The canonical deterministic case has these known reference properties:

```text
reference function:             y = sin(x) + 0.1*x
source sample count:            10
source range:                   0 ... 6.2
maximum source spacing h_max:   0.9
default query count:            201
default uniform query step:     0.031
linear analytical error bound:  0.10125
```

The source/reference check uses:

```text
source tolerance = 5e-12 * max(1, max(abs(reference)))
```

On the 201-point reference grid this evaluates to approximately
`5.81039613032e-12`. The tolerance is tied to the generator's verified `.12g`
serialization rather than selected arbitrarily. Independent inspection of the
generated source values gives a maximum source/reference discrepancy of about
`1.53987933516e-12`, within that envelope.

Interpolation at the original source nodes uses:

```text
identity tolerance = 1e-10 * max(1, max(abs(y_source)))
```

For the canonical generated values this is approximately
`1.12544972999e-10`. This tolerance checks the interpolation identity while
allowing ordinary floating-point arithmetic.

The dense-grid linear reference check uses:

```text
max_abs_error <= 0.10125 + floating-point margin
```

`cubic`, `spline`, and `pchip` report their dense-grid reference errors but do
not receive an invented common error threshold. Their required validation is
interpolation identity at the source points.

The linear resampling consistency check uses a roundoff envelope:

```text
64 * eps(max(1, max(abs(y_linear))))
```

A complete successful run reports overall `PASS` only when the source-reference
integrity check, the required source-point identity checks, the theoretical
linear bound, and the linear resample/interpolate consistency check all pass.

## 11. Output Dataset

The plugin declares one `table.generic` Dataset with ID
`demo.numeric.interpolation.result` by default. The stable published variable IDs
and meanings are:

| Variable ID | Meaning | Unit |
| --- | --- | --- |
| `x` | uniform query coordinate, 201 points by default | inherited from source X |
| `y_reference` | analytical `sin(x)+0.1*x` reference | inherited from source Y |
| `y_linear` | linear interpolation | inherited from source Y |
| `error_linear` | `y_linear - y_reference` | inherited from source Y |
| `y_cubic` | cubic interpolation | inherited from source Y |
| `error_cubic` | `y_cubic - y_reference` | inherited from source Y |
| `y_spline` | spline interpolation | inherited from source Y |
| `error_spline` | `y_spline - y_reference` | inherited from source Y |
| `y_pchip` | PCHIP interpolation | inherited from source Y |
| `error_pchip` | `y_pchip - y_reference` | inherited from source Y |

`x` is declared as an implicit uniform coordinate through Publication API v2.
The `sample` dimension is declared extendible with initial size zero, and all stored Y/error columns are published in one aligned `append` operation. This is required by the CSV Publication v2 provider for a multivariable table; the provider materializes the uniform `x` coordinate automatically.
The derived variables reference `x` as their coordinate variable.

For the canonical Session the source unit fields are empty; the output therefore
also has empty unit fields. With another compatible Dataset that carries units,
the plugin preserves the selected X and Y units. The analytical-reference
validation itself is specific to the canonical generated Session because its
formula is known.

Publication provenance records the source Dataset ID, selected stable source
variable IDs, plugin version, and the fact that `NUMERIC_API_v1` produced the
numerical result.

## 12. Plot

Version 1.0.2 renders two graphs automatically after a successful numerical
analysis. They are declared through the normal GX-TXT Graph Provider API v1 and
rendered with the shared GX-TXT graphics layer; no private plotting framework is
introduced. The same published Dataset remains available to the protected
`plot.dataset` service for further plots.

### 12.1 Automatic graph: Interpolation curves

Graph ID:

```text
demo.numeric.interpolation.curves
```

Artifact:

```text
01_interpolation_curves.png
```

The graph contains:

- the original sparse source samples as markers;
- the analytical reference `sin(x)+0.1*x`;
- linear interpolation;
- cubic interpolation;
- spline interpolation;
- PCHIP interpolation.

The X and Y labels are derived from the bound source variable names and units
when the graph configuration fields are left at `auto`. The graph uses the
standard GX-TXT legend service.

### 12.2 Automatic graph: Interpolation errors

Graph ID:

```text
demo.numeric.interpolation.errors
```

Artifact:

```text
02_interpolation_errors.png
```

It plots, on the common query grid,

```text
y_method - y_reference
```

for `linear`, `cubic`, `spline`, and `pchip`, together with a zero-error
reference line. The Y-axis retains the source Y unit where one exists.

### 12.3 Rerendering the automatic graphs

The analysis writes `render_cache.mat`. GX-TXT uses the descriptor-declared
`standard_octave` rerender entry point to regenerate either enabled graph from
that cache. Rerendering does not repeat the interpolation or republish the
Dataset. Normal global/module/graph graphics settings and the standard legend
configuration therefore remain available after the analysis.

### 12.4 Additional plots with `plot.dataset`

The automatic graphs do not restrict the output Dataset. To build another graph,
enable `Scientific Dataset Plot` (`plot.dataset`), choose
`demo.numeric.interpolation.result` as a Dataset source, and configure Graph
Series using the actual stable variable IDs shown by GX-TXT. Useful output
variables include `y_reference`, `y_linear`, `y_cubic`, `y_spline`, `y_pchip`
and their corresponding `error_*` variables.

The integration test retains a complete public `PLOT_DATASET_API_v1` rendering
path, so the plugin validates both its automatic Graph Provider outputs and the
published Dataset's compatibility with `plot.dataset` when GNU Octave is
available.

### 12.5 What a scientifically sensible plot looks like

The ten source samples should lie on the analytical curve at their X positions.
All interpolation curves should pass through those source samples within the
documented interpolation-identity tolerance. Between source points, the linear
curve is piecewise straight while the higher-order curves follow their public
`NUMERIC_API_v1` definitions. The error graph should remain finite across the
full generated X range; the linear maximum absolute error must satisfy the
analytical bound documented in Section 10.

## 13. Interpretation

A correct canonical result has these properties:

- the source Dataset contains the ten deterministic non-uniform samples;
- source Y values agree with `sin(x)+0.1*x` within the documented serialization
  tolerance;
- all four interpolation methods reproduce the source Y values at the original
  X nodes within the documented identity tolerance;
- the linear interpolation maximum dense-grid error remains inside `0.10125`
  plus the explicit floating-point margin;
- the explicit-grid linear `dataset_resample` result agrees with the linear
  `dataset_interpolate` result to roundoff;
- every method reports finite maximum absolute error, RMSE, and mean absolute
  error against the analytical reference;
- the derived Dataset preserves X/Y units and source provenance;
- the plot shows the source points on the reference curve and no discontinuous
  or obviously displaced interpolation result.

The higher-order error diagnostics are not converted into a ranking. Different
interpolants embody different shape and smoothness behavior, and this reference
module reports their measured errors rather than declaring a preferred method.

A problem is indicated by a failed source/reference check, failed source-point
identity, linear error above the theoretical envelope, linear resampling
inconsistency, missing/invalid Dataset variables, non-increasing X, non-finite
values, Publication failure, or an unavailable `NUMERIC_API_v1` capability.

## 14. Reproducibility

The canonical example is reproducible because:

- GX-TXT reference version is fixed at `0.9.8.10-dev-097`;
- Session Generator Library and generator names are fixed;
- the generator is deterministic;
- X positions are fixed;
- the analytical function is fixed at `sin(x)+0.1*x`;
- `noise=none`;
- the generator serializes values deterministically;
- plugin version is fixed at `1.1.0`;
- default query count is fixed at `201`;
- interpolation method names are the public method names from the installed
  `math.numeric` descriptor;
- the module records the source Dataset/variable identities in publication
  provenance and writes its numerical diagnostics to `interpolation_metrics.ini`.

No random seed is present because the generator uses no randomness.

## 15. Troubleshooting

### Plugin is not visible

Use `Modules` → `Install plugin...` and select the package ZIP. After successful
installation, locate stable ID `demo.numeric.interpolation` in the Modules
catalog. The plugin is not enabled by default.

### The generated Session has no Dataset

This is expected behavior for the Interpolation Session Generator. It creates `raw/interpolation.csv` and ground truth, not an already
registered canonical Dataset. Perform the Section 4.1 import into
`interpolation.source`.

### Wrong Dataset or missing variables

The module accepts `table.generic` as its input contract. For the canonical demo,
bind the imported `interpolation.source` Dataset. X must be the independent `x`
variable and Y the sampled `y` variable. The runtime fails explicitly if the
source Dataset is missing, a binding cannot be resolved to a stable variable ID,
X/Y lengths differ, fewer than three samples exist, values are non-finite, or X
is not strictly increasing.

### `NUMERIC_API_v1` unavailable

The plugin requires the bundled `math.numeric` CORE service and reads its public
descriptor to discover the advertised Octave binding. The runtime fails if
`math.numeric` does not advertise `NUMERIC_API_v1` version 1 or if the advertised
Octave public entrypoint/function is unavailable. It does not fall back to a
private interpolation implementation.

### GNU Octave unavailable

`standard_octave` and `math.numeric` require a working GNU Octave executable in
the GX-TXT environment. The module reports missing runtime dependencies as errors.

### Numerical validation fails

Inspect `interpolation_report.txt` and `interpolation_metrics.ini`. The report
separates source/reference integrity, source-point interpolation identity,
linear analytical-bound validation, resample/interpolate consistency, and the
actual higher-order error diagnostics.

### Output Dataset ID already belongs to something else

The default is `demo.numeric.interpolation.result`. Publication uses owned
replacement. GX-TXT will reject replacement if an existing Dataset with that ID
is not a Publication API v2 Dataset owned by this plugin. Choose another value in
`Output Dataset ID` or remove/rename the conflicting Dataset through normal
GX-TXT Dataset management.

### Automatic graph is unavailable

Confirm that `Interpolation curves` and/or `Interpolation errors` are enabled
under the module's normal Graph Provider controls. A successful analysis must
write `render_cache.mat`; rerendering requires that cache. Renderer failures are
reported through the normal GX-TXT analysis/rerender log.

### Additional `plot.dataset` graph is unavailable

`plot.dataset` is a protected CORE module in this reference framework. Enable
`Scientific Dataset Plot`, select the published Dataset, configure Graph Series,
and run/rerender it through the normal GX-TXT workflow.

## 16. Public API usage

The final implementation uses or participates in the following verified public
GX-TXT interfaces.

### Runtime data and execution

- **Standard Module API v1 (`MODULE_API_v1`)** — descriptor discovery,
  `standard_octave` runtime and module configuration.
- **Analysis Source Map API v1 (`ANALYSIS_SOURCE_MAP_API_v1`)** — source ID to
  canonical Dataset ID mapping.
- **Dataset Variable Schema API v3 (`DATASET_VARIABLE_SCHEMA_API_v3`)** — stable
  Dataset-scoped variable identity exposed to current runtime/data services.
- **Table Stream API v3 (`TABLE_STREAM_API_v3`)** — backend-neutral source reads.
- **`NUMERIC_API_v1`** — `uniform_grid`, `dataset_interpolate`,
  `dataset_resample`, and `dataset_grid_info`; methods `linear`, `cubic`,
  `spline`, and `pchip`.
- **Dataset Publication API v2 (`DATASET_PUBLICATION_API_v2`)** — storage-auto
  derived Dataset declaration, aligned sequential table append, provenance, finalize, and same-owner
  recalculation replacement.
- **Plugin Progress API v1 (`PROGRESS_API_v1`)** — framework-visible run stages,
  completion, and failure.
- **Graph Provider API v1 (`GRAPH_PROVIDER_API_v1`)** — declares the two stable
  automatic graph IDs, enable state, artifacts and rerender lifecycle.
- **Plot Module API v1 (`PLOT_MODULE_API_v1`) / shared graphics layer** —
  standard graph configuration, legend integration and PNG rendering.

### Installation, documentation and graph workflow

- **Plugin Install API v1 (`PLUGIN_INSTALL_API_v1`)** — package installation and
  managed discovery.
- **Documentation API v1 (`DOCUMENTATION_API_v1`)** — descriptor link to this
  manual and API references.
- **`PLOT_DATASET_API_v1` / `plot.dataset`** — validation/additional-plot path
  exercised against the published Dataset; it is separate from the two automatic
  module-owned graphs.

No private Dataset storage locator, generator-library file, or private
`math.numeric/runtime` implementation is part of the plugin contract.

## 17. Package contents

The installable package contains:

```text
demo.numeric.interpolation/
├── plugin-package.ini
├── module.ini
├── README.md
├── MANUAL.md
├── LICENSE
├── runtime/
│   ├── demo_numeric_interpolation.m
│   ├── demo_numeric_interpolation_main.m
│   ├── demo_numeric_interpolation_render.m
│   ├── demo_numeric_interpolation_rerender.m
│   └── demo_numeric_interpolation_rerender_main.m
```

`plugin-package.ini` is the Plugin Install API v1 package manifest. `module.ini`
is the Standard Module API v1 descriptor. The runtime directory contains only
the external plugin's Octave entrypoint/implementation. Validation lives in the integrated framework workspace.

## 18. Dev097 interpretation and validation

The published Dataset retains ten validated CORE pointwise-comparison records:
source/reference integrity, linear resample consistency, and analytical-reference
and source-identity errors for each interpolation method. Existing metric keys,
Dataset/variable IDs and method names remain stable. CORE adds explicit quantity,
status, unit and reason fields; these descriptive errors do not establish a
regression or sampling-inference model.

Source/reference, identity, bound and resampling checks finish before publication.
If a check fails, reports explain the failure and an existing successful output
Dataset and render cache remain unchanged.

The integrated `statistics_comparison_demos.tcl` validator runs the unchanged
stock generator through the actual dev096/dev097 module, publication/reopen,
source preservation and one error graph. Its negative case verifies preservation
of successful output after invalid reference input. `compare_comparison_demos.py`
requires exact canonical numeric dtype/shape/bytes and unchanged legacy metrics,
then checks error reductions independently with NumPy. Development receipts are
separate from final full generator, rerender and frozen-candidate acceptance.
