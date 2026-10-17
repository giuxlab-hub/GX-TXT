set prior [lindex $argv 2];set dataset [lindex $argv 3]
source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
if {$::env(DISPLAY) ne {:1}} {error {Actual Debian DISPLAY :1 required}}
set argv {};::GX::main
proc countCall {name command operation} {dict incr ::counts $name}
proc countNative {command operation} {set sub [lindex $command 1];if {$sub in {create configure}} {dict incr ::counts native_geometry_build}}
proc run {} {
    set session [file join $::out session];file copy $::prior $session;::GX::openSessionPath $session
    set id $::dataset
    set sourceSha [dict get [::GX::sessionInspectionDatasetPayload $id $session] sha256]
    ::GX::datasetBrowserActivate $id
    .top.nb select .top.nb.channels;.top.nb.channels.views select .top.nb.channels.views.preview
    ::GX::datasetPreviewRender;pause 400
    set text [.top.nb.preview.txt get 1.0 end]
    save preview_text $text
    check {![string match {*Scientific preview unavailable*} $text] && ![string match {*Source raster preview unavailable*} $text]} {Actual Digitalizer multi-calibration Preview renders}
    set token [lindex [dict keys $::GX::DigitizerPreview::state] 0]
    set record [dict get $::GX::DigitizerPreview::state $token]
    check {[dict exists $record native_widget] && [dict size [dict get $record native_series]]>=2} {Raster and calibrated XY views share actual curve visibility identities}
    set widget [dict get $record native_widget]
    .top.nb.preview.txt see $widget;pause 300
    check {[winfo ismapped $widget] && [winfo viewable $widget]} {Retained XY surface is visible during the latency measurement}
    exec import -window [winfo id .] [file join $::out retained_preview.png]
    set nativeToken [dict get [::GX::PlotDatasetAPIv4::_widget $widget 0] token]
    set before [::GX::PlotDatasetAPIv4::widgetDraw $widget]
    set curve [lindex [dict keys [dict get $record curves]] 0]
    set view [dict get $before axes]
    set ::counts {table_read 0 curve_open 0 authority_worker 0 native_geometry_build 0}
    foreach {command name} {::GX::tableStreamOpenDataset table_read ::GX::curveSourceOpen curve_open ::GX::datasetAuthorityTransaction authority_worker} {trace add execution $command enter [list countCall $name]}
    trace add execution ::gx::native2d::plot_v4 enter countNative
    set started [clock microseconds]
    for {set i 0} {$i<30} {incr i} {set ::GX::DigitizerPreview::visible($token,$curve) [expr {$i%2}];::GX::datasetDigitizerPreviewToggle $token $curve;update idletasks}
    set milliseconds [expr {([clock microseconds]-$started)/1000.}]
    foreach {command name} {::GX::tableStreamOpenDataset table_read ::GX::curveSourceOpen curve_open ::GX::datasetAuthorityTransaction authority_worker} {trace remove execution $command enter [list countCall $name]}
    trace remove execution ::gx::native2d::plot_v4 enter countNative
    check {[dict get $::counts table_read]==0 && [dict get $::counts curve_open]==0 && [dict get $::counts authority_worker]==0 && [dict get $::counts native_geometry_build]==0} {Thirty visibility changes perform no Dataset reads, scientific workers or geometry rebuild}
    set after [::GX::PlotDatasetAPIv4::widgetDraw $widget]
    check {[dict get [::GX::PlotDatasetAPIv4::_widget $widget 0] token] eq $nativeToken && [dict get $before resident_point_count]==[dict get $after resident_point_count] && [dict get $after axes] eq $view} {Native model, retained points and fitted axes remain stable}
    save visibility [dict create counts $::counts toggles 30 elapsed_ms $milliseconds mean_ms [expr {$milliseconds/30.}] model_token $nativeToken]
    ::GX::PlotDatasetAPIv4::widgetView $widget zoom main 1.2 .5 .5;pause
    check {[dict get [::GX::PlotDatasetAPIv4::widgetDraw $widget] axes] ne $view} {The retained Preview supports actual native zoom without source reconstruction}
    set producer [::GX::datasetField $id producer_module [::GX::datasetField $id source_module {}]]
    ::GX::datasetMetadataAuthorizeContributors $session $id math.numeric [::GX::datasetRevisionToken $id $session]
    ::GX::_datasetPrivateWithModule math.numeric ::GX::datasetMetadataUpdate $session $id {second_module_annotation {Unprefixed second contributor}}
    ::GX::datasetMetadataUpdate $session $id {user_annotation {Visible user contributor}}
    ::GX::_datasetMetadataPublicationWrite $session $id [dict merge [::GX::datasetMetadataRead $session $id] {system_annotation {Actual CORE administrative contribution}}] viewer.curve_digitizer {}
    .top.nb.channels.views select .top.nb.channels.views.metadata
    ::GX::datasetPageRenderSections imported $id;pause
    set groups [::GX::datasetMetadataGroups $session $id]
    set labels [lmap button [winfo children .top.nb.channels.metadata.groups] {$button cget -text}]
    foreach group [dict keys $groups] {check {[::GX::datasetMetadataGroupLabel $group] in $labels} "Actual Metadata GUI exposes present contributor $group"}
    check {[llength $labels]==[dict size $groups]} {Metadata GUI invents no absent module groups}
    check {[::GX::datasetField $id producer_module [::GX::datasetField $id source_module {}]] eq $producer && [dict get [::GX::sessionInspectionDatasetPayload $id $session] sha256] eq $sourceSha} {Contributor edits preserve original producer and exact scientific payload}
    exec import -window [winfo id .] [file join $::out metadata_groups.png]
    ::GX::datasetPreviewStop
    check {![dict exists $::GX::DigitizerPreview::state $token] && ![dict exists $::GX::PlotDatasetAPIv4::widgets $widget]} {Preview lifecycle releases retained native widget and visibility records}
    check {![info exists ::bgfailed]} {No Tk background errors}
    save result [dict create status PASS checks $::checks session $session]
}
set failed {};set done 0
after 500 {if {[catch {run} message options]} {set ::failed [dict get $options -errorinfo];save result [dict create status FAIL checks $::checks details $::failed];puts stderr $::failed};catch {destroy .};set ::done 1}
vwait done
exit [expr {$failed ne {}}]
