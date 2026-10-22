# Session-centric Run page and transparent execution plan.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable runPlanState }

proc ::GX::runPlanInputs {id} {
    variable moduleCfg
    variable moduleAnalysisSource
    set inputs {}
    if {[moduleSupportsAnalysisSources $id]} {
        foreach row [analysisSourceRows $id] {
            set source [expr {[info exists moduleAnalysisSource($id,$row,id)] ? $moduleAnalysisSource($id,$row,id) : "primary"}]
            set dataset [expr {[info exists moduleAnalysisSource($id,$row,dataset_id)] ? $moduleAnalysisSource($id,$row,dataset_id) : ""}]
            if {$dataset ne ""} { lappend inputs "$source: $dataset" }
        }
    } elseif {[info exists moduleCfg($id,dataset_id)] && $moduleCfg($id,dataset_id) ne ""} {
        lappend inputs $moduleCfg($id,dataset_id)
    }
    return [join $inputs {; }]
}

proc ::GX::runPlanEntries {} {
    variable moduleOrder
    variable currentSession
    set out {}
    set order 0
    foreach id $moduleOrder {
        if {![moduleIsRunnableAnalysis $id]} continue
        set enabled [moduleIsEnabled $id]
        if {!$enabled} continue
        set selected [moduleRunIsSelected $id]
        set runner [moduleField $id runner ""]
        set reason ""
        if {!$selected} { set reason "Not selected for this run" }
        if {$reason eq "" && $runner ni {standard_octave script_execution script_module}} { set reason "No standard analysis runner" }
        if {$reason eq "" && ($currentSession eq "" || ![file isdirectory $currentSession])} { set reason "Open a Session" }
        if {$reason eq ""} { incr order }
        lappend out [dict create id $id name [moduleField $id name $id] version [moduleField $id version ""] \
            enabled $enabled selected $selected order [expr {$reason eq "" ? $order : ""}] \
            inputs [runPlanInputs $id] status [expr {$reason eq "" ? "PENDING" : "SKIPPED"}] reason $reason]
    }
    return $out
}

proc ::GX::runPlanRefresh {} {
    variable runPlanState
    variable ui
    set tree .top.nb.run.plan.tree
    if {![winfo exists $tree]} return
    if {[info exists ::GX::analysisPipe] && $::GX::analysisPipe ne ""} return
    $tree delete [$tree children {}]
    array unset runPlanState *
    set ready 0; set skipped 0
    foreach entry [runPlanEntries] {
        set id [dict get $entry id]
        set status [dict get $entry status]
        if {$status eq "PENDING"} { incr ready } else { incr skipped }
        set runPlanState($id) $status
        $tree insert {} end -id $id -text [dict get $entry name] -values [list \
            [dict get $entry order] [dict get $entry version] \
            [expr {[dict get $entry enabled] ? "Enabled" : "Disabled"}] \
            [dict get $entry inputs] $status [dict get $entry reason]]
    }
    set ui(runPlanSummary) "$ready analysis module(s) ready; $skipped skipped. Import files separately in Acquisition."
}

proc ::GX::runPlanStatus {id status {reason ""}} {
    variable runPlanState
    variable ui
    set tree .top.nb.run.plan.tree
    if {$id eq "" || ![winfo exists $tree] || ![$tree exists $id]} return
    set runPlanState($id) $status
    set values [$tree item $id -values]
    lset values 4 $status
    if {$reason ne ""} { lset values 5 $reason }
    $tree item $id -values $values
    $tree see $id
    set counts [dict create]
    foreach key [array names runPlanState] { dict incr counts $runPlanState($key) }
    set pieces {}
    foreach state {PASS RUNNING PENDING FAILED SKIPPED} {
        set count [expr {[dict exists $counts $state] ? [dict get $counts $state] : 0}]
        if {$count} { lappend pieces "$state $count" }
    }
    set ui(runPlanSummary) [join $pieces { | }]
}

proc ::GX::runPageStart {} {
    runPlanRefresh
    startAnalysis
}

proc ::GX::runPageScriptRunner {} {
    if {$::GX::currentSession eq {} || ![file isdirectory $::GX::currentSession]} {
        tk_messageBox -parent . -icon info -title {Script Runner requires a Session} -message {Open or create the intended scientific Session first, then choose Script Runner again. Opening the Runner only prepares a review; Run explicitly submits the Job. Job Manager remains available without a Session.}
        return
    }
    if {[info exists ::GX::scriptWorkspaceChoice] && $::GX::scriptWorkspaceChoice ne {} && ![catch {scriptRegistryDescribe $::GX::scriptWorkspaceChoice}]} {
        scriptWorkspaceRunDialog
    } else {
        # The Library already owns registered-source selection and its Run
        # action. Do not introduce a second script picker or execution path.
        scriptLibraryDialog
    }
}

proc ::GX::buildRunPage {} {
    variable ui
    set f .top.nb.run
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 3 -weight 1
    ttk::frame $f.buttons
    ttk::button $f.buttons.analysis -text "Run enabled analyses" -command ::GX::runPageStart
    ttk::button $f.buttons.stop -text Stop -command ::GX::stopCurrent -state disabled
    ttk::button $f.buttons.copy -text "Copy log" -command [list ::GX::copyTextWidget $f.log "Run log"]
    ttk::button $f.buttons.refresh -text "Refresh plan" -command ::GX::runPlanRefresh
    # Legacy callback targets remain as hidden widgets for headless/old paths.
    ttk::button $f.buttons.start -text "Legacy import" -command ::GX::startAsync
    ttk::button $f.buttons.all -text "Legacy combined run" -command ::GX::startAll
    pack $f.buttons.analysis $f.buttons.stop $f.buttons.refresh $f.buttons.copy -side left -padx 4
    ttk::menubutton $f.buttons.executions -text {Scripts & Jobs…} -menu $f.buttons.executions.menu
    menu $f.buttons.executions.menu -tearoff 0
    $f.buttons.executions.menu add command -label {Script Runner…} -command ::GX::runPageScriptRunner
    $f.buttons.executions.menu add command -label {Job Manager (local / remote)…} -command ::GX::scriptJobsDialog
    $f.buttons.executions.menu add separator
    $f.buttons.executions.menu add command -label {Execution help} -command {::GX::documentationBrowserOpenApi SCRIPT_WORKSPACE_GUI_HOST}
    pack $f.buttons.executions -side right -padx 4
    native2DViewportTooltip $f.buttons.executions {Script Runner prepares a registered script in the current Session. Job Manager inspects local executions or reconnects an exact remote Job ID; opening either does not submit a Job.}
    grid $f.buttons -row 0 -column 0 -sticky ew -padx 5 -pady 7
    set ui(startButton) $f.buttons.start
    set ui(analysisStart) $f.buttons.analysis
    set ui(runAllButton) $f.buttons.all
    set ui(stopButton) $f.buttons.stop
    set ui(analysisStop) $f.buttons.stop
    ttk::labelframe $f.plan -text "Execution plan"
    grid $f.plan -row 1 -column 0 -sticky nsew -padx 5 -pady 4
    grid columnconfigure $f.plan 0 -weight 1
    grid rowconfigure $f.plan 0 -weight 1
    ttk::treeview $f.plan.tree -columns {order version enabled inputs status reason} -show {tree headings} -height 9
    $f.plan.tree heading #0 -text "Analysis module"
    $f.plan.tree column #0 -width 245
    foreach {key title width} {order Order 55 version Version 75 enabled State 80 inputs {Input Dataset(s)} 280 status Status 85 reason Reason 200} {
        $f.plan.tree heading $key -text $title
        $f.plan.tree column $key -width $width
    }
    ttk::scrollbar $f.plan.sy -orient vertical -command [list $f.plan.tree yview]
    $f.plan.tree configure -yscrollcommand [list $f.plan.sy set]
    grid $f.plan.tree -row 0 -column 0 -sticky nsew
    grid $f.plan.sy -row 0 -column 1 -sticky ns
    ttk::label $f.plan.summary -textvariable ::GX::ui(runPlanSummary) -anchor w
    grid $f.plan.summary -row 1 -column 0 -sticky ew -pady 3
    set ui(status) "Ready"
    ttk::frame $f.status
    ttk::label $f.status.lab -textvariable ::GX::ui(status) -width 48
    ttk::progressbar $f.status.pb -orient horizontal -mode determinate -maximum 100
    set ui(progress) $f.status.pb
    pack $f.status.lab -side left -padx 4
    pack $f.status.pb -side left -fill x -expand 1 -padx 4
    grid $f.status -row 2 -column 0 -sticky ew -padx 5 -pady 4
    text $f.log -wrap none -height 12 -state disabled -font TkFixedFont
    ttk::scrollbar $f.sy -orient vertical -command [list $f.log yview]
    ttk::scrollbar $f.sx -orient horizontal -command [list $f.log xview]
    $f.log configure -yscrollcommand [list $f.sy set] -xscrollcommand [list $f.sx set]
    grid $f.log -row 3 -column 0 -sticky nsew -padx {5 0} -pady {4 0}
    grid $f.sy -row 3 -column 1 -sticky ns -pady {4 0}
    grid $f.sx -row 4 -column 0 -sticky ew -padx {5 0}
    set ui(log) $f.log
    runPlanRefresh
}

proc ::GX::runNextAnalysis {} {
    if {[info exists ::GX::analysisQueue] && [llength $::GX::analysisQueue]} {
        set item [lindex $::GX::analysisQueue 0]
        if {[llength $item] >= 3} { runPlanStatus [lindex $item 2] RUNNING }
    }
    ::GX::runNextAnalysis_before_plan_status
}

proc ::GX::onAnalysisReadable {pipe} {
    set id [expr {[info exists ::GX::ui(analysisCurrentModuleId)] ? $::GX::ui(analysisCurrentModuleId) : ""}]
    set before [expr {[info exists ::GX::analysisDone] ? $::GX::analysisDone : 0}]
    set result [::GX::onAnalysisReadable_before_plan_status $pipe]
    if {$id ne ""} {
        if {[info exists ::GX::analysisDone] && $::GX::analysisDone > $before} {
            runPlanStatus $id PASS
        } elseif {![info exists ::GX::analysisPipe] || $::GX::analysisPipe ne $pipe} {
            runPlanStatus $id FAILED "Execution or publication failed"
        }
    }
    return $result
}

proc ::GX::stopAnalysis {{message 1}} {
    variable runPlanState
    if {$message && [info exists ::GX::ui(analysisCurrentModuleId)] && $::GX::currentSession ne {}} {
        set module $::GX::ui(analysisCurrentModuleId)
        set marker [file join $::GX::currentSession analysis $module .registered_job_id]
        if {$module in {analysis.python_script analysis.octave_script} && [file isfile $marker]} {
            set f [open $marker r];set id [string trim [read $f]];close $f
            scriptJobAsync [scriptJobCommand cancel $id] {} ::GX::scriptJobsActionDone
        }
    }
    set result [::GX::stopAnalysis_before_plan_status $message]
    foreach id [array names runPlanState] {
        if {$runPlanState($id) in {RUNNING PENDING}} { runPlanStatus $id SKIPPED "Run stopped" }
    }
    return $result
}

proc ::GX::onNotebookChanged {nb} {
    set result [::GX::onNotebookChanged_before_run_plan $nb]
    if {[$nb select] eq "$nb.run"} { catch {runPlanRefresh} }
    return $result
}
