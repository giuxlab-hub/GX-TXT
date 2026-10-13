# Numerical Root Finding Demo — Manual

## 1. Purpose

`demo.numeric.root_finding` is a small reference plugin demonstrating how a normal GX-TXT Canonical Dataset can drive the public callback-based root solver without private numerical infrastructure.

It is not a general equation solver. It does not parse formulas, search for all zero crossings, solve systems, compute complex roots, or implement its own interpolation/root algorithm.

The module consumes the public `NUMERIC_API_v1` service from `math.numeric` and normal Dataset/Publication/Plot contracts.

## 2. Public APIs used

The plugin uses the following public GX-TXT interfaces:

- Analysis Source API and stable `dataset_id + variable_id` bindings;
- Dataset Selection API v1 for an optional X-range Selection;
- Table Stream API v3 for source diagnostics only;
- `NUMERIC_API_v1` from `math.numeric`;
- Dataset Publication API v2;
- Dataset Variable Schema API v3 and Unit Registry semantics;
- `PLOT_DATASET_API_v2` through the public `standard_octave` bridge `gxtxt_plot_dataset_v2`;
- Plugin Install API v1;
- Session Generator Library API v1.

No private CORE files are read or written by the plugin.

## 3. Public root-finding API

`NUMERIC_API_v1` exposes:

```text
root_find(fun, bracket_or_initial, options)
```

through the public Octave binding. It accepts an executable function callback and delegates scalar root solving to the public `math.numeric` implementation. The result provides:

```text
root
fval
converged
exitflag
iterations
function_evaluations
solver
```

`root_find` is intentionally not serialized through the Tcl numerical worker because executable callbacks are Octave objects.

The same public numerical API also exposes:

```text
dataset_interpolate(session, dataset_id, x_variable_id, y_variable_id, xq, options)
```

This supplies the missing Dataset-to-function bridge needed by the demo. The plugin therefore composes the two public operations:

```text
Dataset curve
→ dataset_interpolate(query x)
→ scalar callback value
→ root_find(callback, explicit bracket)
```

No private interpolant is built.

## 4. Session Generator

Install/import:

```text
gxtxt_numerical_examples_root_finding_1.0.0.zip
```

into:

```text
GX-TXT Numerical Examples
```

Then use:

```text
New Session
→ Generate Session...
→ GX-TXT Numerical Examples
→ Mathematics
→ Root Finding
```

The generator creates:

```text
raw/root_finding.csv
metadata/ground_truth.txt
```

The CSV is deterministic and contains 161 samples on:

```text
-4 ≤ x ≤ 4
step = 0.05
```

for:

```text
f(x) = (x + 2) * (x - 0.5) * (x - 3)
```

The exact analytical roots are:

```text
-2
0.5
3
```

`metadata/ground_truth.txt` is only for tests and human inspection. The plugin never reads it.

## 5. Import the source Dataset

Import `raw/root_finding.csv` through the normal GX-TXT Acquisition workflow as a `table.generic` Canonical Dataset.

The documented demonstration Dataset ID is:

```text
root_finding.source
```

Bind the CSV variables as normal canonical variables:

```text
x
f
```

The reference example uses dimensionless unit `1` for both variables. Other compatible user Datasets may use real scientific units; the plugin preserves those units in the result Dataset.

## 6. Module bindings

Enable:

```text
demo.numeric.root_finding
```

and configure:

```text
Independent X variable
Function Y variable
```

Bindings are persisted by stable Dataset and Variable IDs. CSV column number, filename, and display label are not persistent scientific identity.

The X and Y variables must be different numeric variables from the selected source Dataset.

## 7. Dataset Selection

An optional GX-TXT X-range Dataset Selection may be assigned.

When present, the same Selection is passed to public `dataset_interpolate`, so interpolation and root solving use only the selected rows. The plugin does not implement a private row filter.

Every explicit root-search interval must remain inside the usable selected X domain. Public interpolation uses `extrapolation=error`.

## 8. Root-search intervals

Version 1.0.0 intentionally supports explicit bracket intervals only.

The configuration format is:

```text
start,end;start,end;...
```

Default demonstration intervals are:

```text
-3,-1;0,1;2,4
```

They bracket the three analytical roots independently.

The plugin does not scan the curve to discover sign changes. This is deliberate: GX-TXT 0.9.7.86 exposes a public scalar callback root solver but no public multi-root interval scanner. Building such a scanner privately would defeat the purpose of the demo.

For each configured interval the plugin first evaluates the two endpoints through public `dataset_interpolate`. A valid bracket must have either:

```text
f(a) = 0
or
f(b) = 0
or
opposite non-zero endpoint signs
```

Otherwise the run fails explicitly. The plugin never silently expands or moves the interval.

Overlapping intervals may return the same root more than once. The plugin does not privately de-duplicate roots.

## 9. Interpolation

Available public interpolation choices exposed by the demo are:

```text
linear
pchip
spline
```

The default is:

```text
linear
```

The selected method is passed to `NUMERIC_API_v1 dataset_interpolate` with:

```text
extrapolation=error
```

Interpolation requires strictly increasing X after the selected non-finite policy. GX-TXT does not silently sort X or merge duplicates.

Non-uniform strictly increasing X is supported because public interpolation uses the actual X coordinates. The root therefore belongs to the chosen interpolant of the sampled Dataset, not necessarily to an unknown analytical function that originally produced the samples.

## 10. Root solver settings

The public root solver uses the options exposed by `NUMERIC_API_v1`:

```text
tolerance
max_iterations
```

Defaults in this demo are:

```text
tolerance = 1e-10
max_iterations = 400
```

`root_find` reports solver name `fzero`, convergence state, exit flag, iteration count, and function-evaluation count where available.

The plugin rejects a non-converged result instead of publishing it as a valid root.

## 11. NaN / Inf policy

The module exposes the public numerical policy:

```text
error
omit
```

Default:

```text
error
```

`error` rejects a selected Dataset containing non-finite X/Y observations.

`omit` lets the public interpolation layer discard affected X/Y pairs where that operation is mathematically defined. The plugin never converts invalid data to zero.

## 12. Multiple-root workflow

The canonical demo contains three roots. Version 1.0.0 obtains them by three explicit legitimate public calls:

```text
[-3, -1] → root_find
[ 0,  1] → root_find
[ 2,  4] → root_find
```

This is not private root scanning. Each interval is user-visible configuration and is solved independently.

## 13. Boundary and tangent roots

A root exactly at a configured interval endpoint is allowed when the public solver accepts it.

Even-multiplicity/tangent roots such as:

```text
f(x) = (x - 1)^2
```

do not change sign. The public solver is bracket-oriented; this demo does not implement a private tangent-root detector. Such roots therefore require behavior supported directly by the public solver and are not guaranteed by this demo.

## 14. Published Dataset

Successful execution publishes the deterministic Dataset ID:

```text
demo.numeric.root_finding.roots
```

unless the user explicitly changes the configured output ID.

The schema is:

```text
root_id
root_x
f_at_root
interval_start
interval_end
iterations
function_evaluations
exitflag
converged
```

Unit semantics are:

```text
root_x         → source X unit
interval_start → source X unit
interval_end   → source X unit
f_at_root      → source Y unit
solver diagnostics → dimensionless
```

The source Dataset is never modified.

Publication provenance records the producer/version, source Dataset, source X/Y Variable IDs, Selection, public operations, interpolation method, explicit intervals, tolerance, and maximum iterations.

## 15. Human-readable report

The module writes:

```text
root_finding_report.txt
```

The report includes:

- plugin ID/version;
- source Dataset;
- X and Y variables and units;
- Selection;
- public numerical path;
- interpolation method;
- solver and effective tolerances;
- explicit intervals;
- detected roots and `f(root)`;
- convergence diagnostics;
- canonical-demo reference roots and absolute errors when the source is the documented demo Dataset;
- published Dataset schema;
- plot.dataset graph identity/artifact;
- warnings and limitations.

## 16. Automatic graph

GX-TXT 0.9.7.86 introduced the public `standard_octave` bridge to `PLOT_DATASET_API_v2`. This demo uses that bridge directly rather than implementing a plotting engine.

The PlotSpec contains:

```text
source Dataset f(x) → line series
published roots     → scatter marker series
y = 0               → public reference_line annotation
```

The graph is created as a `plot.dataset.xy` variant so the demo does not replace an existing base plot. The graph and PlotSpec are normal persistent GX-TXT state and survive Session reopen.

The source series uses the original source Dataset; detected markers use exactly `root_x` and `f_at_root` from the published result Dataset.

## 17. Canonical validation

For the generated cubic Dataset, the reference roots are exactly:

```text
-2
0.5
3
```

The default linear interpolant contains those sampled zero values exactly. Validation compares the published roots with those analytical values using numerical tolerance; it does not require impossible bitwise floating-point equality.

The plugin does not read generator ground truth during analysis. The analytical constants are used only to label/validate the documented canonical demo source; arbitrary compatible Datasets are analyzed without reference-root assumptions.

## 18. Save/reopen

Normal GX-TXT persistence applies to:

- module configuration;
- stable Analysis Source bindings;
- Dataset Selection identity;
- published roots Dataset;
- plot.dataset variant and PlotSpec state.

After reopening the Session, the derived Dataset and graph remain normal GX-TXT resources according to the framework lifecycle.

## 19. Known limitations

- Root solving is scalar and real-valued.
- Search intervals are explicit; there is no private automatic multi-root scanner.
- No symbolic equations are parsed.
- No complex roots or systems of nonlinear equations are supported.
- No tangent/even-multiplicity root detector is added.
- Root values describe the selected public interpolation method applied to sampled Dataset data.
- Intervals outside the selected interpolation domain fail because extrapolation is disabled.
- X must satisfy the public interpolation contract: strictly increasing after the chosen non-finite policy.
- The plugin does not sort, resample, smooth, or repair the source Dataset.

## 20. Tests

The package includes:

```text
tests/test_static.py
tests/test_numeric_runtime.m
tests/test_framework_integration.tcl
```

The focused runtime suite covers:

- the three known roots;
- no-root/invalid brackets;
- constant positive function;
- monotonic single crossing;
- boundary root;
- multiple roots through explicit intervals;
- non-uniform X composed with public interpolation;
- public NaN/Inf interpolation behavior;
- Dataset Publication;
- report generation;
- public plot.dataset graph creation;
- Session reopen.

When GNU Octave is unavailable, Octave-dependent checks are reported as `SKIP`, never as `PASS`.
