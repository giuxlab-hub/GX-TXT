namespace eval ::GX {variable scriptJobsUiEpoch 0}
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {variable scriptJobsUi;variable scriptJobsSeen {};variable scriptJobsBusy 0}
proc ::GX::scriptRunBindingsToggle {} {
    set w .gxtxtScriptRun
    if {[winfo ismapped $w.bindings]} {grid remove $w.bindings} else {grid $w.bindings}
    after idle ::GX::scriptRunFit
}
proc ::GX::scriptRunBindingAdd {} {
    variable scriptRunUi
    set n [incr scriptRunUi(input_count)];set w .gxtxtScriptRun.bindings.r$n
    ttk::frame $w
    set scriptRunUi(alias,$n) input$n;set scriptRunUi(label,$n) {};set scriptRunUi(dataset,$n) {}
    ttk::entry $w.alias -textvariable ::GX::scriptRunUi(alias,$n) -width 14
    ttk::entry $w.label -textvariable ::GX::scriptRunUi(label,$n) -width 18
    ttk::combobox $w.dataset -textvariable ::GX::scriptRunUi(dataset,$n) -values $scriptRunUi(eligible) -state readonly -width 36
    ttk::button $w.remove -text Remove -command [list destroy $w]
    pack $w.alias $w.label $w.dataset $w.remove -side left -padx 3
    pack $w -side top -fill x -pady 2
    after idle ::GX::scriptRunFit
}
proc ::GX::scriptRunBindingsBuild {w row} {
    variable scriptRunUi
    set scriptRunUi(session) $::GX::currentSession
    set scriptRunUi(namespace) [datasetNamespaceCurrentGet]
    set scriptRunUi(importOverride) 0
    set scriptRunUi(input_count) 0;set scriptRunUi(eligible) {};set scriptRunUi(output_id) {};set scriptRunUi(output_label) {};set scriptRunUi(replace) 0
    foreach item [dict get [datasetCatalogSnapshot] datasets] {
        if {[dict get $item namespace] eq $scriptRunUi(namespace)} {lappend scriptRunUi(eligible) [dict get $item dataset_id]}
    }
    ttk::button $w.advanced -text {Dataset bindings (optional)…} -command ::GX::scriptRunBindingsToggle
    grid $w.advanced -row $row -column 0 -columnspan 2 -sticky w -padx 8
    incr row
    ttk::frame $w.bindings
    grid $w.bindings -row $row -column 0 -columnspan 2 -sticky ew -padx 8 -pady 4
    ttk::label $w.bindings.scope -text "Current namespace: $scriptRunUi(namespace). Change it in Datasets before opening Run." -wraplength 650
    pack $w.bindings.scope -side top -anchor w
    ttk::label $w.bindings.header -text {Semantic alias                 Display label                    Dataset ID}
    pack $w.bindings.header -side top -anchor w
    ttk::button $w.bindings.add -text {+ Input Dataset} -command ::GX::scriptRunBindingAdd
    pack $w.bindings.add -side top -anchor w
    if {![llength $scriptRunUi(eligible)]} {
        ttk::label $w.bindings.empty -text {No canonical Datasets in this namespace. Parameter-only scripts can run without inputs.}
        pack $w.bindings.empty -side top -anchor w
    }
    ttk::frame $w.bindings.output
    pack $w.bindings.output -side top -fill x -pady 5
    ttk::label $w.bindings.output.name -text {Output ID / label}
    ttk::entry $w.bindings.output.id -textvariable ::GX::scriptRunUi(output_id) -width 26
    ttk::entry $w.bindings.output.label -textvariable ::GX::scriptRunUi(output_label) -width 22
    ttk::checkbutton $w.bindings.output.replace -text {Replace owned} -variable ::GX::scriptRunUi(replace)
    pack $w.bindings.output.name $w.bindings.output.id $w.bindings.output.label $w.bindings.output.replace -side left -padx 3
    ttk::label $w.bindings.hint -text {Optional output applies to scripts that read the runtime output binding. Blank preserves the script's declared output.} -wraplength 650
    pack $w.bindings.hint -side top -anchor w
    grid remove $w.bindings
    return [expr {$row+1}]
}
proc ::GX::scriptWorkspaceSubmitted {response} {
    variable scriptRunUi
    if {![winfo exists .gxtxtScriptRun]} return
    .gxtxtScriptRun.run state !disabled
    if {![dict get $response ok]} {
        set scriptRunUi(status) "Submission failed: [dict get $response error]"
        if {[dict exists $response error_code] && [dict get $response error_code] eq {GXTXT PYTHON IMPORT_PREFLIGHT} && [string match {*MISSING*} [dict get $response error]]} {
            set answer [tk_messageBox -parent .gxtxtScriptRun -icon warning -type yesno -default no -title {Python imports unavailable} -message "[dict get $response error]\nContinue deliberately despite missing imports?"]
            if {$answer eq {yes}} {set scriptRunUi(importOverride) 1;scriptWorkspaceRunCommit}
        }
        return
    }
    set r [dict get $response result]
    set scriptRunUi(status) "[dict get $r state]: [dict get $r id]"
    if {[dict exists $r deduplicated] && [dict get $r deduplicated]} {append scriptRunUi(status) { (existing equivalent job)}}
    scriptJobsDialog
}
proc ::GX::scriptJobsDialog {} {
    variable scriptJobsUi
    variable scriptJobsUiEpoch
    variable scriptJobsBusy
    set w .gxtxtScriptJobs
    if {[winfo exists $w]} {raise $w;return}
    incr scriptJobsUiEpoch
    set scriptJobsBusy 0
    toplevel $w;wm title $w {GX-TXT — Script Jobs};wm geometry $w 1280x760
    wm minsize $w 760 500
    wm protocol $w WM_DELETE_WINDOW ::GX::scriptJobsClose
    bind $w <Destroy> [list ::GX::scriptJobsDestroyed %W]
    ttk::label $w.intro -text {Local Jobs: double-click an execution for details. Jobs > Open/reconnect Job ID also opens configured remote Jobs. Closing this window does not cancel Jobs.} -wraplength 1150
    pack $w.intro -side top -anchor w -padx 8 -pady 5
    scriptJobsBuildMenus $w
    ttk::panedwindow $w.split -orient vertical
    pack $w.split -fill both -expand 1 -padx 5 -pady 5
    ttk::frame $w.split.list;ttk::frame $w.split.preview
    $w.split add $w.split.list -weight 2;$w.split add $w.split.preview -weight 2
    grid rowconfigure $w.split.list 0 -weight 1;grid columnconfigure $w.split.list 0 -weight 1
    ttk::treeview $w.jobs -columns {reference language version revision state started finished duration session jobid} -show {tree headings} -selectmode extended -height 10
    $w.jobs heading #0 -text {Script name} -command {::GX::scriptJobsSort name};$w.jobs column #0 -width 220 -minwidth 140 -stretch 0
    foreach {key title width} {reference {Registered Script ID} 260 language Language 75 version Version 85 revision Revision 75 state State 95 started Started 155 finished Finished 155 duration Duration 110 session Session 200 jobid {Job ID} 350} {
        $w.jobs heading $key -text $title -command [list ::GX::scriptJobsSort $key];$w.jobs column $key -width $width -minwidth 60 -stretch 0
    }
    ttk::scrollbar $w.split.list.sy -command [list $w.jobs yview]
    ttk::scrollbar $w.split.list.sx -orient horizontal -command [list $w.jobs xview]
    $w.jobs configure -yscrollcommand [list $w.split.list.sy set] -xscrollcommand [list $w.split.list.sx set]
    grid $w.jobs -in $w.split.list -row 0 -column 0 -sticky nsew
    grid $w.split.list.sy -row 0 -column 1 -sticky ns;grid $w.split.list.sx -row 1 -column 0 -sticky ew
    bind $w.jobs <<TreeviewSelect>> ::GX::scriptJobsSelection
    bind $w.jobs <Double-1> {::GX::scriptJobsDoubleClick %y}
    bind $w.jobs <Return> ::GX::scriptJobsOpenSelected
    bind $w.jobs <Button-3> {::GX::scriptJobsContext %y %X %Y}
    ttk::frame $w.split.preview.bar;pack $w.split.preview.bar -fill x
    ttk::label $w.split.preview.bar.label -text {Selected execution — 16 KiB log snapshot; open details for complete log / live output}
    ttk::button $w.split.preview.bar.copy -text {Copy details} -command [list ::GX::scriptJobTextCopyAll $w.details]
    ttk::button $w.split.preview.bar.all -text {Select all} -command [list ::GX::scriptJobTextSelectAll $w.details]
    pack $w.split.preview.bar.label $w.split.preview.bar.copy $w.split.preview.bar.all -side left -padx 4
    ttk::frame $w.split.preview.text;pack $w.split.preview.text -fill both -expand 1
    scriptJobTextCreate $w.details $w.split.preview.text
    set scriptJobsUi(selected) {};set scriptJobsUi(previewGeneration) 0
    set scriptJobsUi(status) {Connecting…}
    ttk::label $w.status -textvariable ::GX::scriptJobsUi(status);pack $w.status -side bottom -fill x -padx 5
    set preferences [scriptJobPresentationGet]
    set scriptJobsUi(workspace) [dict get $preferences current_id]
    set scriptJobsUi(view) [dict get $preferences last_view]
    set scriptJobsUi(offset) 0;set scriptJobsUi(generation) 0
    scriptJobsApplyView
    scriptJobsRecover
    scriptJobAsync [scriptJobCommand configure] {} ::GX::scriptJobsPolicyLoaded
    scriptJobsRefresh
}
proc ::GX::scriptJobsRecover {} {scriptJobAsync [scriptJobCommand recover] {} ::GX::scriptJobsActionDone}
proc ::GX::scriptJobsPolicyLoaded {response} {
    if {[winfo exists .gxtxtScriptJobs] && [dict get $response ok]} {set ::GX::scriptJobsUi(limit) [dict get $response result max_jobs]}
}
proc ::GX::scriptJobsRefresh {} {
    variable scriptJobsBusy
    if {![winfo exists .gxtxtScriptJobs] || $scriptJobsBusy} return
    if {[info exists ::GX::scriptJobsUi(timer)]} {after cancel $::GX::scriptJobsUi(timer)}
    set scriptJobsBusy 1
    set request [scriptJobViewRequest [scriptJobsCaptureView] $::GX::scriptJobsUi(offset)]
    set watched {};dict for {id state} $::GX::scriptJobsSeen {if {$state in {QUEUED PREPARING RUNNING FINALIZING}} {lappend watched $id}}
    dict set request watched_ids $watched
    scriptJobAsync [scriptJobCommand view_list] $request [list ::GX::scriptJobsReceived $::GX::scriptJobsUiEpoch $::GX::scriptJobsUi(generation)]
}
proc ::GX::scriptJobsReceived {epoch generation response} {
    variable scriptJobsBusy;variable scriptJobsUi;variable scriptJobsSeen
    set w .gxtxtScriptJobs
    if {![winfo exists $w] || $epoch!=$::GX::scriptJobsUiEpoch} return
    set scriptJobsBusy 0
    if {$generation!=$scriptJobsUi(generation)} {scriptJobsRefresh;return}
    if {![dict get $response ok]} {set scriptJobsUi(status) [dict get $response error]} else {
        set page [dict get $response result];set jobs [dict get $page jobs]
        foreach stateRecord [dict get $page lifecycle] {
            set id [dict get $stateRecord id];set state [dict get $stateRecord state]
            if {[dict exists $scriptJobsSeen $id] && [dict get $scriptJobsSeen $id] ne $state && $state in {COMPLETED FAILED CANCELLED INTERRUPTED} && $::GX::currentSession ne {} && [file normalize $::GX::currentSession] eq [dict get $stateRecord session]} {
                catch {loadDatasetRegistry $::GX::currentSession};catch {refreshResults};catch {refreshGraphs}
            }
            dict set scriptJobsSeen $id $state
        }
        set scriptJobsUi(page) $page;set scriptJobsUi(offset) [dict get $page offset];set scriptJobsUi(records) $jobs
        set previousSelection [$w.jobs selection];set previousY [lindex [$w.jobs yview] 0]
        set wanted [lmap job $jobs {dict get $job id}]
        foreach id [$w.jobs children {}] {if {$id ni $wanted} {$w.jobs delete $id}}
        set rowIndex 0
        foreach job $jobs {
            set id [dict get $job id];set state [dict get $job state]
            set values [list [scriptJobField $job reference] [scriptJobField $job language] [scriptJobField $job script_version] [scriptJobField $job script_revision] $state [scriptJobTime [scriptJobStart $job]] [scriptJobTime [scriptJobField $job finished {}]] [scriptJobDuration $job] [scriptJobSessionName $job] $id]
            set name [scriptJobField $job script_name {Name not recorded}]
            if {[$w.jobs exists $id]} {
                if {[$w.jobs item $id -values] ne $values || [$w.jobs item $id -text] ne $name} {$w.jobs item $id -text $name -values $values}
            } else {$w.jobs insert {} end -id $id -text $name -values $values}
            $w.jobs move $id {} $rowIndex;incr rowIndex
            if {$scriptJobsUi(selected) eq $id} {
                # Only terminal-state transitions replace the bounded preview.
                # Polling unrelated jobs leaves selection, scroll and focus alone.
                if {[info exists scriptJobsUi(selectedState)] && $scriptJobsUi(selectedState) ne $state && [info exists scriptJobsUi(previewLog)]} {
                    scriptJobTextReplace $w.details "[scriptJobDetailsFormat $job]\n\n$scriptJobsUi(previewLog)"
                }
                set scriptJobsUi(selectedState) $state
            }
        }
        $w.jobs selection set [lmap id $previousSelection {if {$id ni $wanted} continue;set id}]
        $w.jobs yview moveto $previousY
        if {[info exists scriptJobsUi(restoreSelection)]} {
            set id $scriptJobsUi(restoreSelection);unset scriptJobsUi(restoreSelection)
            if {$id in $wanted} {$w.jobs selection set $id}
            $w.jobs xview moveto [dict get $scriptJobsUi(view) xscroll]
            $w.jobs yview moveto [dict get $scriptJobsUi(view) yscroll]
        }
        scriptJobsSelection
        set first [expr {[llength $jobs] ? [dict get $page offset]+1 : 0}]
        set scope [dict get $scriptJobsUi(view) scope]
        set scriptJobsUi(status) "Showing $first–[expr {[dict get $page offset]+[llength $jobs]}] of [dict get $page matching] matching; [dict get $page hidden_scoped] hidden / [dict get $page total_scoped] in scope; [dict get $page total_stored] stored. Scope: $scope. Filter: $scriptJobsUi(filter)."
    }
    scriptJobsActionsRefresh
    set scriptJobsUi(timer) [after 1000 ::GX::scriptJobsRefresh]
}
proc ::GX::scriptJobsSelection {} {
    variable scriptJobsUi
    set w .gxtxtScriptJobs
    if {![winfo exists $w]} return
    set selected [$w.jobs selection]
    scriptJobsActionsRefresh
    if {[llength $selected]!=1} {
        set scriptJobsUi(selected) {};incr scriptJobsUi(previewGeneration)
        unset -nocomplain scriptJobsUi(selectedState) scriptJobsUi(previewLog)
        scriptJobTextReplace $w.details [expr {[llength $selected]>1 ? "[llength $selected] Jobs selected. History actions apply to exact Job IDs." : "Select an execution to inspect its retained log."}] 1
        return
    }
    set selected [lindex $selected 0]
    if {$selected eq $scriptJobsUi(selected) || ![info exists scriptJobsUi(records)]} return
    set scriptJobsUi(selected) $selected
    foreach job $scriptJobsUi(records) {if {[dict get $job id] eq $selected} {set scriptJobsUi(selectedState) [dict get $job state];scriptJobsPreviewLoad $job;break}}
}
proc ::GX::scriptJobsRerunSelected {} {
    set selected [.gxtxtScriptJobs.jobs selection]
    if {[llength $selected]!=1} return
    if {[catch {scriptJobsRerun [scriptJobInspect [lindex $selected 0]]} message]} {tk_messageBox -parent .gxtxtScriptJobs -icon error -message $message}
}
proc ::GX::sessionJobsMenuStates {menu} {
    set eligible [expr {[sessionFileExplorerRunSelected] ne {}}]
    $menu entryconfigure 0 -state [expr {$eligible ? "normal" : "disabled"}]
    $menu entryconfigure 2 -state [expr {$::GX::currentSession ne {} ? "normal" : "disabled"}]
    $menu entryconfigure 3 -state [expr {$eligible ? "normal" : "disabled"}]
}
proc ::GX::sessionJobsRerun {} {
    set id [sessionFileExplorerRunSelected]
    if {$id eq {}} return
    if {[catch {scriptJobsRerun [scriptExecutionInspectRun $::GX::currentSession $id]} message]} {tk_messageBox -parent . -icon error -message $message}
}
proc ::GX::scriptJobsRerun {job} {
    if {[scriptJobField $job state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {error {Only a terminal historical execution can be rerun}}
    if {$::GX::currentSession eq {} || [file normalize $::GX::currentSession] ne [file normalize [dict get $job session]]} {error {Open the historical job's origin Session before reviewing a rerun}}
    set reference [dict get $job reference]
    if {[catch {scriptRegistryDescribe $reference} current]} {
        scriptLibraryDialog
        error "Historical registered Script $reference is unavailable. Select a currently valid Script in the Library; no job was submitted."
    }
    scriptWorkspaceRunDialog $reference $job
}
proc ::GX::scriptJobsPreviewLoad {job} {
    variable scriptJobsUi
    set generation [incr scriptJobsUi(previewGeneration)]
    unset -nocomplain scriptJobsUi(previewLog)
    set id [dict get $job id]
    scriptJobTextReplace .gxtxtScriptJobs.details "[scriptJobDetailsFormat $job]\n\nLoading bounded log preview…" 1
    scriptJobAsync [scriptJobCommand log_read $id 0 16384 1] {} [list ::GX::scriptJobsPreviewReady $::GX::scriptJobsUiEpoch $id $generation]
}
proc ::GX::scriptJobsPreviewReady {epoch id generation response} {
    variable scriptJobsUi
    if {![winfo exists .gxtxtScriptJobs] || $epoch!=$::GX::scriptJobsUiEpoch || $generation!=$scriptJobsUi(previewGeneration) || $id ne $scriptJobsUi(selected)} return
    foreach job $scriptJobsUi(records) {if {[dict get $job id] eq $id} break}
    if {[dict get $response ok]} {set page [dict get $response result];set scriptJobsUi(previewLog) "Bounded log snapshot (tail, bytes [dict get $page offset]..[dict get $page next_offset] of [dict get $page size]):\n[dict get $page diagnostic]\n[dict get $page content]"} else {set scriptJobsUi(previewLog) "Log unavailable: [dict get $response error]"}
    scriptJobTextReplace .gxtxtScriptJobs.details "[scriptJobDetailsFormat $job]\n\n$scriptJobsUi(previewLog)"
}
proc ::GX::scriptJobsDoubleClick {y} {
    set t .gxtxtScriptJobs.jobs;set id [$t identify row 0 $y]
    if {$id ne {}} {$t selection set $id;scriptJobDetailsWindow $id}
}
proc ::GX::scriptJobsOpenSelected {} {set id [.gxtxtScriptJobs.jobs selection];if {[llength $id]==1} {scriptJobDetailsWindow [lindex $id 0]}}
proc ::GX::scriptJobsCopySelected {} {
    set id [.gxtxtScriptJobs.jobs selection]
    foreach job $::GX::scriptJobsUi(records) {if {[dict get $job id] eq $id} {scriptJobClipboard [scriptJobField $job reference];return}}
}
proc ::GX::scriptJobsActionDone {response} {
    if {[winfo exists .gxtxtScriptJobs] && ![dict get $response ok]} {set ::GX::scriptJobsUi(status) [dict get $response error]}
    scriptJobsRefresh
}
proc ::GX::scriptJobsCancelSelected {} {
    set records [scriptJobsSelectedRecords]
    if {![llength $records]} return
    foreach record $records {if {[dict get $record state] ni {QUEUED PREPARING RUNNING FINALIZING}} {return}}
    foreach record $records {scriptJobAsync [scriptJobCommand cancel [dict get $record id]] {} ::GX::scriptJobsActionDone}
}
proc ::GX::scriptJobsApplyPolicy {} {
    scriptJobAsync [scriptJobCommand configure max_jobs=$::GX::scriptJobsUi(limit)] {} ::GX::scriptJobsActionDone
}
proc ::GX::scriptJobsPolicyDialog {} {
    scriptJobAsync [scriptJobCommand configure] {} ::GX::scriptJobsPolicyShow
}
proc ::GX::scriptJobsPolicyShow {response} {
    variable scriptJobsUi
    if {![dict get $response ok]} {scriptJobsActionDone $response;return}
    set w .gxtxtJobPolicy;catch {destroy $w};toplevel $w;wm title $w {Local script job resource policy}
    set row 0
    foreach {key label} {max_jobs {Concurrent jobs} max_queue {Admission limit (active + queued)} threads {Threads per job} memory_mib {Memory per job (MiB)} temp_mib {Temporary disk per job (MiB)} max_processes {Processes per job} timeout_seconds {Time per job (seconds)}} {
        set scriptJobsUi(policy,$key) [dict get $response result $key]
        ttk::label $w.l$key -text $label;ttk::entry $w.e$key -textvariable ::GX::scriptJobsUi(policy,$key)
        grid $w.l$key -row $row -column 0 -sticky e -padx 6 -pady 4;grid $w.e$key -row $row -column 1 -padx 6 -pady 4;incr row
    }
    ttk::label $w.hint -text {Limits apply to newly admitted jobs. Resource monitoring is sampled; publication recovery protects committed data.} -wraplength 460
    grid $w.hint -row $row -column 0 -columnspan 2 -padx 6 -pady 5;incr row
    ttk::button $w.save -text Save -command ::GX::scriptJobsPolicySave
    grid $w.save -row $row -column 1 -pady 6
}
proc ::GX::scriptJobsPolicySave {} {
    variable scriptJobsUi
    set args {}
    foreach key {max_jobs max_queue threads memory_mib temp_mib max_processes timeout_seconds} {lappend args $key=$scriptJobsUi(policy,$key)}
    scriptJobAsync [scriptJobCommand configure {*}$args] {} ::GX::scriptJobsPolicySaved
}
proc ::GX::scriptJobsPolicySaved {response} {
    if {[dict get $response ok]} {destroy .gxtxtJobPolicy} else {tk_messageBox -parent .gxtxtJobPolicy -icon error -message [dict get $response error]}
}

proc ::GX::scriptRunFit {} {
    set w .gxtxtScriptRun
    if {![winfo exists $w]} return
    update idletasks
    set width [expr {min([winfo screenwidth $w]-80,max(660,[winfo reqwidth $w]))}]
    set height [expr {min([winfo screenheight $w]-100,[winfo reqheight $w])}]
    wm geometry $w ${width}x${height}
}

source [file join [file dirname [info script]] script_job_details_surface.tcl]

source [file join [file dirname [info script]] script_jobs_presentation.tcl]
