# GX-TXT Projects GUI v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This is a GUI projection of Project API v1, not a second Project backend.

namespace eval ::GX {
    variable projectGuiSelectedId ""
}

proc ::GX::projectGuiSelectedId {} {
    set tree .top.nb.projects.body.left.tree
    if {![winfo exists $tree]} { return "" }
    set sel [$tree selection]
    if {[llength $sel] != 1} { return "" }
    return [lindex $sel 0]
}

proc ::GX::projectGuiRefresh {} {
    set f .top.nb.projects
    if {![winfo exists $f]} return
    set tree $f.body.left.tree
    set selected [projectGuiSelectedId]
    $tree delete [$tree children {}]
    foreach id [projectIds] {
        $tree insert {} end -id $id -values [list [projectField $id name] [projectField $id updated_at]]
    }
    if {$selected ne "" && [projectExists $selected]} { $tree selection set $selected }
    projectGuiShowSelected
}

proc ::GX::projectGuiShowSelected {} {
    set f .top.nb.projects
    if {![winfo exists $f]} return
    set id [projectGuiSelectedId]
    foreach field {name id description tags created_at updated_at} {
        set w "$f.body.right.value_$field"
        if {[winfo exists $w]} { $w configure -text "" }
    }
    $f.body.right.experiments delete [$f.body.right.experiments children {}]
    if {$id eq "" || ![projectExists $id]} {
        $f.body.right.status configure -text "Select a Project to view its metadata and Experiments."
        return
    }
    set d [projectGet $id]
    foreach field {name id description tags created_at updated_at} {
        $f.body.right.value_$field configure -text [dict get $d $field]
    }
    set n 0
    foreach exp [projectListExperiments $id] {
        incr n
        $f.body.right.experiments insert {} end -id "exp:$n" -values [list [dict get $exp experiment_name] [dict get $exp session_path] [dict get $exp experiment_id]]
    }
    $f.body.right.status configure -text "$n Experiment(s) associated with this Project."
}

proc ::GX::projectGuiEditSelected {} {
    set id [projectGuiSelectedId]
    if {$id eq ""} return
    projectMetadataDialog edit $id
}

proc ::GX::projectGuiAssociateSelected {} {
    set id [projectGuiSelectedId]
    if {$id eq ""} return
    if {[catch {projectAssociateCurrentExperiment $id} err]} {
        tk_messageBox -icon error -title "Projects" -message $err
        return
    }
    projectGuiRefresh
}

proc ::GX::projectGuiNewSession {} {
    set id [projectGuiSelectedId]
    if {$id eq ""} {
        tk_messageBox -icon info -title "Projects" -message "Select a Project first."
        return
    }
    newSessionDialog $id
    catch {projectGuiRefresh}
}

proc ::GX::projectGuiOpenExperiment {} {
    set f .top.nb.projects
    set sel [$f.body.right.experiments selection]
    if {[llength $sel] != 1} return
    set values [$f.body.right.experiments item [lindex $sel 0] -values]
    set path [lindex $values 1]
    if {$path eq "" || ![file isdirectory $path]} {
        tk_messageBox -icon error -title "Projects" -message "The recorded Session path is not available:\n$path"
        return
    }
    if {[catch {openSessionPath $path} err]} { tk_messageBox -icon error -title "Projects" -message $err; return }
    projectGuiRefresh
}

proc ::GX::projectGuiDetachExperiment {} {
    set f .top.nb.projects
    set sel [$f.body.right.experiments selection]
    if {[llength $sel] != 1} return
    set values [$f.body.right.experiments item [lindex $sel 0] -values]
    set eid [lindex $values 2]
    if {[tk_messageBox -icon question -type yesno -title "Detach Experiment" -message "Detach this Experiment from the selected Project?\n\nNo Session or scientific data will be deleted."] ne "yes"} return
    if {[info exists ::GX::cfg(experiment_id)] && $::GX::cfg(experiment_id) eq $eid} {
        projectDetachCurrentExperiment
    } else {
        projectDetachExperiment $eid
    }
    projectGuiRefresh
}

proc ::GX::projectGuiBuild {} {
    set f .top.nb.projects
    if {![winfo exists $f]} return
    destroyChildren $f
    grid rowconfigure $f 1 -weight 1
    grid columnconfigure $f 0 -weight 1
    ttk::frame $f.toolbar
    ttk::button $f.toolbar.new -text "Create" -command {::GX::projectMetadataDialog new}
    ttk::button $f.toolbar.edit -text "Edit" -command ::GX::projectGuiEditSelected
    ttk::button $f.toolbar.delete -text "Delete Project..." -command ::GX::resourceLifecycleProjectDeleteSelected
    ttk::button $f.toolbar.select -text "Open / Select" -command ::GX::projectGuiAssociateSelected
    ttk::button $f.toolbar.newSession -text "New Session in Project..." -command ::GX::projectGuiNewSession
    ttk::button $f.toolbar.refresh -text "Refresh" -command ::GX::projectGuiRefresh
    pack $f.toolbar.new $f.toolbar.edit $f.toolbar.delete $f.toolbar.select $f.toolbar.newSession $f.toolbar.refresh -side left -padx 3 -pady 4
    grid $f.toolbar -row 0 -column 0 -sticky ew -padx 5 -pady 4

    ttk::panedwindow $f.body -orient horizontal
    grid $f.body -row 1 -column 0 -sticky nsew -padx 5 -pady 5
    ttk::frame $f.body.left
    ttk::frame $f.body.right
    $f.body add $f.body.left -weight 1
    $f.body add $f.body.right -weight 2

    ttk::treeview $f.body.left.tree -columns {name updated} -show headings -selectmode browse
    $f.body.left.tree heading name -text "Project"
    $f.body.left.tree heading updated -text "Updated"
    $f.body.left.tree column name -width 260 -stretch 1
    $f.body.left.tree column updated -width 180 -stretch 0
    ttk::scrollbar $f.body.left.sy -orient vertical -command [list $f.body.left.tree yview]
    $f.body.left.tree configure -yscrollcommand [list $f.body.left.sy set]
    pack $f.body.left.sy -side right -fill y
    pack $f.body.left.tree -side left -fill both -expand 1
    bind $f.body.left.tree <<TreeviewSelect>> ::GX::projectGuiShowSelected

    grid columnconfigure $f.body.right 1 -weight 1
    set r 0
    foreach {field label} {name Name id {Project ID} description {Description / notes} notes Notes tags {Tags / keywords} author Author storage_path {Storage path} created_at Created updated_at Updated} {
        ttk::label $f.body.right.label_$field -text "$label:"
        ttk::label $f.body.right.value_$field -anchor w -justify left -wraplength 650
        grid $f.body.right.label_$field -row $r -column 0 -sticky ne -padx 5 -pady 3
        grid $f.body.right.value_$field -row $r -column 1 -sticky ew -padx 5 -pady 3
        incr r
    }
    ttk::label $f.body.right.expLabel -text "Experiments:"
    grid $f.body.right.expLabel -row $r -column 0 -sticky nw -padx 5 -pady 4
    ttk::treeview $f.body.right.experiments -columns {name path id} -show headings -height 10 -selectmode browse
    foreach {col label width stretch} {name Experiment 180 0 path {Session path} 360 1 id {Experiment ID} 240 0} {
        $f.body.right.experiments heading $col -text $label
        $f.body.right.experiments column $col -width $width -stretch $stretch
    }
    grid $f.body.right.experiments -row $r -column 1 -sticky nsew -padx 5 -pady 4
    grid rowconfigure $f.body.right $r -weight 1
    incr r
    ttk::frame $f.body.right.actions
    ttk::button $f.body.right.actions.open -text "Open Experiment Session" -command ::GX::projectGuiOpenExperiment
    ttk::button $f.body.right.actions.detach -text "Detach Experiment" -command ::GX::projectGuiDetachExperiment
    pack $f.body.right.actions.open $f.body.right.actions.detach -side left -padx 3
    grid $f.body.right.actions -row $r -column 1 -sticky w -padx 5 -pady 3
    incr r
    ttk::label $f.body.right.status -text "" -anchor w
    grid $f.body.right.status -row $r -column 0 -columnspan 2 -sticky ew -padx 5 -pady 3
    bind $f.body.right.experiments <Double-1> ::GX::projectGuiOpenExperiment
    projectGuiRefresh
}

# Project dialogs can also be opened from Experiment; refresh the Projects tab
# after a committed change so both views remain projections of one API state.
proc ::GX::projectMetadataDialogCommit {w mode id} {
    ::GX::projectMetadataDialogCommit_before_projects_gui_v1 $w $mode $id
    catch {projectGuiRefresh}
}

proc ::GX::projectRefreshExperimentUi {} {
    ::GX::projectRefreshExperimentUi_before_projects_gui_v1
    catch {projectGuiRefresh}
}

proc ::GX::launchGui_before_graph_selection {} {
    ::GX::launchGui_before_projects_gui_v1
    projectGuiBuild
}
