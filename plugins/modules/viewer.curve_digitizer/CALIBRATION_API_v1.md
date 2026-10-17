# CURVE_DIGITIZER_CALIBRATION_API_v1

SPDX-License-Identifier: GPL-3.0-or-later

## Public provider

- API ID: `CURVE_DIGITIZER_CALIBRATION_API_v1`
- Module: `viewer.curve_digitizer` (core-distributed module, not a CORE extension)
- Tcl entrypoint: `api/curve_digitizer_calibration_api_v1.tcl`
- Namespace: `::GX::CurveDigitizerCalibration`
- Minimum GX-TXT baseline: existing public Dataset Metadata v1, Session Inspection, Dataset Publication v2

This API resolves calibration by the **published curve Dataset ID**. It does not inspect image files, read private digitizer configuration documents, depend on a currently open viewer window, or parse plugin-specific metadata in consumers.

```tcl
set info [::GX::CurveDigitizerCalibration::read digitized.sem_contour]
set unit [dict get $info physical_unit]
set transform [dict get $info transform]
set H [dict get $transform normalized_homography]
set dimensions [list [dict get $info image_width] [dict get $info image_height]]
set hasBar [dict exists $info scale_bar]

# Optional Session override (defaults to current Session):
set info [::GX::CurveDigitizerCalibration::read digitized.sem_contour $session]

# Non-throwing predicate for a Dataset with a v1 calibration manifest:
set available [::GX::CurveDigitizerCalibration::hasCalibration digitized.sem_contour]

# API declaration/discovery:
set contract [::GX::CurveDigitizerCalibration::schema]
```

A Dataset absent from the Session, not produced by Curve Digitalizer, missing required calibration metadata, or declaring an unsupported manifest version raises an explicit error in `read`. The predicate returns `0` for unavailable or unsupported Dataset metadata; `read` remains authoritative for validation.

## Stable return fields (v1)

| Tcl dict field | Meaning |
|---|---|
| `api_version` | Always integer `1` |
| `manifest_version` | Always integer `1` |
| `dataset_id` | The published scientific curves Dataset ID |
| `source_dataset_id` | Exact original image Dataset ID |
| `source_sha256` | SHA-256 digest of the linked source image bytes |
| `configuration_id` | Stable digitizer configuration identifier, independent of display name |
| `calibration_type` | `pixel`, `scale_bar`, `affine`, `projective` |
| `image_width`, `image_height` | Original raster dimensions in pixel centers, integer counts |
| `coordinate_origin` | `bottom_left` or `top_left` for scientific coordinates |
| `y_direction` | `up` or `down` in raster coordinates |
| `physical_unit` | Canonical physical length code (`um`, `nm`, `mm`, ...), or empty when none / mixed axes |
| `transform` | Structured transform dictionary, below |
| `scale_bar` | Optional structured bar reference when the calibration type is `scale_bar` |
| `uncertainty` | Optional flat structured uncertainty dictionary when present in source configuration |
| `uncertainty_json` | Optional canonical JSON uncertainty if supplied, including nested payloads |

Missing uncertainty means **unknown**, not zero. Do not use homography corner-fit RMS (zero for four exact control points) as a measurement-uncertainty estimate.

## `transform` structure

| Field | Meaning |
|---|---|
| `convention` | `column_vector_homogeneous_xy1` |
| `raster_origin` | `top_left` always |
| `pixel_reference` | `pixel_center` always |
| `normalized_coordinates` | `x_left_to_right_y_bottom_to_top` |
| `normalized_homography` | A 3×3 Tcl list of lists, raster pixel centers → normalized coordinates `(u,v)` |
| `x_axis`, `y_axis` | Tcl dictionaries with `minimum`, `maximum`, `scale` (`linear` / `log`) and original axis `unit` |
| `scientific_homography` | Optional 3×3 raster → scientific coordinate matrix, present **only** when both axes are linear |

Use homogeneous vectors: `q = H * (pixel_x, pixel_y, 1)`, then `(u, v) = (q0/q2, q1/q2)`. For linear axes, `x = xmin + u*(xmax-xmin)` and `y = ymin + v*(ymax-ymin)`. For a logarithmic axis, use `x = 10 ** (log10(xmin) + u*(log10(xmax)-log10(xmin)))` (analogously for Y); its `scientific_homography` is intentionally absent.

For full-image autocalibration, raster coordinate `(0,0)` is the top-left pixel center, `(W-1,H-1)` the bottom-right pixel center. Physical dimensions use `(W-1)*physical_length/pixel_length` and `(H-1)*physical_length/pixel_length`, not `W` or `H`.

## `scale_bar` structure

When the type is `scale_bar`, the result provides `start_px`, `end_px` (2-element coordinate lists), `pixel_length`, `physical_length`, `unit` (canonical), `display_unit` (original UI spelling) `selection_method` (e.g. `detected` / `manual`) and `edge_convention` (`center`, `inner`, `outer` or `unspecified` for legacy publications). The endpoints are measured on the **original source raster**, not transformed display coordinates. The UI's persistent green overlay is a visualization, not the metadata authority.

## Dataset Metadata storage

The authoritative public Dataset Metadata resource is managed by CORE `DATASET_METADATA_API_v1`. It contains the corresponding domain keys under `curve_digitizer.*` (e.g. `curve_digitizer.source_sha256`, `curve_digitizer.calibration_type`, `curve_digitizer.transform`). `curve_digitizer.calibration_manifest` and nested `curve_digitizer.transform` are canonical UTF-8 JSON strings for portable consumers. Scalar/matrix subkeys such as `curve_digitizer.transform.h00` exist for a Tcl-only contract implementation with no JSON dependency. A caller should use the public Tcl API rather than depend on these internal representation details.

Metadata is included through the `structured_metadata` definition of **Dataset Publication v2** and therefore committed with the output Dataset; no post-finalization overwrite is needed. Unrelated metadata is kept during same-owner republishes. Old Curve Digitalizer namespace values are removed before merging the new manifest, preventing stale scale-bar or uncertainty fields.

The API is part of the packaged Curve Digitalizer module. Consumers must declare its API dependency and handle a disabled/missing provider; never require new CORE functions or import a Python implementation just to read calibration metadata.

## Scale-bar tick reference extension (Curve Digitalizer 1.2.6)

For SEM-style scale bars with terminal vertical marks, the viewer now defaults to **center-to-center** measured across the two tick centers. This is a selectable assumption, not a universal manufacturer standard. The UI also offers `inner` and `outer` references. A candidate must be confirmed before applying physical scale.

The existing public API ID and manifest v1 remain unchanged. In addition to the original scale-bar fields, readers receive:

```tcl
set info [::GX::CurveDigitizerCalibration::read digitized.sem_contour]
if {[dict exists $info scale_bar]} {
    set bar [dict get $info scale_bar]
    set reference [dict get $bar edge_convention]
    # center | inner | outer | unspecified
}
```

For datasets produced before 1.2.6, `edge_convention` is `unspecified`, since their geometry cannot safely be inferred. The raw metadata includes `curve_digitizer.scale_bar.edge_convention`, and the canonical calibration manifest includes `scale_bar.edge_convention`. No new CORE API or alternate persistence storage is introduced.

## Complementary curve-column semantics

Calibration does not assign scientific column roles. For the stable mapping of
curve membership, curve label, point order, X, Y and family parameter, use
`CURVE_DIGITIZER_DATASET_SCHEMA_API_v1` (see
`CURVE_DATASET_SCHEMA_API_v1.md`), also resolved by published Dataset ID.

## Additive operations (Curve Digitalizer 1.2.10)

The API ID and namespace remain `CURVE_DIGITIZER_CALIBRATION_API_v1`;
`read`, `hasCalibration` and `schema` preserve their existing arguments and return
fields. The new Tcl operations operate on a **published output Dataset ID**,
not on the source image ID or an Interactive Document.

```tcl
set identity [::GX::CurveDigitizerCalibration::identity $datasetId]
set physical [::GX::CurveDigitizerCalibration::transformPoints \
    $datasetId {{10.25 20.5} {35 70}} pixel_to_scientific]
set raster [::GX::CurveDigitizerCalibration::transformPoints \
    $datasetId $physical scientific_to_pixel]
set local [::GX::CurveDigitizerCalibration::jacobian \
    $datasetId {{10.25 20.5} {35 70}}]
set errors [::GX::CurveDigitizerCalibration::pointUncertainty \
    $datasetId {{10.25 20.5} {35 70}}]
```

### `transformPoints datasetId points direction`

- `points` is a Tcl list of `{x y}` pairs. For `pixel_to_scientific`, coordinates
  are source raster pixel centers `(0,0)` through `(width-1,height-1)`.
- `direction` is exactly `pixel_to_scientific` or `scientific_to_pixel`.
- Results are ordered `{x y}` pairs in the requested coordinate space.
- The normalized projective homography and each axis's linear/log mapping
  are handled internally. Inversion uses the homography inverse and inverse
  axis mappings; no consumer should reimplement this mathematics.
- A singular mapping, nonfinite number, nonpositive log-axis input or
  point outside the calibrated image/domain raises an explicit Tcl error.
  For domain violations the error code begins
  `CURVE_DIGITIZER CALIBRATION OUT_OF_DOMAIN`; singularity uses
  `CURVE_DIGITIZER CALIBRATION SINGULAR`. A batch fails atomically; no partial
  output is returned.
- The domain is the calibrated original Image Dataset raster. Extrapolation
  beyond the four calibration corners is deliberately unsupported.

### `identity datasetId`

Returns `available=1`, `calibration_id`, `sha256` and `source_sha256` for
1.2.10+ publications. The ID is `cal_` followed by the first 24 hex digits of
the calibration SHA-256. The complete fingerprint uses a deterministic UTF-8
canonical JSON encoding (sorted keys, no insignificant spaces) of the image
SHA-256, raster dimensions, both scientific axis mappings, the normalized
homography and the source-to-calibration pixel mapping. It deliberately
**excludes** configuration ID, output Dataset ID, curve names and traced points.
Two published curves therefore share the identity when they use the exact same
source bytes and geometric calibration, even if digitized independently.

For a pre-1.2.10 publication without fingerprint fields, the method returns
`available=0`, `reason=legacy_fingerprint_unavailable`. It never fabricates a
hash of a historical calibration. The original `read` fields continue to work.

### `jacobian datasetId points`

Returns a list of dictionaries: `valid`, `point_px`, `scientific_point`,
`jacobian` (2×2 derivative of scientific X,Y with respect to original raster
X,Y), and `determinant`. It handles the local derivative of perspective
projection and the actual linear/log scientific axes. Outside-domain or locally
singular transformations produce explicit errors instead of an arbitrary matrix.

### `pointUncertainty datasetId points`

Returns one dictionary per input pixel. Without independently supplied
uncertainty, each says `status=unavailable`, `reason=no_quantified_uncertainty`.
There is **no automatic zero-error or perfect-precision assumption**.

If the published metadata explicitly contain a nonnegative
`uncertainty.pixel_sigma_px`, the method reports that measured/declared input
sigma and propagates it using the local Jacobian under the **explicit**
`isotropic_independent_pixel_errors` model, returning `output_sigma_x` and
`output_sigma_y`. Other systematic calibration effects are not automatically
accounted for. No uncertainty measurement is invented by the Digitalizer.

### Extended `read` result and calibration metadata

New optional fields are `calibration_id`, `calibration_sha256`,
`raster_geometry_json`, `raster_pixel_mapping` (`identity` for current source
pixels, or `legacy_unrecorded`), `calibration_method` and
`calibration_method_json`. The stable published metadata additionally include
`curve_digitizer.calibration_identity_payload` for independent auditing.

`raster_geometry_json` explicitly records the identity relationship between
calibration pixels and the imported Image Dataset's original pixel centers:
no in-viewer crop, rotation or resize. It does **not** claim to know any
pre-import crop, rotation, resampling or other undocumented upstream image
operations (`upstream_processing=unknown`). If a future producer records a
nonidentity transform, the reader must support it explicitly; it will not
silently treat it as identity. `calibration_method` records the calibration
type, point/scale-selection method, tick-edge convention and uncertainty
availability without suggesting an unverified metrological accuracy.

The public API uses only the existing Session Inspection and Dataset Metadata
services. The core framework sources are unchanged.

## Independent repeated calibration measurements

The existing API retains its identifier and all previous default signatures.
New publications include `curve_digitizer.calibration_group_id`,
`curve_digitizer.active_measurement_id`, `curve_digitizer.measurement_count`,
`curve_digitizer.calibration_measurements` (canonical JSON) and indexed
`curve_digitizer.measurement.N.*` scalar fields in ordinary Dataset Metadata.
They never require an Interactive Document to be present.

```tcl
set trials [::GX::CurveDigitizerCalibration::replicates $datasetId]
set trial [lindex $trials 0]
set id [dict get $trial measurement_id]
set scientific [::GX::CurveDigitizerCalibration::transformPoints \
    $datasetId {{100.0 200.0} {300.0 400.0}} pixel_to_scientific $id]
set identity [::GX::CurveDigitizerCalibration::identity $datasetId $id]
```

Each trial has `measurement_id`, `label`, `state` (`draft`, `accepted`,
`rejected`), `active` (0/1), and `valid` (0/1). Valid trials have their own
`transform`, `calibration_id` and `calibration_sha256`. Unknown or invalid
trials produce explicit errors when used for transformations. The default
call with no ID applies the primary active accepted mapping as before.
Legacy datasets without a measurement group report a synthetic single active
record (`measurement_id=legacy_active`) without modifying any source record.
No sample variability/uncertainty is calculated by the viewer or this API.

## Multiple calibration publication layouts

`CurveDigitizerCalibration::replicates datasetId` enumerates **all** calibration
measurements known when the Dataset was published, with stable measurement ID,
label, state, validity, transform and fingerprint where valid. The Dataset
therefore reports other accepted/draft/rejected measurements, not only the one
that produced its default X/Y column. A separate publication selects one of
these measurements for its scientific numeric rows. A combined publication
selects multiple measurements and publishes a `calibration_key` semantic column
(see the Dataset Schema API).

The currently selected subset is independently recorded in public metadata:

```text
curve_digitizer.publication_calibration_mode = separate | combined
curve_digitizer.publication_calibration_ids = ["meas_...", "meas_..."]
curve_digitizer.publication_measurement_id = meas_... (primary calibration)
```

The default `read`/`identity`/`transformPoints` semantics continue to use the
primary calibration stored in the Dataset manifest. Explicitly pass a
`measurementId` to `transformPoints` (or `identity`) to use another mapping.
Consumers must inspect the publication mode and Dataset Schema roles before
assuming there is exactly one calibrated realization per curve.
