set ::env(GXTXT_PREVIEW_TEST_LEGACY) 1
# SPDX-License-Identifier: GPL-3.0-or-later
# Two-axis native Plot v4 presentation and Y2 row binding, no CORE/Session writes.
package require Tk
wm withdraw .
namespace eval ::GX {}
namespace eval ::GX::CurveDigitizerDataset {}
namespace eval ::GX::PlotDatasetAPIv4 {}
set ::context [dict create dataset_id simulated.mixed session /tmp/f4_example token source_token \
 contract table.generic canonical_identity image_sha metadata [dict create \
 curve_digitizer.source_dataset_id source_image curve_digitizer.source_sha256 [string repeat a 64] \
 curve_digitizer.measurement_count 1] representation {}]
set ::mockPlot {}
set ::setControls {}
set ::plotChecked 0
set ::readCount 0
proc ::GX::modulePublicApiActivate {module api} {return 1}
proc ::GX::CurveDigitizerDataset::read {datasetId} {
    return [dict create dataset_id $datasetId contract table.generic \
     curve_schema_version 2 multi_y_available 1 publication_calibration_mode separate \
     grouping_roles {curve_key} raster_points_available 1 \
     columns [dict create x x y y curve_key curve_id curve_name curve_label \
      point_order point_index y_axis_id y_axis_id raster_x pixel_x raster_y pixel_y]]
}
proc ::GX::CurveDigitizerDataset::axes {datasetId} {
    set measurement [dict create measurement_id meas_0123456789abcdef0123456789abcdef \
       label One x [dict create name Frequency unit Hz scale log minimum 10 maximum 10000] \
       y1 [dict create name Voltage unit V scale linear minimum -30 maximum 10] \
       y2 [dict create name Amplitude unit V scale log minimum 0.001 maximum 1000]]
    return [dict create schema_version 1 available_axes {x y1 y2} \
        mode mixed measurements [list $measurement] unit_y1 V unit_y2 V]
}
proc ::GX::datasetPreviewGuiContext {host} {return $::context}
proc ::GX::datasetPreviewPage {session id args} {
    incr ::readCount
    if {$id ne {simulated.mixed}} {error {Wrong source}}
    set opts [lindex $args 0]
    set fields [dict get $opts variable_ids]
    if {$fields ne {curve_id curve_label point_index x y y_axis_id}} {
        error "Y2 canonical projection missing role: $fields"
    }
    set rows [list \
        {gain Gain 0 10 -3 y1} {gain Gain 1 100 -9 y1} \
        {phase Phase 0 10 0.1 y2} {phase Phase 1 100 10 y2}]
    return [dict create available 1 count 4 rows $rows source_rows {1 2 3 4} has_next 0]
}
proc ::GX::datasetPreviewGuiControlConfigure {host id options} {
    if {$id ne {plotarea}} {error {Wrong plot area}}
    return .p.plotarea
}
proc ::GX::datasetPreviewGuiControlSet {host key value} {
    dict set ::setControls $key $value
}
proc ::GX::PlotDatasetAPIv4::widgetValidateSources {model options} {
    if {[dict get $options prepared_model] ne {1}} {error {Not prepared}}
    set ::mockPlot $model
    incr ::plotChecked
    return [dict create valid 1]
}
proc ::GX::PlotDatasetAPIv4::widgetCreate {path model options} {
    set ::mockPlot $model
    canvas $path -width 580 -height 300
    return $path
}
proc ::GX::PlotDatasetAPIv4::widgetConfigure {path model options} {set ::mockPlot $model}
proc ::GX::PlotDatasetAPIv4::widgetDestroy {path} {}
source [file join [file dirname [info script]] .. api preview.tcl]
ttk::frame .p
ttk::frame .p.plotarea
pack .p
pack .p.plotarea
set schema [::GX::DigitizerFamilyPreview::_schema $::context]
set groups [::GX::DigitizerFamilyPreview::_groups [dict merge $::context {preview_host mock}] $schema]
if {[dict get $groups total_rows]!=4} {error {Y2 rows lost}}
if {[llength [dict get $groups ordered]]!=2} {error {Y2 curves not separated}}
set report [::GX::DigitizerFamilyPreview::preview $::context]
set tabs [dict get $report tabs]
if {[dict get [lindex $tabs 1] metadata {Y2 schema version}] ne {2}} {error {Y2 metadata hidden}}
::GX::DigitizerFamilyPreview::_display mock $groups
set panel [lindex [dict get $::mockPlot panels] 0]
set lines [dict get $panel series]
if {[llength $lines]!=2} {error {Wrong series count}}
if {[dict get [lindex $lines 0] axis] ne {left}} {error {Y1 not on left}}
if {[dict get [lindex $lines 1] axis] ne {right}} {error {Y2 not on right}}
if {[dict get $panel axes x scale] ne {log}} {error {Logarithmic X was lost}}
if {[dict get $panel axes right scale] ne {log}} {error {Logarithmic Y2 was lost}}
if {[dict get $panel axes left scale] ne {linear}} {error {Wrong Y1 scale}}
if {$::readCount!=1 || $::plotChecked!=1} {error {Unexpected canonical paging or renderer calls}}
puts {PASS F4 Preview v2: canonical axis row, X log, Y1 left linear, Y2 right log, Plot v4}
destroy .
