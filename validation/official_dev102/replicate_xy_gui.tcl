set prior [lindex $argv 2];set results [lindex $argv 3]
source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
if {$::env(DISPLAY) ne {:1}} {error {Actual Debian DISPLAY :1 required}}
set argv {};::GX::main
proc run {} {
    set session [file join $::out session];file copy $::prior $session;::GX::openSessionPath $session
    ::GX::modulePublicApiActivate viewer.replicate_curve_analysis REPLICATE_VIEWER_API_v1
    set jobs [llength [::GX::scriptJobList]]
    foreach {name topology} {returning_open open periodic_circle closed} {
        set f [open [file join $::results result_$name.tcldict]];try {set result [string trim [read $f]]} finally {close $f}
        set traces {};set hashes {}
        dict for {key trace} [dict get $result original_traces] {set identity [dict get $trace identity];lappend traces $identity;set id [dict get $identity dataset_id];dict set hashes $id [::GX::sha256File [::GX::datasetResolvePath $session $id]]}
        set request [dict create analysis_id $name method xy_path design repeatability grid_points 41 correspondence anchored_source_arclength reference_frame {id laboratory declaration explicit_user_verified x_unit mm y_unit mm} traces $traces]
        set payload [dict create format gxtxt.replicate_viewer.v1 request $request hidden {} result $result]
        set workspace [::GX::sessionWorkspaceCreate replicate_consensus "Analytic $topology shape" $payload]
        set w [::GX::viewerOpen viewer.replicate_curve_analysis replicate_consensus [dict create workspace_id [dict get $workspace workspace_id]]];pause 300
        set path $w.body.canvas.plot;set native [::GX::PlotDatasetAPIv4::widgetDraw $path]
        check {[winfo viewable $path] && [dict get $native resident_point_count]>41 && [dict get $result qualifications topology] eq $topology} "Actual native Viewer displays consensus and original $topology XY scientific paths"
        set axes [dict get $native axes]
        exec xdotool mousemove --sync [expr {[winfo rootx $path]+[winfo width $path]/2}] [expr {[winfo rooty $path]+[winfo height $path]/2}] click 4;pause
        check {[dict get [::GX::PlotDatasetAPIv4::widgetDraw $path] axes] ne $axes} "Actual mouse wheel zoom changes the native $topology viewport"
        exec import -window [winfo id $w] [file join $::out ${name}_viewer.png]
        dict for {id sha} $hashes {check {[::GX::sha256File [::GX::datasetResolvePath $session $id]] eq $sha} "$name retains exact canonical $id"}
        destroy $w;pause
    }
    check {[llength [::GX::scriptJobList]]==$jobs && ![info exists ::bgfailed]} {Opening saved XY scientific Workspaces creates no new analysis Jobs or Tk errors}
    save result [dict create status PASS checks $::checks session $session]
}
set failed {};set done 0
after 500 {if {[catch {run} message options]} {set ::failed [dict get $options -errorinfo];save result [dict create status FAIL checks $::checks details $::failed];puts stderr $::failed};catch {destroy .};set ::done 1}
vwait done
exit [expr {$failed ne {}}]
