# Fitter complex frequency responses

Fitter consumes the public Numeric [complex response model](COMPLEX_RESPONSE_MODELS_v1.md)
and common CORE statistical interpretation. A real-valued source Y Variable is
the selected display projection; the objective fits all declared complex channels
jointly. Display scaling never supplies statistical weights.

## Declare and fit

Choose an exact Dataset source with positive physical frequency on X. Choose
Y matching the intended real, imaginary, magnitude or db20 projection. Open
**Fit → Joint complex responses…**, enable one to three channels, and enter their
IDs, physical units and real/imaginary formulas. Bind each channel to either
Cartesian real/imaginary Variables or amplitude/phase Variables. Polar input
requires explicit degrees or radians. db20 input requires a positive amplitude
reference expressed in that channel's physical unit. Integer phase turns do not
change the physical observations. Zero amplitude has unavailable phase.

Enter the shared parameters' explicit units, initial values, bounds and fixed
flags. Choose the displayed channel and projection; db20 display has its own
positive physical reference. The selected source Y values must agree with the
observed projection before optimization. Select an absolute Cartesian covariance
and confirm component units and original-row correspondence. Declare Gaussian
innovations only when justified. Validate checks the model and units; Apply saves
the declaration. Preview computes, then Accept and save preserve the result.

The covariance is M×M for a shared matrix, or a real float32/float64 M×M×N
Dataset Variable, with M=2×channel count and N=every original Dataset row.
Order components as real1, imaginary1, real2, imaginary2, and so on. Different
frequency rows are independent; covariance may couple channels within a row.
Entries have the product of their component units. For a homogeneous channel
unit the Dataset covariance unit must be its squared unit with no unconverted
prefix scale. A matrix with unlike component units has no single unit: leave
its Variable unit empty and supply the ordered component-unit declaration.
Covariance must be positive definite; no jitter or omitted null mode is added.

Filtering, explicit selection and whole-sequence reversal preserve exact original
uint64 row identities. The same IDs select every channel and the covariance's
third axis. Display decimation never supplies scientific observations. Original
Datasets remain unchanged. Owned float64 observation and covariance resources
retain exact hashes, shapes, units and training/evaluation roles. The original
Dataset and covariance Dataset identities remain in the recipe.

## Public API and Script Bridge

The Tcl call is `preview key complex_response scope domain degree initial options`.
The model owns its parameter initial values; the ordinary `initial` argument can
be empty and the polynomial degree is irrelevant. Supply:

- `complex_recipe`: `predictor_id`, `predictor_unit`, ordered `channels` and
  `parameters`, following the Numeric physical-model contract.
- `complex_data.channels`: ordered dictionaries with `channel_id`,
  `representation=cartesian|polar_linear|polar_db20`, `first_variable_id` and
  `second_variable_id`. Only polar forms add `phase_unit=rad|deg`; only db20 adds
  a positive numeric `reference` in channel units.
- `complex_data.covariance`: `layout=shared`, row-list `values` and ordered
  `component_units`; or `layout=per_observation`, `dataset_id`, `variable_id`,
  `source_dataset_id`, `row_binding=original_source_rows` and `component_units`.
- `complex_data.display`: `channel_id`, `projection=real|imaginary|magnitude|db20`;
  only db20 adds `reference={value,unit}` with the exact physical channel unit.

The orientation is physical `y_of_x`; translations are off. Parameter bounds and
fixed values belong to the recipe. Solver controls reuse the existing bounded
Ceres owner with a quadratic objective and one declared start. Default limits
are 400 iterations and 30 seconds. Both original and evaluated observation sets
are limited to 65,536 rows. Independent scalar/XY weights, full cross-frequency
covariance, unpropagated smoothing/baseline/log transforms, response bands,
bootstrap, influence and robust losses require different contracts and are refused.

Existing `recipe_capture`, `recipe_validate`, `recipe_run`, `result_info`,
`result_query`, `result_export`, `result_residual_page`, `result_parameters_publish`,
`result_publish` and `result_workbench` serve Python and Octave through
`gxtxt_api_call('DATASET_CURVE_FIT_API_v1', operation, arguments)`. Recipes retain
exact source, model, producer and covariance identities. No registered callback
or private statistics API is needed. `complex_settings` is the GUI command;
Workspace fields `complexRecipe` and `complexData` preserve its controls.

## Interpret and retain

`train_n` and `source_n` count physical frequency rows. CORE statistical `n`
counts Cartesian components; DOF uses the existing solver rank. Absolute
covariance gives a dimensionless innovation objective. Physical parameters keep
their own units. `noise_model=independent_gaussian_known_sigma` declares Gaussian
independent innovations under the supplied covariance. `unspecified` does not
authorize Gaussian parameter intervals. Rank loss, bounds and solver failures
retain their explicit inference availability. R-squared, pooled physical RMSE
and ordinary single-response likelihood comparison are unavailable.

Retained residual pages begin with source X, source Y, projected prediction and
projected residual, followed for each channel by observed real/imaginary,
predicted real/imaginary, physical residual real/imaginary, wrapped phase residual
and phase validity. `physical_column_units` names each column's unit;
`meaning_scope=joint_cartesian_covariance_objective` qualifies the common CORE
evaluation meaning. `display_projection` keeps the selected channel/reference.
Evaluation reuses captured parameters and has no training covariance or DOF.
The GUI residual plot shows the selected physical display residual; component
and phase diagnostics do not become extra objective terms.

Accept, persistence, publication, standalone Python/Octave export and retained
queries preserve the complete physical model, not merely its displayed trace.
Workbench imports a sampled editable curve and independently retains the
scientific model/resources. Parameter Datasets preserve the full declaration's
identity. Canonical Dataset publication uses real Variables; complex observations
are represented by explicit real/imaginary components. Historical scientific
identities are unchanged, and saved results are never silently refitted.

Named templates with shared Cartesian covariance require explicit mappings for
every channel Variable, including nondisplayed components. Rebinding replaces
original capture receipts with the new source identity; fitting and acceptance
remain explicit. Per-observation covariance belongs to its original rows and
cannot be transferred by a generic template. Use its exact recipe, or declare
a new covariance binding for the target source.
