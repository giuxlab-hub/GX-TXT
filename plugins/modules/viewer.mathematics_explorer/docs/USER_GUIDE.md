# Mathematics Explorer

Mathematics Explorer evaluates real functions through the public Numeric service
and presents them in the shared native interactive graph. It requires an open
Session. The optional module is separate from numerical Analysis selection.

## Functions, parameters and units

Enable up to three functions. Each row provides a label, preset and editable
formula. The accepted bounded formula grammar contains `x`, `a`, `b`, `c`, `pi`,
parentheses, `+ - * / ^` and `sin`, `cos`, `tan`, `exp`, `log`, `log10`, `sqrt`,
`abs`. Powers associate right to left; `-x^2` means `-(x^2)`. Expressions are data,
not Tcl, Python, Octave or shell commands.

Set parameters using their numeric fields or sliders. Sliders cover −10 to10;
the fields accept other finite values. Set the increasing X interval and32–1201
samples. **Plot / Refresh** evaluates the model. Changes schedule an update after
900ms; the bounded public worker call is synchronous.

Declare the units of X, each parameter and Y. Use `1` for dimensionless values.
Compatible scales are converted by the shared Unit Registry. For example,
`a*x+b`, with X in V, a in1 and b in V, can display Y in mV. A dimensioned sine,
incompatible sum, unknown unit, absolute affine arithmetic, nonfinite result or
invalid real domain produces an explicit error. Trigonometric arguments are
normalized dimensionless quantities; the radians convention applies. A failed
edit retains the previous valid graph with an explicit error status.

## Numerical analysis

Save the current model, choose **roots**, **intersections** or **extrema**, then **Analyze**. Roots and
extrema use Function1; intersections require Functions1 and2 enabled. The
analysis uses the displayed interval, explicit parameter/unit declarations and
public Numeric root/minimization methods. Results show status, residuals,
physical units, evaluation count and limitations.

The service samples a bounded grid to locate candidate intervals. It verifies
crossing roots and may identify non-crossing residual candidates. Neither finite
sampling nor a small residual proves all roots, continuity or exact
multiplicity. An identically near-zero sampled function remains indeterminate.
Local extrema are interior candidates; endpoint values are reported separately.
No measurement uncertainty or confidence interval is estimated. Analysis runs through the existing durable Script Jobs; **Cancel analysis** cancels only its owned process tree. The GUI remains responsive. Edited, replaced or foreign-Session models cannot adopt stale results. Closing the Viewer leaves the owned Job and its actual log available in Jobs.

**Show sampled derivative of F1** adds a separate native panel with its actual
unit. **Integrate F1** returns a composite trapezoidal integral and product unit.
Both depend on the selected sample grid. Compare suitable grids independently
when numerical accuracy matters.

## Native graph interaction and persistence

Wheel input zooms; middle-button drag pans; double-click fits the complete
sampled scientific extent, including negative coordinates. Clicking uses native
point identities. Resize changes presentation only. **Save model** persists
formulas, parameters, units and current numerical viewport through the Session's
Interactive Document authority. **Open…** restores a saved model and its view.
A Session switch cannot transfer an old window's work into another Session.

**Publish Dataset…** requires a saved current model and a new Dataset ID. It
creates canonical `x`, enabled `f1`/`f2`/`f3`, and optional `f1_derivative`
Variables with actual units, formula and Document provenance. **Publish Graph…**
also creates a retained native Graph Variant in Plots. Publication freezes
sampled values; later model edits do not change the published Dataset or Graph.
If a later Graph phase fails, its already committed Dataset remains available
and is identified in the error. Existing scientific data are never replaced.

The GUI does not overlay experimental Datasets or edit arbitrary multivariable
models. Scripts may use the public [Numeric expression operations](../../../../docs/api/NUMERIC_EXPRESSION_OPERATIONS.md)
for bounded canonical Dataset inputs, richer registered pointwise functions and
managed Script Job cancellation. The GUI's expression and sampling bounds remain
explicit. This is a numerical explorer, not a symbolic algebra system.
