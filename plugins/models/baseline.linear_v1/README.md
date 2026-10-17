# Linear baseline

`baseline.linear_v1` version 1.0.0 is a reusable scalar regression component.

Equation: `intercept+slope*x`. The independent coordinate is `x`.

| Parameter | Meaning | Unit | Domain |
| --- | --- | --- | --- |
| `intercept` | Response baseline at x = 0 | Y | real |
| `slope` | Baseline change per independent-coordinate unit | Y/X | real |

`X` and `Y` denote the declared independent and response units. The baseline is fitted jointly with the selected peaks; it does not replace source values.

Use `NUMERIC_API_v1` `fit_model_catalog` to discover this card and
`fit_model_compose` to combine components with explicit initial values and
optional shared parameter identities. Fit the returned expression through
`nonlinear_fit`; evaluate it through `nonlinear_evaluate`. Native automatic
differentiation supplies the parameter Jacobian. Bounds and fixed parameters
use the shared Ceres solver. Strictly positive parameters use the smallest
normal binary64 number as their numerical lower bound.

Defaults are dimensional placeholders requiring review. Negative heights are
allowed for absorption dips. Finite real coordinates are supported. Formula
extrapolation does not establish physical validity beyond measured support.
Local covariance and pointwise intervals require the public CORE eligibility
checks for rank, convergence, constraints and the chosen measurement model.
Overlapping or interchangeable components can be unidentifiable; a sum does
not establish a unique physical decomposition.

The fitted model captures descriptor version, SHA256, formula, units and
parameter mapping. Reopening a saved model evaluates that frozen declaration.
The original Dataset and its scientific identities remain unchanged.
