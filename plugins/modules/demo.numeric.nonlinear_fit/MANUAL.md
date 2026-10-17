# `demo.numeric.nonlinear_fit` — Complete User and Scientific Manual

## 1. Module overview

**Plugin ID:** `demo.numeric.nonlinear_fit`  
**Plugin version:** `1.1.0`  
**Plugin name in GX-TXT:** `Nonlinear fit integration demo`  
**Group:** `Generic analysis / Numerical examples`  
**Reference framework:** GX-TXT `0.9.8.10-dev-097`  
**License:** GNU GPL v3 or later

This external plugin demonstrates nonlinear least-squares fitting through the
public GX-TXT numerical architecture.

Its canonical teaching input comes from:

```text
Library: GX-TXT Numerical Examples
Category: Mathematics
Generator: Nonlinear Fitting
```

The complete workflow is:

```text
Session Generator
→ normal GX-TXT Session
→ generated nonlinear_fitting.csv
→ import CSV into the current Session as a canonical Dataset
→ select Dataset in the plugin
→ bind x and y
→ NUMERIC_API_v1 nonlinear fit
→ published Dataset demo.nonlinear.fit
→ rendered fit graph
```

The Session directory name is not part of the plugin contract.

---

## 2. Import the example CSV as a Canonical Dataset

The `Nonlinear Fitting` Session Generator creates scientific source files:

```text
raw/nonlinear_fitting.csv
metadata/ground_truth.txt
```

It does not register `nonlinear_fitting.csv` as a canonical Dataset.

The module requires a registered Canonical Dataset as its selected scientific input. Import the generated CSV through the normal Acquisition workflow before running the analysis:

```text
Generated CSV
→ acq.generic_csv incremental import
→ canonical Dataset
→ analysis plugin
```

This is why the import step below is necessary.

The module accepts any compatible Canonical Dataset selected as Analysis Source `primary`; it does not require a fixed Dataset ID.

---

## 3. Required GX-TXT version and numerical service

This version requires:

```text
GX-TXT 0.9.8.10-dev-097
```

It depends on the bundled CORE numerical service:

```text
math.numeric
```

and uses:

```text
NUMERIC_API_v1
```

The normal `standard_octave` environment dispatches the declared expression to the platform Numeric Ceres backend. The model remains `A*exp(-k*x)+c`, with parameter identities `A`, `k`, `c`. CORE `STATISTICAL_RESULT_SEMANTICS_API_v1` interprets existing results without repeating the fit.

The plugin package does not modify GX-TXT CORE.

---

## 4. Create the canonical example Session

1. Start GX-TXT.
2. Press the top-bar button:

   ```text
   New Session
   ```

3. In the `New Session` window verify:

   ```text
   Session root:
   Session name:
   ```

4. Press:

   ```text
   Generate Session...
   ```

5. In the generator tree choose:

   ```text
   GX-TXT Numerical Examples
   └── Mathematics
       └── Nonlinear Fitting
   ```

6. Enter any valid Session name.
7. Press:

   ```text
   Generate Session
   ```

GX-TXT creates and opens the Session.

The suggested name `nonlinear-fitting-example` is only a suggestion. The plugin
works with any valid Session name.

---

## 5. Generated scientific files

The generator creates:

```text
raw/nonlinear_fitting.csv
metadata/ground_truth.txt
```

### 5.1 CSV structure

The CSV header is:

```text
x,y
```

The generator creates 51 rows. The independent variable is:

```text
x = i × 0.12
```

for `i = 0 ... 50`.

The observation model is:

```text
y = A exp(-k x) + c + noise
```

### 5.2 Ground truth

The reference file contains:

```text
A=4.2
k=0.65
c=0.35
noise=Gaussian sigma 0.03
seed=1973
```

The deterministic seed makes the example reproducible.

---

## 6. Import the generated CSV into the current Session

This step makes the generated source accessible to the Dataset-native analysis.

Keep the generated Session open.

### 6.1 Select the generic CSV importer

Go to the `Acquisition` tab and choose:

```text
Import module = acq.generic_csv
```

### 6.2 Use the multi-CSV table

In:

```text
Multi-CSV canonical dataset import (v0.8.2)
```

activate:

```text
Use batch table
```

Then press:

```text
+ Add CSV
```

Select the file inside the current generated Session:

```text
raw/nonlinear_fitting.csv
```

### 6.3 Dataset ID

GX-TXT proposes a Dataset ID from the filename. You may keep the proposed ID or
choose another valid Dataset ID.

For example:

```text
nonlinear_fitting
```

or:

```text
demo.nonlinear.source
```

The plugin no longer requires either exact value.

### 6.4 Dataset contract

Use a normal flat-table contract accepted by the module:

```text
table.generic
```

or:

```text
timeseries.table
```

`table.generic` is the more natural choice because `x` is an arbitrary numerical
coordinate rather than elapsed time.

### 6.5 Variable mapping

Use `Variables` if necessary and preserve the canonical variable names:

```text
x

y
```

### 6.6 Import into the already open Session

Because the Session already exists, do **not** create a second Session.

Use:

```text
Import enabled pending into current session
```

After successful import, the Dataset is registered in the current Session and
becomes available to analysis modules.

---

## 7. Install the plugin

Package filename:

```text
demo.numeric.nonlinear_fit_1.1.0.zip
```

1. Open the `Modules` tab.
2. Press:

   ```text
   Install plugin...
   ```

3. Select the ZIP package.
4. Confirm that the installed module appears as:

   ```text
   Nonlinear fit integration demo
   ```

   under:

   ```text
   Generic analysis / Numerical examples
   ```

The package is managed by Plugin Install API v1 and can later be updated or
uninstalled normally.

---

## 8. Enable the plugin

The `Modules` tab is the installed-plugin catalog and controls experiment
membership.

Enable:

```text
Nonlinear fit integration demo
```

Then open the `Analysis` tab.

GX-TXT creates the module's analysis panel there.

---

## 9. Select the primary Dataset source

The module uses GX-TXT **Analysis Source Map API v1**, which owns both the Dataset selector and its variable bindings.

In the module's Analysis panel locate:

```text
Dataset sources (Analysis Source Map API v1)
```

The module declares one required source:

```text
primary
```

Select the canonical Dataset created from `raw/nonlinear_fitting.csv` in
section 6. For the standard example it will normally be named:

```text
nonlinear_fitting
```

but any valid Dataset ID is accepted. The Dataset does **not** have to be named
`demo.nonlinear.source`.

After selecting the Dataset, GX-TXT refreshes the binding choices from that
Dataset.

---

## 10. Configure X and Y bindings

The module declares two required GX-TXT bindings. For the canonical generated
example choose exactly:

```text
X variable (choose primary.x for the generated example) = primary.x
Y variable (choose primary.y for the generated example) = primary.y
```

The `primary.` prefix is the Analysis Source Map source identity. The runtime
removes that prefix only to obtain the selected source token, then resolves it
through `gxtxt_analysis_source_variable_meta()`. The resolved stable
`variable_id` values are what the plugin passes to `NUMERIC_API_v1` and Table
Stream API. The canonical names shown in the GUI (`x` and `y`) are preserved
separately for human-readable reports.

If the binding comboboxes show only `auto`, the primary Dataset has not yet been
selected. Select the Dataset in the `Dataset sources` section first; the choices
should then include `primary.x` and `primary.y`.

---

## 11. Run the module

In the `Analysis` tab enable the module's normal run selector:

```text
Run / recalculate this module
```

Then execute the normal analysis Run workflow.

A successful run performs:

```text
selected canonical Dataset
→ selected x/y variables
→ NUMERIC_API_v1 dataset_nonlinear_fit
→ parameter validation
→ demo.nonlinear.fit publication
→ fit_report.txt
→ fit_metrics.ini
→ render_cache.mat
→ 01_nonlinear_fit.png
```

No Tcl command is required.

---

## 12. Mathematical background

The fitted model is:

```text
y(x) = A exp(-k x) + c
```

where:

- `A` is the exponential amplitude;
- `k` is the decay constant;
- `c` is the asymptotic offset.

The module uses initial parameter values:

```text
A = 4.0
k = 0.5
c = 0.2
```

and requests numerical optimizer tolerance:

```text
1e-9
```

Parameter units follow the source: A and c use the response unit; k uses the reciprocal X unit. Missing units remain unspecified. The interpretation retains an unspecified inferential noise model; generator prose alone does not establish an inference assumption.

Because the generator adds Gaussian noise, the fitted parameters are not
expected to equal the generator values exactly.

---

## 13. Expected numerical result

Reference parameters:

```text
A = 4.2
k = 0.65
c = 0.35
```

Validation limits:

```text
|A_fit - 4.2|  <= 0.10
|k_fit - 0.65| <= 0.05
|c_fit - 0.35| <= 0.08
```

These limits account for the deterministic observation noise and are separate
from the optimizer convergence tolerance.

If the recovered parameters exceed these limits, the module fails explicitly.

---

## 14. Output Dataset

The plugin publishes:

```text
Dataset ID: demo.nonlinear.fit
Contract: table.generic
```

Variables:

```text
x
measured
fitted
```

The published Dataset records the selected input Dataset and selected source
variable IDs as provenance, together with validated CORE `analysis.statistical_results` metadata. Parameter identities, covariance ordering, applicability and physical units survive Session reopen.

`x` is the output coordinate, `measured` is the source observation, and `fitted`
is the predicted value returned by `NUMERIC_API_v1`.

---

## 15. Reports

### `fit_metrics.ini`

Contains:

```text
source_dataset_id
x_variable
y_variable
derived_dataset_id
expected / recovered / error / tolerance for A, k, c
solver
converged
sse
rmse
r_squared
noise
seed
```

### `fit_report.txt`

Human-readable summary of the same scientific result, with CORE parameter, uncertainty and applicability text. Existing INI statistic keys add `.statistical_status`, `.statistical_quantity`, `.statistical_label`, `.statistical_reason` and `.statistical_unit`. The legacy `rmse` means the Numeric residual-DOF-scaled standard deviation, not the n-denominator residual RMSE; its identifier remains unchanged.

---

## 16. Plot

The plugin exposes the Graph Provider graph:

```text
Graph ID: demo.nonlinear.fit.curve
Name: Generated observations and nonlinear fit
Artifact: 01_nonlinear_fit.png
```

It contains:

- generated observations as markers;
- fitted exponential curve as a line.

The plot uses normal GX-TXT graphics settings, standard legend handling, and
atomic PNG export.

A correct graph should show a smooth exponential decay passing through the
central trend of the noisy observations and approaching the fitted offset at
large `x`.

`render_cache.mat` permits plot rerendering without repeating the numerical fit.

---

## 17. Reproducibility

The Session Generator uses:

```text
seed=1973
```

with fixed reference values:

```text
A=4.2
k=0.65
c=0.35
```

A newly generated `Nonlinear Fitting` example produces reproducible observations from this seed.

The plugin does not read files from the installed Session Generator Library. It
uses only the generated Session and the canonical Dataset imported from that
Session.

---

## 18. Troubleshooting

### 18.1 The plugin shows no usable primary Dataset

The generated CSV has not yet been imported as a canonical Dataset.

Return to section 6 and use:

```text
acq.generic_csv
→ Use batch table
→ + Add CSV
→ raw/nonlinear_fitting.csv
→ Import enabled pending into current session
```

### 18.2 Do I have to call my Session `nonlinear-fitting-example`?

No. The Session name is irrelevant.

### 18.3 Does the Dataset have to be called `demo.nonlinear.source`?

No. The module accepts any compatible Dataset selected as the `primary` Analysis Source.

### 18.4 Which variables do I select?

For the canonical generated example:

```text
X variable = primary.x
Y variable = primary.y
```

If only `auto` is available, select the `primary` Dataset first. GX-TXT then
populates the binding selectors from the selected Dataset.

### 18.5 `metadata/ground_truth.txt is missing`

The currently open Session was not generated by the canonical `Nonlinear
Fitting` Session Generator, or that metadata file was removed.

### 18.6 `NUMERIC_API_v1 is unavailable`

The required `math.numeric` public numerical service is unavailable or the
framework installation is incompatible.

### 18.7 Fit outside reference tolerances

The numerical fit ran but the recovered parameters do not agree with the known
deterministic example within the documented limits. Treat this as a real
validation failure.

### 18.8 Plot not rendered

Verify that the graph is enabled in the module Analysis panel and that the
GX-TXT graphics backend can render normal module plots.

---

## 19. Public GX-TXT APIs used

The plugin uses:

```text
Standard Module API v1
Plugin Install API v1
Dataset / standard runtime selection
Table Stream API through public Octave helpers
NUMERIC_API_v1
STATISTICAL_RESULT_SEMANTICS_API_v1
Dataset Publication API v2 standard_octave binding
Graph Provider API v1
Plot Module API v1
```

It does not edit `metadata/datasets.ini` directly.

---

## 20. Package contents

```text
plugin-package.ini
module.ini
README.md
MANUAL.md
CHANGELOG.md
runtime/
    demo_numeric_nonlinear_fit.m
    demo_numeric_nonlinear_fit_main.m
    demo_numeric_nonlinear_fit_render.m
    demo_numeric_nonlinear_fit_rerender.m
    demo_numeric_nonlinear_fit_rerender_main.m
```

---

## 21. Complete practical procedure

For quick reference, the entire normal GUI procedure is:

```text
New Session
→ Generate Session...
→ GX-TXT Numerical Examples
→ Mathematics
→ Nonlinear Fitting
→ Generate Session

Acquisition
→ Import module = acq.generic_csv
→ Use batch table
→ + Add CSV
→ choose raw/nonlinear_fitting.csv
→ use table.generic
→ preserve x,y variable names
→ Import enabled pending into current session

Modules
→ Install plugin...
→ demo.numeric.nonlinear_fit_1.1.0.zip
→ enable Nonlinear fit integration demo

Analysis
→ Dataset sources (Analysis Source Map API v1)
→ primary = imported nonlinear fitting Dataset
→ X variable = primary.x
→ Y variable = primary.y
→ Run / recalculate this module
→ execute normal analysis Run

Results
→ demo.nonlinear.fit
→ fit_report.txt / fit_metrics.ini
→ Generated observations and nonlinear fit graph
```

The module uses the Analysis Source Map for Dataset-bound `primary.x` and `primary.y` selectors and resolves these GUI bindings to stable Dataset `variable_id` values before calling `NUMERIC_API_v1` and Table Stream API.

This second distinction matters because an imported Dataset may display
canonical variables named `x` and `y` while internally using stable IDs such as
`v0001` and `v0002`.


## 22. Dev097 migration validation

`validation/integrated_dev097/statistics_nonlinear_demo.tcl` runs the unchanged stock generator in an isolated Session, stable-ID binding, the actual module, metadata publication/reopen and one canonical plot. Its baseline mode runs accepted dev096 independently. `nonlinear_demo_reference.py` compares candidate parameters, covariance and standard errors with SciPy/NumPy using an independent analytic Jacobian. Development receipts and final acceptance are separate; validator presence does not itself claim a PASS. All historical generator and release archives remain preserved.
