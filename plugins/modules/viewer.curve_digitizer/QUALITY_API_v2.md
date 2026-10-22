# Curve Digitizer Quality and Image Evidence API — v2

SPDX-License-Identifier: GPL-3.0-or-later

## Scope and publication model

`CURVE_DIGITIZER_QUALITY_API_v2` reads immutable diagnostics **from a published
Curve Digitizer Dataset** using only its Dataset ID and the public GX-TXT
Dataset/Metadata services. No originating Interactive Document, viewer instance,
C/X11 program or private metadata parsing is required by its consumers.

The earlier Quality API v1 and its report layout are **not supported**. Republish
previously generated curve Datasets with the current viewer to obtain schema 2.
Other public APIs (Calibration, Dataset Schema, Image Processing) retain their
separate contracts.

**Do not treat these metrics as image-to-curve accuracy or calibration uncertainty.**
The report provides structural checks, image-space observations, per-curve and
per-segment references, and the empirical spread across selected calibration
realizations. These are not substitutes for independent reference measurements.

## How to call from GX-TXT Tcl

```tcl
::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_QUALITY_API_v2
set report [::GX::CurveDigitizerQuality::read $datasetId]
set exists [::GX::CurveDigitizerQuality::hasReport $datasetId]
set json [::GX::CurveDigitizerQuality::reportJson $datasetId]
```

`read` returns a Tcl dictionary (scalar convenience fields plus the full UTF-8
`report_json`):

| Field | Meaning |
| --- | --- |
| `api_id`, `api_version`, `report_schema_version` | Public identity = v2; schema = 2. |
| `dataset_id` | Canonical Dataset ID. |
| `report_available`, `status`, `issue_count` | Current report and severity aggregation. |
| `unique_raster_point_count` | Count of input raster click points *before* multi-calibration replication. |
| `published_row_count` | Actual scientific table rows written. |
| `calibration_realization_count` | Number of accepted calibration mappings included in this publication. |
| `curve_count`, `segment_count` | Unique curves and original consecutive raster intervals. |
| `image_evidence_available` | Source-image raster contrast evidence was evaluated. |
| `source_dataset_id`, `source_sha256` | Source Dataset and SHA-256 recorded at publication. |
| `source_integrity`, `source_current_sha256` | Live source status (`verified`, `changed`, `missing`, `unknown`). |
| `accuracy_status` | Explicitly `not_assessed`; structural/image diagnostics do not establish image-to-curve accuracy. |
| `uncertainty_status` | `declared_propagated` when published Dataset metadata declares `curve_digitizer.uncertainty_schema_version=2`; otherwise `not_declared`. This facade flag reports the declaration, not an independent validation of its uncertainty values or statistical coverage. |
| `report_json` | Complete report, encoded as JSON, schema 2. |

A report of a different version produces an explicit error from `read` and
`hasReport` returns false. Missing data are not interpreted as perfect quality.

The facade `uncertainty_status` above is distinct from
`report_json.metrology.uncertainty.status`, which remains `not_assessed` in the
quality report. A published propagation declaration is not proof of accuracy,
calibration uncertainty or independently validated coverage. Use the existing
uncertainty API and its source/Dataset binding checks for that separate contract.

## JSON report schema 2 (public contract)

Top-level objects:

| Object | Contents |
| --- | --- |
| `schema_version`, `producer`, `scope`, `image_space` | Identity and coordinate convention. |
| `source` | Dataset identity, raster SHA-256 and width/height. |
| `publication` | Layout (`separate` / `combined`), selected measurement IDs, realization count, source-point count, *actual* row count, curve count and point-ordering policy. |
| `calibrations[]` | One entry per **published** measurement, including calibration identifier, label/state, axis units, polygon area/validity, homography condition number and same-four-control reprojection RMS in normalized unit-square mapping coordinates (dimensionless, not px or physical uncertainty, and not independent accuracy). Independent verification is marked not recorded unless it becomes available as persistent data. |
| `calibration_realization_spread` | Descriptive range across published maps at bounded sampled raster locations, per axis, with physical units. No statistical or uncertainty claim. |
| `curves[]` | Stable curve ID/label, point and segment counts, origin counts, raster bounds, point spacing statistics, observed line-contrast statistics, issue counts, monotonicity checks and rows per realization. |
| `segments.records[]` | Source raster XY endpoints, stable curve ID, zero-based `segment_index`, raster length, flags, local image evidence if sampled. |
| `segments.total`, `.returned`, `.truncated`, `.sampling_policy` | Coverage and explicit retention cap. |
| `image_evidence` | Sampling method, threshold, available/sample counts, coverage and validity limitations. |
| `issues.items[]` | `severity`, stable `code`, `message`, `curve_id` and/or `segment_index` or `measurement_id`, raster endpoints for applicable findings. |
| `issues.total`, `.returned`, `.omitted`, `.counts_by_severity` | Aggregate findings with bounded detail. |
| `metrology` | Explicit `not_assessed` accuracy/uncertainty and `not_recorded` independent calibration verification. |

`segments.records` retains every interval up to 1,500 and keeps flagged
intervals preferentially if more are present. At most 400 issues carry detail;
additional occurrences are counted. Image evidence samples at most 12,000
cross-section pixels per Dataset. The report states truncation and coverage;
absence of a record is **never evidence that an interval is error-free**.

### Raster evidence interpretation

Image evidence uses **bounded samples along each segment**, with between one
and seven centers and flanks 4 pixels either side along the segment normal.
The segment diagnostics retain median contrast and a threshold-visible fraction;
per-curve fields summarize those segment fractions. This can indicate weakly
visible intervals. It does **not** distinguish curves from grid lines,
text or intersecting curves, and it cannot resolve overlapping traces. The
original canonical source image is used, not GUI opacity or a display filter.
Publishing a processed image Dataset and then selecting it as a new source
establishes it as the canonical raster and the above still applies.

Codes include `axis_invalid`, `calibration_geometry_invalid`,
`homography_condition_invalid`, `calibration_invalid`, `corner_outside_image`,
`point_outside_image`, `repeated_consecutive_point`, `long_segment`,
`weak_local_contrast`, `empty_curve` and `monotonicity_violation`.

### Image overlay and grouping in Dataset Preview

Use this API for locations and findings, together with:

```tcl
::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_CALIBRATION_API_v1
::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_DATASET_SCHEMA_API_v1
set calibration [::GX::CurveDigitizerCalibration::read $datasetId]
set schema [::GX::CurveDigitizerDataset::read $datasetId]
set pixelRows [::GX::CurveDigitizerDataset::rasterPoints $datasetId]
```

For combined datasets, group published rows by **curve_key AND calibration_key**.
For an image background the X/Y raster points are independent of calibration,
so duplicate overlay points should be de-duplicated by curve/point identity;
scientific-space plots must keep each calibration separate. Segment diagnostics
refer to unique raster-source curve point order (not replicated Dataset rows).

## Python and Octave Script Bridge

Operation names on `CURVE_DIGITIZER_QUALITY_API_v2`:

- `diagnostics(dataset_id)` -> Tcl dictionary converted to a quality struct;
- `issue_report(dataset_id)` -> full UTF-8 JSON v2 report (not just issue list);
- `has_quality(dataset_id)` -> boolean.

```python
from gxtxt import gxtxt_api_call, gxtxt_api_require
import json
gxtxt_api_require('CURVE_DIGITIZER_QUALITY_API_v2')
summary = gxtxt_api_call('CURVE_DIGITIZER_QUALITY_API_v2', 'diagnostics', ['digitized.example'])
report = json.loads(summary['report_json'])
for curve in report['curves']:
    print(curve['curve_id'], curve['spacing_px'])
```

```octave
gxtxt_api_require('CURVE_DIGITIZER_QUALITY_API_v2');
summary = gxtxt_api_call('CURVE_DIGITIZER_QUALITY_API_v2', ...
                         'diagnostics', {'digitized.example'});
disp(summary.source_integrity);
disp(summary.published_row_count);
```

The report describes a *publication-time snapshot*. A subsequent user edit in
the viewer does not update already-published data; republish to regenerate it.
