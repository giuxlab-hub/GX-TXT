# GX-TXT Resource Lifecycle API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
# Destructive operations validate authoritative state again at commit time.

namespace eval ::GX { variable resourceLifecycleApiVersion 1 }

proc ::GX::resourceLifecycleScriptDependencies {reference} {
    if {![regexp {^(user|session):[A-Za-z][A-Za-z0-9_.-]*$} $reference]} {
        error "A qualified user:<id> or session:<id> script reference is required."
    }
    set dependencies {}
    foreach moduleId {analysis.octave_script analysis.python_script} {
        if {[info exists ::GX::moduleCfg($moduleId,registered_script)] &&
                $::GX::moduleCfg($moduleId,registered_script) eq $reference &&
                (![info exists ::GX::moduleCfg($moduleId,source_mode)] ||
                 $::GX::moduleCfg($moduleId,source_mode) eq "registered_script")} {
            lappend dependencies "Current Analysis configuration: $moduleId"
        }
    }
    if {[info exists ::GX::currentSession] && $::GX::currentSession ne ""} {
        set manifest [file join $::GX::currentSession metadata manifest.ini]
        if {[file isfile $manifest]} {
            set ini [parseIni $manifest]
            foreach moduleId {analysis.octave_script analysis.python_script} {
                set key "module_config.$moduleId.registered_script"
                set mode "module_config.$moduleId.source_mode"
                if {[dict exists $ini $key] && [dict get $ini $key] eq $reference &&
                        (![dict exists $ini $mode] || [dict get $ini $mode] eq "registered_script")} {
                    lappend dependencies "Saved Session Analysis configuration: $moduleId"
                }
            }
        }
    }
    return [lsort -unique $dependencies]
}

proc ::GX::resourceLifecycleDeleteScript {reference} {
    set metadata [scriptRegistryDescribe $reference]
    set dependencies [resourceLifecycleScriptDependencies $reference]
    if {[llength $dependencies]} {
        error "Cannot delete [dict get $metadata scope] script '[dict get $metadata name]' ($reference). Active dependencies:\n[join $dependencies \n]"
    }
    scriptRegistryRemove $reference
    return $reference
}

proc ::GX::resourceLifecycleSessionGuard {path} {
    if {[string trim $path] eq ""} { error "Select a Session path." }
    if {![file isdirectory $path] || [file type $path] eq "link"} {
        error "Selected path is not a Session directory: $path"
    }
    set normalized [file normalize $path]
    set forbidden [list [file normalize /] [file normalize [pwd]] [file normalize $::GX::scriptDir]]
    if {[info exists ::env(HOME)] && $::env(HOME) ne ""} {
        lappend forbidden [file normalize $::env(HOME)]
    }
    if {[info exists ::GX::cfg(output_root)] && [string trim $::GX::cfg(output_root)] ne ""} {
        lappend forbidden [file normalize $::GX::cfg(output_root)]
    }
    foreach id [projectIds] { lappend forbidden [projectStoragePath $id] [file join [projectStoragePath $id] Sessions] }
    if {$normalized in $forbidden} { error "Refusing to delete a root or Project storage directory: $normalized" }
    set manifest [file join $normalized metadata manifest.ini]
    if {![file isdirectory [file join $normalized channels]] || ![file isfile $manifest]} {
        error "Selected directory is not a complete GX-TXT Session: $normalized"
    }
    set ini [parseIni $manifest]
    if {![dict exists $ini pipeline.format] || [dict get $ini pipeline.format] ne "2"} {
        error "Selected directory does not contain a GX-TXT Format 2 Session manifest: $normalized"
    }
    return $normalized
}

proc ::GX::resourceLifecycleSessionInspect {path} {
    set path [resourceLifecycleSessionGuard $path]
    set ini [parseIni [file join $path metadata manifest.ini]]
    set source [expr {[dict exists $ini pipeline.input_csv] ? [dict get $ini pipeline.input_csv] : ""}]
    set external 0
    if {$source ne "" && [file pathtype $source] eq "absolute" &&
            [string first "$path/" [file normalize $source]] != 0} { set external 1 }
    return [dict create name [file tail $path] path $path external_source_count $external]
}

proc ::GX::resourceLifecycleSessionCandidates {} {
    set roots {}
    if {[info exists ::GX::cfg(output_root)] && [file isdirectory $::GX::cfg(output_root)]} {
        lappend roots [file normalize $::GX::cfg(output_root)]
    }
    foreach id [projectIds] {
        set root [file join [projectStoragePath $id] Sessions]
        if {[file isdirectory $root]} { lappend roots $root }
    }
    set paths {}
    foreach root [lsort -unique $roots] {
        foreach path [glob -nocomplain -directory $root *] {
            if {![file isdirectory $path]} continue
            if {![catch {set info [resourceLifecycleSessionInspect $path]}]} {
                dict set paths [dict get $info path] $info
            }
        }
    }
    foreach id [projectIds] {
        foreach membership [projectListExperiments $id] {
            set path [dict get $membership session_path]
            if {$path ne "" && ![catch {set info [resourceLifecycleSessionInspect $path]}]} {
                dict set paths [dict get $info path] $info
            }
        }
    }
    if {[info exists ::GX::currentSession] && $::GX::currentSession ne "" &&
            ![catch {set info [resourceLifecycleSessionInspect $::GX::currentSession]}]} {
        dict set paths [dict get $info path] $info
    }
    set result {}
    foreach path [lsort -dictionary [dict keys $paths]] { lappend result [dict get $paths $path] }
    return $result
}

proc ::GX::resourceLifecycleDeleteSession {path} {
    variable projectMembership
    variable currentSession
    variable cfg
    set info [resourceLifecycleSessionInspect $path]
    set path [dict get $info path]
    set previous [array get projectMembership]
    set associated {}
    foreach id [projectIds] {
        foreach item [projectListExperiments $id] {
            if {[dict get $item session_path] eq $path} { lappend associated [dict get $item experiment_id] }
        }
    }
    foreach eid $associated {
        foreach key [array names projectMembership "$eid,*"] { unset projectMembership($key) }
    }
    if {[catch {projectSaveRegistry} problem options]} {
        array unset projectMembership *; array set projectMembership $previous
        return -options $options "Session deletion refused: Project association cleanup failed: $problem"
    }
    set wasCurrent [expr {$currentSession ne "" && [file normalize $currentSession] eq $path}]
    if {$wasCurrent} {
        set currentSession ""
        foreach key {experiment_id experiment_project_id experiment_project experiment_project_legacy} {
            set cfg($key) ""
        }
    }
    if {[catch {file delete -force -- $path} problem options]} {
        # If recursive removal failed, do not recreate a link to a possibly
        # partial Session. Report the exact path for manual recovery.
        return -options $options "Session deletion was incomplete at $path. Project links were detached; inspect the remaining tree: $problem"
    }
    if {$wasCurrent} {
        catch {projectRefreshExperimentUi}
        catch {updateSessionUi}
        catch {sessionFileExplorerPopulate}
        catch {refreshResults}
        catch {refreshGraphs}
        catch {scriptAnalysisRefresh}
    }
    catch {projectGuiRefresh}
    return $info
}

proc ::GX::resourceLifecycleProjectSessions {id} {
    set paths {}
    foreach item [projectListExperiments $id] {
        set path [dict get $item session_path]
        if {$path ne "" && [file isdirectory $path]} { dict set paths [file normalize $path] 1 }
    }
    set root [file join [projectStoragePath $id] Sessions]
    if {[file isdirectory $root]} {
        foreach path [glob -nocomplain -directory $root *] {
            if {[file isdirectory $path]} { dict set paths [file normalize $path] 1 }
        }
    }
    if {[info exists ::GX::currentSession] && $::GX::currentSession ne "" &&
            [projectCurrentId] eq $id} { dict set paths [file normalize $::GX::currentSession] 1 }
    return [lsort -dictionary [dict keys $paths]]
}

proc ::GX::resourceLifecycleProjectInspect {id} {
    if {![projectExists $id]} { error "Unknown Project '$id'." }
    set storage [projectStoragePath $id]
    set protected [list [file normalize /] [file normalize [pwd]] [file normalize $::GX::scriptDir]]
    if {[info exists ::env(HOME)] && $::env(HOME) ne ""} { lappend protected [file normalize $::env(HOME)] }
    if {[info exists ::GX::cfg(output_root)] && [string trim $::GX::cfg(output_root)] ne ""} {
        lappend protected [file normalize $::GX::cfg(output_root)]
    }
    if {$storage in $protected || ([file exists $storage] && [file type $storage] eq "link")} {
        error "Project storage path is unsafe: $storage"
    }
    set metadata [file join $storage project.ini]
    if {[file isfile $metadata]} {
        set descriptor [parseIni $metadata]
        if {![dict exists $descriptor project.id] || [dict get $descriptor project.id] ne $id} {
            error "Project metadata identity disagrees with the registry at $metadata"
        }
    }
    set extras {}
    if {[file isdirectory $storage]} {
        foreach path [glob -nocomplain -directory $storage * .*] {
            set name [file tail $path]
            if {$name in {. .. project.ini Sessions}} continue
            lappend extras $name
        }
    }
    return [dict create id $id name [projectField $id name] path $storage \
        session_count [llength [resourceLifecycleProjectSessions $id]] \
        experiment_count [llength [projectListExperiments $id]] \
        resource_count [expr {[file isfile $metadata] + [llength $extras]}] unexpected_resources $extras]
}

proc ::GX::resourceLifecycleReadBytes {path} {
    set fd [open $path rb]
    try { return [read $fd] } finally { close $fd }
}

proc ::GX::resourceLifecycleWriteBytes {path bytes} {
    set tmp "${path}.tmp.[pid].[clock clicks]"
    set fd [open $tmp wb]
    try { puts -nonewline $fd $bytes } finally { close $fd }
    file rename -force -- $tmp $path
}

proc ::GX::resourceLifecycleDetachedManifest {path projectId} {
    set ini [parseIni $path]
    set linked [expr {[dict exists $ini project_link.project_id] ? [dict get $ini project_link.project_id] : ""}]
    set named [expr {[dict exists $ini experiment.project] ? [dict get $ini experiment.project] : ""}]
    if {$linked ne $projectId && ($linked ne "" || $named ne [projectField $projectId name])} { return "" }
    set original [resourceLifecycleReadBytes $path]
    set section ""
    set result ""
    set found 0
    foreach line [split $original "\n"] {
        if {[regexp {^\[([^]]+)\]\r?$} $line -> name]} { set section $name }
        if {$linked eq $projectId && $section eq "project_link" && [regexp {^project_id=} $line]} {
            set line "project_id="
            set found 1
        } elseif {$section eq "experiment" && [regexp {^project=} $line]} {
            set line "project="
            set found 1
        }
        append result $line "\n"
    }
    if {!$found} { error "Project link cannot be detached safely from $path" }
    return [string range $result 0 end-1]
}

proc ::GX::resourceLifecycleDeleteProject {id} {
    variable projectCatalog
    variable projectMembership
    variable cfg
    set info [resourceLifecycleProjectInspect $id]
    if {[llength [dict get $info unexpected_resources]]} {
        error "Project owns unclassified resources: [join [dict get $info unexpected_resources] {, }]. Move or resolve them before deletion."
    }
    set manifests [dict create]
    foreach session [resourceLifecycleProjectSessions $id] {
        set session [resourceLifecycleSessionGuard $session]
        set path [file join $session metadata manifest.ini]
        set ini [parseIni $path]
        if {[dict exists $ini project_link.project_id] &&
                [dict get $ini project_link.project_id] ne "" &&
                [dict get $ini project_link.project_id] ne $id} {
            error "Session belongs to another Project: $session"
        }
        set revised [resourceLifecycleDetachedManifest $path $id]
        if {$revised ne ""} { dict set manifests $path [list [resourceLifecycleReadBytes $path] $revised] }
    }
    set oldProjects [array get projectCatalog]
    set oldMembership [array get projectMembership]
    set registryPath [projectRegistryPath]
    set oldRegistry [expr {[file isfile $registryPath] ? [resourceLifecycleReadBytes $registryPath] : ""}]
    set metadata [file join [dict get $info path] project.ini]
    set oldMetadata [expr {[file isfile $metadata] ? [resourceLifecycleReadBytes $metadata] : ""}]
    set committed {}
    if {[catch {
        dict for {path pair} $manifests {
            resourceLifecycleWriteBytes $path [lindex $pair 1]
            lappend committed $path
        }
        foreach key [array names projectMembership "*,project_id"] {
            set eid [string range $key 0 end-11]
            if {$projectMembership($key) eq $id} {
                foreach field [array names projectMembership "$eid,*"] { unset projectMembership($field) }
            }
        }
        foreach key [array names projectCatalog "$id,*"] { unset projectCatalog($key) }
        projectSaveRegistry
        if {[file exists $metadata]} { file delete -- $metadata }
    } problem options]} {
        array unset projectCatalog *; array set projectCatalog $oldProjects
        array unset projectMembership *; array set projectMembership $oldMembership
        set rollbackErrors {}
        foreach path $committed {
            if {[catch {resourceLifecycleWriteBytes $path [lindex [dict get $manifests $path] 0]} reason]} {
                lappend rollbackErrors "$path: $reason"
            }
        }
        if {$oldRegistry ne "" && [catch {resourceLifecycleWriteBytes $registryPath $oldRegistry} reason]} {
            lappend rollbackErrors "$registryPath: $reason"
        }
        if {$oldMetadata ne "" && ![file exists $metadata] &&
                [catch {resourceLifecycleWriteBytes $metadata $oldMetadata} reason]} {
            lappend rollbackErrors "$metadata: $reason"
        }
        if {[llength $rollbackErrors]} {
            return -options $options "Project deletion failed and rollback is incomplete. Inspect these authoritative paths: [join $rollbackErrors {; }]. Initial failure: $problem"
        }
        return -options $options "Project deletion refused; association cleanup was rolled back: $problem"
    }
    if {[info exists cfg(experiment_project_id)] && $cfg(experiment_project_id) eq $id} {
        set cfg(experiment_project_id) ""
        set cfg(experiment_project) ""
        set cfg(experiment_project_legacy) ""
        catch {projectRefreshExperimentUi}
    }
    catch {projectGuiRefresh}
    return $info
}

# Module Reset discards only the Session's named derived cache. It never
# deletes analysis outputs, plots, documents, scripts, or Session metadata.
proc ::GX::resourceLifecycleModuleReset {moduleId} {
    if {[moduleField $moduleId descriptor ""] eq ""} { error "Unknown module '$moduleId'." }
    if {![info exists ::GX::currentSession] || $::GX::currentSession eq ""} {
        error "Open a Session before resetting module runtime."
    }
    set session [resourceLifecycleSessionGuard $::GX::currentSession]
    set cache [file join $session cache $moduleId]
    foreach ref {analysis.octave_script analysis.python_script} {
        if {![info exists ::GX::moduleCfg($ref,source_mode)] ||
                $::GX::moduleCfg($ref,source_mode) ne "registered_script" ||
                ![info exists ::GX::moduleCfg($ref,registered_script)]} continue
        set selected $::GX::moduleCfg($ref,registered_script)
        if {$selected ne "" && [catch {scriptRegistryDescribe $selected} reason]} {
            error "Module runtime reset found a missing active Script reference '$selected' in $ref: $reason. Select a valid script or clear the Analysis binding."
        }
    }
    set project [projectCurrentId]
    if {$project ne "" && ![projectExists $project]} {
        error "Module runtime reset found a missing Project '$project'. Detach or repair the Session Project link."
    }
    if {[file exists $cache]} {
        if {[file type $cache] eq "link"} { error "Refusing to follow a linked module cache: $cache" }
        file delete -force -- $cache
    }
    set refreshErrors {}
    if {[llength [info commands winfo]]} {
        foreach command {scriptAnalysisRefresh scriptWorkspaceRefreshChoices sessionFileExplorerPopulate projectGuiRefresh refreshGraphs refreshResults refreshAnalysisStatus refreshModuleCatalog} {
            if {[llength [info commands ::GX::$command]] && [catch {::GX::$command} reason]} {
                lappend refreshErrors "$command: $reason"
            }
        }
    }
    if {[llength $refreshErrors]} {
        error "Module cache was reset, but some resource views did not refresh. Reopen the Session. Details: [join $refreshErrors {; }]"
    }
    return [dict create module_id $moduleId session $session cache_reset $cache persistent_state preserved]
}
