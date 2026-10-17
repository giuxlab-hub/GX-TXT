# Arrhenius law in absolute temperature

`kinetics.arrhenius_temperature_v1` evaluates `prefactor*exp(-activation_temperature/T)`.
The predictor must be positive absolute temperature with declared unit `K`.
The positive prefactor has response units; activation temperature B has units K
and equals Ea/R. It is not an energy parameter. Converting B to molar activation
energy requires an explicitly chosen gas constant and energy units outside this
descriptor. Signed B allows apparent negative activation energies.

Fitting uses the original response and its stated error model, without a hidden
logarithmic transform. ODR may include temperature uncertainty and must retain
positive adjusted temperatures. Fitter translations are rejected for both axes;
use an explicit baseline component if the scientific model requires an offset.
Celsius data must be explicitly converted before binding, never relabeled K.

The fit is local and extrapolation assumes a constant activated process. CORE
controls covariance and interval eligibility. The absolute-unit, input-domain
and translation rules are frozen with the descriptor for later replay.

Reference: [IUPAC Arrhenius equation](https://goldbook.iupac.org/terms/view/A00446).
