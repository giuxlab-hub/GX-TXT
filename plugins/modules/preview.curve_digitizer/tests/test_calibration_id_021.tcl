set ::env(GXTXT_PREVIEW_TEST_LEGACY) 1
# SPDX-License-Identifier: GPL-3.0-or-later
# Actual Tk Treeviews + production public datasetPreviewGuiTableSet, simulated
# canonical host/page transport. Never modifies Session or CORE.
package require Tk
wm withdraw .
namespace eval ::GX {}
namespace eval ::GX::CurveDigitizerDataset {}
namespace eval ::GX::PreviewGui {}
namespace eval ::GX::UiField {variable componentTableFonts {}}
proc ::GX::datasetPublicationV2DictDefault {d key fallback} {
    if {[dict exists $d $key]} {return [dict get $d $key]}
    return $fallback
}
if {![info exists ::env(GXTXT_FRAMEWORK_ROOT)]} {error {Set GXTXT_FRAMEWORK_ROOT}}
source [file join $::env(GXTXT_FRAMEWORK_ROOT) core tcl ui_field_viewer_regions_v1.tcl]
source [file join $::env(GXTXT_FRAMEWORK_ROOT) core tcl dataset_preview_numeric_gui_v1.tcl]
proc ::GX::uiFieldInspectionColumnsSchedule {tree} {}
set ::model [dict create dataset_id mock.canonical session /isolated/mock token tok canonical_identity abc \
    metadata [dict create curve_digitizer.curve_column.point_id opaque_pt_identifier \
        curve_digitizer.calibration_id cal_4899cc7784f6f6009d10e897 \
        curve_digitizer.active_measurement_id meas_434ccf2e4e2a4596bb7b3ee1c64c287a \
        curve_digitizer.measurement.0.calibration_id cal_4899cc7784f6f6009d10e897 \
        curve_digitizer.measurement.0.measurement_id meas_434ccf2e4e2a4596bb7b3ee1c64c287a \
        curve_digitizer.measurement.0.label {Measurement 1}] \
    variables [list [dict create variable_id x unit Hz rank 1 dtype float64 dimension_ids row enabled 1] \
        [dict create variable_id y unit dB rank 1 dtype float64 dimension_ids row enabled 1] \
        [dict create variable_id opaque_pt_identifier unit {} rank 1 dtype string dimension_ids row enabled 1] \
        [dict create variable_id uncertainty_x unit Hz rank 1 dtype float64 dimension_ids row enabled 1 semantic_role uncertainty_standard_x] \
        [dict create variable_id uncertainty_y unit dB rank 1 dtype float64 dimension_ids row enabled 1 semantic_role uncertainty_standard_y] \
        [dict create variable_id uncertainty_cross unit {Hz*dB} rank 1 dtype float64 dimension_ids row enabled 1 semantic_role uncertainty_covariance_xy]]]
set ::pageCalls 0
set ::precision {6 digits}
set ::labels {}
ttk::frame .science
ttk::treeview .science.table -columns {{Row} {Curve} {Point} {X (physical)} {Y (physical)} Axis Calibration {Sigma X} {Sigma Y} {Cov XY}} -show headings
ttk::frame .technical
ttk::treeview .technical.table -columns {{Row} {Curve ID} {Point ID} {Calibration ID} {Pixel X} {Pixel Y}} -show headings
foreach table {.science.table .technical.table} {
    foreach col [$table cget -columns] {$table heading $col -text $col}
}
proc ::GX::_datasetPreviewGuiControl {host id} {
    if {$id eq {science_table}} {return [dict create widget .science type table properties {scrollbars both}]}
    if {$id eq {provenance_table}} {return [dict create widget .technical type table properties {scrollbars both}]}
    error {Unknown table id}
}
proc ::GX::datasetPreviewGuiContext {host} {return $::model}
proc ::GX::datasetPreviewGuiControlGet {host id} {
    if {$id ne {precision}} {error {Unsupported control}}
    return $::precision
}
proc ::GX::datasetPreviewGuiControlSet {host id value} {
    dict set ::labels $id $value
}
proc ::GX::CurveDigitizerDataset::read {id} {
    return [dict create publication_calibration_mode separate \
        columns [dict create curve_key curve_id curve_name curve_label point_order point_index \
            x x y y y_axis_id y_axis_id raster_x pixel_x raster_y pixel_y]]
}
proc ::GX::modulePublicApiActivate {module api} {}
proc ::GX::datasetPreviewPage {session id options} {
    incr ::pageCalls
    if {$session ne {/isolated/mock} || $id ne {mock.canonical}} {error {Wrong source authority}}
    set requested [dict get $options variable_ids]
    if {$requested ne {curve_id curve_label point_index x y y_axis_id pixel_x pixel_y opaque_pt_identifier uncertainty_x uncertainty_y uncertainty_cross}} {
        error "Incorrect public Variable projection: $requested"
    }
    set start [dict get $options start]
    set last [expr {min(119,$start+[dict get $options count]-1)}]
    set rows {};set indices {}
    for {set i $start} {$i<=$last} {incr i} {
        set x [format %.17g [expr {10.0+0.1234567890123456*$i}]]
        set y [format %.17g [expr {-0.03141592653589793*$i}]]
        lappend rows [list curve_uuid Gain $i $x $y y1 [expr {180+$i*.5}] [expr {173+$i*.1}] point_$i 0.055474596310924718 0.050331291394424556 5.3824979972947501e-05]
        lappend indices [expr {$i+1}]
    }
    return [dict create available 1 count [llength $rows] rows $rows source_rows $indices \
        has_next [expr {$last<119}]]
}
source [file join [file dirname [info script]] .. api preview.tcl]
set ::GX::DigitizerFamilyPreview::tableState [dict create mock [dict create start 0 page_size 50 loaded 0 has_next 0]]
if {$::pageCalls} {error {A canonical read occurred before explicit Load}}
# No hard-coded variable ID: the schema v1 has no point_id role. Read mapping
# from producer metadata and independently validate the canonical V3 variable.
set good [::GX::DigitizerFamilyPreview::_tablePointIdColumn $::model [dict get [::GX::CurveDigitizerDataset::read mock.canonical] columns]]
if {$good ne {opaque_pt_identifier}} {error {Metadata Point ID mapping not admitted}}
set bad $::model
dict set bad metadata curve_digitizer.curve_column.point_id missing_point
if {![catch {::GX::DigitizerFamilyPreview::_tablePointIdColumn $bad [dict get [::GX::CurveDigitizerDataset::read mock.canonical] columns]}]} {error {Missing mapped Variable ID accepted}}
set bad $::model
dict set bad metadata curve_digitizer.curve_column.point_id x
if {![catch {::GX::DigitizerFamilyPreview::_tablePointIdColumn $bad [dict get [::GX::CurveDigitizerDataset::read mock.canonical] columns]}]} {error {Point ID aliased to X accepted}}
set bad $::model
dict set bad variables [lreplace [dict get $bad variables] 2 2 [dict create variable_id opaque_pt_identifier unit {} rank 1 dtype float64 dimension_ids row enabled 1]]
if {![catch {::GX::DigitizerFamilyPreview::_tablePointIdColumn $bad [dict get [::GX::CurveDigitizerDataset::read mock.canonical] columns]}]} {error {Non-text Point ID accepted}}
set columns [dict get [::GX::CurveDigitizerDataset::read mock.canonical] columns]
set u [::GX::DigitizerFamilyPreview::_tableUncertaintyColumns $::model $columns]
if {[dict get $u sigma_x] ne {uncertainty_x} ||
    [dict get $u sigma_y] ne {uncertainty_y} ||
    [dict get $u covariance_xy] ne {uncertainty_cross}} {
    error {Uncertainty semantic roles were not resolved}
}
set bad $::model
set vars [dict get $bad variables]
dict set bad variables [lrange $vars 0 end-1]
if {![catch {::GX::DigitizerFamilyPreview::_tableUncertaintyColumns $bad $columns}]} {
    error {Partial uncertainty schema accepted}
}
set bad $::model
set vars [dict get $bad variables]
set last [lindex $vars end]
dict set last unit wrong
dict set bad variables [lreplace $vars end end $last]
if {![catch {::GX::DigitizerFamilyPreview::_tableUncertaintyColumns $bad $columns}]} {
    error {Incompatible covariance unit accepted}
}
set sourceSchema [::GX::CurveDigitizerDataset::read mock.canonical]
set c [::GX::DigitizerFamilyPreview::_tableSeparateCalibration $::model $sourceSchema]
if {[dict get $c id] ne {cal_4899cc7784f6f6009d10e897} ||
    [dict get $c label] ne {Measurement 1}} {error {Separate calibration identity was lost}}
set inconsistent $::model
dict set inconsistent metadata curve_digitizer.measurement.0.calibration_id cal_927b2c3b4f87bdbed5594555
if {![catch {::GX::DigitizerFamilyPreview::_tableSeparateCalibration $inconsistent $sourceSchema}]} {
    error {Conflicting Calibration ID accepted}
}
set missing $::model
dict unset missing metadata curve_digitizer.calibration_id
if {[dict get [::GX::DigitizerFamilyPreview::_tableSeparateCalibration $missing $sourceSchema] id] ne {Not published}} {
    error {Missing Calibration ID was fabricated}
}
set combined [dict create publication_calibration_mode combined]
if {[::GX::DigitizerFamilyPreview::_tableSeparateCalibration $::model $combined] ne {}} {
    error {Combined per-row calibration was unexpectedly replaced}
}
set first [::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id first]]
if {[dict get $first displayed]!=50 || $::pageCalls!=1} {error {First bounded page failed}}
if {[llength [.science.table children {}]]!=50 || [llength [.technical.table children {}]]!=50} {error {Tk rows mismatch}}
set row [.science.table item [lindex [.science.table children {}] 0] -values]
if {[llength $row]!=10 || [lindex $row 7] ne {0.0554746} ||
    [lindex $row 8] ne {0.0503313} ||
    [lindex $row 9] ne {5.3825e-05}} {error "Missing or malformed uncertainty cells: $row"}

if {[lindex $row 0] ne {1} || [lindex $row 1] ne {Gain} || [lindex $row 5] ne {Y1}} {error "Scientific metadata changed: $row"}
set traceRow [.technical.table item [lindex [.technical.table children {}] 0] -values]
if {[lindex $traceRow 3] ne {cal_4899cc7784f6f6009d10e897}} {
    error "Actual calibration was not displayed in Point traceability: $traceRow"
}
if {[lindex $row 6] ne {Measurement 1}} {
    error "Calibrated label was not displayed: $row"
}

if {[lindex $traceRow 1] ne {curve_uuid} || [lindex $traceRow 2] ne {point_0}} {error {Source identifiers lost}}
set second [::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id next]]
if {$::pageCalls!=2} {error {Second page was not read exactly once}}
if {[dict get $second displayed]!=50 || [dict get $second start]!=50} {error {Second page did not advance}}
set third [::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id next]]
if {$::pageCalls!=3} {error {Third page was not read exactly once}}
if {[dict get $third displayed]!=20 || [dict get $third has_next]} {error {Last page incorrectly bounded}}
set priorCalls $::pageCalls
::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id next]
if {$::pageCalls!=$priorCalls} {error {Next past end read again}}
set ::precision {Full precision}
::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id precision]
if {$::pageCalls!=$priorCalls} {error {Precision change unnecessarily re-read a cached canonical page}}
set original [.science.table item [lindex [.science.table children {}] 0] -values]
if {[lindex $original 0] ne {101}} {error {Precision change shifted source rows}}
::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id previous]
if {$::pageCalls!=3} {error {Back-navigation failed to reuse retained canonical page}}
::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id previous]
if {$::pageCalls!=4} {error {Bounded eviction did not trigger correct public read}}
if {[lindex [.science.table item [lindex [.science.table children {}] 0] -values] 0] ne {1}} {error {Previous did not restore first page}}
puts "PASS calibration, uncertainty and cache v0.1.11: public projection, Tk Treeviews, 50/50/20 paging, full precision, Y-axis, raw identities, no extra reads"
destroy .
