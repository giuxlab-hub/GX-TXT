# math.numeric

SPDX-License-Identifier: GPL-3.0-or-later

`math.numeric` is the bundled `core=1` numerical service for GX-TXT. It exposes the stable public `NUMERIC_API_v1` used by scientific modules for reusable mathematical primitives. Domain workflows remain outside this module.

The service provides data-only operation introspection, explicit observation
counts, coherent reductions, complex/phase operations, distributions, matrix
SVD, reproducible resampling indices and linear-time residual metrics. The
public `nonlinear_fit` operation offers an optional bounded fallback
(`bounded_fminsearch=penalty_clip`) and `fallback_on_solver_error` for `auto`.
Default solver behavior remains strict; the caller must request fallback.

The current API provides dimension-aware `matrix_statistics` for finite real
matrices, vector normalization, vector similarity, cumulative sums and weighted
quantiles, as well as reusable analytic-signal construction, FFT/IFFT,
frequency-grid, one-sided-transform, detrending and window generation. The service also provides interpolation and resampling, cubic spline/PCHIP models, numerical calculus, grid/range utilities, descriptive and weighted statistics, OLS/WLS, linear regression, arbitrary-degree polynomial fitting, generic nonlinear least squares, smoothing, coefficient-based digital filtering, peak primitives, generic baseline estimation, root finding/minimization, first-order uncertainty propagation, and Dataset-aware forms for the operations that naturally apply to canonical scientific variables.

Low-level numerical code uses documented GNU Octave functionality. It does **not** call GX-TXT internal Scientific Analysis kernel dispatchers. Dataset-aware calls use public Canonical Dataset, Table Stream v3, Dataset Variable Schema v3 and Dataset Selection APIs; storage providers remain transparent.

The Tcl facade is intended for data-only calls. Registered Octave and Python scripts can pass execution-scoped callback handles to `nonlinear_fit`, `dataset_nonlinear_fit`, `root_find`, `minimize_1d`, `minimize`, and callback-bearing foundation actions. Direct Octave calls keep accepting function handles. No executable source is serialized through the Bridge.

The module does not implement scientific spectrum/PSD workflows, Curve Family Fitting semantics, tube/thyratron models, chromatography workflows, UV/Vis workflows, peak identity, or chemistry-specific calculations. Generic FFT/IFFT, analytic-signal construction and related transform helpers are mathematical primitives exposed for those consumers.

## Bundled CORE package

This archive is a release-integration package for `plugins/modules/math.numeric/`. It is not a normal user plugin and contains no user-extension installer manifest. It must not be treated as a user-installable extension.

See `NUMERIC_API_v1.md` for the complete public contract and `tests/run_tests.sh` for validation.

Savitzky-Golay uses `sgolayfilt` from the Octave `signal` package. Generic nonlinear fitting uses base-Octave `fminsearch` as an unbounded fallback; bounded least squares uses `lsqnonlin` from the Octave `optim` package when available. Missing optional packages produce explicit numerical errors for the affected operation rather than changing methods silently.

Real/complex linear algebra is available through `linear_matrix` (see
`NUMERIC_API_v1.md` section 2.2). The public `foundation` operation provides
vector/tensor and geometry operations, multidimensional interpolation and
integration, derivatives, adaptive and stiff ODE methods, constrained SQP
and diagnostics, sparse and equation operations, variational methods and
statistics/special functions. Registered Octave and Python scripts may use
execution-scoped handles for supported callback-bearing actions; data-only
Script Bridge operations remain available.
