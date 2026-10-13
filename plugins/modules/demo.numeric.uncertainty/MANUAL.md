# Numerical Uncertainty Demo — User Manual

## Purpose

This reference plugin demonstrates the uncertainty-aware capabilities that GX-TXT 0.9.7.82 actually exposes through `math.numeric` / `NUMERIC_API_v1`. It is not a complete GUM uncertainty-budget, calibration or metrology application.

## Installation

Install `demo.numeric.uncertainty_1.0.0.zip` through the normal GX-TXT Plugin Install interface/API. The package requires GX-TXT 0.9.7.82 or later and the bundled `math.numeric` service.

## Demonstration Session

Import the bundled generator package into the existing **GX-TXT Numerical Examples** library, then use:

`Generate Session... → GX-TXT Numerical Examples → Mathematics → Measurement Uncertainty`

The generator creates `raw/measurement_uncertainty_demo.csv` with:

- `measurement_id` — dimensionless measurement number;
- `value_V` — measured voltage in V;
- `sigma_V` — measurement standard uncertainty in V;
- `weight_V_m2` — explicit reference inverse-variance weight in `V^-2`.

The generator computes the weight column explicitly as `1/sigma^2`. That conversion exists only in the deterministic demonstration source. The analysis plugin never performs it automatically and never reads generator-private ground truth.

Import the CSV through normal Acquisition as a `table.generic` Canonical Dataset.

## Bindings

Bind:

- **Measured value variable** to the quantity being estimated;
- **Uncertainty / weight variable** to either a standard-uncertainty variable or an explicit-weight variable, according to **Input interpretation**.

Bindings are persisted through Dataset ID + stable variable ID, not CSV column number or display text.

## Input interpretation

### Standard uncertainty

The auxiliary variable is interpreted as measurement standard uncertainty of the measured value. For this first demo, its unit string must exactly match the measured-value unit string.

The public numerical path is:

1. `statistics(values)` → arithmetic mean and descriptive reference statistics;
2. `propagate_uncertainty(J, sigma, input_kind=standard_uncertainty)` → standard uncertainty of the arithmetic mean, where the plugin supplies the Jacobian of the mean.

`NUMERIC_API_v1` requires standard uncertainties to be finite and non-negative. Zero is accepted; negative uncertainty is rejected.

### Explicit statistical weight

The auxiliary variable is interpreted only as an explicit statistical weight. It is never reinterpreted as standard uncertainty.

The public numerical path is:

1. `statistics(values)` → ordinary mean of the finite paired observations;
2. `weighted_statistics(values, weights)` → weighted mean, weighted spread, sum of weights and effective sample size;
3. with `weight_semantics=inverse_variance`, `least_squares(ones, values, weights)` → coefficient standard error and reduced chi-squared using the public absolute inverse-variance covariance convention.

Public weighted statistics reject negative weights, discard zero weights, and require at least one positive weight.

`weight_semantics=relative` treats weights as relative statistical importance. Relative weights alone do not define absolute measurement uncertainty, so the plugin does not label a residual-scaled fit error as measurement uncertainty in this mode.

## NaN / Inf policy

`error` preserves the public rejection behavior. `omit` removes affected value/auxiliary pairs before uncertainty propagation because `propagate_uncertainty` itself requires finite inputs. Invalid finite uncertainties/weights are still validated by the public numerical operations and are never repaired or replaced.

## Dataset Selection

An optional normal GX-TXT X-range Dataset Selection can be applied before analysis. No private row-filtering UI or persistent range format is introduced.

## Published Dataset

The default output Dataset ID is `demo.numeric.uncertainty.result`. The Canonical Dataset uses a long-form schema:

- `quantity`
- `value`
- `unit`
- `definition`

Standard-uncertainty mode publishes counts, arithmetic mean, propagated standard uncertainty of the mean, and value spread. Explicit-weight mode publishes counts, sum of weights, effective sample size, ordinary/weighted means and weighted spread; inverse-variance mode additionally publishes the public least-squares estimate standard error and reduced chi-squared.

The Dataset preserves normal producer/source-variable provenance and never modifies the source Dataset.

The module also publishes `<output_dataset_id>.series`, containing the selected measurement values, auxiliary uncertainty or weight, and mean-reference variables. Plot.dataset reads this canonical Dataset when drawing and rerendering the graph; the render cache stores only its identity and presentation metadata.

## Report

`uncertainty_report.txt` records the source Dataset, bound stable variables, interpretation, public operations, Selection, counts, non-finite policy, results, units, weighting semantics and warnings/limitations.

## Graph

`01_uncertainty_measurements.png` is owned by the module's Graph Provider entry and rendered through the public Plot.dataset API. Its persistent Plot Variant can be edited with the framework plot controls and rerendered after reopening the Session.

- Standard-uncertainty mode shows measurement values with supplied standard uncertainty as Y error bars plus the arithmetic mean.
- Explicit-weight mode shows measurement values plus ordinary and weighted mean reference lines. Statistical weights are not drawn as uncertainty bars.

## Save / reopen

Normal module configuration, Analysis Source bindings, Selection identity and published Dataset state follow standard GX-TXT Session persistence rules.

## Known limitations

GX-TXT 0.9.7.82 does not expose a generic public `standard uncertainty → inverse-variance weight` conversion operation. This plugin therefore does not implement one privately. Supply an explicit weight variable when weighted estimation is desired.

This demo does not provide a full uncertainty budget, Type A/Type B workflow, coverage-factor calculation, covariance editor, Monte Carlo propagation, calibration database or regression workbench.
