# SPDX-License-Identifier: GPL-3.0-or-later
# CURVE_DIGITIZER_QUALITY_API_v2. Breaking replacement; no v1 fallback.
# This facade reads only canonical Dataset metadata via CORE services.
namespace eval ::GX::CurveDigitizerQuality {}
proc ::GX::CurveDigitizerQuality::_metadata {datasetId} {
    if {$datasetId eq {}} {error {Dataset ID is required.}}
    set session [::GX::sessionInspectionCurrentSession]
    ::GX::sessionInspectionDataset $datasetId $session
    set md [::GX::datasetMetadataRead $session $datasetId]
    if {![dict exists $md curve_digitizer.plugin_id] ||
        [dict get $md curve_digitizer.plugin_id] ne {viewer.curve_digitizer}} {
        error {Dataset is not a Curve Digitizer publication.}
    }
    return [list $session $md]
}
proc ::GX::CurveDigitizerQuality::hasReport {datasetId} {
    if {[catch {lassign [_metadata $datasetId] session md}]} {return 0}
    return [expr {[dict exists $md curve_digitizer.quality_schema_version] &&
        [dict get $md curve_digitizer.quality_schema_version] eq {2} &&
        [dict exists $md curve_digitizer.quality_report_json] &&
        [dict get $md curve_digitizer.quality_report_json] ne {}}]
}
proc ::GX::CurveDigitizerQuality::read {datasetId} {
    lassign [_metadata $datasetId] session md
    if {![dict exists $md curve_digitizer.quality_schema_version] ||
        [dict get $md curve_digitizer.quality_schema_version] ne {2} ||
        ![dict exists $md curve_digitizer.quality_report_json]} {
        error {This Dataset has no Curve Digitizer quality schema v2. Republish it with the current viewer.}
    }
    set source [expr {[dict exists $md curve_digitizer.source_dataset_id] ?
        [dict get $md curve_digitizer.source_dataset_id] : {}}]
    set expected [expr {[dict exists $md curve_digitizer.source_sha256] ?
        [dict get $md curve_digitizer.source_sha256] : {}}]
    set sourceStatus unknown
    set currentSha {}
    if {$source ne {}} {
        if {[catch {set src [::GX::sessionInspectionDataset $source $session]}]} {
            set sourceStatus missing
        } else {
            # A registry digest is not verification of current canonical bytes.
            # Reuse the same public resource authority as Uncertainty/source
            # inspection, without substituting a different integrity engine.
            set sourceStatus unverified
            if {[dict exists $src path] && ![catch {set actual [::GX::sessionInspectionResolveResource [dict get $src path] $session]}]} {set currentSha [dict get $actual sha256]}
            if {$expected ne {} && $currentSha ne {}} {
                set sourceStatus [expr {[string equal -nocase $expected $currentSha] ? {verified} : {changed}}]
            }
        }
    }
    set fields [dict create api_id CURVE_DIGITIZER_QUALITY_API_v2 api_version 2 \
        dataset_id $datasetId report_schema_version 2 report_available 1 \
        source_dataset_id $source source_sha256 $expected \
        source_current_sha256 $currentSha source_integrity $sourceStatus \
        accuracy_status not_assessed \
        uncertainty_status [expr {[dict exists $md curve_digitizer.uncertainty_schema_version] && [dict get $md curve_digitizer.uncertainty_schema_version] eq {2} ? {declared_propagated} : {not_declared}}] \
        report_json [dict get $md curve_digitizer.quality_report_json]]
    # Explicit scalar summary fields avoid forced JSON parsing in Tcl preview UI.
    foreach {key name} {
        quality_status status
        quality_issue_count issue_count
        quality_source_point_count unique_raster_point_count
        quality_published_row_count published_row_count
        quality_curve_count curve_count
        quality_calibration_realizations calibration_realization_count
        quality_segment_count segment_count
        quality_evidence_available image_evidence_available
    } {
        dict set fields $name [expr {[dict exists $md curve_digitizer.$key] ?
            [dict get $md curve_digitizer.$key] : {}}]
    }
    return $fields
}
proc ::GX::CurveDigitizerQuality::reportJson {datasetId} {
    return [dict get [read $datasetId] report_json]
}
