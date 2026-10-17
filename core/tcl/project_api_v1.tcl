# GX-TXT Project API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Persistent Projects organize Experiments. New Project Sessions live under the
# Project's stable storage path; older associated Sessions keep their own paths.
# Identity remains independent from the editable display name.

namespace eval ::GX {
    variable projectApiVersion 1
    variable projectCatalog
    variable projectMembership
    variable projectRegistryLoaded 0
    variable projectIdCounter 0
    variable experimentIdCounter 0
}

proc ::GX::projectTimestamp {} {
    return [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
}

proc ::GX::projectRegistryPath {} {
    if {[info exists ::env(XDG_CONFIG_HOME)] && [string trim $::env(XDG_CONFIG_HOME)] ne ""} {
        set root $::env(XDG_CONFIG_HOME)
    } elseif {[info exists ::env(HOME)] && [string trim $::env(HOME)] ne ""} {
        set root [file join $::env(HOME) .config]
    } else {
        set root [pwd]
    }
    return [file join $root gxtxt_pipeline projects.ini]
}

proc ::GX::projectGenerateId {} {
    variable projectIdCounter
    variable projectCatalog
    projectEnsureRegistryLoaded
    while {1} {
        incr projectIdCounter
        set id [format "project-%s-%d-%d-%d" \
            [clock format [clock seconds] -gmt 1 -format "%Y%m%dT%H%M%SZ"] \
            [pid] [clock clicks] $projectIdCounter]
        if {![info exists projectCatalog($id,id)]} { return $id }
    }
}

proc ::GX::experimentGenerateId {} {
    variable experimentIdCounter
    incr experimentIdCounter
    return [format "experiment-%s-%d-%d-%d" \
        [clock format [clock seconds] -gmt 1 -format "%Y%m%dT%H%M%SZ"] \
        [pid] [clock clicks] $experimentIdCounter]
}

proc ::GX::projectEnsureRegistryLoaded {} {
    variable projectRegistryLoaded
    if {!$projectRegistryLoaded} { projectLoadRegistry }
}

proc ::GX::projectLoadRegistry {} {
    variable projectCatalog
    variable projectMembership
    variable projectRegistryLoaded
    array unset projectCatalog *
    array unset projectMembership *
    set path [projectRegistryPath]
    if {![file isfile $path]} {
        set projectRegistryLoaded 1
        return {}
    }
    set d [parseIni $path]
    foreach key [dict keys $d] {
        if {[regexp {^project\.([^.]+)\.([^.]*)$} $key -> id field]} {
            set projectCatalog($id,$field) [dict get $d $key]
        } elseif {[regexp {^experiment\.([^.]+)\.([^.]*)$} $key -> id field]} {
            set projectMembership($id,$field) [dict get $d $key]
        }
    }
    set projectRegistryLoaded 1
    return [projectIdsLoaded]
}

proc ::GX::projectIdsLoaded {} {
    variable projectCatalog
    set ids {}
    foreach key [array names projectCatalog "*,id"] {
        set id [string range $key 0 end-3]
        if {[lsearch -exact $ids $id] < 0} { lappend ids $id }
    }
    return [lsort -dictionary $ids]
}

proc ::GX::projectIds {} {
    projectEnsureRegistryLoaded
    return [projectIdsLoaded]
}

proc ::GX::projectSaveRegistry {} {
    variable projectCatalog
    variable projectMembership
    variable projectApiVersion
    variable projectRegistryLoaded
    projectEnsureRegistryLoaded
    set path [projectRegistryPath]
    file mkdir [file dirname $path]
    set tmp "${path}.tmp.[pid].[clock clicks]"
    set fd [open $tmp w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT Project API v1 registry"
    puts $fd "; SPDX-License-Identifier: GPL-3.0-or-later"
    puts $fd "\[registry\]"
    putKV $fd api_version $projectApiVersion
    set ids [projectIdsLoaded]
    putKV $fd project_count [llength $ids]
    foreach id $ids {
        puts $fd "\n\[project.$id\]"
        foreach field {id name description tags author storage_path created_at updated_at origin} {
            putKV $fd $field [expr {[info exists projectCatalog($id,$field)] ? $projectCatalog($id,$field) : ""}]
        }
    }
    set eids {}
    foreach key [array names projectMembership "*,experiment_id"] {
        set eid [string range $key 0 end-14]
        if {[lsearch -exact $eids $eid] < 0} { lappend eids $eid }
    }
    foreach eid [lsort -dictionary $eids] {
        puts $fd "\n\[experiment.$eid\]"
        foreach field {experiment_id project_id session_path experiment_name associated_at updated_at} {
            putKV $fd $field [expr {[info exists projectMembership($eid,$field)] ? $projectMembership($eid,$field) : ""}]
        }
    }
    close $fd
    file rename -force -- $tmp $path
    set projectRegistryLoaded 1
    return $path
}

proc ::GX::projectField {id field {default ""}} {
    variable projectCatalog
    projectEnsureRegistryLoaded
    if {[info exists projectCatalog($id,$field)]} { return $projectCatalog($id,$field) }
    return $default
}

proc ::GX::projectExists {id} {
    variable projectCatalog
    projectEnsureRegistryLoaded
    return [info exists projectCatalog($id,id)]
}

proc ::GX::projectGet {id} {
    if {![projectExists $id]} { error "Unknown Project '$id'." }
    set out [dict create]
    foreach field {id name description tags author storage_path created_at updated_at origin} {
        dict set out $field [projectField $id $field ""]
    }
    return $out
}

proc ::GX::projectCreate {name {description ""} {tags ""} {author ""}} {
    variable projectCatalog
    set name [string trim $name]
    if {$name eq ""} { error "Project name must not be empty." }
    set id [projectGenerateId]
    set now [projectTimestamp]
    set storage [projectDefaultStoragePath $id]
    if {[file exists $storage]} { error "Project storage path already exists: $storage" }
    _projectAtomic [list [file join $storage project.ini]] {
    file mkdir [file join $storage Sessions]
    foreach {field value} [list \
        id $id name $name description $description tags $tags author $author \
        storage_path $storage created_at $now updated_at $now] {
        set projectCatalog($id,$field) $value
    }
    set projectCatalog($id,origin) [_originCreate project]
    projectSaveRegistry
    projectWriteMetadata $id
    }
    return $id
}

proc ::GX::projectDefaultStoragePath {id} {
    variable cfg
    set root [expr {[info exists cfg(output_root)] ? [string trim $cfg(output_root)] : ""}]
    if {$root eq ""} { error "Set the Session / Project root in Configuration before creating a Project." }
    return [file normalize [file join $root $id]]
}

proc ::GX::projectStoragePath {id} {
    if {![projectExists $id]} { error "Unknown Project '$id'." }
    set path [projectField $id storage_path ""]
    if {$path eq ""} { set path [projectDefaultStoragePath $id] }
    return [file normalize $path]
}

proc ::GX::projectSessionsRoot {id} {
    variable projectCatalog
    set path [projectStoragePath $id]
    file mkdir [file join $path Sessions]
    if {![info exists projectCatalog($id,storage_path)] || $projectCatalog($id,storage_path) eq ""} {
        set projectCatalog($id,storage_path) $path
        projectSaveRegistry
        projectWriteMetadata $id
    }
    return [file join $path Sessions]
}

proc ::GX::projectWriteMetadata {id} {
    set path [file join [projectStoragePath $id] project.ini]
    file mkdir [file dirname $path]
    set temp "${path}.[pid].tmp"
    set ch [open $temp w]
    fconfigure $ch -encoding utf-8 -translation lf
    try {
        puts $ch "; GX-TXT Project API v1"
        puts $ch "\[project\]"
        foreach field {id name description tags author storage_path created_at updated_at origin} {
            putKV $ch $field [projectField $id $field ""]
        }
    } finally { close $ch }
    file rename -force -- $temp $path
    return $path
}

proc ::GX::projectUpdate {id fields} {
    variable projectCatalog
    if {![projectExists $id]} { error "Unknown Project '$id'." }
    foreach {field value} $fields {
        if {$field ni {name description tags author}} { error "Project field '$field' is not editable." }
        if {$field eq "name" && [string trim $value] eq ""} { error "Project name must not be empty." }
        set projectCatalog($id,$field) $value
    }
    set projectCatalog($id,updated_at) [projectTimestamp]
    projectSaveRegistry
    projectWriteMetadata $id
    return [projectGet $id]
}

proc ::GX::projectMembershipField {experimentId field {default ""}} {
    variable projectMembership
    projectEnsureRegistryLoaded
    if {[info exists projectMembership($experimentId,$field)]} { return $projectMembership($experimentId,$field) }
    return $default
}

proc ::GX::projectAssociateExperiment {projectId experimentId sessionPath experimentName} {
    variable projectMembership
    if {![projectExists $projectId]} { error "Unknown Project '$projectId'." }
    set experimentId [string trim $experimentId]
    if {$experimentId eq ""} { error "Experiment identity must not be empty." }
    set now [projectTimestamp]
    set previousAssociated [projectMembershipField $experimentId associated_at ""]
    if {$previousAssociated eq ""} { set previousAssociated $now }
    set normalizedPath ""
    if {[string trim $sessionPath] ne ""} { set normalizedPath [file normalize $sessionPath] }
    foreach {field value} [list \
        experiment_id $experimentId project_id $projectId session_path $normalizedPath \
        experiment_name $experimentName associated_at $previousAssociated updated_at $now] {
        set projectMembership($experimentId,$field) $value
    }
    projectSaveRegistry
    return $experimentId
}

proc ::GX::projectDetachExperiment {experimentId} {
    variable projectMembership
    projectEnsureRegistryLoaded
    foreach key [array names projectMembership "$experimentId,*"] { unset projectMembership($key) }
    projectSaveRegistry
}

proc ::GX::projectListExperiments {projectId} {
    variable projectMembership
    if {![projectExists $projectId]} { error "Unknown Project '$projectId'." }
    set out {}
    set ids {}
    foreach key [array names projectMembership "*,experiment_id"] {
        set eid [string range $key 0 end-14]
        if {[projectMembershipField $eid project_id ""] eq $projectId} { lappend ids $eid }
    }
    foreach eid [lsort -dictionary -unique $ids] {
        set d [dict create]
        foreach field {experiment_id project_id session_path experiment_name associated_at updated_at} {
            dict set d $field [projectMembershipField $eid $field ""]
        }
        lappend out $d
    }
    return $out
}

proc ::GX::projectEnsureCurrentExperimentId {} {
    variable cfg
    if {![info exists cfg(experiment_id)] || [string trim $cfg(experiment_id)] eq ""} {
        set cfg(experiment_id) [experimentGenerateId]
    }
    return $cfg(experiment_id)
}

proc ::GX::projectCurrentId {} {
    variable cfg
    if {![info exists cfg(experiment_project_id)]} { return "" }
    return [string trim $cfg(experiment_project_id)]
}

proc ::GX::projectCurrentDisplay {} {
    variable cfg
    set id [projectCurrentId]
    if {$id ne ""} {
        if {[projectExists $id]} { return [projectField $id name $id] }
        return "Missing Project: $id"
    }
    set legacy [expr {[info exists cfg(experiment_project_legacy)] ? [string trim $cfg(experiment_project_legacy)] : ""}]
    if {$legacy eq "" && [info exists cfg(experiment_project)]} { set legacy [string trim $cfg(experiment_project)] }
    if {$legacy ne ""} { return "Legacy text: $legacy" }
    return "None"
}

proc ::GX::projectPersistCurrentExperimentLink {} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return "" }
    set mdir [file join $currentSession metadata]
    file mkdir $mdir
    set path [file join $mdir manifest.ini]
    writeManifest $path
    catch {refreshManifestPreview}
    return $path
}

proc ::GX::projectSynchronizeCurrentExperiment {} {
    variable cfg
    variable currentSession
    set pid [projectCurrentId]
    if {$pid eq ""} {
        projectRefreshExperimentUi
        return
    }
    if {[projectExists $pid]} {
        set cfg(experiment_project) [projectField $pid name $cfg(experiment_project)]
        if {[info exists cfg(experiment_id)] && [string trim $cfg(experiment_id)] ne "" && \
                $currentSession ne "" && [file isdirectory $currentSession]} {
            projectAssociateExperiment $pid $cfg(experiment_id) $currentSession $cfg(experiment_name)
        }
    }
    projectRefreshExperimentUi
}

proc ::GX::projectAssociateCurrentExperiment {projectId} {
    variable cfg
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {
        error "Open or create a Session before associating its Experiment with a Project."
    }
    if {![projectExists $projectId]} { error "Unknown Project '$projectId'." }
    set previousId [projectCurrentId]
    set oldText [expr {[info exists cfg(experiment_project)] ? $cfg(experiment_project) : ""}]
    if {$previousId eq "" && [string trim $oldText] ne "" && \
            (![info exists cfg(experiment_project_legacy)] || [string trim $cfg(experiment_project_legacy)] eq "")} {
        # Historical free text is retained explicitly instead of being
        # reinterpreted as a Project identity during the first association.
        set cfg(experiment_project_legacy) $oldText
    }
    set eid [projectEnsureCurrentExperimentId]
    set cfg(experiment_project_id) $projectId
    set cfg(experiment_project) [projectField $projectId name]
    projectAssociateExperiment $projectId $eid $currentSession $cfg(experiment_name)
    projectPersistCurrentExperimentLink
    projectRefreshExperimentUi
    return $projectId
}

proc ::GX::projectDetachCurrentExperiment {} {
    variable cfg
    set eid [expr {[info exists cfg(experiment_id)] ? [string trim $cfg(experiment_id)] : ""}]
    if {$eid ne ""} { projectDetachExperiment $eid }
    set cfg(experiment_project_id) ""
    if {[info exists cfg(experiment_project_legacy)] && [string trim $cfg(experiment_project_legacy)] ne ""} {
        set cfg(experiment_project) $cfg(experiment_project_legacy)
    } else {
        set cfg(experiment_project) ""
    }
    projectPersistCurrentExperimentLink
    projectRefreshExperimentUi
}

proc ::GX::projectRefreshExperimentUi_before_projects_gui_v1 {} {
    variable ui
    set ui(experimentProjectDisplay) [projectCurrentDisplay]
    if {![llength [info commands winfo]]} { return }
    set has [expr {[projectCurrentId] ne "" && [projectExists [projectCurrentId]]}]
    foreach name {edit experiments detach} {
        set w ".top.nb.exp.project.$name"
        if {[winfo exists $w]} { $w configure -state [expr {$has ? "normal" : "disabled"}] }
    }
}

proc ::GX::projectMetadataDialogCommit_before_projects_gui_v1 {w mode id} {
    variable ui
    set name [string trim $ui(projectDialogName)]
    set description [string trimright [$w.description get 1.0 end] "\n"]
    if {$mode eq "new"} {
        if {[catch {set id [projectCreate $name $description $ui(projectDialogTags) $ui(projectDialogAuthor)]} err]} {
            tk_messageBox -parent $w -icon error -title "Project" -message $err
            return
        }
        # Creating an organization record never changes an existing Experiment.
        # Membership is changed only by an explicit move/association command.
    } else {
        if {[catch {projectUpdate $id [list name $name description $description tags $ui(projectDialogTags) author $ui(projectDialogAuthor)]} err]} {
            tk_messageBox -parent $w -icon error -title "Project" -message $err
            return
        }
        if {[projectCurrentId] eq $id} {
            set ::GX::cfg(experiment_project) [projectField $id name]
            if {$::GX::currentSession ne "" && [file isdirectory $::GX::currentSession]} {
                set eid [projectEnsureCurrentExperimentId]
                projectAssociateExperiment $id $eid $::GX::currentSession $::GX::cfg(experiment_name)
                projectPersistCurrentExperimentLink
            }
        }
    }
    destroy $w
    projectRefreshExperimentUi
}

proc ::GX::projectMetadataDialog {{mode new} {id ""}} {
    variable ui
    if {$mode eq "edit"} {
        if {$id eq ""} { set id [projectCurrentId] }
        if {![projectExists $id]} { tk_messageBox -icon info -title "Project" -message "No persistent Project is selected."; return }
        set d [projectGet $id]
        set ui(projectDialogName) [dict get $d name]
        set ui(projectDialogTags) [dict get $d tags]
        set ui(projectDialogAuthor) [dict get $d author]
        set description [dict get $d description]
        set title "Edit Project"
        set action "Save"
    } else {
        set ui(projectDialogName) ""
        set ui(projectDialogTags) ""
        set ui(projectDialogAuthor) [expr {[info exists ::env(USER)] ? $::env(USER) : ""}]
        set description ""
        set title "New Project"
        set action "Create"
    }
    set w .gxProjectEditor
    catch {destroy $w}
    toplevel $w
    wm title $w $title
    wm transient $w .
    grid columnconfigure $w 1 -weight 1
    grid rowconfigure $w 1 -weight 1
    ttk::label $w.nameLabel -text "Name:"
    ttk::entry $w.name -textvariable ::GX::ui(projectDialogName) -width 46
    ttk::label $w.descriptionLabel -text "Description:"
    text $w.description -height 7 -width 54 -wrap word -undo 1
    $w.description insert 1.0 $description
    ttk::label $w.tagsLabel -text "Tags / keywords:"
    ttk::entry $w.tags -textvariable ::GX::ui(projectDialogTags)
    ttk::label $w.authorLabel -text "Author / username:"
    ttk::entry $w.author -textvariable ::GX::ui(projectDialogAuthor)
    ttk::frame $w.buttons
    ttk::button $w.buttons.ok -text $action -command [list ::GX::projectMetadataDialogCommit $w $mode $id]
    ttk::button $w.buttons.cancel -text "Cancel" -command [list destroy $w]
    grid $w.nameLabel -row 0 -column 0 -sticky e -padx 6 -pady 5
    grid $w.name -row 0 -column 1 -sticky ew -padx 6 -pady 5
    grid $w.descriptionLabel -row 1 -column 0 -sticky ne -padx 6 -pady 5
    grid $w.description -row 1 -column 1 -sticky nsew -padx 6 -pady 5
    grid $w.tagsLabel -row 2 -column 0 -sticky e -padx 6 -pady 5
    grid $w.tags -row 2 -column 1 -sticky ew -padx 6 -pady 5
    grid $w.authorLabel -row 3 -column 0 -sticky e -padx 6 -pady 5
    grid $w.author -row 3 -column 1 -sticky ew -padx 6 -pady 5
    pack $w.buttons.ok $w.buttons.cancel -side left -padx 4
    grid $w.buttons -row 4 -column 0 -columnspan 2 -pady 8
    bind $w <Escape> [list destroy $w]
    focus $w.name
}

proc ::GX::projectSelectDialogAssociate {w} {
    set sel [$w.list selection]
    if {![llength $sel]} { tk_messageBox -parent $w -icon info -title "Project" -message "Select a Project first."; return }
    set id [lindex $sel 0]
    if {[catch {projectAssociateCurrentExperiment $id} err]} {
        tk_messageBox -parent $w -icon error -title "Project" -message $err
        return
    }
    destroy $w
}

proc ::GX::projectSelectDialog {} {
    set w .gxProjectSelect
    catch {destroy $w}
    toplevel $w
    wm title $w "Select Project"
    wm transient $w .
    ttk::treeview $w.list -columns {name updated} -show headings -selectmode browse -height 10
    $w.list heading name -text "Project"
    $w.list heading updated -text "Updated"
    $w.list column name -width 300 -stretch 1
    $w.list column updated -width 170 -stretch 0
    foreach id [projectIds] {
        $w.list insert {} end -id $id -values [list [projectField $id name] [projectField $id updated_at]]
    }
    ttk::frame $w.buttons
    ttk::button $w.buttons.use -text "Associate" -command [list ::GX::projectSelectDialogAssociate $w]
    ttk::button $w.buttons.cancel -text "Cancel" -command [list destroy $w]
    pack $w.buttons.use $w.buttons.cancel -side left -padx 4
    pack $w.list -fill both -expand 1 -padx 6 -pady 6
    pack $w.buttons -pady {0 8}
    bind $w.list <Double-1> [list ::GX::projectSelectDialogAssociate $w]
    bind $w <Escape> [list destroy $w]
}

proc ::GX::projectOpenExperimentFromList {w} {
    set sel [$w.list selection]
    if {![llength $sel]} return
    set path [lindex [$w.list item [lindex $sel 0] -values] 1]
    if {$path eq "" || ![file isdirectory $path]} {
        tk_messageBox -parent $w -icon error -title "Project Experiments" -message "The recorded Session path is not available:\n$path"
        return
    }
    if {[catch {openSessionPath $path} err]} {
        tk_messageBox -parent $w -icon error -title "Project Experiments" -message $err
        return
    }
    destroy $w
}

proc ::GX::projectExperimentsDialog {} {
    set id [projectCurrentId]
    if {$id eq "" || ![projectExists $id]} { tk_messageBox -icon info -title "Project Experiments" -message "No persistent Project is selected."; return }
    set w .gxProjectExperiments
    catch {destroy $w}
    toplevel $w
    wm title $w "Project Experiments — [projectField $id name]"
    wm transient $w .
    ttk::treeview $w.list -columns {name path experiment_id} -show headings -selectmode browse -height 12
    foreach {col label width} {name Experiment 220 path {Session path} 460 experiment_id {Experiment ID} 260} {
        $w.list heading $col -text $label
        $w.list column $col -width $width -stretch [expr {$col eq "path" ? 1 : 0}]
    }
    set n 0
    foreach d [projectListExperiments $id] {
        incr n
        $w.list insert {} end -id "row$n" -values [list [dict get $d experiment_name] [dict get $d session_path] [dict get $d experiment_id]]
    }
    ttk::frame $w.buttons
    ttk::button $w.buttons.open -text "Open Session" -command [list ::GX::projectOpenExperimentFromList $w]
    ttk::button $w.buttons.close -text "Close" -command [list destroy $w]
    pack $w.buttons.open $w.buttons.close -side left -padx 4
    pack $w.list -fill both -expand 1 -padx 6 -pady 6
    pack $w.buttons -pady {0 8}
    bind $w.list <Double-1> [list ::GX::projectOpenExperimentFromList $w]
    bind $w <Escape> [list destroy $w]
}

proc ::GX::projectDetachCurrentExperimentDialog {} {
    if {[projectCurrentId] eq ""} return
    set answer [tk_messageBox -icon question -type yesno -title "Detach Project" -message "Remove this Experiment from the current Project?\n\nNo Session or scientific data will be deleted."]
    if {$answer eq "yes"} { projectDetachCurrentExperiment }
}

# Add Project state to defaults without changing the historical free-text field.
proc ::GX::defaults_before_configuration_v1 {} {
    variable cfg
    ::GX::defaults_before_project_api_v1
    set cfg(experiment_id) ""
    set cfg(experiment_project_id) ""
    set cfg(experiment_project_legacy) ""
    catch {projectLoadRegistry}
}

# Manifest Format 2 keeps experiment.project for backward compatibility and adds
# an unambiguous Project link section. Historical free text is never used as an
# internal Project identity.
proc ::GX::manifestStringV2_before_instrument_library_v1 {} {
    variable cfg
    set out [::GX::manifestStringV2_before_project_api_v1]
    append out "\n\[project_link\]\n"
    appendKV out api_version 1
    foreach key {experiment_id experiment_project_id experiment_project_legacy} {
        set value [expr {[info exists cfg($key)] ? $cfg($key) : ""}]
        switch -- $key {
            experiment_id { appendKV out experiment_id $value }
            experiment_project_id { appendKV out project_id $value }
            experiment_project_legacy { appendKV out legacy_project $value }
        }
    }
    return $out
}

proc ::GX::loadManifestV2_before_instrument_library_v1 {path} {
    variable cfg
    ::GX::loadManifestV2_before_project_api_v1 $path
    set d [parseIni $path]
    set cfg(experiment_id) [expr {[dict exists $d project_link.experiment_id] ? [dict get $d project_link.experiment_id] : ""}]
    set cfg(experiment_project_id) [expr {[dict exists $d project_link.project_id] ? [dict get $d project_link.project_id] : ""}]
    if {[dict exists $d project_link.legacy_project]} {
        set cfg(experiment_project_legacy) [dict get $d project_link.legacy_project]
    } elseif {$cfg(experiment_project_id) eq "" && [string trim $cfg(experiment_project)] ne ""} {
        # Old manifests remain old free text until the user explicitly selects a
        # persistent Project. This prevents accidental name-based migration.
        set cfg(experiment_project_legacy) $cfg(experiment_project)
    } else {
        set cfg(experiment_project_legacy) ""
    }
    if {$cfg(experiment_project_id) ne "" && [projectExists $cfg(experiment_project_id)]} {
        set cfg(experiment_project) [projectField $cfg(experiment_project_id) name $cfg(experiment_project)]
    }
    catch {projectRefreshExperimentUi}
}

# Keep the current Session manifest and the user-local membership index aligned.
proc ::GX::saveCurrentSessionConfig {} {
    variable cfg
    variable currentSession
    set pid [projectCurrentId]
    if {$pid ne "" && [projectExists $pid] && $currentSession ne "" && [file isdirectory $currentSession]} {
        set eid [projectEnsureCurrentExperimentId]
        set cfg(experiment_project) [projectField $pid name]
        projectAssociateExperiment $pid $eid $currentSession $cfg(experiment_name)
    }
    return [::GX::saveCurrentSessionConfig_before_project_api_v1]
}

proc ::GX::openSessionPath_before_configuration_v1 {path} {
    set result [::GX::openSessionPath_before_project_api_v1 $path]
    catch {projectSynchronizeCurrentExperiment}
    return $result
}

# Replace only the historical free-text Project row in Experiment. The rest of
# the established Experiment notebook is built by the previous implementation.
proc ::GX::rebuildNativeExperimentGui {} {
    variable ui
    ::GX::rebuildNativeExperimentGui_before_project_api_v1
    set f .top.nb.exp
    if {![winfo exists $f]} return
    catch {destroy $f.l1}
    catch {destroy $f.e1}
    ttk::label $f.projectLabel -text "Project"
    ttk::frame $f.project
    ttk::label $f.project.value -textvariable ::GX::ui(experimentProjectDisplay) -anchor w -width 30
    ttk::button $f.project.new -text "New..." -command {::GX::projectMetadataDialog new}
    ttk::button $f.project.edit -text "Edit..." -command {::GX::projectMetadataDialog edit}
    pack $f.project.value -side left -fill x -expand 1 -padx {0 5}
    # Phase 1 removes only these GUI entry points. Project association,
    # detachment and navigation remain supported by their unchanged public APIs.
    pack $f.project.new $f.project.edit -side left -padx 2
    grid $f.projectLabel -row 1 -column 0 -sticky e -padx 5 -pady 3
    grid $f.project -row 1 -column 1 -columnspan 2 -sticky ew -padx 5 -pady 3
    projectRefreshExperimentUi
}
