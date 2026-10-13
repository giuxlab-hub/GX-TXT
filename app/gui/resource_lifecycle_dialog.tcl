# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {
    variable resourceLifecycleUi
}

proc ::GX::resourceLifecycleSessionDialog {} {
    variable resourceLifecycleUi
    set w .gxtxtDeleteSession
    if {[winfo exists $w]} {raise $w; focus $w; resourceLifecycleSessionRefresh; return}
    toplevel $w
    wm title $w "Delete Session"
    wm geometry $w 830x480
    wm minsize $w 610 320
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 1 -weight 1
    ttk::label $w.intro -text "Select a GX-TXT Session. Deletion removes only the selected Session-owned tree." -wraplength 780
    grid $w.intro -row 0 -column 0 -sticky ew -padx 12 -pady 10
    ttk::frame $w.list
    grid $w.list -row 1 -column 0 -sticky nsew -padx 12
    grid columnconfigure $w.list 0 -weight 1
    grid rowconfigure $w.list 0 -weight 1
    ttk::treeview $w.list.tree -columns {name path} -show headings -selectmode browse
    $w.list.tree heading name -text "Session name"
    $w.list.tree heading path -text "Resolved path"
    $w.list.tree column name -width 220
    $w.list.tree column path -width 580
    ttk::scrollbar $w.list.sy -orient vertical -command [list $w.list.tree yview]
    $w.list.tree configure -yscrollcommand [list $w.list.sy set]
    grid $w.list.tree -row 0 -column 0 -sticky nsew
    grid $w.list.sy -row 0 -column 1 -sticky ns
    ttk::label $w.details -textvariable ::GX::resourceLifecycleUi(sessionDetails) -wraplength 780 -justify left
    grid $w.details -row 2 -column 0 -sticky ew -padx 12 -pady 8
    ttk::frame $w.actions
    ttk::button $w.actions.refresh -text Refresh -command ::GX::resourceLifecycleSessionRefresh
    ttk::button $w.actions.browse -text "Choose Session folder..." -command ::GX::resourceLifecycleSessionBrowse
    ttk::button $w.actions.delete -text "Delete selected Session..." -command ::GX::resourceLifecycleSessionDeleteSelected
    ttk::button $w.actions.close -text Close -command [list destroy $w]
    pack $w.actions.refresh $w.actions.browse $w.actions.delete $w.actions.close -side left -padx 4
    grid $w.actions -row 3 -column 0 -sticky ew -padx 8 -pady 10
    bind $w.list.tree <<TreeviewSelect>> ::GX::resourceLifecycleSessionShowSelected
    set resourceLifecycleUi(sessionDetails) "Select a Session to inspect its path and deletion scope."
    resourceLifecycleSessionRefresh
}

proc ::GX::resourceLifecycleSessionRefresh {} {
    variable resourceLifecycleUi
    set tree .gxtxtDeleteSession.list.tree
    if {![winfo exists $tree]} return
    set previous [resourceLifecycleSessionSelectedPath]
    $tree delete [$tree children {}]
    if {[catch {set sessions [resourceLifecycleSessionCandidates]} reason]} {
        set resourceLifecycleUi(sessionDetails) "Session list could not be loaded: $reason"
        return
    }
    set index 0
    set selected ""
    foreach session $sessions {
        set path [dict get $session path]
        set item "session[incr index]"
        $tree insert {} end -id $item -values [list [dict get $session name] $path]
        if {$path eq $previous} {set selected $item}
    }
    if {$selected ne ""} {$tree selection set $selected; $tree see $selected}
    resourceLifecycleSessionShowSelected
}

proc ::GX::resourceLifecycleSessionSelectedPath {} {
    set tree .gxtxtDeleteSession.list.tree
    if {![winfo exists $tree]} {return ""}
    set selected [$tree selection]
    if {[llength $selected] != 1} {return ""}
    return [lindex [$tree item [lindex $selected 0] -values] 1]
}

proc ::GX::resourceLifecycleSessionShowSelected {} {
    variable resourceLifecycleUi
    set path [resourceLifecycleSessionSelectedPath]
    if {$path eq ""} {
        set resourceLifecycleUi(sessionDetails) "Select a Session to inspect its path and deletion scope."
        return
    }
    if {[catch {set session [resourceLifecycleSessionInspect $path]} reason]} {
        set resourceLifecycleUi(sessionDetails) "This entry cannot be deleted: $reason"
        return
    }
    set resourceLifecycleUi(sessionDetails) "Session: [dict get $session name]\nPath: [dict get $session path]\nExternal RAW/source references are preserved."
}

proc ::GX::resourceLifecycleSessionBrowse {} {
    variable resourceLifecycleUi
    set w .gxtxtDeleteSession
    set path [tk_chooseDirectory -parent $w -title "Choose GX-TXT Session to delete" -mustexist 1]
    if {$path eq ""} return
    if {[catch {set session [resourceLifecycleSessionInspect $path]} reason]} {
        set resourceLifecycleUi(sessionDetails) "Selected folder is not a deletable Session: $reason"
        tk_messageBox -parent $w -type ok -icon error -title "Invalid Session" -message $reason
        return
    }
    set path [dict get $session path]
    set tree $w.list.tree
    foreach item [$tree children {}] {
        if {[lindex [$tree item $item -values] 1] eq $path} {
            $tree selection set $item
            $tree see $item
            resourceLifecycleSessionShowSelected
            return
        }
    }
    set item "session[expr {[llength [$tree children {}]] + 1}]"
    $tree insert {} end -id $item -values [list [dict get $session name] $path]
    $tree selection set $item
    $tree see $item
    resourceLifecycleSessionShowSelected
}

proc ::GX::resourceLifecycleSessionDeleteSelected {} {
    variable resourceLifecycleUi
    set path [resourceLifecycleSessionSelectedPath]
    if {$path eq ""} {return 0}
    if {[catch {set session [resourceLifecycleSessionInspect $path]} reason]} {
        set resourceLifecycleUi(sessionDetails) "Deletion refused: $reason"
        tk_messageBox -parent .gxtxtDeleteSession -type ok -icon error -title "Invalid Session" -message $reason
        return 0
    }
    set resolved [dict get $session path]
    set name [dict get $session name]
    set message "Delete Session '$name'?\n\nResolved path: $resolved\n\nWILL delete: this Session-owned folder and its contained data, analysis results, scripts, Worksheet documents, and metadata. If open, this Session will be closed first. Project associations to it will be removed.\nWILL preserve: externally referenced RAW/source files, other Sessions, Projects, and user libraries."
    if {[tk_messageBox -parent .gxtxtDeleteSession -type yesno -default no -icon warning -title "Delete Session" -message $message] ne "yes"} {return 0}
    if {[catch {resourceLifecycleDeleteSession $resolved} reason]} {
        set resourceLifecycleUi(sessionDetails) "Delete failed: $reason"
        tk_messageBox -parent .gxtxtDeleteSession -type ok -icon error -title "Delete Session failed" -message $reason
        return 0
    }
    resourceLifecycleSessionRefresh
    catch {updateSessionUi}
    catch {sessionFileExplorerPopulate}
    catch {scriptLibraryRefresh}
    catch {scriptWorkspaceRefreshChoices}
    catch {scriptAnalysisRefresh}
    catch {projectGuiRefresh}
    set resourceLifecycleUi(sessionDetails) "Deleted Session '$name' at $resolved. External RAW/source files were preserved."
    return 1
}

proc ::GX::resourceLifecycleProjectDeleteSelected {{id ""}} {
    if {$id eq ""} {set id [projectGuiSelectedId]}
    if {$id eq ""} {return 0}
    if {[catch {set project [resourceLifecycleProjectInspect $id]} reason]} {
        tk_messageBox -type ok -icon error -title "Delete Project" -message $reason
        return 0
    }
    set name [dict get $project name]
    set sessions [dict get $project session_count]
    set experiments [dict get $project experiment_count]
    set resources [dict get $project resource_count]
    set message "Delete Project '$name'?\n\nStable ID: $id\nAssociated Sessions: $sessions\nAssociated Experiments: $experiments\nProject-owned resources: $resources\n\nWILL delete: this Project record and Project-owned metadata. Associated Sessions and Experiments will be detached.\nWILL preserve: all Session folders and scientific data, external RAW/source files, user libraries, and unrelated Projects."
    if {[tk_messageBox -type yesno -default no -icon warning -title "Delete Project" -message $message] ne "yes"} {return 0}
    if {[catch {resourceLifecycleDeleteProject $id} reason]} {
        tk_messageBox -type ok -icon error -title "Delete Project failed" -message $reason
        return 0
    }
    catch {projectGuiRefresh}
    catch {projectRefreshExperimentUi}
    catch {updateSessionUi}
    return 1
}
