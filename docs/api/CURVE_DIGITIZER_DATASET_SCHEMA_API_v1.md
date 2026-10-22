# CURVE_DIGITIZER_DATASET_SCHEMA_API_v1

Version 1, provider `viewer.curve_digitizer`, namespace `::GX::CurveDigitizerDataset`,
entrypoint `api/curve_digitizer_dataset_schema_api_v1.tcl`. It resolves published
column meanings from metadata plus stable Variable IDs using public Schema v3
and Canonical Dataset access; no label/CSV-position or GUI-state inference.

## Complete public methods

| Exact Tcl signature | Actual result |
|---|---|
| `read datasetId ?session=""?` | Semantic manifest with columns/Variable descriptors/grouping/units/legacy status |
| `column datasetId semanticRole ?session=""?` | Stable Variable ID mapped to that role; absent role errors |
| `hasSchema datasetId ?session=""?` | Boolean: complete read succeeds; all read errors become false |
| `schema` | API/version/schema version, modes, mandatory/optional roles, role meanings and all five methods |
| `rasterPoints datasetId ?curveKey=""? ?start=0? ?count=10000? ?calibrationKey=""?` | Bounded original-raster/scientific row records and consumed-row receipt; current Session |

All calls use the namespace prefix. No direct Python/Octave Script registration
or typed C++ method exists for this family at this checkpoint. Actual image,
quality and uncertainty Script registrations remain separate; metadata discovery
does not create generic call admission.

## Live Session and semantic schema

Dataset ID must be nonempty and exist. Omitted Session means current Session;
an explicit different Session path rejects because public Variable Schema is
live-Session bound. Producer metadata must be
curve_digitizer.plugin_id=viewer.curve_digitizer.

For current records curve_schema_version must equal 1; required curve_mode is
independent or numerical_family, curve_grouping is curve_key or
curve_key_and_calibration_key, and curve_row_dimension is nonempty. Independent
mode requires contract table.generic; numerical_family requires curve_family.table.
Mandatory roles: x, y, curve_key, curve_name, point_order. A numerical family also
requires family_parameter. Optional raster_x/raster_y mappings occur together;
combined calibration grouping requires both calibration_key/calibration_name.
An independent publication must not map a family_parameter.

Each role's actual stable Variable ID must exist, be distinct from every other
role mapping, have rank one and exactly the declared row dimension. X/Y/family/
raster roles require an integer or float numeric dtype; point_order requires
integer dtype; curve/calibration key/name require text/string dtype. These
checks are schema/type checks, not a complete scan proving every point-order
value or scientific accuracy. Returned Variable descriptors retain actual units;
the owner does not infer physical unit from role/display text.

Meaning is explicit: curve_key is opaque grouping identity, curve_name is an
editable label; point_order is zero-based within each curve, not global X sort.
family_parameter is a true numeric family value. raster_x/y are original source
image pixel-center coordinates. calibration_key is stable realization identity,
calibration_name is display text; combined publications group by both curve and
calibration keys. Do not group by labels or equate raster and scientific units.

Historical records lacking curve_schema_version use only known technical IDs
x/y, curve_id/curve_label, point_index, and family_value when the contract is a
family. This restricted producer-checked compatibility sets legacy_inferred=1,
curve_schema_version=0 and row_dimension=row; it does not guess arbitrary labels
or promise missing legacy raster columns exist.

The result fields are api_version, curve_schema_version, dataset_id, contract,
mode, row_dimension, grouping_role, grouping_roles,
publication_calibration_mode (separate/combined), columns (role→ID), variables
(role→full descriptor), role_meanings, index_origin=0, legacy_inferred and
raster_points_available. No canonical data is rewritten by these read methods.

## Bounded raster/scientific row access

start is a nonnegative integer canonical Dataset row ordinal; count is an
integer 1–100000, default 10000. It is not a per-curve offset. A compatible
manifest with original raster columns is required. Canonical Dataset API opens,
reads the selected IDs, and closes in finally. Rows include curve_key/name,
point_order, x/y, raster_x/y, optional calibration_key/name and dataset_row.

Optional curveKey/calibrationKey filters are exact string matches **after the
bounded canonical range read**. Thus points may be empty while consumed_rows
is nonzero. Continue using start+consumed_rows, not returned-point count. A
calibrationKey filter on a Dataset without that role returns no matching points.
The first curve-key column sets consumed_rows. A selected column shorter than
that reference errors; extra trailing values in another column are not separately
checked by this adapter. No direct CSV/file path is opened.

Result is `{dataset_id start consumed_rows points coordinate_reference}` with
coordinate_reference=original_source_image_pixel_centers. Units of x/y come
from their scientific descriptors; raster coordinates are original pixel centers.
This is not a calibrated Jacobian/uncertainty API or proof of physical accuracy.

## Source-backed use and errors

```tcl
set m [::GX::CurveDigitizerDataset::read $publishedDigitizerDataset]
set yId [::GX::CurveDigitizerDataset::column $publishedDigitizerDataset y]
if {[dict get $m raster_points_available]} {
    set page [::GX::CurveDigitizerDataset::rasterPoints $publishedDigitizerDataset {} 0 100]
}
```

The example is unexecuted documentation of actual public calls. Wrong Session/
producer/version, contract/mode disagreement, missing/duplicate role IDs, wrong
dtype/rank/dimension, malformed range or absent raster history raise errors.
Only hasSchema catches those errors into a boolean. Installed/native/scientific
verification remains an independent release gate.
