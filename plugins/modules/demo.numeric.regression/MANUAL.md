# demo.numeric.regression — Complete User Manual

## 1. Module overview

`demo.numeric.regression` is an external GX-TXT demonstration/reference module
for regression and polynomial fitting through the public numerical architecture.

```text
Plugin ID: demo.numeric.regression
Version: 1.0.0
Reference framework: GX-TXT 0.9.7.72
Required service: math.numeric
Public numerical API: NUMERIC_API_v1
```

The module is not a private fitting implementation. Numerical fitting is
performed by the public `math.numeric` service. The plugin demonstrates the
complete scientific workflow:

```text
Session Generator
→ normal GX-TXT Session
→ Acquisition / canonical Dataset
→ Analysis Source + stable variable_id bindings
→ NUMERIC_API_v1 regression/fitting
→ residual and coefficient diagnostics
→ Dataset Publication API v2
→ automatic Graph Provider outputs
→ optional plot.dataset use
```

## 2. GX-TXT requirement and installation model

The package targets GX-TXT `0.9.7.72`. It is independently installable and does
not modify or repackage the framework.

Install it from the GX-TXT plugin UI using:

```text
Install plugin...
```

Select:

```text
demo.numeric.regression_1.0.0.zip
```

After installation, module discovery must expose:

```text
Numerical Regression Demo
```

under the numerical examples analysis group.

## 3. Public NUMERIC_API_v1 capabilities used

GX-TXT 0.9.7.72 exposes the following relevant capabilities and operations:

```text
linear_least_squares
weighted_linear_least_squares
linear_regression
polynomial_fit
weighted_polynomial_fit
dataset_fitting
descriptive_statistics
```

The plugin calls these public Octave dispatcher operations where applicable:

```text
dataset_polynomial_fit
polynomial_evaluate
linear_regression
least_squares
statistics
```

`dataset_polynomial_fit` is the Dataset-aware canonical fitting operation. A
separate `dataset_linear_regression` operation does not exist in GX-TXT
0.9.7.72; linear regression is therefore represented as degree-1 Dataset
polynomial fitting and is cross-checked against the public low-level
`linear_regression` and `least_squares` operations.

## 4. Session Generators

### 4.1 Stock Linear Regression generator

```text
Library: GX-TXT Numerical Examples
Category: Mathematics
Generator: Linear Regression
Generator ID: linear_regression
Version: 1.0.0
```

It creates:

```text
raw/linear_regression.csv
metadata/ground_truth.txt
```

The CSV contains:

```text
x
y
```

The deterministic source uses a straight-line model with known coefficients and
seeded Gaussian noise. The plugin does not read `ground_truth.txt` directly.

### 4.2 Stock Polynomial Fitting generator

```text
Library: GX-TXT Numerical Examples
Category: Mathematics
Generator: Polynomial Fitting
Generator ID: polynomial_fitting
Version: 1.0.0
```

It creates:

```text
raw/polynomial_fitting.csv
metadata/ground_truth.txt
```

The CSV contains:

```text
x
y
```

The deterministic source is a cubic polynomial with seeded Gaussian noise. The
plugin does not depend on its generator sidecar.

### 4.3 Portable Weighted Regression generator

Weighted fitting requires explicit uncertainty/weight data. The stock generators
above contain only `x` and `y`, so the complete demo additionally provides a
separate Session Generator API v1 package:

```text
gxtxt_numerical_examples_weighted_regression_1.0.0.zip
```

Import it into the existing library using:

```text
New Session
→ Generate Session...
→ Manage Libraries...
→ select GX-TXT Numerical Examples
→ Import Generator...
```

The imported generator is:

```text
Library: GX-TXT Numerical Examples
Category: Mathematics
Generator: Weighted Regression
Generator ID: weighted_regression
Version: 1.0.0
```

It generates two CSV files:

```text
raw/weighted_linear_regression.csv
raw/weighted_polynomial_fitting.csv
```

Both contain:

```text
x
y
reference_y
sigma_y
weight_inv_variance
```

The distinction is important:

- `sigma_y` is the measurement standard uncertainty used for error bars;
- `weight_inv_variance` is the statistical fit weight `1/sigma_y^2`;
- residuals are measured minus fitted values;
- coefficient standard errors are fit-parameter uncertainty estimates returned
  by the regression API.

These concepts are not interchangeable.

## 5. Creating a demonstration Session

For any stock generator:

1. Click `New Session`.
2. Click `Generate Session...`.
3. Select `GX-TXT Numerical Examples`.
4. Select category `Mathematics`.
5. Select `Linear Regression` or `Polynomial Fitting`.
6. Click `Generate Session`.

For the weighted demo, first import the portable generator as described above,
then select `Weighted Regression` and click `Generate Session`.

Every generated Session is a normal independent GX-TXT Session. The analysis
plugin never reads files from the installed generator library.

## 6. Importing the source Dataset

Open the `Acquisition` tab and use:

```text
Multi-CSV canonical dataset import (v0.8.2)
```

Enable `Use batch table`, click `+ Add CSV`, and choose the generated CSV.

### 6.1 Linear Regression

Recommended Dataset ID:

```text
regression.linear.source
```

Use:

```text
Contract = table.generic
Delimiter = auto
Header = 1
```

Keep `x` and `y`. Suggested semantic roles:

```text
x → independent
y → measured
```

### 6.2 Polynomial Fitting

Recommended Dataset ID:

```text
regression.polynomial.source
```

Use the same import settings and preserve `x` and `y`.

### 6.3 Weighted Regression

Import either generated weighted CSV. Recommended Dataset IDs are:

```text
regression.weighted.linear.source
regression.weighted.polynomial.source
```

Preserve all five columns and use these semantic roles:

```text
x                     → independent
y                     → measured
reference_y           → reference
sigma_y               → uncertainty
weight_inv_variance   → weight
```

No physical units are defined by these synthetic examples, so do not invent
units during import.

Click:

```text
Import enabled pending into current session
```

Stable Dataset `variable_id` values are assigned by GX-TXT. The plugin resolves
the selected bindings through public Analysis Source and Variable Schema runtime
metadata and does not hard-code those IDs.

## 7. Dataset Metadata — optional, never required

The plugin works completely when no Dataset Metadata have been imported.

When Dataset Metadata are available through `DATASET_METADATA_API_v1`, the
standard Analysis Source runtime bridge makes them available to the Octave
module without exposing CORE storage paths. The plugin recognizes the optional
namespaced keys:

```text
regression.model
regression.truth.degree
regression.truth.coefficients
regression.truth.slope
regression.truth.intercept
regression.noise
regression.seed
regression.sigma_variable
regression.weight_variable
regression.weight_semantics
regression.reference_variable
```

The most important optional key is:

```text
regression.truth.coefficients
```

whose value is a semicolon-separated coefficient list in descending polynomial
power order. Example cubic truth:

```text
0.5;-2;1.5;3
```

If truth coefficients are available and match the selected degree, the plugin
uses the public `polynomial_evaluate` operation to construct/reference the known
curve and reports coefficient errors. Metadata therefore add diagnostics, but
missing metadata never block fitting, publication or automatic graphs.

The plugin never opens generator `ground_truth.txt` files directly.

## 8. Variable binding

Select `Numerical Regression Demo` and bind:

```text
Independent X variable                     required
Measured Y variable                        required
Reference Y variable (optional)            optional
Measurement standard uncertainty variable  optional
Statistical weight variable (optional)     optional
```

For the weighted generator use:

```text
X         = x
Measured  = y
Reference = reference_y
Sigma     = sigma_y
Weight    = weight_inv_variance
```

## 9. Regression configuration

### Regression mode

```text
linear
polynomial
```

`linear` always uses degree 1. `polynomial` uses `Polynomial degree`.

### Polynomial degree

Default:

```text
3
```

The selected Dataset must contain at least `degree + 1` observations.

### Weight semantics

```text
relative
inverse_variance
```

Use `relative` for generic relative statistical weights. Use
`inverse_variance` only when the supplied weights are absolute inverse
measurement variances. The canonical weighted generator provides exactly
`1/sigma_y^2`, so use:

```text
inverse_variance
```

With inverse-variance semantics, coefficient covariance is not rescaled by the
fitted residual variance and the API reports reduced chi-square.

## 10. Ordinary least squares

The primary unweighted fit is always performed through:

```text
dataset_polynomial_fit
```

with no weight variable. This is ordinary least squares.

In linear mode, the degree-1 coefficients are also cross-checked through:

```text
linear_regression
least_squares
```

using the same public data values. The comparison verifies consistency between
the convenience regression operation, the general least-squares foundation and
the Dataset-aware polynomial-fit path.

## 11. Weighted least squares

If a statistical weight binding is supplied, the plugin performs a second
Dataset-aware fit with:

```text
weight_variable_id = selected stable weight variable_id
```

and the selected weight semantics.

In linear mode, weighted results are again cross-checked against the public
`linear_regression` and `least_squares` operations.

A sigma binding alone does not silently become a weight. Weighted fitting is
activated only by an explicit statistical weight variable. This preserves the
scientific distinction between uncertainty and weighting.

## 12. Polynomial fitting

Polynomial mode invokes `dataset_polynomial_fit` at the configured degree.
GX-TXT 0.9.7.72 solves in centered/scaled X coordinates by default and returns
coefficients transformed back into the original X polynomial basis.

Coefficient order is descending polynomial power. A cubic result is therefore:

```text
c3; c2; c1; c0
```

The plugin uses the public `polynomial_evaluate` operation to verify that model
evaluation reproduces the fitted values returned by the fitting operation.

## 13. Regression diagnostics

For OLS and, when present, WLS, the plugin records:

```text
coefficients
coefficient standard errors
R²
adjusted R²
RMSE = sqrt(mean(residual²))
MAE = mean(abs(residual))
maximum absolute residual
API objective-space RMSE
condition number
weight semantics
reduced chi-square when defined
```

Residual is defined as:

```text
measured - fitted
```

For weighted fits, the objective-space RMSE returned by the API is not the same
quantity as unweighted residual RMSE. The manual and report keep them separate.

## 14. Known synthetic truth

The stock Linear Regression generator uses the known model:

```text
y = 2.5*x + 1.2 + noise
```

The stock Polynomial Fitting generator uses:

```text
y = 0.5*x^3 - 2*x^2 + 1.5*x + 3 + noise
```

The portable weighted generator uses the same coefficient sets but adds
heteroscedastic Gaussian noise, reference values, standard uncertainties and
inverse-variance weights.

Runtime coefficient-truth diagnostics are enabled only when equivalent truth
coefficients are available as normal Dataset Metadata. The plugin does not
hard-code generator truth as a required runtime dependency.

## 15. Derived Dataset

Default Dataset ID:

```text
demo.numeric.regression.result
```

Always published:

```text
x
measured
fitted_ols
residual_ols
absolute_residual_ols
```

When a weight variable is bound:

```text
fitted_wls
residual_wls
absolute_residual_wls
weight
```

When sigma is bound:

```text
sigma
```

When a reference is available through a Dataset variable or compatible Dataset
Metadata:

```text
reference
fit_error_ols
fit_error_wls   (when WLS exists)
```

Publication uses Dataset Publication API v2. Fitting and API-contract validation
finish before publication begins, preventing invalid calculations from leaving a
partial derived Dataset.

The module also publishes `<output_dataset_id>.coefficients` with coefficient
index, OLS estimates and standard errors, and WLS estimates and standard errors
when present. The coefficient graph uses this Dataset. Polynomial coefficient
units vary by power, so that graph labels its Y axis as mixed units.

## 16. Automatic graphs

A normal successful Run automatically generates six module-owned Graph Provider
artifacts.

### 16.1 Measured data and fitted model

```text
Graph ID: demo.numeric.regression.fit
Artifact: 01_fit_comparison.png
```

Displays measured points, OLS fit and WLS fit when available. If `sigma_y` is
bound, measured data are displayed with error bars using the actual Dataset
uncertainty variable.

### 16.2 Coefficient diagnostics

```text
Graph ID: demo.numeric.regression.coefficients
Artifact: 02_coefficient_diagnostics.png
```

Displays fitted coefficients with standard-error bars. OLS and WLS estimates are
shown separately when both exist.

### 16.3 Residuals versus X

```text
Graph ID: demo.numeric.regression.residual_x
Artifact: 03_residuals_vs_x.png
```

Shows residual structure over the independent variable.

### 16.4 Residuals versus fitted value

```text
Graph ID: demo.numeric.regression.residual_fitted
Artifact: 04_residuals_vs_fitted.png
```

Useful for identifying variance changes or systematic model inadequacy.

### 16.5 Absolute residuals

```text
Graph ID: demo.numeric.regression.absolute_residual
Artifact: 05_absolute_residuals.png
```

Shows residual magnitude over X without sign cancellation.

### 16.6 Reference comparison

```text
Graph ID: demo.numeric.regression.reference
Artifact: 06_reference_comparison.png
```

When a reference curve is available, this directly compares reference, OLS and
WLS curves. If no reference is available, the same artifact becomes a measured
versus fitted parity diagnostic rather than inventing a reference function.

All graphs are rendered automatically after Run through public Plot.dataset
variants. They can be edited with framework plot controls and rerendered from
the two published Datasets without repeating fitting.

## 17. Interpreting the weighted demonstration

The weighted generator deliberately changes measurement uncertainty with X.
This demonstrates that WLS changes the fit objective according to statistical
weights. It does not establish that WLS is universally superior to OLS.

Inspect together:

```text
coefficient estimates and standard errors
residual plots
R² / adjusted R²
unweighted residual RMSE / MAE
reduced chi-square under inverse-variance semantics
reference-curve agreement
```

Do not compare the API weighted objective-space RMSE directly with the OLS
unweighted residual RMSE as though they were identical quantities.

## 18. Reproducibility

The generators are deterministic.

Stock Linear Regression:

```text
seed = 1971
truth = slope 2.5, intercept 1.2
noise sigma = 0.12
```

Stock Polynomial Fitting:

```text
seed = 1972
truth = 0.5; -2; 1.5; 3
noise sigma = 0.08
```

Portable Weighted Regression:

```text
linear seed = 1975
polynomial seed = 1976
weights = 1/sigma_y^2
```

The generated Session is the interface. The plugin never reads files from the
installed generator package.

## 19. Dataset Selection

An optional X-range Dataset Selection is supported. The public selection object
is passed to the Dataset-aware fitting operation, and the source vectors used
for graphs/reference comparison are filtered by the same public selection mask.
Private row filtering is not implemented.

## 20. Rerender

After a successful run the module writes:

```text
render_cache.mat
```

The cache contains Dataset identities and display metadata, not full measurement
or fit vectors. Rerender reads the published Datasets; it does not repeat
regression, modify them or reread generator files.

## 21. plot.dataset compatibility

Both published `table.generic` Datasets are normal GX-TXT data. The six automatic
graphs are persistent Plot.dataset variants and can be edited directly.

## 22. Troubleshooting

### Plugin is not visible

Install the ZIP with `Install plugin...` and verify that
`demo.numeric.regression` is discovered.

### Weighted fit is absent

A sigma variable does not automatically activate WLS. Bind an explicit positive
statistical weight variable.

### Inverse-variance diagnostics look inconsistent

Verify that the weight variable actually equals `1/sigma_y^2` if
`inverse_variance` was selected. The plugin reports the maximum relative
sigma/weight consistency error when both variables are bound.

### Polynomial degree is rejected

The degree must be a positive integer and the selected data must contain at
least `degree + 1` observations.

### Reference graph uses parity instead of a known curve

No reference variable was bound and no compatible truth coefficients were
available through Dataset Metadata. This is valid; the plugin does not invent a
reference function.

### Metadata sidecar exists but truth diagnostics are absent

The plugin does not read generator sidecars. Import equivalent values into
Dataset Metadata through the normal public metadata mechanism. Missing metadata
does not prevent fitting.

## 23. Public APIs actually used

```text
MODULE_API_v1
ANALYSIS_SOURCE_MAP_API_v1
ANALYSIS_SOURCE_METADATA_RUNTIME_v1
DATASET_METADATA_API_v1 (optional runtime metadata transport)
DATASET_SELECTION_API_v1
DATASET_VARIABLE_SCHEMA_API_v3
TABLE_STREAM_API_v3
DATASET_PUBLICATION_API_v2
NUMERIC_API_v1
PROGRESS_API_v1
GRAPH_PROVIDER_API_v1
PLOT_DATASET_API_v2 (all six automatic graphs and user editing)
PLUGIN_INSTALL_API_v1
SESSION_GENERATOR_LIBRARY_API_v1
DOCUMENTATION_API_v1
```

## 24. Package contents

```text
plugin-package.ini
module.ini
README.md
MANUAL.md
CHANGELOG.md
LICENSE
runtime/demo_numeric_regression.m
runtime/demo_numeric_regression_main.m
runtime/demo_numeric_regression_render.m
runtime/demo_numeric_regression_rerender.m
runtime/demo_numeric_regression_rerender_main.m
tests/README.md
tests/test_static.py
tests/test_framework_integration.tcl
```

The required weighted Session Generator is distributed separately as:

```text
gxtxt_numerical_examples_weighted_regression_1.0.0.zip
```

## 25. Validation strategy and limitations

The package tests verify real GX-TXT installation/discovery, stock and external
Session generation, Dataset import, stable variable resolution, Dataset Metadata
runtime transport and `NUMERIC_API_v1` capability discovery in all environments.
When GNU Octave is available, they additionally execute real Dataset-aware OLS
and WLS polynomial fitting, the installed plugin, Dataset publication, automatic
PNG rendering and Dataset-backed rerender.

The plugin does not perform robust regression, generalized linear models,
orthogonal-distance regression or Bayesian fitting because those are not public
`NUMERIC_API_v1` regression operations in GX-TXT 0.9.7.72.

Polynomial coefficient units are not synthesized because `math.numeric` does not
invent those compound units. Fitted/residual series preserve the source Y unit.
The coefficient graph explicitly labels its axis as mixed units. Coefficient
estimates and standard errors are also published in `<output_dataset_id>.coefficients`;
their numeric values remain editable through the public Plot Variant.
