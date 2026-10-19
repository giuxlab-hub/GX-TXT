# SPDX-License-Identifier: GPL-3.0-or-later
if {$::env(DISPLAY) ne {:109} || $::GX::currentSession ne {}} {error {Own fresh :109 required}}
proc settle {{ms 180}} {after $ms [list set ::cursorSettled 1];vwait ::cursorSettled;update}
set archive [file join [file dirname $::out] qa_portable01 sweep170.gxtxt-session.zip]
set imported [file join $::out Sessions imported_cursor];file mkdir [file dirname $imported]
record cursor_import [::GX::sessionPortableImport $archive $imported]
::GX::openSessionPath $imported
set original {}
foreach item [::GX::sessionWorkspaceList] {if {[dict get $item module_id] eq {viewer.circuit_workbench}} {set original [dict get $item id];break}}
if {$original eq {}} {error {Original imported Workspace missing}}
set project [file join [file dirname $::root] _private_dev108 qa_upgrade_project01]
::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
set ::cursorCalls {}
proc cursorTrace {args} {lappend ::cursorCalls [lindex $args 0]}
set ::cursorMethods {::GX::NumericAPIv1::callOperation ::GX::NumericAPIv1::callOperationCaptured ::GX::NumericAPIv1::expressionDataset ::GX::NumericAPIv1::expressionDatasetCaptured ::GX::NumericAPIv1::interpolateDatasetCaptured ::GX::NumericAPIv1::complexDatasetCaptured ::GX::scientificExecutionSubmit ::GX::scientificExecutionCircuitSweepSubmit ::GX::scientificExecutionRemoteCall ::GX::scientificExecutionStatus}
foreach method $::cursorMethods {if {[llength [info commands $method]]} {trace add execution $method enter cursorTrace}}
set report [::GX::viewerDevelopmentWorkspaceReviewWait $project $original]
set upgraded [::GX::viewerDevelopmentWorkspaceUpgrade $project [dict get $report review_id]]
set ::cursorWorkspace [dict get $upgraded workspace_id]
set ::cursorWindow [::GX::sessionWorkspaceOpen $::cursorWorkspace]
for {set n 0} {$n<1200} {incr n} {
 settle 100
 if {[dict exists $::GX::ViewerDevelopment::windows $::cursorWindow] && [dict get $::GX::ViewerDevelopment::windows $::cursorWindow busy] eq {} && [dict get $::GX::ViewerDevelopment::windows $::cursorWindow status] eq {COMPLETED}} break
}
set w $::cursorWindow
if {![dict exists $::GX::ViewerGui::instances $w]} {error {Normal installed factory failed}}
set ::cursorSource [::GX::native2DGeometryDiagramRead [dict get [::GX::viewerGuiDesignCapture $w] bindings graphics document_id]]
set ::cursorDatasets [dict get [::GX::datasetCatalogSnapshot] dataset_ids]
set ::cursorPlot [dict get $::GX::ViewerGui::instances $w widgets waveform_plot].plot
set plot $::cursorPlot
raise $w;wm geometry $w 1100x720+30+30;settle 300
set ::cursorBefore [::GX::viewerGuiDesignCapture $w]
set axes [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $plot] axes]
set point {}
for {set x 70} {$x<[winfo width $plot]-30 && $point eq {}} {incr x 12} {
 for {set y 35} {$y<[winfo height $plot]-40} {incr y 10} {
  set hit [::GX::PlotDatasetAPIv4::widgetHit $plot $x $y]
  if {[dict exists $hit source_row_ordinal]} {set point [list $x $y];break}
 }
}
if {$point eq {}} {error {No actual native waveform source point hit}}
lassign $point x y
exec xdotool windowfocus --sync [winfo id $w]
exec xdotool mousemove [expr {[winfo rootx $plot]+$x}] [expr {[winfo rooty $plot]+$y}] click 1
settle 300
set after [::GX::viewerGuiDesignCapture $w]
set annotations [dict get [lindex [dict get $after bindings waveform_plot spec panels] 0] annotations]
if {[llength $annotations]!=2} {record cursor_failed [dict create before $::cursorBefore after $after hit $hit];error {Actual source-point release did not create two reference annotations}}
if {$axes ne [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $plot] axes]} {error {Source cursor changed the native viewport}}
if {[dict get [::GX::native2DGeometryDiagramRead [dict get $::cursorSource id]] sha256] ne [dict get $::cursorSource sha256] || $::cursorDatasets ne [dict get [::GX::datasetCatalogSnapshot] dataset_ids] || [llength $::cursorCalls]} {error "Cursor changed scientific authority: $::cursorCalls"}
set ::cursorPoint $point
record cursor_actual_point [dict create status PASS_ACTUAL_POINT_CURSOR_ONLY hit $hit point $point annotations $annotations before_axes $axes after_axes [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $plot] axes] source [dict remove $::cursorSource payload] datasets $::cursorDatasets cpp_counter [dict get $::GX::ViewerDevelopment::windows $w state counter] history [::GX::scientificHistoryViewerRecord $w] science_calls $::cursorCalls]
capture $w cursor_actual_point
return PASS_ACTUAL_NATIVE_CURSOR_REVIEW_SCREENSHOT_REQUIRED
