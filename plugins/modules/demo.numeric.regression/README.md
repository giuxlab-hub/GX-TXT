# demo.numeric.regression

External GX-TXT 0.9.7.72 numerical demonstration plugin for public regression
and polynomial fitting through `math.numeric` / `NUMERIC_API_v1`.

The plugin supports:

- ordinary least-squares linear regression;
- weighted least-squares linear regression when a weight variable is bound;
- arbitrary-degree polynomial fitting;
- weighted polynomial fitting;
- coefficient standard errors and covariance-derived diagnostics;
- R², adjusted R², residual RMSE/MAE/max-absolute diagnostics;
- optional Dataset Metadata truth-coefficient diagnostics;
- six editable public Plot.dataset variants and Dataset-backed rerender;
- canonical fit-series and coefficient Dataset publication through Dataset Publication API v2.

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
