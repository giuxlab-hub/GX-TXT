# SPDX-License-Identifier: GPL-3.0-or-later
rename ::GX::launchGui ::GX::launchGui_before_session_menus065
proc ::GX::launchGui {} {
    launchGui_before_session_menus065
    set bar .top.nb.sessionfiles.bar
    ttk::button $bar.projectHome -text {⌂ Project Home} -command ::GX::projectGuiCurrentHome -state disabled
    pack $bar.projectHome -side left -padx 3 -before $bar.refresh
    foreach {key title entries} {
        session Session {{{New Session...} ::GX::newSessionDialog} {{Duplicate Experiment...} ::GX::newExperimentDialog} {{Open Session...} ::GX::chooseSession} {{Session information} ::GX::showCurrentSessionInfo} {{Save configuration} ::GX::saveCurrentSessionConfig} {{Delete Session...} ::GX::resourceLifecycleSessionDialog} {{Duplication report...} ::GX::experimentDuplicationReportDialog}}
        instruments Instruments {{{Add Instrument...} ::GX::sessionInstrumentAddDialog} {{Open Library...} ::GX::instrumentLibraryOpenWindow}}
        configuration Configuration {{{Export configuration (.ini)...} ::GX::saveManifestDialog} {{Load configuration only (.ini)...} ::GX::loadManifestDialog}}
    } {
        ttk::menubutton $bar.$key -text $title -menu $bar.$key.menu
        menu $bar.$key.menu -tearoff 0
        foreach entry $entries {lassign $entry label command;$bar.$key.menu add command -label $label -command $command}
        pack $bar.$key -side left -padx 3 -before $bar.refresh
    }
    foreach key {lab path open new save export import tools} {if {[winfo exists .top.sessionbar.$key]} {pack forget .top.sessionbar.$key}}
    # Reuse the existing Session display variable so load/switch/close updates
    # remain owned by the Session controller, beside the unchanged selector.
    ttk::label .top.sessionbar.loadedSession -textvariable ::GX::ui(sessionPath) -anchor w
    pack .top.sessionbar.loadedSession -side left -padx {12 3}
    sessionActionGuiRefresh
    .top.nb.sessionfiles.navigation configure -values {{Session files} {Session scripts} Workspaces {Configuration / Manifest} {Session Parameters} Experiment Instrumentation {Preview Cache}}
    # Remove the notebook entry only after the established panel and Session
    # content host exist. Forget does not destroy/recreate the Experiment UI.
    .top.nb forget .top.nb.exp
    .top.nb forget .top.nb.instr
    sessionPageSelect
    updateSessionUi
}
proc ::GX::sessionActionGuiRefresh {} {
    set w .top.nb.sessionfiles.bar.tools
    if {![winfo exists .top.nb.sessionfiles.bar]} return
    if {[winfo exists $w]} {destroy $w}
    set actions [sessionActionProviderList]
    ttk::menubutton $w -text Tools -menu $w.menu;menu $w.menu -tearoff 0
    $w.menu add command -label {Export Session...} -command ::GX::sessionPortableGuiExport
    $w.menu add command -label {Import Session...} -command ::GX::sessionPortableGuiImport
    if {[llength $actions]} {$w.menu add separator}
    foreach action $actions {$w.menu add command -label [dict get $action name] -command [list ::GX::sessionActionGuiInvoke [dict get $action module_id] [dict get $action action_id]]}
    pack $w -side left -padx 3 -before .top.nb.sessionfiles.bar.refresh
}

# Accessible completion diagnostics: no modal acknowledgement or approval flow.
proc ::GX::experimentDuplicationReportDialog {} {
    set path [file join $::GX::currentSession metadata experiment_preparation.txt]
    if {![file isfile $path]} {setStatus {This Session has no duplication report.};return}
    set w .gxDuplicationReport;catch {destroy $w};toplevel $w;wm title $w {Experiment duplication report}
    text $w.text -wrap word -width 100 -height 28
    ttk::scrollbar $w.scroll -command [list $w.text yview];$w.text configure -yscrollcommand [list $w.scroll set]
    set ch [open $path r];fconfigure $ch -encoding utf-8;try {$w.text insert end [read $ch]} finally {close $ch}
    $w.text configure -state disabled
    pack $w.scroll -side right -fill y;pack $w.text -fill both -expand 1
    bind $w <Escape> [list destroy $w]
}
