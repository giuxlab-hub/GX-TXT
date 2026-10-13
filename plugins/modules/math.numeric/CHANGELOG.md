# math.numeric 1.17.0

Reusable reversible positive-axis translation and optional reviewed point ordering, including retained closed endpoints.

# 1.16.1 — dev093

Use the shared typed binary Script Bridge worker without changing scientific
algorithms or public v1 defaults. Preserve existing Tcl/Octave consumers.

# math.numeric changelog

## 1.16.0 — GX-TXT0.9.8.10-dev-052

Ordered parametric/polar/oriented models, sparse smoothing and indexed native cubic projection, exact reconstruction and independent scientific validation.

## 1.12.0 — Execution-scoped script callbacks

## 1.13.0 — P1/P2 mathematical foundation

- Added Schur, principal matrix logarithm/square root, stiff ODE/events/dense output, variational/equations/sparse/statistics/geometry families and VTK-backed mesh/STEP cuts.
- Added derivative-free constrained fallback and advanced special functions.
- Validated 67 known-answer checks plus public API and Bridge discovery.

- Accept registered Octave and Python callbacks for public ODE, constrained optimization, callable derivatives, root finding, minimization and nonlinear fitting, including Dataset fitting.
- Keep callback registration and reverse invocation in the shared Script Bridge; preserve direct Octave and data-only provider paths.

## 1.11.0 — Mathematical foundation extension

- Add vector/tensor algebra, 2D/3D regular and scattered interpolation, integration, finite differences, adaptive ODE IVP, constrained SQP/KKT diagnostics and essential special functions.
- Expose data-only foundation operations through the same provider-owned Octave/Python Script Bridge.

## 1.10.0 — Mathematical API foundation

- Add split-complex matrix transport, inspection, solve with explicit rank policy, decompositions, eigenproblems, inverse/pseudoinverse, matrix exponential/power and provider-owned Octave/Python Script Bridge operation.
- Add focused numerical and script acceptance fixtures.

## 1.9.1

- Resolve Dataset Selections through public read-only Session Inspection and Canonical Dataset variable metadata.

# math.numeric changelog

## 1.9.0

- Added data-only operation introspection to the Tcl and Octave bindings, with stable IDs, signatures, binding availability, result metadata, and unit rules.
- Added explicit input/valid/nonfinite observation counts to descriptive and weighted results; expanded axis reductions and typed Script Bridge result adaptation.
- Added generic ranking, covariance, Pearson/Spearman correlation, MAD, histogram, ECDF, split-complex arithmetic/phase, probability CDFs, matrix SVD, and seeded resampling indices.
- Added a chunk-composable Dataset summary for count, sum, mean, min, and max; full-result and sorting/fitting operations retain their explicit memory requirements.
- Shared Scientific Analysis expressions now dispatch arithmetic and discoverable functions through the public numerical API.
- Added Octave `student_t_quantile` and `hypothesis_test` primitives for one-sample, independent, Welch and paired t-tests plus Mann-Whitney and signed-rank tests. Rank tests use exact conditional enumeration for at most 20 observations and a documented tie-corrected normal approximation for larger samples.
- Added Octave `one_way_anova` for ordinary and Welch group comparisons, group summaries, F/p values, sums of squares and ordinary-ANOVA effect sizes.

## 1.8.0

- Adds public `residual_metrics` to NUMERIC_API_v1 for reusable RMSE, MAE, maximum error, R² and relative-error summaries, with a finite-input and relative-floor contract.

SPDX-License-Identifier: GPL-3.0-or-later

## 1.6.0

- Added public Octave `matrix_statistics` with dimension-aware mean, median, variance and standard deviation for replicated curve datasets.

## 1.5.0

- Added public `vector_normalize` / `normalizeVector` with `unit_vector` and `mean_center_unit_vector` methods.
- Added public `vector_similarity` / `vectorSimilarity` with cosine, Pearson, angular-similarity and normalized-residual methods.
- These generic primitives remove reusable vector mathematics from spectroscopy/domain consumers while preserving their scientific matching semantics.

## 1.4.0

- Added public `weighted_quantiles` / `weightedQuantiles` for arbitrary weighted empirical-CDF inverse quantiles.
- Added public `cumulative_sum` / `cumulativeSum` as a generic vector reduction.
- These additions allow scientific consumers such as `analysis.spectral_features` to keep percentile and cumulative-distribution semantics in the analysis layer without implementing generic reductions privately.

## 1.3.0

- Added public `analytic_signal` / `analyticSignal` construction using the standard FFT Hilbert multiplier for even and odd real-valued records.
- The primitive returns split complex data plus amplitude and deliberately excludes detrending, band selection and PSD/spectrum semantics.
- Added Octave and Tcl regression coverage and exposed the `analytic_signal` capability through normal dependency discovery.

## 1.2.0

- Added public `NUMERIC_API_v1` FFT and IFFT primitives with explicit transform length and normalization conventions.
- Added reusable frequency-grid and one-sided transform selection helpers with explicit DC/Nyquist behavior.
- Added generic `none`/`mean`/`linear` detrending and reusable rectangular, Hann, Hamming, Blackman, Blackman-Harris and flat-top windows.
- Exposed the new data-only operations through the Tcl facade/worker using split real/imaginary transport for complex transforms.
- Added deterministic transform, round-trip, odd/even, frequency-grid, detrend and window regression coverage.

## 1.1.0

- Completed `NUMERIC_API_v1` before framework integration while preserving the existing v1 operation names where practical.
- Removed the dependency on internal `gxtxt_analysis_dispatch_kernel` implementation details; low-level primitives now use documented GNU Octave numerical functions.
- Added nearest/linear/cubic/spline/PCHIP interpolation, arbitrary-grid resampling, portable spline models, spline evaluation and spline integration.
- Added cumulative integration, non-uniform-coordinate differentiation, uniform-grid generation, monotonic validation and expanded grid statistics.
- Added quantiles, expanded descriptive/weighted statistics, linear regression and richer OLS/WLS diagnostics.
- Added arbitrary-degree polynomial fitting, weighted polynomial fitting and polynomial model evaluation, with explicit relative/inverse-variance weight semantics for covariance scaling.
- Added generic nonlinear least squares with structured diagnostics, optional bounds through Octave `optim`/`lsqnonlin`, and an unbounded `fminsearch` fallback.
- Added moving mean, moving median, Savitzky-Golay and local-polynomial smoothing; coefficient-based causal digital filtering.
- Added generic peak detection with height, distance, prominence and width primitives.
- Added constant, linear, polynomial and anchor-interpolated baseline estimation with corrected-signal output.
- Added scalar root finding, one-dimensional and multivariable minimization, plus first-order covariance/independent uncertainty propagation.
- Expanded Dataset-aware operations to interpolation/resampling, cumulative integration/differentiation, weighted statistics, polynomial fitting, nonlinear fitting (Octave callback binding), smoothing, peaks and baseline estimation.
- Removed Plugin Install API packaging/instructions: `math.numeric` remains bundled CORE.

## 1.0.0

- Initial protected bundled numerical service with interpolation/resampling, integration/differentiation, grid/range utilities, statistics, OLS/WLS and basic Dataset-aware operations.
# 1.7.0

- Added explicit bounded `fminsearch` penalty/clipping and optional `auto` solver retry to the public Octave `nonlinear_fit` operation. Curve Family Fitting can now use the CORE numerical service while preserving its prior bounded fallback.
## 1.14.0 — Guided mathematical clients

- Added provider-owned discovery metadata for 115 foundation subactions.
- Added public data-only catalog dispatch, including Octave-only statistics operations, and bounded declarative model callbacks for guided clients.
- Extended shared scientific transport to preserve nested result structs and cells.
