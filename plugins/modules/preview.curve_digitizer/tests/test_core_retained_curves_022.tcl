# GPL-3.0-or-later. Isolated, real CORE-retained model fixture, no Session writes.
package require Tk
wm withdraw .
namespace eval ::GX {}
namespace eval ::GX::CurveDigitizerDataset {}
namespace eval ::GX::PlotDatasetAPIv4 {}
set path /home/giu/progetti-gx/project-20261029T075850Z-477340-1793260730340107-1/Sessions/Lesson_04/cache/dataset_previews/a5dac8ccfb62c47bef710de960985dbb66c2d8cb2704fe7d5e553a82d1ad5ba5/representation.tcldict
set fd [open $path r];set record [read $fd];close $fd
set ::retained [dict get $record native_model]
set ::cachedCalls 0
set ::pageCalls 0
set ::plotCreated 0
set ::model {}
set ::notice {}
set ::context [dict create dataset_id digitized.tutorial.04.1_uncertainty.measurement_1.curves.y2 session /isolated/mock token valid metadata {} canonical_identity stable]
proc ::GX::datasetPreviewGuiContext {host} {return $::context}
proc ::GX::modulePublicApiActivate {args} {}
proc ::GX::CurveDigitizerDataset::read {id} {
    return [dict create publication_calibration_mode separate multi_y_available 1 columns [dict create curve_key curve_id curve_name curve_label point_order point_index x x y y]]
}
proc ::GX::CurveDigitizerDataset::axes {id} {
    set axes [dict create x [dict create name Frequency unit Hz scale log] y1 [dict create name Gain unit dB scale linear] y2 [dict create name Phase unit deg scale linear]]
    return [dict create mode y2 measurements [list $axes]]
}
proc ::GX::CurveDigitizerDataset::curves {id} {
    return [dict create curves [list [dict create curve_id 3095e611-31c4-45b9-a0e3-4a8cfaee239a curve_name Phase axis_id y2]]]
}
proc ::GX::viewerGuiDesignRead {file} {return {}}
proc ::GX::viewerGuiDesignPreviewMount {design host callback} {
    ttk::frame .p
    ttk::frame .p.plotarea
    pack .p
    pack .p.plotarea
}
proc ::GX::datasetPreviewGuiControlConfigure {host control properties} {
    if {$control ne {plotarea}} {error {Bad target}}
    return .p.plotarea
}
proc ::GX::datasetPreviewGuiControlSet {host key value} {dict set ::notice $key $value}
proc ::GX::datasetPreviewGuiControlGet {host key} {
    return [dict create selection {0}]
}
proc ::GX::PlotDatasetAPIv4::widgetValidateSources {model options} {
    if {[dict get $options prepared_model]!=1} {error {Not prepared Plot v4}}
    return [dict create valid 1]
}
proc ::GX::PlotDatasetAPIv4::widgetCreate {path model options} {
    set ::model $model
    incr ::plotCreated
    canvas $path -height 200 -width 400
    return $path
}
proc ::GX::PlotDatasetAPIv4::widgetConfigure {path model options} {set ::model $model}
proc ::GX::PlotDatasetAPIv4::widgetDestroy {path} {if {[winfo exists $path]} {destroy $path}}
proc ::GX::datasetPreviewGuiCachedPageRequest {host options callback} {
    error {Page request is not part of the Curves test}
}
proc ::GX::datasetPreviewGuiCachedCurvesRequest {host callback} {
    incr ::cachedCalls
    after idle [list {*}$callback [dict create status ready dataset_id [dict get $::context dataset_id] model $::retained total_rows 100 displayed_points 100 cache_hit 1]]
    return [dict create status ready cache_hit 1]
}
source [file join [file dirname [info script]] .. api preview.tcl]
::GX::DigitizerFamilyPreview::guiMount h $::context
set response [::GX::DigitizerFamilyPreview::load h]
if {[dict get $response status] ne {ready} ||
    [dict size $::model] || $::pageCalls} {error {CORE model request did not return without synchronous plotting}}
update
set panel [lindex [dict get $::model panels] 0]
if {[dict get $panel axes x scale] ne {log} ||
    [dict get $panel axes x min] <= 0 ||
    [dict get $panel axes right label] ne {Phase (deg)} ||
    [dict get [lindex [dict get $panel series] 0] axis] ne {right} ||
    [llength [dict get [lindex [dict get $panel series] 0] source_rows]] != 100 ||
    $::pageCalls} {error {CORE retained model lost scientific axes/source row identities}}
# The widget is reused on a second Load; no canonical paging occurs.
::GX::DigitizerFamilyPreview::load h
update
if {$::cachedCalls!=2 || $::plotCreated!=1 || $::pageCalls} {
    error {Repeat Load wrongly reconstructed canonical points}
}
# Mock Session reopening: new host/widget, same valid retained CORE model.
::GX::DigitizerFamilyPreview::guiDispose h $::context {closed}
destroy .p
::GX::DigitizerFamilyPreview::guiMount h2 $::context
::GX::DigitizerFamilyPreview::load h2
update
if {$::plotCreated!=2 || $::cachedCalls!=3 || $::pageCalls} {
    error {Reopen failed to consume retained source without canonical paging}
}
puts {PASS cached Curves, source rows, right Y2, logarithmic X, reopen, zero canonical re-reads}
destroy .
