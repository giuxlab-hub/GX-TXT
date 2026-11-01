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
    metadata [dict create curve_digitizer.curve_column.point_id opaque_pt_identifier] \
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

# The production public CORE adapter responds only from an asynchronous
# cache result. These stubs model its notifications and source-bound retention.
namespace eval ::TEST {variable retained {};variable requests 0}
proc ::GX::datasetPreviewGuiCachedPageRequest {host options callback} {
    incr ::TEST::requests
    after idle [list ::TEST::fulfill $host $options $callback]
    return [dict create status preparing]
}
proc ::TEST::fulfill {host options callback} {
    set key [list [dict get $::model canonical_identity] $options]
    if {[dict exists $::TEST::retained $key]} {
        set page [dict get $::TEST::retained $key]
    } else {
        set page [::GX::datasetPreviewPage [dict get $::model session] [dict get $::model dataset_id] $options]
        dict set ::TEST::retained $key $page
    }
    uplevel #0 [list {*}$callback [dict create status ready page $page cache_hit 1]]
}
set first [::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id first]]
if {[dict get $first status] ne {preparing} || $::pageCalls!=0} {
    error {First table Load blocked GUI or read canonical data synchronously}
}
update
if {$::pageCalls!=1 || [.science.table children {}] eq {}} {
    error {First asynchronous canonical page was not displayed}
}
set ::precision {Full precision}
::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id precision]
if {$::pageCalls!=1} {error {Precision change re-read cached page}}
set next [::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id next]]
if {[dict get $next status] ne {preparing} || $::pageCalls!=1} {
    error {Next navigation blocked the UI}
}
update
if {$::pageCalls!=2} {error {Second page was not prepared}}
::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id previous]
if {$::pageCalls!=2} {error {Previous did not reuse retained page}}
::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id next]
if {$::pageCalls!=2} {error {Next did not reuse retained page}}
::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id next]
update
if {$::pageCalls!=3} {error {Third page was not prepared}}
# Reopening the GUI host discards its two-page memo. The CORE-backed
# persistent page is still available; no canonical Dataset read.
set ::GX::DigitizerFamilyPreview::tableState [dict create mock [dict create start 0 page_size 50 loaded 0 has_next 0]]
::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id first]
if {$::pageCalls!=3} {error {Reopen incurred synchronous read}}
update
if {$::pageCalls!=3} {error {Reopen failed to use durable CORE page}}
# Genuine scientific identity changes invalidate the public retained page.
dict set ::model canonical_identity changed
set ::GX::DigitizerFamilyPreview::tableState [dict create mock [dict create start 0 page_size 50 loaded 0 has_next 0]]
::GX::DigitizerFamilyPreview::_tableDispatch mock [dict create control_id first]
update
if {$::pageCalls!=4} {error {Scientific revision change returned stale cache}}
puts {PASS async Canonical Data with all-page CORE cache, reopen, precision, backward/forward, revision invalidation}
destroy .
