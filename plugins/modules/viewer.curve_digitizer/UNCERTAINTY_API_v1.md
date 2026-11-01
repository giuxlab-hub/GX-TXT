# Curve Digitalizer physical uncertainty API

**Implementation:** `CURVE_DIGITIZER_UNCERTAINTY_API_v1`; published report schema `gxtxt.curve_digitizer.uncertainty.v2`.

## Provenance and scope

Physical uncertainty uses analytic homography and axis sensitivities with the per-calibration row and Session model. The v1 public reader is *independent* of the existing `CURVE_DIGITIZER_QUALITY_API_v2`: visual evidence about curve shape is not a metrological uncertainty model.

The uncertainty declaration is **disabled by default**, and no numeric uncertainty fields are pre-filled for a new declaration. The editor is available in **Publish → Pixel / calibration uncertainty...**. Every enabled declaration must contain a rationale. Two models are supported:

- **pixel_calibration**: `pixel_scale=[width_x,width_y]` plus explicit `pixel_distribution=rectangular_full_width|normal_standard_uncertainty`; and **12** (monoaxis) or **14** (Y1/Y2) calibration input standard uncertainties in the order BL(x,y), BR(x,y), TL(x,y), TR(x,y), X min, X max, Y1 min, Y1 max, then optionally Y2 min, Y2 max. A rectangular full width `w` becomes `w/sqrt(12)`; normal takes its supplied sigma directly.
- **physical_override**: explicitly declared independent standard uncertainties (X, Y) in monoaxis mode or (X, Y1, Y2) for dual-axis
  configurations, in the declared physical units. This *replaces* the pixel/calibration model and must not be interpreted as a measurement of calibration uncertainty.

For physical SEM scale-bar calibrations, the corner perturbations of a general homography do **not** represent the physical length/tick convention error. Nonzero corner uncertainties with a scale bar are rejected. Use a justified physical override until a separate scale-bar measurement model is implemented. The center/inner/outer convention remains a **systematic interpretation choice**, not a random error.

## Derivatives

The canonical 4-point map solves `A(c) h = b`, where `c` are eight pixel coordinates. Differentiation gives `dh/dc=-A^{-1}(dA/dc)h`. Applying the projective quotient derivative and the chosen physical axis transforms yields `Jpixel` (2N×2 point-local) and `Jcal` (2N×12 shared).

For each original point, the local 2×2 factor `L_i = Jpixel_i diag(sigma_pixel_x,sigma_pixel_y)` and shared 2×12 factor `S_i = Jcal_i diag(sigma_cal)`. The physical covariance for points i,j is:

`Cov(z_i,z_j) = [i=j] * L_i L_i^T + S_i S_j^T`.

The diagonal block contains `sigma_x^2`, `sigma_y^2` and `covariance_xy`. Within-point correlation and calibration-shared correlation are distinguished. Marginal sigmas alone never imply independence.

## Publication

Numeric publication retains the curve variables and the **stable original `point_id`** in every published curve Dataset. An enabled uncertainty declaration adds `sigma_x`, `sigma_y`, `covariance_xy` and:

- `curve_digitizer.uncertainty_schema_version=2`
- `curve_digitizer.uncertainty_report_json` — explicit declaration, mode, units and calibration summaries
- `curve_digitizer.uncertainty_factors_json` — zlib/base64/float64-le compact local/shared factors with SHA-256
- `curve_digitizer.uncertainty_dataset_sha256` — SHA-256 of published canonical bytes
- `curve_digitizer.uncertainty_source_sha256` — source image SHA-256

Publication uses the **actual ordered point rows for each accepted calibration** and verifies the source image hash. Uncertainty-enabled publication currently accepts **one calibration realization per Dataset**. If multiple accepted calibrations are selected, choose **Separate** layout; combined multi-realization uncertainty is rejected because shared pixel-click perturbations would require a cross-realization covariance model. Ordinary Combined publication without uncertainty remains supported. Changed row count, point identities, calibration identities and numeric X/Y values are rejected before the canonical publication transaction.

Uncertainty declarations are fingerprinted against source identity, axes, calibrations and original points. Changing these scientific inputs after **Apply and save declaration** requires an explicit re-review before publishing. Visual opacity and notes do not invalidate the declaration.

**Limits:** 4096 physical rows per output Dataset, 1 MiB of compressed factor metadata, and 512 rows for a materialized full X or Y covariance array. Larger datasets must be partitioned or use retained factors without matrix materialization. Metadata is not a separate external source file.

## Tcl API

```tcl
::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_UNCERTAINTY_API_v1
set result [::GX::CurveDigitizerUncertainty::read $datasetId]
set has [::GX::CurveDigitizerUncertainty::hasReport $datasetId]
set reportJson [::GX::CurveDigitizerUncertainty::reportJson $datasetId]
set factorsJson [::GX::CurveDigitizerUncertainty::factorsJson $datasetId]
```

The reader checks the canonical Dataset and source hashes when available. The two JSON strings are structured, documented and encoded independently of the viewer GUI. `read` returns `source_integrity` (verified, changed, missing, unknown), original row count and the canonical Dataset hash.

## Script Bridge Python / Octave

The public Script Bridge registration declares `uncertainty_read(dataset_id)`, `uncertainty_report(dataset_id)`, `uncertainty_factors(dataset_id)`, `uncertainty_available(dataset_id)`, and `uncertainty_covariance(dataset_id,axis)`. Matrix materialization is bounded to 512 source rows; its result is the real full covariance calculated from retained factors, **not** a diagonal approximation.

## CORE numerical owner, covariance and scientific Fitter

For an enabled declaration, the public Numeric service is **mandatory**. The saved configuration, accepted calibration and ordered original points are staged through typed binary transport. The public operation `gxtxt_numeric_v1('digitization_uncertainty',linearization,specification)` calculates the values; CORE Statistical Semantics validates the reported correlation and the fit plans. The host refuses publication if Numeric is absent or its output does not reproduce the calibrated X/Y and local preflight values.

Published metadata adds `curve_digitizer.uncertainty_binding` with its **retained managed-resource binding**. It binds original ordered points, saved configuration, numerical MAT state, physical float64 columns, interpretation and canonical Dataset bytes. It is not a copy of the local preflight JSON. The public reader requires the retained CORE binding to establish reviewed uncertainty; a local preflight report alone is insufficient.

```tcl
::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_UNCERTAINTY_API_v1
set capture [::GX::CurveDigitizerUncertainty::coreMeaning $datasetId]
set published [::GX::CurveDigitizerUncertainty::publishCovariance \
    $datasetId "${datasetId}.covariance_y" y]
```

The Companion API also exposes `publicationUncertainty`, `validateUncertaintyBinding`, `publishCovariance` and `covariancePublication` so the scientific Fitter can validate the original-row HDF5 covariance and the public CORE fit eligibility. Shared calibration is not admissible as independent sigma-only weighting, and within-point XY correlation may invalidate diagonal ODR. Original-order response covariance permits qualified GLS where CORE reports `status=value`; predictor uncertainty remains explicitly excluded. Materialization is bounded to 512 original points.

The Numeric and Companion public APIs own propagation, retained resources and covariance publication. Fitter consumers determine whether correlated response uncertainty is eligible for GLS or another declared model.

### Explicit zero localization and CORE ownership

`pixel_scale` accepts any two finite **nonnegative** values, including `[0, 0]`,
when `mode=pixel_calibration` and an evidence/rationale is explicitly supplied.
The calibration input standard uncertainties remain independent declarations.
The propagated result uses public `NUMERIC_API_v1`; there is no epsilon
substitution, raster-resolution default, or independent GUI-side solver.
The public Numeric operation supports explicitly declared zero localization without replacing it with a positive epsilon.
The public covariance reader continues to validate source identities and the
CORE statistical fit plan.

### Complete factor verification
The published `curve_digitizer.uncertainty_factors_json` is retained only when its entire point-local and calibration-shared loading arrays agree with the authoritative Numeric CORE state. Changing the sign of a shared loading can preserve every marginal uncertainty and still change cross-point covariance; publication explicitly rejects this condition. The physical X-times-Y `covariance_xy` unit is recorded and checked in both Variable Schema v3 and Dataset metadata. Unit convertibility remains the responsibility of CORE Unit Registry.


## 2.0.25 — Logical Y1/Y2 shared-calibration uncertainty

This version keeps the public API ID CURVE_DIGITIZER_UNCERTAINTY_API_v1 and
the CORE NUMERIC_API_v1/digitization_uncertainty operation. The actual
Numeric operation already accepts M=1..32 shared calibration inputs. The
producer now supplies 14 such inputs when Y2 is present:

    BL(pixel x,y), BR(pixel x,y), TL(pixel x,y), TR(pixel x,y)
    X minimum, X maximum, Y1 minimum, Y1 maximum, Y2 minimum, Y2 maximum

The point-local Jacobian is (2N×2); the shared Jacobian is (2N×14),
with physical coordinate rows interleaved X/Y for each original point. The
selected logical axis is read from the canonical text Variable y_axis_id.
The eight corner uncertainties and both X endpoint uncertainties are common
to Y1 and Y2. Their physical Y endpoint sensitivities are kept in separate
columns, ensuring scientific units are never interchanged.

The user must review all 14 nonnegative calibration standard uncertainties
and both pixel-localization declarations, including the distribution
assumption and justification. Or choose physical_override and explicitly
state the independent standard uncertainties for X, Y1 and Y2. The public
Numeric adapter maps each row to the correct physical Y1/Y2 override (N×2),
rather than applying an incorrect common Y standard uncertainty.

For a single Dataset mixing Y1/Y2, the Y physical units must be identical.
Different units require separate canonical output Datasets. Those outputs
can share a declared source, accepted calibration and Group; this retains
their common physical origin but does not fabricate a cross-Dataset covariance
matrix. The retained shared-factor coordinates identify the common
calibration sources within each output.

The low-rank factor schema is v1 (12 inputs) for legacy and v2 (14 inputs)
for dual-axis publications. The full shared factor matrix is SHA256 bound to
its exact float64-le bytes; the real CORE Numeric calculation checks each
local and shared loading before accepting Dataset publication. A sign error
in a common corner sensitivity may preserve every marginal sigma yet change
the correlation, so validating sigma alone is insufficient.

Publishing reviewed uncertainty on several accepted calibrations is
supported through Separate mode, with one individual source calibration
per published Dataset. Combining multiple independent calibration
realizations into one uncertain Dataset is rejected until a more general
cross-realization covariance model is reviewed. Missing CORE Numeric
services, stale Source/Document/point identities, wrong axes or malformed
14-input factors cause explicit errors.

This is first-order propagated **standard uncertainty**, conditional on
the documented input distributions. It is not measured accuracy and is not
a confidence interval. The public Statistical Semantics/Fitter remains
authoritative for eligibility of response-only GLS, XY ODR, or any other
fit model. CORE and the canonical contract registry are unchanged.
