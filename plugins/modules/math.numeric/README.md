# math.numeric

SPDX-License-Identifier: GPL-3.0-or-later

`math.numeric` is the bundled `core=1` numerical service for GX-TXT. It exposes the stable public `NUMERIC_API_v1` used by scientific modules for reusable mathematical primitives. Domain workflows remain outside this module.

Callback nonlinear fits support mixed fixed/free parameters and equal-bound
constants through the same public operation in direct Octave and both Script
languages. They preserve physical parameter order, free-rank/DOF and full
covariance shape; all-fixed evaluation bypasses optimization. See
[the callback contract](NUMERIC_API_v1.md#9-generic-nonlinear-least-squares).

Version 1.9.0 adds data-only operation introspection, explicit observation counts, coherent reductions, generic complex/phase operations, reusable distribution mathematics, matrix SVD, and reproducible resampling indices. Version 1.8.0 added linear-time public residual metrics for reusable model verification. Version 1.7.0 added an explicit bounded `nonlinear_fit` fallback (`bounded_fminsearch=penalty_clip`) and optional `fallback_on_solver_error` for `auto`. The default solver behavior remains strict; callers must request the fallback.

Version 1.6.0 adds public dimension-aware `matrix_statistics` for finite real matrices. Version 1.5.0 added public vector normalization and vector-similarity primitives. Version 1.4.0 added cumulative-sum and arbitrary weighted-quantile primitives. It retains reusable analytic-signal construction, FFT/IFFT, frequency-grid, one-sided-transform, detrending and window-generation primitives. The service also provides interpolation and resampling, cubic spline/PCHIP models, numerical calculus, grid/range utilities, descriptive and weighted statistics, OLS/WLS, linear regression, arbitrary-degree polynomial fitting, generic nonlinear least squares, smoothing, coefficient-based digital filtering, peak primitives, generic baseline estimation, root finding/minimization, first-order uncertainty propagation, and Dataset-aware forms for the operations that naturally apply to canonical scientific variables.

Low-level numerical code uses documented GNU Octave functionality. It does **not** call GX-TXT internal Scientific Analysis kernel dispatchers. Dataset-aware calls use public Canonical Dataset, Table Stream v3, Dataset Variable Schema v3 and Dataset Selection APIs; storage providers remain transparent.

The Tcl facade is intended for data-only calls. Registered Octave and Python scripts can pass execution-scoped callback handles to `nonlinear_fit`, `dataset_nonlinear_fit`, `root_find`, `minimize_1d`, `minimize`, and callback-bearing foundation actions. Direct Octave calls keep accepting function handles. No executable source is serialized through the Bridge.

The module does not implement scientific spectrum/PSD workflows, Curve Family Fitting semantics, tube/thyratron models, chromatography workflows, UV/Vis workflows, peak identity, or chemistry-specific calculations. Generic FFT/IFFT, analytic-signal construction and related transform helpers are mathematical primitives exposed for those consumers.

## Bundled CORE package

This archive is a release-integration package for `plugins/modules/math.numeric/`. It is not a normal user plugin and contains no user-extension installer manifest. It must not be treated as a user-installable extension.

See `NUMERIC_API_v1.md` for the complete public contract and `tests/run_tests.sh` for validation.

Savitzky-Golay uses `sgolayfilt` from the Octave `signal` package. Generic nonlinear fitting uses base-Octave `fminsearch` as an unbounded fallback; bounded least squares uses `lsqnonlin` from the Octave `optim` package when available. Missing optional packages produce explicit numerical errors for the affected operation rather than changing methods silently.

Version 1.10.0 adds public real/complex linear algebra through `linear_matrix`; see `NUMERIC_API_v1.md` section 2.2.
Version 1.13.0 adds the P1/P2 geometry, sparse, equations, variational and statistics families, advanced matrix/special functions and stiff ODE options. Version 1.11.0 adds vector/tensor, multidimensional interpolation and integration, derivatives, adaptive ODE IVP, constrained SQP diagnostics and essential special functions through the public `foundation` operation. Version 1.12.0 makes callback-bearing operations available to registered Octave and Python scripts through execution-scoped handles; data-only Script Bridge behavior remains available.

Retained queries support physical orientations/translations and radial frames;
centered/scaled polynomials support derivative orders 0..12. See
[retained query contracts](../../../docs/api/RETAINED_MODEL_QUERIES_v1.md).

Live registered callback queries use declared two-sided numerical differences
with explicit unavailable masks and share the existing bounded local root owner.
They are exposed to both Python and Octave Script Jobs; no automatic derivative
or statistical uncertainty is claimed for opaque callback code.
