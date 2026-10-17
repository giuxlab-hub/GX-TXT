set prior [lindex $argv 2]
source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
if {$::env(DISPLAY) ne {:1}} {error {Actual Debian DISPLAY :1 required}}
set argv {};::GX::main
proc run {} {
    set session [file join $::out session];file copy $::prior $session;::GX::openSessionPath $session
    check {$::GX::version eq {0.9.8.10-dev-102}} {Actual deposited framework reports dev102}
    foreach {module version} {math.numeric 1.62.0 plot.dataset 4.2.0 curve.replicate_analysis 16.0 viewer.scientific_worksheet 2.1.0 viewer.replicate_curve_analysis 1.0.0} {check {[::GX::moduleField $module version {}] eq $version} "Actual deposited $module reports $version"}
    set jobs [llength [::GX::scriptJobList]]
    set w [::GX::viewerOpen viewer.replicate_curve_analysis replicate_consensus {workspace_id idoc_0001}];pause 300
    check {[winfo viewable $w.body.canvas.plot] && [dict get [::GX::PlotDatasetAPIv4::widgetReceipt $w.body.canvas.plot] resident_point_count]>0} {Actual deposit reconstructs retained native Replicate result and Graph recipe}
    set native [::GX::native2DGeometryPathValidate {{0 0} {3 0} {3 2} {0 2}} closed]
    check {[dict get $native length]==10 && [dict get $native signed_area]==6} {Actual deposited additive native geometry returns exact analytic metrics}
    check {[string first [file join $::root core native2d bin gx2dtcl.so] [info loaded]]>=0} {GUI loads the actual deposited Native2D binary}
    exec import -window [winfo id $w] [file join $::out deposited_replicate.png]
    destroy $w
    set w [::GX::viewerOpen viewer.scientific_worksheet scientific_worksheet {workspace_id new}];pause 300
    set g [::GX::ScientificWorksheet::UI::grid $w]
    check {[winfo class $g] eq {GXNativeGrid} && [dict get [$g receipt] rows]<200} {Actual deposited Worksheet opens its compact native virtual grid}
    set choice $w.description.historyStrip.choice;::GX::uiFieldSelectorPost $choice $w;pause
    set panel [::GX::_uiFieldSelectorPanel $choice $w]
    check {[winfo exists $panel] && [winfo rooty $panel]+[winfo height $panel]<=[winfo rooty $w]+[winfo height $w]} {Actual deposit uses the shared Viewer-contained History selector}
    ::GX::uiFieldSelectorClose $choice $w
    check {[llength [::GX::scriptJobList]]==$jobs && ![::GX::moduleIsEnabled curve.replicate_analysis]} {Opening actual deposited Viewers creates no Jobs or Analysis enablement}
    check {![info exists ::bgfailed]} {Deposited native GUI smoke has no Tk background errors}
    save result [dict create status PASS checks $::checks framework $::root loaded [info loaded] session $session]
}
set failed {};set done 0
after 500 {if {[catch {run} message options]} {set ::failed [dict get $options -errorinfo];save result [dict create status FAIL checks $::checks details $::failed];puts stderr $::failed};catch {destroy .};set ::done 1}
vwait done
exit [expr {$failed ne {}}]
