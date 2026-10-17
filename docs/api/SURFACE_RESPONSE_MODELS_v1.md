# Physical surface response models

SPDX-License-Identifier: GPL-3.0-or-later

`NUMERIC_API_v1` fits a declared physical response `z=f(x,y)` with the existing
dimensional formula compiler and Ceres solver. The canonical statistical model is
`math.numeric.surface`. CORE `STATISTICAL_RESULT_SEMANTICS_API_v1` interprets the
captured result for every scientific module and both Script languages.

## Declaration and observations

`surface_model_compose(recipe)` uses the [formula declaration](FIT_FORMULA_v1.md)
with exactly `predictor_ids={x,y}`, two explicit linear predictor units, one
linear response unit and 1–32 physical parameters. Expressions, dimensional
receipts, initial values, bounds and fixed flags belong to the same compiler.
The returned `gxtxt.surface_model.v1` retains the complete recipe, parameter
identities/units, compiled expression identities and physical parameter state.
Mutating these identities or violating the declared constraints is rejected.

`surface_fit(model,x,y,z,options)` requires an explicit observation layout:

| Layout | Input | Original index ordering |
| --- | --- | --- |
| `points` | Three matched vectors; duplicates retain their observed multiplicity | Original vector order |
| `grid_yx` | Unique finite X and Y axis vectors; Z has exactly Y-by-X shape | Column-major original matrix order |

The maximum is 65,536 original observations. Input axes are never silently
sorted, transposed, resampled or interpolated. `nonfinite=error` is the default;
explicit `nonfinite=omit` removes nonfinite observed coordinate/response pairs.
Grid axes must always be finite. Missing Z cells remain missing source data.
`source_linear_indices` is a zero-based `uint64` vector into the original layout.
The observation receipt retains original shape/count, omitted count, ordering,
policy and exact original/retained working-array identities. Integer coordinates
outside the exact binary64 range are refused before conversion. Original
scientific datasets are not modified by these operations.

Response `sigma` or relative precision `weights` may be supplied, exclusively.
Their values must match every original observation; a matrix must have the exact
original shape. Retained uncertainties must be finite and positive. Zero weights
do not silently remove observations. Sigma supplies absolute measurement variance;
relative weights retain the shared solver's estimated-scale convention.
Predictor X/Y errors are outside this exact-coordinate model.

Other options are the existing `solver`, `strategy`, `max_iterations`,
`max_seconds`, tolerances, `parameter_scales` and `threads`. Defaults are 400
iterations and 30 seconds. Bounds and fixed flags come from the physical recipe;
the objective uses quadratic response residuals. Fit results retain the original
solver facts, covariance, observation signature, exact observed coordinates/Z,
the saved physical model and a bounded `gxtxt.surface_fit_summary.v1` receipt.

## Retained evaluation and export

`surface_evaluate(model,xy,options={})` accepts 1–65,536 finite N-by-2 coordinate
pairs and returns physical predictions, N-by-3 XYZ points, coordinate units and
extrapolation flags. `jacobian=true` returns the existing parameter Jacobian;
it does not claim derivatives with respect to X or Y. `extrapolation=error` is
the default; explicit `allow` retains an outside-bounds flag. An unfitted model
requires an explicit 2-by-2 domain `[xmin xmax; ymin ymax]`. A fitted model retains
its observed axis bounds. These bounds do not claim interior observation coverage,
including across missing cells or unobserved regions.

`surface_grid(model,x_axis,y_axis,options={})` requires strictly increasing finite
axes and at most 65,536 output cells. Its Y-by-X values are labelled
`sampled_declared_surface_model`; sampling the model does not fill source holes.
The normal [Dataset publication API](DATASET_PUBLICATION_API_v2.md) can publish
X/Y axes and rank-two Z with explicit dimension IDs and units. The existing
[Plot Dataset 3D API](PLOT_DATASET_3D_API_v1.md) consumes that declared sampled
Dataset through a persistent surface or mesh Variant.

`surface_residuals(model,x,y,z,options)` uses the same explicit layout/omission
contract, retained parameter evaluator and shared residual-metrics owner. Options
are `layout`, `nonfinite` and `extrapolation`. It performs no optimization and
returns unweighted physical Z residuals, original indices and a
`gxtxt.surface_residual_summary.v1` receipt. Evaluation cannot acquire training
DOF, covariance or parameter inference.

`model_export(model,{name,domain,source_reference})` generates independently
runnable Python and Octave functions plus LaTeX. The function name starts with
`fit_`; the explicit 2-by-2 export domain must lie within the retained observed
bounds. Generated functions accept finite N-by-2 XY pairs and return N-by-3 XYZ.
They reject unsafe integer narrowing and out-of-bounds coordinates. Metadata
retains the complete recipe, units, parameter values, expression hashes and
qualified coordinate domain. Python needs NumPy, plus SciPy for erf/Voigt
expressions; Octave needs its core runtime. Neither export requires GX-TXT.

## Common interpretation and Script calls

`surface_model_state(model)` returns the closed `gxtxt.surface_state.v1` envelope
containing the full recipe, physical parameter values, qualified observation
domain and declaration/source/binding SHA256 identities.
`surface_model_restore(state)` validates and reconstructs that retained model
without fitting. Unknown fields, altered expression identities, incompatible
units/constraints, out-of-bound parameters and invented domain coverage are
refused. The existing bounded scientific result file format can carry the state;
owned-resource integrity and model-state validation remain separate checks.
See [Fitter surface lifecycle and Script integration](FITTER_SURFACE_v1.md).

Use `from_numeric('math.numeric.surface','surface_fit',fit,context)` or
`from_numeric('math.numeric.surface','surface_residuals',evaluation,context)`.
CORE validates `z_of_xy`, physical Z residual units, both predictor identities,
original shape/count, parameter identities and formula binding. Common reports
retain exact-coordinate, missing-cell and conditional-uncertainty qualifications.
Parameter covariance and Gaussian intervals use the existing shared owners.
Supplying absolute sigma alone does not declare a Gaussian error distribution.
Ordinary one-predictor likelihood comparison plans do not establish a surface
comparison contract; their result remains explicitly unavailable.

Octave example:

```octave
model = gxtxt_api_call('NUMERIC_API_v1', 'surface_model_compose', {recipe});
fit = gxtxt_api_call('NUMERIC_API_v1', 'surface_fit', ...
    {model, x, y, z, struct('layout','grid_yx','nonfinite','omit','sigma',sigma)});
meaning = gxtxt_api_call('STATISTICAL_RESULT_SEMANTICS_API_v1', 'from_numeric', ...
    {'math.numeric.surface','surface_fit',fit, ...
     struct('noise_model','independent_gaussian_known_sigma')});
```

Python uses `from gxtxt import gxtxt_api_call`, the same operation names and
argument order, native dictionaries and NumPy arrays. Tcl consumers discover the
same contracts with `::GX::NumericAPIv1::operationMetadata` and use
`callOperation` with typed ScientificTransport operands. All numerical paths use
the existing binary transport and numerical owner. Modules consume common CORE
meaning instead of interpreting raw covariance or inventing private policies.
