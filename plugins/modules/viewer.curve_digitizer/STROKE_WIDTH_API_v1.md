
# CURVE_DIGITIZER_STROKE_WIDTH_API_v1

SPDX-License-Identifier: GPL-3.0-or-later

This is a versioned public module API in module.ini with entrypoint api/curve_digitizer_stroke_width_api_v1.tcl. It is read-only, uses public GX-TXT Session/Companion/Dataset Metadata CORE services, and introduces no implicit scientific uncertainty.

## Configuration reads

::GX::CurveDigitizerStrokeWidth::configurationRead documentId
::GX::CurveDigitizerStrokeWidth::curveRead documentId curveId

configurationRead returns a Tcl dict with api_id, schema_version, source_dataset_id, source_sha256 and stroke_width_json containing per-curve records keyed by immutable curve IDs. curveRead returns document_id, curve_id, source_dataset_id, source_sha256, status (inactive, measured, unavailable), method, width_px (blank when not measured), curve_record_json, propagated_uncertainty=0. Only the active GX-TXT Session may be queried. Curve display names are not identifiers.

## Published Dataset reads

::GX::CurveDigitizerStrokeWidth::hasPublished datasetId
::GX::CurveDigitizerStrokeWidth::publishedRead datasetId

These access the metadata of an existing published Dataset through the public Dataset Metadata API, checking producer ownership. The stored keys are curve_digitizer.stroke_width_schema_version = 1 and curve_digitizer.stroke_width_report_json. The report schema is gxtxt.curve_digitizer.stroke_width.v1 and contains source_dataset_id, source_sha256 and curves keyed by curve_id. Each record has status, method, units=px, propagated_uncertainty=false. Measured curves add width_px, min_px, max_px, iqr_px, accepted_samples, rejected_samples, and total_samples. It is a publication-time snapshot, not a live mutable measure.

## Scientific interpretation

Thickness is descriptive geometry in the original source raster, NOT the original measuring instrument accuracy. It is not a standard uncertainty, is not propagated automatically to Numeric CORE, and does not authorize GLS/ODR weighting. Stale or unavailable results cannot be silently treated as zeros. A separate justified localization-error distribution and CORE model would be required to relate width to pixel centerline uncertainty.
