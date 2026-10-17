# CURVE_DIGITIZER_DATASET_SCHEMA_API_v1

SPDX-License-Identifier: GPL-3.0-or-later

**Module:** `viewer.curve_digitizer`  
**Minimum publication format:** curve schema version 1 (Curve Digitalizer 1.2.8)  
**Goal:** retrieve semantic role / Variable ID bindings for scientific curve
Datasets using only the published Dataset ID. All public access goes through
CORE Session Inspection, Dataset Metadata and Variable Schema v3 APIs.

## Why

`table.generic` and a variable's display label do not encode whether a column
is the curve membership key, its human title, or the within-curve point order.
Consumers must not assume a particular CSV header, physical column position,
Variable ID or UI implementation. Every publication carries a versioned role
manifest linked to real CORE Variable Schema IDs.

## Stable API

```tcl
# datasetId is the canonical output Dataset ID, current Session is default.
set m [::GX::CurveDigitizerDataset::read $datasetId]
set id [::GX::CurveDigitizerDataset::column $datasetId curve_key]
set supported [::GX::CurveDigitizerDataset::hasSchema $datasetId]
set descriptor [::GX::CurveDigitizerDataset::schema]
```

`read datasetId ?session?` returns a Tcl dictionary with:

| Key | Type | Meaning |
|---|---|---|
| `api_version` | integer | Always 1 |
| `curve_schema_version` | integer | 1; 0 for validated historical fallback |
| `dataset_id` | string | Canonical Dataset ID |
| `contract` | string | `table.generic` or `curve_family.table` |
| `mode` | string | `independent` or `numerical_family` |
| `row_dimension` | string | Row Dimension ID of every published column |
| `grouping_role` | string | Always `curve_key` |
| `columns` | dict | Semantic role → current **Variable ID** |
| `variables` | dict | Semantic role → CORE V3 Variable Schema descriptor |
| `role_meanings` | dict | Stable English meaning for each role |
| `index_origin` | integer | Always zero |
| `legacy_inferred` | boolean | 1 only for validated pre-v1 publications |

`column datasetId role ?session?` returns the mapped Variable ID for a declared
role and raises an error when the role is absent. `hasSchema` returns 1/0;
`read` is the authoritative diagnostic and raises meaningful errors.
`schema` reports the supported contract version, modes, roles and meanings.

The optional `session` must identify the **current** Session: CORE Variable
Schema lookup does not expose a foreign-Session API. The manifest never reads
Curve Digitalizer configuration files, private JSON, CSV headers or generated
runtime caches.

## Roles and precise semantics

| Role | Type | Semantics |
|---|---|---|
| `x` | numeric | Calibrated scientific X coordinate of each digitized point, in Variable Schema unit |
| `y` | numeric | Calibrated scientific Y coordinate of each digitized point, in Variable Schema unit |
| `curve_key` | text | Opaque, stable identifier of the curve to which the row belongs. Group rows by this value; unique within the Dataset |
| `curve_name` | text | User-editable display title repeated for each point. Must not be used for grouping, joins or curve identity |
| `point_order` | integer | Zero-based digitization order within each `curve_key`; not a global sequence or an X sort order |
| `family_parameter` | numeric | A true numerical family parameter, repeated per point; present only for `numerical_family` mode |

Each row represents **one digitized point**. For `independent`, columns
`x`, `y`, `curve_key`, `curve_name`, and `point_order` are mandatory. For
`numerical_family`, `family_parameter` is additionally mandatory. A numeric
family value is **not** a replacement for `curve_key`: two curves might share
one family value and must still be independently addressable.

Scientific axis roles like `independent` or `measured` remain user-selectable in
Variable Schema; they do not replace this dataset-structure role contract.
Plugin Semantic Registry definitions describe `curve_series_identifier`,
`curve_series_label`, `curve_point_index` in the V3 variable descriptors.

## Canonical Dataset Metadata representation

Every v1 Dataset has the following keys (under the public Dataset Metadata API):

```text
curve_digitizer.curve_schema_version = 1
curve_digitizer.curve_mode = independent | numerical_family
curve_digitizer.curve_grouping = curve_key
curve_digitizer.curve_row_dimension = row
curve_digitizer.curve_column.x = <variable_id>
curve_digitizer.curve_column.y = <variable_id>
curve_digitizer.curve_column.curve_key = <variable_id>
curve_digitizer.curve_column.curve_name = <variable_id>
curve_digitizer.curve_column.point_order = <variable_id>
# only for mode=numerical_family:
curve_digitizer.curve_column.family_parameter = <variable_id>
```

The producer version is **not** the schema version. A new producer can change
technical Variable IDs, labels and ordering while keeping the same role names
and `curve_schema_version=1`. A breaking semantic change requires a new schema
version and a suitable backward-compatible API evolution.

All mappings are persisted with the data in CORE Dataset Publication API v2's
`structured_metadata` transaction. Renaming a display label does not alter the
column mappings. The public API validates the mapped IDs against public Dataset
Variable Schema v3, including datatype and row dimension, so it cannot silently
accept a nonexistent or wrongly typed column.

## Consumer example: two independent SEM contours

```tcl
set manifest [::GX::CurveDigitizerDataset::read sem_contours]
if {[dict get $manifest mode] ne "independent"} {
    error "Not a collection of independent curves"
}
set keyId [dict get $manifest columns curve_key]
set nameId [dict get $manifest columns curve_name]
set orderId [dict get $manifest columns point_order]
set xId [dict get $manifest columns x]
set yId [dict get $manifest columns y]
# Read numeric/text values by these IDs through CORE canonical Dataset APIs.
# Group rows by the opaque value in $keyId, order each group by $orderId,
# then plot each group using the values of $xId and $yId.
```

**Do not** infer the roles by comparing strings such as `curve_id` or
`curve_label`, by matching display labels, or by examining GUI state.

## Compatibility and errors

`read` rejects non-Digitizer datasets, invalid schema versions, missing roles,
mode/contract mismatch, repeated mapping to the same Variable ID, wrong
Variable datatypes, and dimensions inconsistent with the declared row axis.

Pre-1.2.8 publications lack a curve schema manifest. When an output is
explicitly identified as Curve-Digitizer-owned and has the known historical
technical variable IDs, `read` maps them through a strictly checked historical
layout and returns `legacy_inferred=1`, `curve_schema_version=0`. It does not
silently guess semantics from a variable's *display label*. Old Dataset files
are not rewritten or migrated. The old calibration API is unchanged.

## Relation to other public APIs

- `CURVE_DIGITIZER_CALIBRATION_API_v1`: physical/image calibration provenance.
- `DATASET_METADATA_API_v1`: persistent semantic binding fields.
- `DATASET_VARIABLE_SCHEMA_API_v3`: type, unit, Variable ID, semantic role.
- `DATASET_PUBLICATION_API_v2`: atomic data+metadata publication.

## Additive source raster semantics (Curve Digitalizer 1.2.10)

The existing `CURVE_DIGITIZER_DATASET_SCHEMA_API_v1` remains unchanged in name,
return contract and mandatory roles. All new publications add **two numeric
Dataset variables** with declared role mappings:

| Semantic role | Meaning | Default Variable ID | Unit |
|---|---|---|---|
| `raster_x` | X coordinate of the original source-image pixel center | `pixel_x` | `px` |
| `raster_y` | Y coordinate of the original source-image pixel center | `pixel_y` | `px` |

The variable IDs and human-readable labels are examples, **not** the contract.
Consumers must resolve the canonical Variable IDs from the existing `columns`
dictionary returned by `CurveDigitizerDataset::read`. The Variable Schema
also contains `curve_raster_x` and `curve_raster_y` roles registered through
GX-TXT's existing Semantic Registry API. Scientific X,Y and original raster X,Y
coexist in one table, one row per digitized point.

`read` now adds `raster_points_available` (0/1). Existing pre-1.2.10 outputs
remain readable and correctly report unavailable raster columns. Partial or
invalid X/Y mappings are rejected rather than guessed.

### Optional data-centric reader

```tcl
set info [::GX::CurveDigitizerDataset::read $datasetId]
if {[dict get $info raster_points_available]} {
    set batch [::GX::CurveDigitizerDataset::rasterPoints \
        $datasetId "" 0 10000]
    # One filtered batch of the first 10000 dataset rows:
    set left [::GX::CurveDigitizerDataset::rasterPoints \
        $datasetId $curveKey 0 10000]
}
```

`rasterPoints datasetId ?curveKey? ?start? ?count?` reads only the requested
bounded row range using **CORE Canonical Dataset API v2**. Default range is
start=0, count=10000; maximum count is 100000. A nonempty `curveKey` filters
just the fetched batch; `start` is the source Dataset row ordinal, **not**
a curve-relative offset. The result is a dictionary:

- `dataset_id`, `start`, `consumed_rows`,
  `coordinate_reference=original_source_image_pixel_centers`;
- `points`: list of dictionaries with `curve_key`, `curve_name`,
  `point_order`, `x`, `y`, `raster_x`, `raster_y`, `dataset_row`.

Read subsequent row ranges until fewer than `count` rows are consumed. The API
never parses CSV files or accesses the Curve Digitizer's private UI state.
A historical output without persisted raster columns raises a clear error.
The values cannot reliably be reconstructed when the original calibration
was lost. Scientific values are not rounded to integer raster positions.

For comparisons of five digitizations of one SEM image, first use the
Calibration API `identity` fingerprints and source SHA-256. Compare the
original raster points independently of the transform. Then transform the
same positions with `transformPoints` and use `jacobian` / `pointUncertainty`
only where actual uncertainty inputs exist.

## Calibration-repeat data independence

`rasterPoints` returns original source-raster points. These remain independent
of the active calibration measurement, which allows another module to apply
multiple published calibrations to the same pixels through
`CurveDigitizerCalibration::transformPoints(datasetId, points, direction, measurementId)`.
No additional curve-family semantics or Dataset duplication is implied.

## Calibration-aware combined publication

The existing API name and version remain unchanged. In `separate` publication,
`x` and `y` represent points calibrated with a single selected measurement,
while `CurveDigitizerCalibration::replicates` still exposes the complete group.
Combined publication extends the mapping without changing the mandatory roles:

| Role | Current Variable ID example | Semantics |
|---|---|---|
| `calibration_key` | `calibration_id` | Stable opaque measurement ID; identifies the calibration applied to **this row** |
| `calibration_name` | `calibration_label` | Editable human-readable calibration label; not a group key |

For combined datasets:

```text
curve_digitizer.curve_grouping = curve_key_and_calibration_key
curve_digitizer.curve_column.calibration_key = calibration_id
curve_digitizer.curve_column.calibration_name = calibration_label
```

The public `read` result adds `grouping_roles` (`{curve_key calibration_key}`
in combined mode, otherwise `{curve_key}`) and `publication_calibration_mode`
(`combined` or `separate`). A consumer MUST group combined rows by the **pair**
`(curve_key, calibration_key)` and order points by `point_order` within that
pair. `curve_key` alone is insufficient: every original curve has one numeric
realization per selected calibration. Legacy/simple consumers should use the
separate layout.

For combined output, `rasterPoints` accepts an additional optional final
`calibrationKey` filter:

```tcl
set schema [::GX::CurveDigitizerDataset::read $datasetId]
set calColumn [dict get $schema columns calibration_key]
set result [::GX::CurveDigitizerDataset::rasterPoints $datasetId "" 0 10000 $calibrationId]
```

This filter is applied only to the requested CORE row batch, not to the entire
Dataset. The original raster positions are intentionally repeated for each
calibration so a combined Dataset remains self-contained. The calibration
metadata lists **all** available measurements, even when only a subset was
selected for a publication. Selection provenance uses
`curve_digitizer.publication_calibration_mode`,
`curve_digitizer.publication_calibration_ids` (JSON list), and
`curve_digitizer.publication_measurement_id` (primary measurement whose
calibration is exposed by the default Calibration API `read` call).
