# demo.numeric.regression

External GX-TXT 0.9.8.10-dev-097 numerical demonstration plugin for public regression
and polynomial fitting through `math.numeric` / `NUMERIC_API_v1`.

The plugin supports:

- ordinary least-squares linear regression;
- weighted least-squares linear regression when a weight variable is bound;
- arbitrary-degree polynomial fitting;
- weighted polynomial fitting;
- coefficient standard errors and covariance-derived diagnostics interpreted by the public CORE statistical API;
- R², adjusted R², residual RMSE/MAE/max-absolute diagnostics;
- optional Dataset Metadata truth-coefficient diagnostics;
- six editable public Plot.dataset variants and Dataset-backed rerender;
- canonical fit-series and coefficient Dataset publication through Dataset Publication API v2.

Both output Datasets retain validated CORE statistical metadata. Existing numeric fields and coefficient order remain stable; coefficients add parameter identities, units and uncertainty status/reason columns. Reduced chi-squared requires declared independent Gaussian measurement errors with known absolute sigma.

The sigma/weight numerical consistency check now uses public Numeric residual
metrics and a third CORE comparison record on both outputs. Its legacy INI error
field carries quantity identity, unit, status and reason. Missing input bindings
are unavailable. A complete consistency claim requires every expected inverse
variance to be eligible at the recorded `realmin` denominator floor and the
maximum relative discrepancy to be at most `1e-8`; excluded subnormal denominators
cannot certify consistency. Nonfinite or zero inverse variances are rejected
before publication. This diagnostic does not establish a measurement noise model.

Canonical stock Session Generators:

```text
GX-TXT Numerical Examples → Mathematics → Linear Regression
GX-TXT Numerical Examples → Mathematics → Polynomial Fitting
```

Weighted demonstrations use the separately distributed portable generator:

```text
GX-TXT Numerical Examples → Mathematics → Weighted Regression
```

The plugin does not read Session Generator files directly and does not require
Dataset Metadata. Imported Dataset Metadata is optional and only enriches truth
and provenance diagnostics.

License: GNU GPL v3 or later.
