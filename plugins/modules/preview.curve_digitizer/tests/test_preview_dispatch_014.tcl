set ::env(GXTXT_PREVIEW_TEST_LEGACY) 1
# SPDX-License-Identifier: GPL-3.0-or-later
# Isolated functional test of 3-tab descriptors, correct group filters and Plot v4 callbacks.
package require Tk
wm withdraw .
namespace eval ::GX {}
namespace eval ::GX::CurveDigitizerDataset {}
namespace eval ::GX::PlotDatasetAPIv4 {}
set ::mock_source_count 0
set ::mock_series {}
set ::mock_visibility {}
set ::mock_values {}
set ::mock_context {}
set ::mock_plot_created 0
proc ::GX::modulePublicApiActivate {module api} {return 1}
proc ::GX::CurveDigitizerDataset::read {id} {
    if {$id ne {digitized.tutorial02.family.combined.curves}} {error {Wrong scientific source}}
    return [dict create dataset_id $id publication_calibration_mode combined \
        grouping_roles {curve_key calibration_key} raster_points_available 1 \
        columns [dict create curve_key curve_id curve_name curve_label calibration_key calibration_id \
            calibration_name calibration_label x x y y point_order point_index \
            family_parameter family_value raster_x pixel_x raster_y pixel_y point_id point_id]]
}
set ::mock_context [dict create \
    dataset_id digitized.tutorial02.family.combined.curves \
    session /tmp/isolated_token token mock_token contract curve_family.table \
    canonical_identity canonical_900_rows metadata [dict create curve_digitizer.source_dataset_id calibrated.family.image \
       curve_digitizer.source_sha256 [string repeat a 64] \
       curve_digitizer.measurement_count 3 curve_digitizer.quality_status reviewed \
       curve_digitizer.quality_issue_count 0 curve_digitizer.calibration_type affine \
       curve_digitizer.family_label c curve_digitizer.family_unit 1] \
    representation {}]
dict set ::mock_context variables [list     [dict create variable_id x display_label Time unit s]     [dict create variable_id y display_label Voltage unit V]]
proc ::GX::datasetPreviewGuiContext {host} {return $::mock_context}
proc ::GX::viewerGuiDesignRead {path} {
    set f [open $path r];set d [read $f];close $f;return $d
}
proc ::GX::viewerGuiDesignPreviewMount {design host callback} {
    ttk::frame .p
    ttk::frame .p.plotarea
    pack .p
    pack .p.plotarea
    return .p
}
proc ::GX::datasetPreviewGuiControlConfigure {host id properties} {
    if {$id ne {plotarea}} {error {unexpected control}}
    return .p.plotarea
}
proc ::GX::datasetPreviewGuiControlSet {host id value} {
    dict set ::mock_values $id $value
}
proc ::GX::datasetPreviewGuiControlGet {host id} {
    if {$id ne {groups}} {error {Invalid group list}}
    return [dict create items [dict get $::mock_values groups] selection {3}]
}
proc ::GX::datasetPreviewPage {session id options} {
    if {$session ne {/tmp/isolated_token} ||
        $id ne {digitized.tutorial02.family.combined.curves}} {
        error {Incorrect canonical source}
    }
    set requested [dict get $options variable_ids]
    if {$requested ne {curve_id curve_label point_index x y calibration_id calibration_label}} {
        error "Unexpected public schema Variable projection $requested"
    }
    set start [dict get $options start]
    set limit [dict get $options count]
    set all {}
    foreach c {5 15 25} {
      foreach k {0 1 4} {
        for {set j 0} {$j<100} {incr j} {
            lappend all [list "curve_c$c" "Source curve [expr {$c+1}]" \
                $j [expr {$j*0.1}] [expr {$c*0.1+$k*0.01+$j*0.001}] \
                "meas_k$k" "k$k"]
        }
      }
    }
    set last [expr {min($start+$limit-1,899)}]
    set rows [lrange $all $start $last]
    set sourceRows {}
    for {set i $start} {$i<=$last} {incr i} {lappend sourceRows [expr {$i+1}]}
    return [dict create available 1 count [llength $rows] rows $rows \
        source_rows $sourceRows has_next [expr {$last<899}]]
}
proc ::GX::PlotDatasetAPIv4::newSpec {args} {
    return [dict create graph_id plot.dataset.xy title {Test} panels {}]
}
proc ::GX::PlotDatasetAPIv4::widgetValidateSources {model options} {
    if {[dict get $options prepared_model]!=1} {error {Expected Plot v4 prepared model}}
    return [dict create valid 1 source_count 0]
}
proc ::GX::PlotDatasetAPIv4::widgetCreate {path model options} {
    if {[dict get $options prepared_model]!=1} {error {Missing Plot v4 prepare flag}}
    set ::mock_series [dict get [lindex [dict get $model panels] 0] series]
    set ::mock_plot_created 1
    canvas $path -width 800 -height 300
    return $path
}
proc ::GX::PlotDatasetAPIv4::widgetConfigure {path spec args} {
    set ::mock_series [dict get [lindex [dict get $spec panels] 0] series]
}
proc ::GX::PlotDatasetAPIv4::widgetVisibility {path panel series visible} {
    lappend ::mock_visibility [list $path $panel $series $visible]
}
proc ::GX::PlotDatasetAPIv4::widgetView {path action args} {return}
proc ::GX::PlotDatasetAPIv4::widgetPointer {path args} {return}
proc ::GX::PlotDatasetAPIv4::widgetDestroy {path} {set ::mock_plot_created 0}
source [file join [file dirname [info script]] .. api preview.tcl]
set response [::GX::DigitizerFamilyPreview::preview $::mock_context]
set tabs [dict get $response tabs]
if {[llength $tabs]!=3} {error "Expected exactly 3 tabs"}
set names [lmap tab $tabs {dict get $tab label}]
if {$names ne {Curves {Calibration & Quality} {Canonical Data}}} {error "Wrong three tab labels: $names"}
set q [lindex $tabs 1]
if {[dict get $q metadata {Accuracy status}] ne {Not assessed}} {error {Accuracy was invented}}
set t [lindex $tabs 2]
if {[dict get $t kind] ne {gui}} {error {Canonical GUI table descriptor mismatch}}
::GX::DigitizerFamilyPreview::guiMount fakehost $::mock_context
# The Preview mount may populate only bounded metadata/choices. It must NOT
# perform a canonical scientific Dataset read before explicit interaction.
if {![dict exists $::mock_values groups] ||
    [llength [dict get $::mock_values groups]] != 1} {
    error {The GUI left an unexplained empty curve list}
}
if {[llength $::mock_series] || [dict size $::GX::DigitizerFamilyPreview::pending]} {
    error {Scientific work occurred during passive guiMount}
}
# The real Builder invokes dispatch even for passive List selection.
# The 0.1.2 implementation threw "extra switch pattern with no body".
foreach id {groups identity plotarea notice unexpected} {
    if {[catch {
        ::GX::DigitizerFamilyPreview::dispatch fakehost [dict create control_id $id]
    } message]} {error "Passive GUI control $id failed: $message"}
}
set receipt [::GX::DigitizerFamilyPreview::dispatch fakehost \
    [dict create control_id groups type list event changed value [dict create items {{Select here or press Load curves}} selection {0}]]]
if {[dict get $receipt status] ne {preparing}} {
    error {Load must return immediately with preparing status}
}
set maxTime [expr {[clock milliseconds]+2500}]
while {![llength $::mock_series] && [clock milliseconds]<$maxTime} {
    update
    after 5
}
if {[llength $::mock_series]!=9} {
    error {Expected 9 canonical curve/calibration Plot v4 series}
}
set expectedSourceStart 0
foreach item $::mock_series {
    set points [dict get $item points]
    set sourceRows [dict get $item source_rows]
    if {[llength $points]!=100 || [llength $sourceRows]!=100} {
        error {Incomplete canonical Plot v4 series}
    }
    if {[lindex $sourceRows 0]!=$expectedSourceStart} {
        error {Source-row identity changed}
    }
    incr expectedSourceStart 100
}
if {$expectedSourceStart!=900} {error {Missing source rows}}
::GX::DigitizerFamilyPreview::dispatch fakehost [dict create control_id hide]
if {[lindex [lindex $::mock_visibility end] 3]!=0} {error {Hide did not use Plot v4}}
::GX::DigitizerFamilyPreview::dispatch fakehost [dict create control_id show_all]
::GX::DigitizerFamilyPreview::dispatch fakehost [dict create control_id fit]
::GX::DigitizerFamilyPreview::dispatch fakehost [dict create control_id zoom_in]
::GX::DigitizerFamilyPreview::dispatch fakehost [dict create control_id zoom_out]
if {[llength $::mock_visibility]!=10} {error {Expected one hide plus 9 show calls}}
if {[dict size $::GX::DigitizerFamilyPreview::pending] != 0} {
    error {Completed coroutine remains pending}
}
::GX::DigitizerFamilyPreview::guiDispose fakehost $::mock_context {closed}
if {$::mock_plot_created} {error {Plot native resources leaked}}
puts "PASS placeholder-click loads 9 groups; GUI dispatch/Hide/Show/Fit/Zoom and source checks"
destroy .
