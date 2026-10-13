# Numerical 1D Minimization Demo — User Manual

## Purpose

`demo.numeric.minimization` demonstrates GX-TXT's public one-dimensional bounded minimization path on normal Dataset data. It is a reference plugin, not a general optimizer.

The production numerical path is:

```text
Canonical Dataset X/f(X)
→ Analysis Source / stable variable IDs
→ NUMERIC_API_v1 dataset_interpolate
→ callback containing only that public interpolation call
→ NUMERIC_API_v1 minimize_1d
→ Dataset Publication API v2
→ report + PLOT_DATASET_API_v2 graph
```

No private Dataset reader, interpolator, or minimizer is implemented.

## Baseline and public APIs

Version 1.0.0 was built against the authoritative GX-TXT 0.9.7.86 source. The relevant bundled numerical module is `math.numeric` 1.1.0 and its public `NUMERIC_API_v1` API version is 1.

The current public numerical architecture exposes:

- `dataset_interpolate(session,dataset_id,x_id,y_id,xq,options)`;
- callback-bearing `minimize_1d(fun,[lower upper],options)`;
- Dataset Selection support on Dataset-aware numerical calls;
- stable `dataset_id + variable_id` bindings.

`minimize_1d` uses GNU Octave `fminbnd` inside `math.numeric` and returns the optimum, objective value, convergence flag, exit flag, iteration count, function-evaluation count, and solver name where available. The plugin never calls `fminbnd` directly.

## Installation

Install `demo.numeric.minimization_1.0.2.zip` through normal GX-TXT Plugin Install. The package is independent and does not modify CORE.

The plugin contains a portable Session Generator package:

```text
gxtxt_numerical_examples_minimization_1d_1.0.0.zip
```

Import it into the existing **GX-TXT Numerical Examples** library if required.

## Demonstration Dataset

Choose:

```text
New Session
→ Generate Session...
→ GX-TXT Numerical Examples
→ Mathematics
→ 1D Minimization
```

The generator creates:

```text
raw/minimization_1d.csv
metadata/ground_truth.txt
```

The CSV columns are:

```text
x
f
```

with deterministic samples of:

```text
f(x) = (x - 1.75)^2 + 2
```

on `x=-3 ... 5` with step `0.05`. The exact analytical reference is:

```text
x_min = 1.75
f_min = 2
```

`metadata/ground_truth.txt` is only for tests and human inspection. The plugin does not read it.

Import `raw/minimization_1d.csv` through normal Acquisition as a `table.generic` Canonical Dataset. The documented example Dataset ID is `minimization.source`.

## Bindings

Bind:

- **Independent X variable** → the Dataset X coordinate;
- **Function Y variable** → the sampled objective value.

Bindings persist through stable Dataset and variable identities, not CSV column positions, filenames, or display labels.

## Selection and bounds

An optional GX-TXT X-range Dataset Selection can restrict the source data available to the numerical path.

The plugin also requires explicit public minimization bounds:

```text
Lower minimization bound
Upper minimization bound
```

with `lower < upper`. Both bounds must remain inside the selected Dataset X range. Extrapolation is always disabled.

The plugin does not silently swap invalid bounds and does not create a private row-range mechanism.

## Interpolation

Available public methods are:

- `linear` — default;
- `pchip`;
- `spline`.

The callback passed to `minimize_1d` evaluates each requested X through public `dataset_interpolate` with `extrapolation=error`.

X must therefore satisfy the public interpolation contract: strictly increasing after the selected non-finite policy, without duplicate coordinates. Non-uniform increasing X is supported by the interpolation path.

## NaN / Inf policy

The module exposes the public policy:

- `error` — default, rejects non-finite X/Y pairs;
- `omit` — explicitly omits non-finite pairs where public interpolation defines omission.

Non-finite values are never converted to zero.

## Minimization semantics

`NUMERIC_API_v1 minimize_1d` is a bounded scalar minimizer backed by GNU Octave `fminbnd`.

The demo describes its result as a **bounded scalar local minimum on the supplied interpolated curve**. For the canonical convex function this is also the unique bounded minimum. For a multimodal curve the operation must not be interpreted as exhaustive global optimization or as discovery of every local minimum.

A flat function has non-unique minima; any returned valid point is solver-dependent and must not be interpreted as a unique physical optimum.

## Tolerance and iteration limit

The configuration fields map directly to the public operation:

```text
Minimizer absolute X tolerance
Maximum minimizer iterations
```

Defaults are `1e-10` and `400` for this demo. The report records the effective values.

## Published Dataset

Default output identity:

```text
demo.numeric.minimization.result
```

The published `table.generic` Dataset contains one result row with:

```text
minimum_id
minimum_x
minimum_y
interval_start
interval_end
iterations
function_evaluations
exitflag
converged
```

Units are preserved as follows:

- `minimum_x`, `interval_start`, `interval_end` → source X unit;
- `minimum_y` → source Y unit;
- solver diagnostics → dimensionless.

Normal GX-TXT provenance records producer/version, source Dataset, source variable IDs, Selection/bounds, interpolation method, public numerical operations, tolerance and iteration limit.

The source Dataset is never modified.

## Report

The module writes:

```text
minimization_report.txt
```

It records source Dataset and variables, Selection, public operations, interpolation method, `fminbnd` solver identity returned by the public API, bounds, tolerance, counts, computed minimum, diagnostics, canonical reference/error where applicable, output Dataset and graph artifact.

## Graph

The module creates a normal `plot.dataset` Cartesian 2-D graph through the public standard-Octave `PLOT_DATASET_API_v2` bridge.

It contains:

- source `f(x)` as a line;
- published `(minimum_x, minimum_y)` as a marker.

No private plotting engine is used.

## Save/reopen

Module bindings/configuration, Dataset Selection, published result Dataset and normal plot state follow standard GX-TXT Session persistence. Fresh-package integration tests verify save/reopen behavior when the numerical runtime is available.

## Error behavior

Explicit errors are produced for missing Dataset/bindings, identical X/Y bindings, invalid non-finite policy, unsupported interpolation method, non-finite bounds, `lower >= upper`, bounds outside the selected X range, invalid Selection identity, missing public API capabilities, failed interpolation, or a minimizer that does not report convergence.

## Known limitations

- One minimum is computed for one explicit bounded interval per Run.
- The module is not a global/multimodal extrema enumerator.
- It does not extrapolate outside measured X data.
- Results are minima of the selected interpolant of sampled data, not of an unknown analytical source function.
- Only public `linear`, `pchip`, and `spline` interpolation choices are exposed here.
- Real numerical execution requires GNU Octave because callback-bearing `minimize_1d` is an Octave-binding operation.

## Tests

The package includes:

- static package/API-composition tests;
- focused real-Octave public numerical tests for quadratic, quartic, flat, monotonic, invalid-bounds, non-uniform-X and non-finite cases;
- fresh-package framework integration covering Plugin Install, Session Generator, Acquisition, Analysis Source, Selection, public capability discovery, Dataset Publication, report, graph and persistence.

Runtime-dependent tests report `SKIP` rather than false `PASS` when GNU Octave is unavailable.

SPDX-License-Identifier: GPL-3.0-or-later
