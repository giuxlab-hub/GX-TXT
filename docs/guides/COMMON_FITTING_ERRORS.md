# Common fitting errors

Check the fitted observations, residuals, parameter units and uncertainty status
before accepting a model. A converged solver has met a numerical stopping rule;
the scientific report explains what its result supports. These examples use
named physical parameters so coefficient-vector order cannot change their meaning.

## A small example to keep the quantities distinct

Use time `x = [0, 1, 2, 3] s` and response `y = [1, 3, 2, 5] V`.
Ordinary straight-line regression gives

`y_fit = 1.1 V + (1.1 V/s) x`.

The observed-minus-fitted residuals are `[-0.1, 0.8, -1.3, 0.6] V`.
Their squared sum is `2.7 V²`. There are four observations and two fitted
parameters, giving two residual degrees of freedom. Thus:

**Response RMSE:** `sqrt(2.7/4) = 0.821584 V`. This describes the average
squared prediction discrepancy on these observations.

**Estimated residual SD:** `sqrt(2.7/2) = 1.161895 V`. This estimates the noise
scale conditional on this regression model.

**R²:** `1 − 2.7/8.75 = 0.691429`. This describes the reduction in squared
discrepancy relative to this sample's constant mean.

**Intercept standard error:** `sqrt(0.945) = 0.972111 V`. This describes
uncertainty of the fitted intercept under the stated error assumptions.

**Slope standard error:** `sqrt(0.27) = 0.519615 V/s`. This describes uncertainty
of the fitted slope under those assumptions.

These quantities have different denominators and meanings. The estimated noise
scale is not a standard error for either parameter. With independent Gaussian
errors and estimated variance, the marginal 95% intervals here use Student's t
with two degrees of freedom: the multiplier is about `4.30265`, not `1.96`.

## High R² does not establish a good model

A cubic through the same four observations has effectively zero training SSE
and R² of one. It uses four fitted coefficients and has zero residual degrees
of freedom: these observations cannot estimate its residual noise variance.
Estimated-noise covariance intervals are therefore unavailable.

Check residual patterns, the actual free-parameter count and the model's physical
assumptions. Do not choose a more flexible model solely because it reduces
training SSE. Model comparisons require the same retained observations and
compatible response/error definitions. An ineligible AIC/AICc comparison is not
made valid by copying the displayed scores into another table.

For a constant response, such as four measurements all equal to `5 V`, the
reference total variation is zero. GX-TXT marks ordinary R² undefined. That
status does not mean the data or the application have failed.

## Extrapolation can dominate the error

At `x = 6 s`, the fitted line above predicts `7.7 V`; the interpolating cubic
predicts `108 V`. Both match the same training range `0…3 s` according to their
own fitting criteria. Neither result establishes the response at `6 s`.

Inspect the retained training domain and extrapolation flags. Extend a curve
only when the scientific model justifies it, and review its domain restrictions.
A narrow interval conditional on a model does not account for an incorrect
extrapolation law. The output display range does not enlarge the training range.

## R² and reduced chi squared answer different questions

If the four response measurements have known independent standard uncertainties
of `0.5 V`, their absolute precision weights are `4 V⁻²`. The same fitted line
has chi squared `4 × 2.7 = 10.8`, and reduced chi squared `10.8/2 = 5.4`.
The discrepancy is large relative to that declared measurement-noise scale;
inspect the model, measurement uncertainties, residual structure and independence
assumptions. A single value does not identify which assumption is wrong.

Declaring the numbers `[4, 4, 4, 4]` as **relative** weights supplies no absolute
measurement scale. The estimated parameter covariance then equals the ordinary
unweighted result, and CORE does not label a reduced chi squared as available.
Choose response sigma or relative precision according to its actual origin.
Do not tune sigma merely to make reduced chi squared equal one.

## Correlation is not the same as nonidentifiability

For the line above, the intercept/slope covariance is `−0.405 V²/s` and their
correlation is about `−0.801784`. The parameters are still identifiable. If the
same line is written as `y = c + slope × (x − 1.5 s)`, then `c = 2.75 V` and
the intercept/slope covariance is zero. The intercept now refers to a different
physical point; the observations and their information have not changed.

Keep the full covariance when deriving thresholds, time scales or other combined
properties. Adding independent parameter variances would discard the cross term.
Use **Results → Derived physical properties** for supported expressions and read
the reported eligibility and units.

If all four X values are identical, a free slope and intercept cannot both be
identified. GX-TXT refuses the rank-deficient straight-line fit. Changing initial
guesses cannot create missing information. Fixed parameters are conditional
declared values, not precisely estimated parameters; they have no fitted interval.
Active bounds and rank loss can also invalidate ordinary local covariance claims.

## A logarithmic display does not change the fitting objective

Changing an axis to logarithmic display leaves the scientific observations and
the fitting objective unchanged. Explicit log-response fitting instead minimizes
errors in a declared dimensionless response ratio and changes the noise model.
Nonpositive responses cannot enter that logarithm.

For a Gaussian log response with location `ln(2)` and standard deviation `0.5`,
using a `1 V` response reference gives median `2 V` and mean
`2 × exp(0.5²/2) = 2.266297 V`. Simply exponentiating the fitted log location
produces the median. The mean correction requires the declared lognormal model;
an estimated log variance gives a plug-in estimate. A confidence interval for a
log location and an interval for a future observation have different targets.
Use the explicit log-response controls and retain their transformation report.

## Regression, interpolation and ODR use different information

PCHIP through the four example observations reproduces every observed Y exactly.
It is interpolation: this fact alone supplies no estimated parameter covariance,
confidence interval or evidence that observation noise is zero. A smoothing curve
also needs its own effective-complexity and variance treatment.

Ordinary Y(X) regression treats the supplied X values as exact. If both X and Y
have relevant measurement uncertainty, select an actually supported both-axis
ODR fit and bind sigma_X and sigma_Y to the original rows. For independent axis
errors, a displacement of `0.1 V` in X with sigma_X `0.1 V`, and `0.2 mA` in Y
with sigma_Y `0.2 mA`, contributes `1² + 1² = 2` to the normalized squared
distance. Adding the raw squared displacements would mix incompatible units.
Coordinate scaling or a geometric distance alone does not establish an ODR
measurement model. Read the report's residual definition and units.

## Preserve the population and read unavailable results

Review filters, omitted measurements, point selections, preprocessing and the
exact source-row audit before comparing fits. Screen decimation only changes
display. Smoothing can correlate errors, and fitting the smoothed values does
not automatically retain the original independent-error uncertainty assumptions.

For parameter bootstrap, inspect failed, boundary and unfinished trials. Such
trials remain in their original positions and withhold nominal percentile bounds.
Increasing the replicate count reduces Monte Carlo quantile error; it cannot
repair a wrong sampling assumption or prove coverage. A bootstrap confidence
interval is not a posterior credible interval. [Bayesian MCMC availability](../api/BAYESIAN_INFERENCE_AVAILABILITY.md) is stated separately.

Use the [Fitter manual](../../plugins/modules/viewer.dataset_curve_fit/MANUAL.md),
[model cards](../api/FITTER_MODEL_CARDS_v1.md),
[preprocessing audit](../api/FITTER_PREPROCESSING_v1.md), and
[statistical-result contract](../api/STATISTICAL_RESULT_SEMANTICS_API_v1.md)
for the actual controls and supported interpretations.
