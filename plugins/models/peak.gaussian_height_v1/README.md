# Gaussian peak (height, sigma)

`peak.gaussian_height_v1` version 1.0.0 is a reusable scalar regression component.

Equation: `height*exp(-0.5*((x-center)/sigma)^2)`. The independent coordinate is `x`.

| Parameter | Meaning | Unit | Domain |
| --- | --- | --- | --- |
| `height` | Peak height above the separate baseline | Y | real |
| `center` | Peak center | X | real |
| `sigma` | Positive Gaussian standard-width parameter | X | positive |

`X` and `Y` denote the declared independent and response units. Peak height is not integrated area. FWHM = 2*sqrt(2*log(2))*sigma.

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
