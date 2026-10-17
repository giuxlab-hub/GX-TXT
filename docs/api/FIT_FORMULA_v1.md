# Safe fit formula declaration v1

`NUMERIC_API_v1.fit_formula_compose(recipe)` creates an immutable data-only
expression model for the existing Numeric fitting, evaluation, prediction and
export operations. It does not run an optimizer while declaring a formula.
There is no Tcl/Octave/Python source evaluation. CORE's controlled grammar and
Unit/Dimension API check the declaration; Numeric's existing compiled expression
backend evaluates it and provides derivatives.

## Recipe

The recipe has exactly `expression`, `predictor_ids`, `predictor_units`,
`response_unit` and `parameters`. It supports one scalar response, 1..32 named
predictors and 1..128 named parameters. Predictor names and parameter names are
unique, separate identifiers; `pi`, `e` and called function names are reserved.
Every declared fitted parameter must appear in the equation. A predictor may be
unused, for example in a constant-response model, but still needs explicit units.

Each parameter is a struct with `id`, finite `initial`, optional `unit`, optional
`lower`/`upper`, and optional boolean `fixed`. Defaults are unbounded and free;
equal bounds make a parameter fixed. Initial values must satisfy the bounds.
An empty or omitted parameter unit requests dimensional inference. The initial
value is expressed in the resulting parameter unit, so inspect inferred units
before fitting. All supplied units must be supported linear units; use `1` for
dimensionless quantities. Convert semantic, affine or opaque scientific units
explicitly before declaring an equation.

The supported arithmetic is `+ - * / ^`, unary signs and parentheses, with named
scalar functions supported by both the controlled Numeric expression compiler
and its published unit rules, such as exp/log/sqrt/trigonometric/hyperbolic
functions and abs. The declaration rejects unsupported calls, undeclared symbols,
arrays/indexing, assignments and executable text. Limits are 32,768 characters,
4,096 expression tokens and the existing native program/stack bounds.

## Dimensions and numeric units

CORE solves structural dimensional constraints over its seven base dimensions.
If units cannot be determined uniquely, supply the ambiguous units explicitly.
For `a*x+b` with X in V and Y in mA, automatic inference yields a in A/V and
b in A; these are canonical units. To fit a in mA/V and b in mA, declare those
units. Inconsistent addition, dimensional logarithms and other invalid formulas
are refused. This dimensional check does not establish parameter identifiability;
the normal fit rank and covariance eligibility checks still apply.

Integer constant powers carry dimensions, including bounded constant arithmetic
such as `x^(1+1)`. A variable or noninteger exponent requires a dimensionless base
and exponent: write `a*(x/x0)^b` with x0 in the same dimensions as x. Square roots
must produce supported integer dimensions. This strict physical formula contract
does not assign a fixed unit to a dimensional base raised to a fitted exponent.

The original equation and declared symbol scales are frozen. Numeric inserts
conversion factors into the controlled expression: symbols convert to canonical
units, then the result converts to the requested response unit. Parameters,
bounds, optimization scales and covariance remain in the parameters' declared
physical units. There is no silent Dataset conversion, axis relabeling or change
to user data. Formula declarations prohibit Fitter coordinate translations.

For example, X in mV, a in mA/V, b in mA and response in A gives the effective
calculation `(0.001*a)*(0.001*x)+0.001*b`. At x=1000, a=3 and b=2, the response
is 0.005 A. The original author expression remains `a*x+b`.

## Public calls

```python
recipe = dict(expression='a*x+b', predictor_ids=['x'], predictor_units=['mV'],
              response_unit='A', parameters=[
                  dict(id='a', unit='mA/V', initial=1., lower=0., upper=10.),
                  dict(id='b', unit='mA', initial=1.)])
model = gxtxt_api_call('NUMERIC_API_v1', 'fit_formula_compose', [recipe])
fit = gxtxt_api_call('NUMERIC_API_v1', 'nonlinear_fit',
                    [x, y, model, model['initial_parameters'],
                     {'parameter_scales': [3., 2.]}])
meaning = gxtxt_api_call('STATISTICAL_RESULT_SEMANTICS_API_v1', 'from_numeric',
    ['math.numeric.nonlinear', 'nonlinear_fit', fit,
     {'x_unit': 'mV', 'y_unit': 'A',
      'noise_model': 'independent_gaussian_estimated_variance'}])
```

Octave Script Jobs use the same operation through `gxtxt_api_call`, or the public
Octave binding `gxtxt_numeric_v1('fit_formula_compose', recipe)`. Tcl uses
`::GX::NumericAPIv1::callOperation fit_formula_compose` with one typed recipe
operand. The resulting model goes through existing nonlinear fit/evaluation,
CORE parameter inference and independent Python/Octave export APIs.

## Retained declaration

`formula_declaration.schema='gxtxt.fit_formula_declaration.v1'` contains the
original recipe, original/effective expression, source-expression SHA256,
dimensional receipt and derivative/unit policies. The model also retains named
parameter order/units and initial/bound/fixed constraints. Replay validates these
facts together; changed expressions, conversions, units, fixed values or weakened
constraints fail. Solver options may tighten bounds but cannot weaken the frozen
constraints. The existing binding and expression hashes continue to identify the
compiled scientific model; no canonical identity is renamed.

The dimensional receipt is `gxtxt.expression_dimensions.v1` from
`gxtxt_unit_expression_dimensions_v1(expression, symbol_units, output_unit,
unknown_parameter_ids)`. It lists resolved units, symbol scales, inferred IDs,
used symbols, output scale/dimensions and the explicit normalization policy.
Only referenced symbol metadata participates in general expression checking;
unrelated Dataset columns do not change an expression's meaning. Numeric formula
declarations additionally validate their declared predictors and parameter use.

At non-smooth points or outside a function's real domain, a symbolic formula does
not guarantee valid derivatives or convergence. Retain native stopping/domain
diagnostics and CORE uncertainty eligibility; inspect the fitted result before
accepting it.

`NUMERIC_API_v1.expression_dimensions(expression, symbol_units, output_unit,
unknown_parameter_ids)` also exposes the generic CORE dimensional receipt to
Python, Octave and typed Tcl callers independently of fitting. The last two
arguments are optional. It delegates to the same public Unit/Dimension helper;
there is no second dimension engine. For example, `x*t` with `x=m/s` and `t=s`
returns output unit `m` without evaluating either series.

The Fitter authoring and replay adapter is documented in
[Dataset Curve Fit](DATASET_CURVE_FIT_API_v1.md#safe-physical-unit-formulas).
It retains the original declaration and uses this same native model for fitting,
prediction, bootstrap and export. Fitter currently binds one predictor `x` to
its selected independent physical axis; the generic constructor retains its
1..32-predictor contract.
