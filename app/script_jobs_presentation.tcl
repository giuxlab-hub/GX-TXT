# SPDX-License-Identifier: GPL-3.0-or-later
# Native Runner menus and layout. CORE Job/Configuration APIs own all state.
proc ::GX::scriptJobsBuildMenus {w} {
    ttk::frame $w.actions -padding {4 3};pack $w.actions -side top -fill x
    foreach group {Jobs History View Workspace Settings Help} {
        set key [string tolower $group]
        ttk::menubutton $w.actions.$key -text $group -menu $w.actions.$key.menu
        menu $w.actions.$key.menu -tearoff 0 -postcommand ::GX::scriptJobsActionsRefresh
    }
    set m $w.actions.jobs.menu
    foreach {label command} {{Open execution details} scriptJobsOpenSelected {Rerun selected...} scriptJobsRerunSelected {Cancel running jobs} scriptJobsCancelSelected {Copy Script ID} scriptJobsCopySelected Refresh scriptJobsRefresh {Reconnect / recover} scriptJobsRecover {Script Library...} scriptLibraryDialog Close scriptJobsClose} {$m add command -label $label -command [list ::GX::$command]}
    set m $w.actions.history.menu
    $m add command -label {Hide selected / Remove from visible list} -command {::GX::scriptJobsHistory hide}
    $m add command -label {Restore selected} -command {::GX::scriptJobsHistory restore}
    $m add command -label {Hide finished in current scope...} -command {::GX::scriptJobsHistory finished}
    $m add command -label {Clear visible finished history...} -command {::GX::scriptJobsHistory finished}
    $m add checkbutton -label {Include hidden} -variable ::GX::scriptJobsUi(showHidden) -command ::GX::scriptJobsViewChanged
    set m $w.actions.view.menu
    foreach filter {All Active Finished Failed Hidden} {$m add radiobutton -label $filter -value $filter -variable ::GX::scriptJobsUi(filter) -command ::GX::scriptJobsViewChanged}
    $m add separator
    $m add command -label {Scope: All Sessions} -command {::GX::scriptJobsSetScope all}
    $m add command -label {Scope: current Session} -command {::GX::scriptJobsSetScope current}
    $m add command -label {Scope: specific Session...} -command ::GX::scriptJobsScopeDialog
    $m add separator
    $m add command -label {Previous page} -command {::GX::scriptJobsPage -1}
    $m add command -label {Next page} -command {::GX::scriptJobsPage 1}
    menu $m.columns -tearoff 0
    foreach column [scriptJobViewColumns] {$m.columns add checkbutton -label $column -variable ::GX::scriptJobsUi(column,$column) -command ::GX::scriptJobsColumnsChanged}
    $m add cascade -label Columns -menu $m.columns
    set m $w.actions.workspace.menu
    foreach {label operation} {{New} new {Open...} manager Save save {Save As / Duplicate...} duplicate {Rename...} rename {Manager...} manager Close close} {$m add command -label $label -command [list ::GX::scriptJobsWorkspaceAction $operation]}
    $w.actions.settings.menu add command -label {Concurrency and resource policy...} -command ::GX::scriptJobsPolicyDialog
    $w.actions.help.menu add command -label {History and Workspace help} -command [list tk_messageBox -parent $w -title {Runner history and Workspaces} -message {Jobs manages exact executions; the Run dialog prepares a new execution. Cancel stops active Jobs. History hides only finished Job IDs and is reversible with Include hidden / Restore. Hidden state is local to this user's Configuration and applies across all Runner Workspaces. Workspaces save filters, scope and layout only; they never change Jobs, scripts, logs, outputs or resource policy. View pages contain at most 500 Jobs; counts cover the full stored history.}]
    ::GX::uiMenuRowAttach $w.actions [list $w.actions.jobs $w.actions.history $w.actions.view $w.actions.workspace $w.actions.settings $w.actions.help]
    menu $w.context -tearoff 0 -postcommand ::GX::scriptJobsActionsRefresh
    foreach {label command} {{Open execution details} ::GX::scriptJobsOpenSelected {Cancel running jobs} ::GX::scriptJobsCancelSelected {Hide selected execution(s)} {::GX::scriptJobsHistory hide} {Restore selected execution(s)} {::GX::scriptJobsHistory restore}} {$w.context add command -label $label -command $command}
}
proc ::GX::scriptJobsSelectedRecords {} {
    if {![winfo exists .gxtxtScriptJobs] || ![info exists ::GX::scriptJobsUi(records)]} {return {}}
    set ids [.gxtxtScriptJobs.jobs selection];set records {}
    foreach job $::GX::scriptJobsUi(records) {if {[dict get $job id] in $ids} {lappend records $job}}
    return $records
}
proc ::GX::scriptJobsActionsRefresh {} {
    set w .gxtxtScriptJobs
    if {![winfo exists $w.jobs]} return
    set records [scriptJobsSelectedRecords];set count [llength $records]
    set active [expr {$count>0}];set finished $active;set hidden $active;set visible $active
    foreach job $records {
        if {[dict get $job state] ni {QUEUED PREPARING RUNNING FINALIZING}} {set active 0}
        if {[dict get $job state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {set finished 0}
        if {[dict get $job hidden]} {set visible 0} else {set hidden 0}
    }
    foreach {menu index enabled} [list jobs 0 [expr {$count==1}] jobs 1 [expr {$count==1 && $finished}] jobs 2 $active jobs 3 [expr {$count==1}] history 0 [expr {$finished&&$visible}] history 1 $hidden] {
        $w.actions.$menu.menu entryconfigure $index -state [expr {$enabled ? "normal" : "disabled"}]
    }
    foreach {index enabled} [list 0 [expr {$count==1}] 1 $active 2 [expr {$finished&&$visible}] 3 $hidden] {$w.context entryconfigure $index -state [expr {$enabled ? "normal" : "disabled"}]}
    $w.actions.view.menu entryconfigure 7 -state [expr {$::GX::currentSession eq {} ? "disabled" : "normal"}]
    if {[info exists ::GX::scriptJobsUi(page)]} {
        set page $::GX::scriptJobsUi(page)
        foreach {index enabled} [list 10 [expr {[dict get $page offset]>0}] 11 [expr {[dict get $page offset]+[dict get $page limit]<[dict get $page matching]}]] {$w.actions.view.menu entryconfigure $index -state [expr {$enabled ? "normal" : "disabled"}]}
    }
    if {[info exists ::GX::scriptJobsUi(workspace)]} {$w.actions.workspace.menu entryconfigure 4 -state [expr {$::GX::scriptJobsUi(workspace) eq {} ? "disabled" : "normal"}]}
}
proc ::GX::scriptJobsContext {y xroot yroot} {
    set w .gxtxtScriptJobs;set id [$w.jobs identify row 0 $y]
    if {$id eq {}} return
    if {$id ni [$w.jobs selection]} {$w.jobs selection set $id}
    scriptJobsSelection;uiMenuPopup $w.context $xroot $yroot
}
proc ::GX::scriptJobsCaptureView {} {
    variable scriptJobsUi
    set w .gxtxtScriptJobs;set view $scriptJobsUi(view)
    dict set view filter $scriptJobsUi(filter);dict set view show_hidden $scriptJobsUi(showHidden)
    dict set view geometry [wm geometry $w]
    dict set view columns [$w.jobs cget -displaycolumns]
    foreach column [concat {#0} [scriptJobViewColumns]] {dict set view widths $column [$w.jobs column $column -width]}
    if {[winfo height $w.split]>1} {dict set view pane [expr {double([$w.split sashpos 0])/[winfo height $w.split]}]}
    dict set view xscroll [lindex [$w.jobs xview] 0];dict set view yscroll [lindex [$w.jobs yview] 0]
    dict set view selected [lindex [$w.jobs selection] 0]
    return [scriptJobViewValidate $view]
}
proc ::GX::scriptJobsApplyView {} {
    variable scriptJobsUi
    set w .gxtxtScriptJobs;set view [scriptJobViewValidate $scriptJobsUi(view)]
    set scriptJobsUi(filter) [dict get $view filter];set scriptJobsUi(showHidden) [dict get $view show_hidden]
    $w.jobs configure -displaycolumns [dict get $view columns]
    foreach column [scriptJobViewColumns] {set scriptJobsUi(column,$column) [expr {$column in [dict get $view columns]}]}
    dict for {column width} [dict get $view widths] {$w.jobs column $column -width $width}
    wm geometry $w [dict get $view geometry];update idletasks
    # Keep a saved layout reachable after monitor changes without altering Jobs.
    lassign [uiMenuWorkarea $w [winfo rootx $w] [winfo rooty $w]] left top width height
    set ww [expr {min([winfo width $w],$width-30)}];set wh [expr {min([winfo height $w],$height-70)}]
    set x [expr {max($left,min([winfo x $w],$left+$width-$ww-20))}];set y [expr {max($top,min([winfo y $w],$top+$height-$wh-40))}]
    wm geometry $w [format {%dx%d%+d%+d} $ww $wh $x $y];update idletasks
    $w.split sashpos 0 [expr {int([dict get $view pane]*[winfo height $w.split])}]
    set scriptJobsUi(restoreSelection) [dict get $view selected]
    scriptJobsTitle
}
proc ::GX::scriptJobsTitle {} {
    set preferences [scriptJobPresentationGet];set id $::GX::scriptJobsUi(workspace)
    set name {Default / unsaved}
    if {$id ne {} && [dict exists $preferences workspaces $id]} {set name [dict get $preferences workspaces $id name]}
    wm title .gxtxtScriptJobs "GX-TXT — Script Jobs — Workspace: $name"
}
proc ::GX::scriptJobsViewChanged {} {
    variable scriptJobsUi
    set scriptJobsUi(view) [scriptJobsCaptureView];set scriptJobsUi(offset) 0
    incr scriptJobsUi(generation);scriptJobsRefresh
}
proc ::GX::scriptJobsColumnsChanged {} {
    set columns {};foreach column [scriptJobViewColumns] {if {$::GX::scriptJobsUi(column,$column)} {lappend columns $column}}
    .gxtxtScriptJobs.jobs configure -displaycolumns $columns
    scriptJobsViewChanged
}
proc ::GX::scriptJobsSort {column} {
    variable scriptJobsUi
    if {[dict get $scriptJobsUi(view) sort] eq $column} {dict set scriptJobsUi(view) descending [expr {![dict get $scriptJobsUi(view) descending]}]} else {dict set scriptJobsUi(view) sort $column;dict set scriptJobsUi(view) descending 0}
    scriptJobsViewChanged
}
proc ::GX::scriptJobsPage {direction} {
    variable scriptJobsUi
    set scriptJobsUi(offset) [expr {max(0,$scriptJobsUi(offset)+500*$direction)}]
    incr scriptJobsUi(generation);scriptJobsRefresh
}
proc ::GX::scriptJobsSetScope {scope} {
    if {$scope eq "current"} {set scope $::GX::currentSession;if {$scope eq {}} return;set scope [file normalize $scope]}
    dict set ::GX::scriptJobsUi(view) scope $scope
    scriptJobsViewChanged
}
proc ::GX::scriptJobsScopeDialog {} {
    set current [dict get $::GX::scriptJobsUi(view) scope];if {$current eq "all"} {set current $::GX::currentSession}
    uiFieldFormCreate .gxtxtScriptJobs.scope {Runner Session scope} {scope {type path required 1 label {Session directory (view filter only)}}} [dict create scope $current] ::GX::scriptJobsScopeApply .gxtxtScriptJobs
}
proc ::GX::scriptJobsScopeApply {values} {
    set view $::GX::scriptJobsUi(view);dict set view scope [dict get $values scope];scriptJobViewValidate $view
    scriptJobsSetScope [dict get $view scope];destroy .gxtxtScriptJobs.scope
}
proc ::GX::scriptJobsHistory {action} {
    variable scriptJobsUi
    if {[catch {
        if {$action eq "finished"} {
            set ids [scriptJobHistoryCandidates [scriptJobsCaptureView]]
            if {![llength $ids]} return
            set scope [dict get $scriptJobsUi(view) scope]
            if {[tk_messageBox -parent .gxtxtScriptJobs -type okcancel -default cancel -icon question -title {Hide finished history} -message "Hide [llength $ids] finished Jobs in scope '$scope', filter '$scriptJobsUi(filter)'? This changes only the visible list. Logs, source snapshots, outputs and scientific data remain available. Active Jobs are excluded."] ne "ok"} return
            scriptJobHistoryHide $ids
        } else {
            set ids [lmap job [scriptJobsSelectedRecords] {dict get $job id}]
            if {![llength $ids]} return
            if {$action eq "hide"} {scriptJobHistoryHide $ids} elseif {$action eq "restore"} {scriptJobHistoryRestore $ids} else {error {Unknown history action}}
        }
        incr scriptJobsUi(generation)
        # Apply the persisted mask now; an old asynchronous response is rejected.
        if {$action ne "restore" && !$scriptJobsUi(showHidden) && $scriptJobsUi(filter) ne "Hidden"} {
            foreach id $ids {if {[.gxtxtScriptJobs.jobs exists $id]} {.gxtxtScriptJobs.jobs delete $id}}
            scriptJobsSelection
        }
        scriptJobsRefresh
    } message]==1} {tk_messageBox -parent .gxtxtScriptJobs -icon error -message $message}
}
proc ::GX::scriptJobsWorkspaceAction {action} {
    variable scriptJobsUi
    if {[catch {
        set id $scriptJobsUi(workspace);set preferences [scriptJobPresentationGet]
        switch -- $action {
            new - close {
                set scriptJobsUi(workspace) {};set scriptJobsUi(view) [scriptJobViewDefault]
                scriptJobViewRemember $scriptJobsUi(view);scriptJobsApplyView;scriptJobsViewChanged
            }
            manager {scriptJobsWorkspaceManager}
            save {
                if {$id eq {}} {scriptJobsWorkspaceAction duplicate;return}
                scriptJobWorkspaceSave $id [dict get $preferences workspaces $id name] [scriptJobsCaptureView]
                scriptJobsTitle
            }
            duplicate - rename {
                set name {Runner Workspace}
                if {$id ne {}} {set name [dict get $preferences workspaces $id name];if {$action eq "duplicate"} {append name { copy}}}
                uiFieldFormCreate .gxtxtScriptJobs.workspaceName "[string totitle $action] Runner Workspace" {name {type string required 1 label Name}} [dict create name $name] [list ::GX::scriptJobsWorkspaceNamed $action] .gxtxtScriptJobs
            }
        }
    } message]==1} {tk_messageBox -parent .gxtxtScriptJobs -icon error -message $message}
}
proc ::GX::scriptJobsWorkspaceNamed {action values} {
    variable scriptJobsUi
    if {$action eq "rename"} {scriptJobWorkspaceRename $scriptJobsUi(workspace) [dict get $values name]} else {set scriptJobsUi(workspace) [scriptJobWorkspaceSave {} [dict get $values name] [scriptJobsCaptureView]]}
    scriptJobsTitle;destroy .gxtxtScriptJobs.workspaceName
    if {[winfo exists .gxtxtScriptJobs.workspaces]} {scriptJobsWorkspaceManager}
}
proc ::GX::scriptJobsWorkspaceManager {} {
    set w .gxtxtScriptJobs.workspaces;catch {destroy $w};toplevel $w;wm title $w {User-local Runner Workspaces}
    ttk::label $w.note -text {Saved layouts and filters only. Hidden Job IDs remain global to this user's Configuration.} -wraplength 560
    pack $w.note -fill x -padx 8 -pady 8
    ttk::treeview $w.list -columns {name scope filter} -show headings -selectmode browse
    foreach column {name scope filter} {$w.list heading $column -text [string totitle $column]}
    pack $w.list -fill both -expand 1
    dict for {id record} [dict get [scriptJobPresentationGet] workspaces] {$w.list insert {} end -id $id -values [list [dict get $record name] [dict get $record view scope] [dict get $record view filter]]}
    ttk::frame $w.buttons;pack $w.buttons -fill x
    foreach {key title} {open Open rename Rename delete {Delete layout}} {ttk::button $w.buttons.$key -text $title -command [list ::GX::scriptJobsWorkspaceManagerAction $key];pack $w.buttons.$key -side left -padx 5 -pady 5}
    ttk::button $w.buttons.close -text Close -command [list destroy $w];pack $w.buttons.close -side right -padx 5 -pady 5
}
proc ::GX::scriptJobsWorkspaceManagerAction {action} {
    variable scriptJobsUi
    set w .gxtxtScriptJobs.workspaces;set ids [$w.list selection]
    if {[llength $ids]!=1} return
    set id [lindex $ids 0]
    if {[catch {
        switch -- $action {
            open {set scriptJobsUi(view) [scriptJobWorkspaceOpen $id];set scriptJobsUi(workspace) $id;scriptJobsApplyView;scriptJobsViewChanged;destroy $w}
            rename {uiFieldFormCreate .gxtxtScriptJobs.workspaceName {Rename Runner Workspace} {name {type string required 1 label Name}} [dict create name [dict get [scriptJobPresentationGet] workspaces $id name]] [list ::GX::scriptJobsWorkspaceManagerRename $id] $w}
            delete {
                if {[tk_messageBox -parent $w -type okcancel -default cancel -message {Delete this saved layout? Jobs, logs, outputs and hidden status are preserved.}] ne "ok"} return
                scriptJobWorkspaceDelete $id
                if {$scriptJobsUi(workspace) eq $id} {set scriptJobsUi(workspace) {};scriptJobsTitle}
                scriptJobsWorkspaceManager
            }
        }
    } message]==1} {tk_messageBox -parent $w -icon error -message $message}
}
proc ::GX::scriptJobsWorkspaceManagerRename {id values} {
    scriptJobWorkspaceRename $id [dict get $values name];scriptJobsTitle
    destroy .gxtxtScriptJobs.workspaceName;scriptJobsWorkspaceManager
}
proc ::GX::scriptJobsClose {} {
    if {[catch {scriptJobViewRemember [scriptJobsCaptureView] $::GX::scriptJobsUi(workspace)} message]} {tk_messageBox -parent .gxtxtScriptJobs -icon error -message $message;return}
    destroy .gxtxtScriptJobs
}
proc ::GX::scriptJobsDestroyed {widget} {
    if {$widget ne ".gxtxtScriptJobs"} return
    if {[info exists ::GX::scriptJobsUi(timer)]} {after cancel $::GX::scriptJobsUi(timer)}
    incr ::GX::scriptJobsUiEpoch;set ::GX::scriptJobsBusy 0
}
