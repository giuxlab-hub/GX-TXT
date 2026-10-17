# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {}
proc ::GX::sessionInspectionCurrentSession {} {return /test/session}
proc ::GX::sessionInspectionDataset {id session} {
    if {$id eq {missing}} {error {Not found}}
    if {$id eq {source}} {return [dict create dataset_id source canonical_sha256 aa11]}
    return [dict create dataset_id $id contract curve_family.table]
}
proc ::GX::datasetMetadataRead {session id} {
    switch -- $id {
        current {return [dict create curve_digitizer.plugin_id viewer.curve_digitizer \
            curve_digitizer.source_dataset_id source curve_digitizer.source_sha256 aa11 \
            curve_digitizer.quality_schema_version 2 \
            curve_digitizer.quality_report_json {"schema_version":"2","issues":{"items":[]}} \
            curve_digitizer.quality_status observations curve_digitizer.quality_issue_count 3 \
            curve_digitizer.quality_source_point_count 20 \
            curve_digitizer.quality_published_row_count 60 \
            curve_digitizer.quality_curve_count 2 \
            curve_digitizer.quality_calibration_realizations 3 \
            curve_digitizer.quality_segment_count 18 \
            curve_digitizer.quality_evidence_available 1]}
        old {return [dict create curve_digitizer.plugin_id viewer.curve_digitizer \
            curve_digitizer.quality_schema_version 1 curve_digitizer.quality_report_json old]}
        default {return [dict create]}
    }
}
source [file join [file dirname [info script]] .. api curve_digitizer_quality_api_v2.tcl]
if {![::GX::CurveDigitizerQuality::hasReport current]} {error {missing v2 report}}
set result [::GX::CurveDigitizerQuality::read current]
foreach {k v} {api_version 2 status observations unique_raster_point_count 20 \
                 published_row_count 60 calibration_realization_count 3 \
                 segment_count 18 source_integrity verified image_evidence_available 1} {
    if {[dict get $result $k] ne $v} {error "Wrong $k: [dict get $result $k] != $v"}
}
if {[::GX::CurveDigitizerQuality::hasReport old]} {error {v1 report mistakenly accepted}}
if {![catch {::GX::CurveDigitizerQuality::read old} message] ||
     ![string match {*Republish*} $message]} {error {v1 report not rejected explicitly}}
if {[::GX::CurveDigitizerQuality::reportJson current] ne [dict get $result report_json]} {error {wrong JSON}}
puts {PASS quality v2 API}
