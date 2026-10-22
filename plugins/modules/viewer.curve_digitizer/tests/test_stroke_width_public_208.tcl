# SPDX-License-Identifier: GPL-3.0-or-later
# Hermetic public API contract fixture. Run with tclsh from the module root.
namespace eval ::GX {}
namespace eval ::GX::CurveDigitizerCompanion {}
proc ::GX::CurveDigitizerCompanion::configurationRead {doc} {
    if {$doc ne "cfg1"} {error "wrong document"}
    return [dict create configuration [dict create \
        stroke_width_json {{"source_sha256":"sha","by_curve":{"c1":{"enabled":true}}}} \
        source_dataset_id src source_sha256 sha]]
}
proc ::GX::CurveDigitizerCompanion::curveContext {doc cid} {
    if {$doc ne "cfg1" || $cid ne "c1"} {error "wrong curve"}
    return [dict create curve_id c1 source_dataset_id src source_sha256 sha \
        stroke_width_status measured stroke_width_method manual stroke_width_px 4.2 \
        stroke_width_curve_json {{"enabled":true,"method":"manual"}}]
}
proc ::GX::sessionInspectionCurrentSession {} {return /tmp/stroke208}
proc ::GX::sessionInspectionDataset {id session} {
    if {$id ne "ds1" || $session ne "/tmp/stroke208"} {error "wrong Dataset"}
    return [dict create id ds1]
}
proc ::GX::datasetMetadataRead {session id} {
    return [dict create curve_digitizer.plugin_id viewer.curve_digitizer \
        curve_digitizer.source_dataset_id src curve_digitizer.source_sha256 sha \
        curve_digitizer.stroke_width_schema_version 1 \
        curve_digitizer.stroke_width_report_json {{"schema":"gxtxt.curve_digitizer.stroke_width.v1","curves":{"c1":{"status":"measured","width_px":4.2}}}}]
}
source [file join [file dirname [info script]] .. api curve_digitizer_stroke_width_api_v1.tcl]
set c [::GX::CurveDigitizerStrokeWidth::curveRead cfg1 c1]
if {[dict get $c width_px] ne "4.2" || [dict get $c propagated_uncertainty] != 0} {error "curve read"}
set all [::GX::CurveDigitizerStrokeWidth::configurationRead cfg1]
if {[dict get $all source_sha256] ne "sha"} {error "config read"}
if {![::GX::CurveDigitizerStrokeWidth::hasPublished ds1]} {error "published discovery"}
set published [::GX::CurveDigitizerStrokeWidth::publishedRead ds1]
if {[dict get $published propagated_uncertainty] ne "0"} {error "implicit sigma forbidden"}
if {![string match *measured* [dict get $published report_json]]} {error "no public report"}
puts {PASS: Stroke Width API v1 configuration, curve and publication facade}
