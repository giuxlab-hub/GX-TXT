# Weighted Regression Session Generator

Portable GX-TXT Session Generator API v1 package for `demo.numeric.regression`.

Canonical destination:

```text
Library: GX-TXT Numerical Examples
Category: Mathematics
Generator: Weighted Regression
Generator ID: weighted_regression
Version: 1.0.0
```

It generates two ordinary CSV inputs:

```text
raw/weighted_linear_regression.csv
raw/weighted_polynomial_fitting.csv
```

Each contains `x`, measured `y`, `reference_y`, measurement standard uncertainty
`sigma_y`, and the explicit inverse-variance weight `weight_inv_variance = 1/sigma_y^2`.
The deterministic scientific truth is also recorded as namespaced `key=value`
metadata in `metadata/ground_truth_linear.txt` and
`metadata/ground_truth_polynomial.txt`. The analysis plugin does not require those
files; when equivalent keys are imported into Dataset Metadata, the plugin can
use them additively for parameter-truth diagnostics.

License: GNU GPL v3 or later.

## Ready-to-run Session (1.0.1)

Generation registers a canonical Dataset and saves its Analysis source, bindings, and settings in the Session Manifest. Open the generated Session in GX-TXT and use the normal Run page. The raw CSV and independent reference remain available for inspection; no Acquisition import is needed. Save, reopen, rerun, and HTML export were validated through the Tk GUI.

The Session includes both linear and polynomial Datasets. The initial configuration runs weighted linear regression. To exercise the polynomial source in the same Session, choose `regression.polynomial`, bind its `x`, `y`, `reference_y`, `sigma_y` and `weight_inv_variance` variables, set fit mode to `polynomial` and degree to `3`, then run again.
