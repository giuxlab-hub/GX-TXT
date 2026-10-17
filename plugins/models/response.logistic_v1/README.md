# Logistic response

`response.logistic_v1` evaluates `amplitude/(1+exp(-rate*(x-center)))`
with stable sign-dependent evaluation in saturated tails. Amplitude has units
Y, center units X, and rate inverse X. At the center the response equals half
the amplitude. Signed rate allows either transition direction; add a separate
constant baseline for a nonzero lower or upper plateau.

This is continuous nonlinear regression through the public Numeric fitter.
It is distinct from binary logistic regression and does not imply a Bernoulli
likelihood, probabilities or odds ratios. Zero amplitude or rate, or data far
from the transition, may leave parameters unidentified; CORE reports inference
eligibility. Initial values are reviewed dimensional placeholders.

The versioned descriptor and units are frozen in composed models, accepted
Fitter records and Script publications. Explicit coordinate translations are
visible in the Fitter physical formula and affect the fitted midpoint/baseline.
