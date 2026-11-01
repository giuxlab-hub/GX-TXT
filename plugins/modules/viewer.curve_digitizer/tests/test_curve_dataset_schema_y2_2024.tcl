# SPDX-License-Identifier: GPL-3.0-or-later
# Public API v1 understands its producer's v2 metadata without CORE edits.
namespace eval ::GX {
    variable currentSession /tmp/isolated_f4_session
    variable metadata {}
    variable variables {}
    variable scanRows {}
    variable accessClosed 0
}
proc ::GX::sessionInspectionCurrentSession {} {return $::GX::currentSession}
proc ::GX::sessionInspectionDataset {id session} {
    if {$id ne "bode" || $session ne $::GX::currentSession} {error {Unknown dataset}}
    return [dict create contract table.generic]
}
proc ::GX::datasetMetadataRead {session id} {return $::GX::metadata}
proc ::GX::datasetVariableV3ById {id col} {return [dict get $::GX::variables $col]}
proc ::GX::datasetAccessOpen {session id} {return handle}
proc ::GX::datasetAccessReadRange {handle ids start count} {
    if {$ids ne {curve_id curve_label}} {error {Unexpected v1 metadata read}}
    set slice [lrange $::GX::scanRows $start [expr {$start+$count-1}]]
    set keys {};set labels {}
    foreach r $slice {lappend keys [lindex $r 0];lappend labels [lindex $r 1]}
    return [dict create curve_id [dict create values $keys] curve_label [dict create values $labels]]
}
proc ::GX::datasetAccessClose {handle} {incr ::GX::accessClosed}
proc ::GX::datasetGroupForDataset {session id} {return grp_example}
proc ::GX::datasetGroupGet {session id} {
    return [dict create status COMPLETE primary_dataset_id bode members \
        [list [dict create dataset_id bode role curve_digitizer.axis.y1 required 1]]]
}
proc assert {actual expected what} {
    if {$actual ne $expected} {error "$what: expected '$expected', received '$actual'"}
}
source [file join [file dirname [info script]] .. api curve_digitizer_dataset_schema_api_v1.tcl]
set ::GX::metadata [dict create curve_digitizer.plugin_id viewer.curve_digitizer \
    curve_digitizer.curve_schema_version 2 curve_digitizer.axis_schema_version 1 \
    curve_digitizer.axis_model_version 2 curve_digitizer.axis_mode mixed \
    curve_digitizer.curve_mode independent curve_digitizer.curve_grouping curve_key \
    curve_digitizer.curve_row_dimension row \
    curve_digitizer.curve_column.x x curve_digitizer.curve_column.y y \
    curve_digitizer.curve_column.curve_key curve_id \
    curve_digitizer.curve_column.curve_name curve_label \
    curve_digitizer.curve_column.point_order point_index \
    curve_digitizer.curve_column.y_axis_id y_axis_id \
    curve_digitizer.curve_column.raster_x pixel_x \
    curve_digitizer.curve_column.raster_y pixel_y \
    curve_digitizer.axis_units_y1 V curve_digitizer.axis_units_y2 V \
    curve_digitizer.publication_set_id pubset_123]
set measurements [list [dict create measurement_id meas_0123456789abcdef0123456789abcdef label First \
    x [dict create name F minimum 1 maximum 1000 unit Hz scale log] \
    y1 [dict create name Voltage minimum 0 maximum 5 unit V scale linear] \
    y2 [dict create name Other minimum 1 maximum 100 unit V scale log]]]
package require json
set json { [ {"measurement_id":"meas_0123456789abcdef0123456789abcdef","label":"First","x":{"name":"F","minimum":1,"maximum":1000,"unit":"Hz","scale":"log"},"y1":{"name":"Voltage","minimum":0,"maximum":5,"unit":"V","scale":"linear"},"y2":{"name":"Other","minimum":1,"maximum":100,"unit":"V","scale":"log"}} ] }
# Tcl literal includes braces and whitespace, which json::json2dict accepts.
dict set ::GX::metadata curve_digitizer.axis_definitions_json $json
dict set ::GX::metadata curve_digitizer.curves_json {[
    {"curve_id":"gain","curve_name":"Gain","axis_id":"y1","point_count_per_calibration":2},
    {"curve_id":"phase","curve_name":"Phase","axis_id":"y2","point_count_per_calibration":3}
]}
dict set ::GX::metadata curve_digitizer.curve_axis.gain y1
dict set ::GX::metadata curve_digitizer.curve_axis.phase y2
foreach {role var dtype} {
    x x float64 y y float64 curve_key curve_id string curve_name curve_label string
    point_order point_index int64 y_axis_id y_axis_id string
    raster_x pixel_x float64 raster_y pixel_y float64
} {
    dict set ::GX::variables $var [dict create variable_id $var dtype $dtype rank 1 dimension_ids row]
}
set m [::GX::CurveDigitizerDataset::read bode]
assert [dict get $m curve_schema_version] 2 v2
assert [dict get $m multi_y_available] 1 availability
assert [dict get $m columns y_axis_id] y_axis_id axis_mapping
set a [::GX::CurveDigitizerDataset::axes bode]
assert [dict get $a mode] mixed mode
assert [llength [dict get $a measurements]] 1 calibration_count
set c [::GX::CurveDigitizerDataset::curves bode]
assert [llength [dict get $c curves]] 2 curve_count
assert [dict get [lindex [dict get $c curves] 1] axis_id] y2 curve_axis
set description [::GX::CurveDigitizerDataset::describe bode]
assert [dict get $description group group_id] grp_example group
dict set ::GX::metadata curve_digitizer.curve_axis.phase y1
if {![catch {::GX::CurveDigitizerDataset::curves bode}]} {
    error {Inconsistent curve binding accepted}
}
dict set ::GX::metadata curve_digitizer.curve_axis.phase y2
dict set ::GX::metadata curve_digitizer.curve_schema_version 3
if {![catch {::GX::CurveDigitizerDataset::read bode}]} {error {Unknown schema accepted}}
dict set ::GX::metadata curve_digitizer.curve_schema_version 1
dict unset ::GX::metadata curve_digitizer.curve_column.y_axis_id
set ::GX::scanRows [list [list a "Alpha"] [list a "Alpha"] [list b "Beta"]]
set legacy [::GX::CurveDigitizerDataset::curves bode]
assert [llength [dict get $legacy curves]] 2 legacy_curve_count
assert [dict get [lindex [dict get $legacy curves] 0] point_count_per_calibration] 2 legacy_point_count
assert $::GX::accessClosed 1 legacy_access_closed
puts {PASS F4 public schema v2 normalized Y1/Y2, curve metadata, group reference, legacy scanner, invalid version/binding}
