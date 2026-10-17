# Numerical Uncertainty Demo — User Manual

## Purpose

This reference plugin demonstrates the uncertainty-aware capabilities that GX-TXT 0.9.8.10-dev-097 exposes through `math.numeric` / `NUMERIC_API_v1`. It is not a complete GUM uncertainty-budget, calibration or metrology application.

## Installation

Install `demo.numeric.uncertainty_1.1.0.zip` through the normal GX-TXT Plugin Install interface/API. The package requires GX-TXT 0.9.8.10-dev-097 or later and the bundled `math.numeric` service.

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
3. with `weight_semantics=inverse_variance`, the same summary supplies the known measurement uncertainty of the weighted mean and its reduced sum of squared residuals. No auxiliary fit is run. CORE displays reduced chi-squared only after selecting `noise_model=independent_gaussian_known_sigma`; the default unspecified model returns `unavailable`, and zero residual DOF returns `undefined`.

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
- `status`, `reason`, `quantity_id` from CORE interpretation

Standard-uncertainty mode publishes counts, arithmetic mean, propagated standard uncertainty of the mean, and value spread. Explicit-weight mode publishes counts, sum of weights, effective sample size, ordinary/weighted means and weighted spread; inverse-variance mode additionally publishes known measurement uncertainty and the explicitly qualified reduced chi-squared. Their legacy row IDs are preserved.

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

Supply an explicit weight variable when weighted estimation is desired. The selected interpretation remains explicit; this demo never silently converts the uncertainty column.

This demo does not provide a full uncertainty budget, Type A/Type B workflow, coverage-factor calculation, covariance editor, Monte Carlo propagation, calibration database or regression workbench.

## CORE interpretation

Both published Datasets include the validated ordinary summary and either the
weighted summary or `math.numeric.propagation` record. Propagated uncertainty of
the arithmetic mean assumes independent input measurements; its Jacobian is an
exact affine transformation. The generic API also supports correlated input
covariance and multiple named outputs with different units. This demo does not
supply a covariance editor or claim a confidence level. A single observation can
have a known supplied measurement uncertainty while its sample spread remains
undefined. Known zero uncertainty remains zero; missing estimates use NaN with
an explicit status and reason.

Targeted dev097 checks use analytical synthetic cases, public API round trips,
real Python/Octave Jobs and publication/reopen validation. The complete frozen
candidate acceptance and generator campaign remain separate release gates.
