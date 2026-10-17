set prior [lindex $argv 2]
source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
if {$::env(DISPLAY) ne {:1}} {error {Actual Debian DISPLAY :1 required}}
set argv {};::GX::main
proc click {w} {raise [winfo toplevel $w];update;exec xdotool mousemove --sync [expr {[winfo rootx $w]+[winfo width $w]/2}] [expr {[winfo rooty $w]+[winfo height $w]/2}] click 1;pause 200}
proc run {} {
    set session [file join $::out session];file copy $::prior $session;::GX::openSessionPath $session
    set traces {};foreach number {1 2 3} {lappend traces [dict create dataset_id source_$number x_variable_id arbitrary_coordinate y_variable_id arbitrary_measurement physical_feature_id edge_A curve_key physical_edge observation_id observation_$number point_set_id clicked_$number calibration_realization_id calibration_$number source_group_id instrument_A frame_id laboratory]}
    set request [dict create analysis_id gui_independent_yx method yx design repeatability reference_frame {id laboratory declaration explicit_user_verified x_unit mm y_unit mm} traces $traces grid_points 11 localization_uncertainty 0 calibration_uncertainty 0.2]
    set count [llength [::GX::scriptJobList]]
    set w [::GX::viewerOpen viewer.replicate_curve_analysis replicate_consensus [dict create request $request]];pause 500
    check {[winfo exists $w.body.inspector.scroll] && [winfo exists $w.body.canvas] && [dict get [::GX::viewerGuiHostApiInfo] api_id] eq {VIEWER_GUI_HOST_API_v1}} {Real Replicate CORE Viewer consumes common integration manifest}
    check {[llength [::GX::scriptJobList]]==$count && ![::GX::moduleIsEnabled curve.replicate_analysis]} {Opening the Viewer never enables or executes legacy Analysis}
    click $w.toolbar.command2
    set deadline [expr {[clock milliseconds]+180000}]
    while {$::GX::ReplicateViewer::state($w,busy) && [clock milliseconds]<$deadline} {pause 150}
    save analysis_diagnostic [dict create status_text [$w.footer.status cget -text] busy $::GX::ReplicateViewer::state($w,busy) ticket_exists [info exists ::GX::ReplicateViewer::state($w,ticket)]]
    check {[dict exists $::GX::ReplicateViewer::state($w,payload) result]} "Real Analyze toolbar command adopts the supervised scientific result; status: [$w.footer.status cget -text]"
    set result [dict get $::GX::ReplicateViewer::state($w,payload) result]
    check {abs([lindex [dict get $result columns y_mean] 5]-4)<1e-10} {14 Viewer result matches independently tested public scientific service}
    set path $w.body.canvas.plot;pause
    set token [dict get [::GX::PlotDatasetAPIv4::_widget $path 0] token]
    set before [::GX::PlotDatasetAPIv4::widgetDraw $path]
    set chooser $w.body.inspector.scroll.content.visibility.s2
    set started [clock microseconds]
    for {set i 0} {$i<20} {incr i} {$chooser invoke;update idletasks}
    set elapsed [expr {([clock microseconds]-$started)/1000.}]
    check {[dict get [::GX::PlotDatasetAPIv4::_widget $path 0] token] eq $token && [dict get [::GX::PlotDatasetAPIv4::widgetDraw $path] resident_point_count]==[dict get $before resident_point_count]} {Visibility retains the same native model and scientific geometry buffers}
    save visibility [dict create toggles 20 elapsed_ms $elapsed mean_ms [expr {$elapsed/20.}] native_token $token]
    click $w.toolbar.command5;pause
    check {[dict exists $::GX::ReplicateViewer::state($w,payload) plot_ref]} {Actual toolbar publishes an editable canonical Plot v4 Graph}
    set id [::GX::ReplicateViewer::save $w]
    ::GX::sessionPersistenceCommit
    exec import -window [winfo id $w] [file join $::out replicate_viewer.png]
    destroy $w;pause
    set w [::GX::viewerOpen viewer.replicate_curve_analysis replicate_consensus [dict create workspace_id $id]];pause
    check {[dict exists $::GX::ReplicateViewer::state($w,payload) result] && [dict exists $::GX::ReplicateViewer::state($w,payload) plot_ref]} {Workspace reopen retains source recipe, scientific result and Plot reference}
    ::GX::PlotDatasetAPIv4::widgetView $w.body.canvas.plot zoom main 1.25 .5 .5
    ::GX::ReplicateViewer::rememberView $w;set axes [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $w.body.canvas.plot] axes]
    ::GX::ReplicateViewer::save $w;destroy $w;pause
    set w [::GX::viewerOpen viewer.replicate_curve_analysis replicate_consensus [dict create workspace_id $id]];pause
    check {[dict get [::GX::PlotDatasetAPIv4::widgetReceipt $w.body.canvas.plot] axes] eq $axes} {Native view axes persist through actual Workspace reopen}
    set payload $::GX::ReplicateViewer::state($w,payload);set large [dict get $payload result]
    dict set large resource_validation_padding [string repeat x 600000]
    set payload [::GX::ReplicateViewer::storeResult $w $payload $large]
    set ::GX::ReplicateViewer::state($w,payload) $payload;::GX::ReplicateViewer::save $w
    check {[dict exists $payload result_resource] && ![dict exists $payload result]} {Large results use existing Workspace managed resources rather than oversized History payloads}
    destroy $w;pause
    set archive [file join $::out portable_study.zip];::GX::sessionPortableExport $session $archive;::GX::sessionPortableValidate $archive
    set imported [file join $::out imported];::GX::sessionPortableImport $archive $imported;::GX::openSessionPath $imported
    set w [::GX::viewerOpen viewer.replicate_curve_analysis replicate_consensus [dict create workspace_id $id]];pause
    check {[dict exists $::GX::ReplicateViewer::state($w,payload) result_resource] && abs([lindex [dict get [::GX::ReplicateViewer::resultValue $::GX::ReplicateViewer::state($w,payload)] columns y_mean] 5]-4)<1e-10 && [dict exists $::GX::ReplicateViewer::state($w,payload) plot_ref]} {Portable Session import reconstructs managed scientific result and genuine Graph reference}
    check {[::GX::documentationResolveApiRef VIEWER_GUI_HOST_API_v1] ne {}} {New public GUI manifest documentation resolves through the existing Help owner}
    event generate $w <F1>;pause
    set manual .gxManual_[binary encode hex [encoding convertto utf-8 viewer.replicate_curve_analysis]]
    check {[winfo exists $manual]} {Actual F1 opens the English Replicate manual through the existing Help host}
    destroy $manual
    set list $w.body.inspector.scroll.content.sources
    $list selection set 0;event generate $list <<ListboxSelect>>;pause
    check {[::GX::viewerCommandEnabled $w edit_source]} {Existing native/source selection enables semantic source editing}
    ::GX::ReplicateViewer::editSource $w;pause
    check {[winfo exists $w.source.landmark_id] && [winfo exists $w.source.phase_index]} {Selected source editor exposes explicit physical landmark, phase and direction}
    destroy $w.source
    check {![info exists ::bgfailed]} {No Tcl/Tk background failures}
    save result [dict create status PASS checks $::checks session $session workspace_id $id]
}
set failed {};set done 0
after 500 {if {[catch {run} message options]} {set ::failed [dict get $options -errorinfo];save result [dict create status FAIL checks $::checks details $::failed];puts stderr $::failed};catch {destroy .};set ::done 1}
vwait done
exit [expr {$failed ne {}}]
