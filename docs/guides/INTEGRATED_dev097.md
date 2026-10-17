# GX-TXT dev097 guide

This release targets Debian GNU/Linux. Existing scientific Dataset, Variable,
Session and Workspace identities remain stable. Work with a disposable copy
when trying new fitting settings; accepting a new result preserves its own
model settings, source bindings and scientific interpretation.

## Fit and inspect scientific models

Open **Dataset Curve Fit**, select the intended source Variables and inspect
their physical units and coordinate declarations. Use **Preview** to examine a
candidate, then accept it explicitly. Accepted results retain parameters,
residuals, assumptions and provenance. Display transformations do not silently
change the scientific source or fitting coordinates.

The [Fitter manual](../../plugins/modules/viewer.dataset_curve_fit/MANUAL.md)
covers ordinary and weighted regression, interpolation and smoothing, nonlinear
models, ODR, regional/family fitting, registered script models, and saved results.
Specialized contracts describe [full observation covariance](../api/FITTER_COVARIANCE_v1.md),
[implicit equations](../api/IMPLICIT_EQUATION_MODELS_v1.md),
[joint complex responses](../api/FITTER_COMPLEX_v1.md),
[surfaces](../api/FITTER_SURFACE_v1.md),
[rational models](../api/FITTER_RATIONAL_v1.md) and
[explicit knot models](../api/FITTER_KNOT_MODELS_v1.md).

Use **Results → Query selected model and derivatives…** for physical model
queries. Read the [query contract](../api/FITTER_RETAINED_QUERIES_v1.md) before
extrapolating or requesting an inverse: a missing root, singular derivative or
unsupported historical model produces an explicit availability result.

Parameter covariance, bootstrap and [profile likelihood](../api/FIT_PROFILE_LIKELIHOOD_v1.md)
answer different questions. Rank deficiency, active constraints, geometric
residuals and assumed noise models affect which quantities have an interpretation.
An unavailable uncertainty is not zero. Bayesian MCMC remains an explicitly
[unimplemented optional capability](../api/BAYESIAN_INFERENCE_AVAILABILITY.md).

## Shared statistical interpretation and scripts

[CORE Statistical Result Semantics](../api/STATISTICAL_RESULT_SEMANTICS_API_v1.md)
is the versioned authority for interpretation, units, degrees of freedom,
applicability and unavailable results. Numeric remains the calculation owner.
Fitter, Worksheet, scientific modules and real Python/Octave jobs consume this
common contract. Use the existing `gxtxt_api_call` interface and public discovery;
avoid private implementation paths or parallel result-policy tables.

The [transport contract](../api/SCIENTIFIC_BINARY_TRANSPORT_v2.md) preserves exact
64-bit integers, real and complex array types, shape and row lineage through
managed buffers. Dataset publication has its own storage contract: its eleven
real numeric types do not imply direct complex Dataset storage. Explicit
real/imaginary Variables preserve complex results where required.

The [current tutorials](tutorials_dev097/index.html) include the large-data,
STFT, Terrain and residual-validation workflows with downloadable sources,
scientific figures and their stated evidence scope. Keep input bindings and
dependencies in the documented order; a downstream validation job needs the
upstream measured data and fitted model.

## Units, plots and saved Sessions

Use public coordinate declarations to distinguish display units from the
underlying physical representation. The same policies reach Workbench, Preview,
Plot and native XYZ consumers. Declaring a custom canonical relation requires
both permitted forward and reverse expressions; an opaque label does not
automatically supply a scientifically valid conversion.

Initial Session opening reuses the existing Dataset authority only when Session,
exact Registry bytes, current in-memory record and transaction state agree.
External changes and recovery records return through the normal locked owner.
Huge Dataset payloads are not scanned merely to open the Session overview.

For digitized measurements, review [pixel and calibration uncertainty](../api/DIGITIZATION_UNCERTAINTY_v1.md)
before publication. Preserve the original image and calibration provenance;
display precision is not measurement uncertainty.

The independent [Calibrated Curve Digitization generator](../../session_generator_libraries/gxtxt.numerical_examples/generators/calibrated_digitizer/STUDENT_GUIDE.md)
provides a synthetic image, four exact physical points and analytical uncertainty
references. Generate a fresh Session to practise calibration and publication.
Existing user libraries can import its standalone ZIP through the Library Manager.

## Common problems

- **R² or chi-square is unavailable:** inspect the model, residual definition
  and noise assumptions. Do not substitute a number from a different convention.
- **A saved query or replay is refused:** inspect its producer, source binding
  and immutable receipt. Preserve the historical result and make a new explicit
  fit when its original execution contract is unavailable.
- **A Script Job fails during publication:** read the exact job log and check
  dtype, logical shape, units, ownership and source identity before retrying.
  Do not reinterpret large integers as floating-point values to bypass a guard.
- **A new native installation cannot load a library:** use the shipped relative
  layout and declared Debian dependencies. The [native rebuild guide](../legal/DEBIAN_NATIVE_REBUILD_dev097.md)
  explains source archives, notices, replacement builds and loader paths.

See [Common fitting errors](COMMON_FITTING_ERRORS.md) for worked scientific
examples. Independent numerical verification remains necessary when applying the workflows to new experimental measurements.
