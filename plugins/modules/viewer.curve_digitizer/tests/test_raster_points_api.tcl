# SPDX-License-Identifier: GPL-3.0-or-later
# Read original raster pixels through CORE canonical dataset access, no CSV paths.
namespace eval ::GX {
    variable session /tmp/gxtxt_mock
    variable metadata {}
    variable opened 0
    variable closed 0
}
proc ::GX::sessionInspectionCurrentSession {} {return $::GX::session}
proc ::GX::sessionInspectionDataset {id s} {return [dict create id $id contract table.generic]}
proc ::GX::datasetMetadataRead {s id} {return $::GX::metadata}
proc ::GX::datasetVariableV3ById {datasetId varId} {
    set type [expr {$varId in {curve_id curve_label} ? "string" : $varId eq "point_index" ? "int64" : "float64"}]
    return [dict create variable_id $varId dtype $type rank 1 dimension_ids row]
}
proc ::GX::datasetAccessOpen {s id} {incr ::GX::opened;return handle}
proc ::GX::datasetAccessReadRange {handle ids start count} {
    set source [dict create curve_id {left right left} curve_label {L R L} point_index {0 0 1} \
        x {1.0 2.0 3.0} y {3.0 4.0 5.0} pixel_x {25.3 26.4 27.5} pixel_y {44.1 45.2 46.3}]
    set out [dict create]
    foreach id $ids {
        dict set out $id [dict create values [lrange [dict get $source $id] $start [expr {$start+$count-1}]]]
    }
    return $out
}
proc ::GX::datasetAccessClose {handle} {incr ::GX::closed}
source [file join [file dirname [info script]] .. api curve_digitizer_dataset_schema_api_v1.tcl]
set ::GX::metadata [dict create curve_digitizer.plugin_id viewer.curve_digitizer \
 curve_digitizer.curve_schema_version 1 curve_digitizer.curve_mode independent \
 curve_digitizer.curve_grouping curve_key curve_digitizer.curve_row_dimension row]
foreach {role variableId} {x x y y curve_key curve_id curve_name curve_label point_order point_index raster_x pixel_x raster_y pixel_y} {
    dict set ::GX::metadata curve_digitizer.curve_column.$role $variableId
}
set m [::GX::CurveDigitizerDataset::read dataset]
if {![dict get $m raster_points_available]} {error "Missing raster mapping"}
set data [::GX::CurveDigitizerDataset::rasterPoints dataset left 0 3]
if {[dict get $data consumed_rows] != 3 || [llength [dict get $data points]] != 2} {error "Grouping/range failed"}
if {[dict get [lindex [dict get $data points] 0] raster_x] ne "25.3"} {error "Pixel coordinate changed"}
if {$::GX::opened != 1 || $::GX::closed != 1} {error "CORE reader handle leaked"}
# Legacy output: must clearly reject unavailable raster points, never guess.
dict unset ::GX::metadata curve_digitizer.curve_column.raster_x
dict unset ::GX::metadata curve_digitizer.curve_column.raster_y
if {![catch {::GX::CurveDigitizerDataset::rasterPoints dataset} err] || ![string match "*not published*" $err]} {error "Legacy contract did not reject missing original pixels"}
puts "PASS semantic raster columns, per-curve filtering, bounded CORE reader, legacy missing-pixels rejection"
