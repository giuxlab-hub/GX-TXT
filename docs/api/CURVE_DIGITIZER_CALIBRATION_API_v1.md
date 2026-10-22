# CURVE_DIGITIZER_CALIBRATION_API_v1

Version 1, provider `viewer.curve_digitizer`, namespace
`::GX::CurveDigitizerCalibration`, entrypoint
`api/curve_digitizer_calibration_api_v1.tcl`. This reads published calibration
metadata and applies that producer's retained mapping. It neither edits the GUI
configuration nor infers calibration from Variable names or raster display.

## All public methods

| Exact Tcl signature | Actual result |
|---|---|
| `read datasetId ?session=""?` | Validated published calibration manifest dictionary; omitted Session uses current Session |
| `hasCalibration datasetId ?session=""?` | Boolean metadata-tag/version presence check; catches metadata-read errors, not equivalent to full read/transform validation |
| `schema` | API/version, manifest fields/types, all eight methods, point/direction/measurement/fingerprint conventions |
| `replicates datasetId` | List of published calibration measurement dictionaries; current Session |
| `transformPoints datasetId points direction ?measurementId=""?` | Complete transformed list of XY pairs, or error without a partial returned list |
| `identity datasetId ?measurementId=""?` | `{available 1 calibration_id sha256 source_sha256}` or `{available 0 reason legacy_fingerprint_unavailable dataset_id}` |
| `jacobian datasetId points` | Per-point `{valid 1 point_px scientific_point jacobian determinant}` using the base published calibration |
| `pointUncertainty datasetId points` | Per-point unavailable record or declared isotropic pixel-sigma propagation; base calibration |

All methods above use the namespace prefix. The final schema wrapper replaces
the original three-method metadata inventory while preserving its base contract;
the `_schema_before_batch` alias and other underscore functions are internals.
There is no direct registration of this family in the actual Python/Octave
Script binding, nor a direct typed C++ SDK method. Related Digitizer uncertainty
bindings are separate APIs, not grants to call arbitrary calibration Tcl methods.

## Manifest read contract

`read` checks Dataset existence through Session Inspection, producer tag
curve_digitizer.plugin_id=viewer.curve_digitizer and manifest_version=1. Required
fields: source_dataset_id/source_sha256, configuration_id, calibration_type,
image_width/image_height (integer at least 2), coordinate_origin
(top_left/bottom_left), y_direction (up/down), physical_unit and transform.
Calibration types: pixel, scale_bar, affine, projective.

Transform contains convention, raster_origin, pixel_reference, declared normalized
coordinates x_left_to_right_y_bottom_to_top and a finite 3×3 normalized_homography.
Each x_axis/y_axis has finite minimum/maximum, scale linear/log and its own unit.
Optional scientific_homography is read only when its first metadata element is
present and then requires its complete finite matrix. The transforms below use
normalized homography plus axis mapping, not an arbitrary consumer-fitted matrix.

Scale-bar records require positive finite pixel_length/physical_length, unit,
display_unit, selection_method and finite start_px/end_px. Tick edge_convention
is center/inner/outer/unspecified; legacy absence remains unspecified, never
silently center. Optional uncertainty flat fields and original uncertainty_json,
raster_geometry_json, calibration_method_json and its available flattened fields
are preserved. Source-to-calibration mapping accepts identity when declared;
absence is explicitly legacy_unrecorded.

If both calibration_id and calibration_sha256 exist, SHA must be 64 hex digits
and ID must be `cal_` plus its first 24 digits. This checks recorded format and
internal consistency; `read/identity` do not independently rehash the current
source image or recompute a calibration fingerprint from every retained field.
Use actual source-integrity owners before treating a captured record as current.
The schema's fingerprint description is a producer convention, not an extra
verification operation performed by identity.

## Measurement realizations and coordinate transform

`replicates` without measurement_count returns one legacy_active accepted/valid/
active record merged with the base manifest. Otherwise count is 1–200, IDs unique,
state accepted/rejected/draft, active/valid literal 0/1, exactly one active record.
Valid records carry calibration ID/SHA/type, finite normalized matrix and x/y
axis maps; optional corners/axes/scale_reference JSON is returned unchanged.
Invalid records can be listed but cannot be selected for transformation.

Empty measurementId uses the base published manifest. Explicit stable ID selects
its valid retained map; unknown/invalid selections have dedicated errors. The
selected manifest derives common physical_unit only for equal non-pixel axis
symbols and derives Y direction/origin from the selected Y limits. This does
not convert either axis to a shared physical norm.

Points are Tcl lists of exactly two finite numbers. Directions are exactly
pixel_to_scientific or scientific_to_pixel. Pixel input is original raster pixel
centers, X in [0,width−1], Y in [0,height−1], with 1e−8 boundary allowance.
Homography maps pixels into normalized [0,1] axes; normalized-domain allowance
is 1e−8. Linear axes interpolate their retained endpoints; log axes require
positive bounds and use logarithmic interpolation. Inverse mapping rejects
zero axis range/nonpositive log values, applies inverse homography, and checks
original raster bounds with 1e−7 allowance. Homogeneous divisor magnitude below
1e−12 or nonfinite normalized homography coordinates causes rejection; inverse determinant
below 1e−14 rejects. Linear scientific-axis interpolation has finite retained
bounds but no separate final finite-output check; this reference does not promise
overflow rejection for every scientific coordinate returned by that branch.
No fixed public batch-count bound is imposed in this Tcl owner; callers should
chunk deliberately rather than infer a bounded scientific page API.

## Jacobian and declared uncertainty limits

`jacobian` uses the base read manifest; it has no measurementId argument. The
2×2 matrix rows are derivatives of scientific X/Y with respect to raster px/py,
so each row has its axis unit per pixel. It includes homography and linear/log
axis derivatives, validating the same input domain. Nonfinite or near-singular
local determinant (absolute magnitude below 1e−14) rejects.

`pointUncertainty` reads only uncertainty.pixel_sigma_px when available, requiring
finite nonnegative sigma. Without it, each record is
`status=unavailable,reason=no_quantified_uncertainty,point_px,local_valid=1`.
With it, output_sigma_x/y are sigma times the Euclidean norm of the corresponding
Jacobian row, in separate scientific axis units. The explicit assumption is
isotropic_independent_pixel_errors; status is reported_and_propagated. Unknown
systematic/calibration uncertainty is excluded, not zero. This convenience
method is distinct from the newer retained-factor uncertainty/GLS APIs and does
not provide full cross-point covariance, coverage or accuracy validation.

## Errors and source-backed example

Malformed/incomplete metadata, wrong producer/version, invalid dimensions/map,
singular/domain errors, invalid measurement ID/state or invalid uncertainty
raise errors. Dedicated error codes include CURVE_DIGITIZER CALIBRATION SINGULAR,
OUT_OF_DOMAIN, INVALID_MEASUREMENT and UNKNOWN_MEASUREMENT. Merely returning true
from hasCalibration does not guarantee every later method succeeds.

```tcl
set schema [::GX::CurveDigitizerCalibration::schema]
set manifest [::GX::CurveDigitizerCalibration::read $publishedDigitizerDataset]
set realizations [::GX::CurveDigitizerCalibration::replicates $publishedDigitizerDataset]
# pixelPoints must be valid points in this actual published raster/calibration.
set scientific [::GX::CurveDigitizerCalibration::transformPoints \
    $publishedDigitizerDataset $pixelPoints pixel_to_scientific]
```

This is source-backed usage, unexecuted during documentation authoring. It
requires an actual compatible published Dataset and does not fabricate a new
calibration or establish installed/native scientific acceptance.
