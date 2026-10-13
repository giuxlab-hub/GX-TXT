# SPDX-License-Identifier: GPL-3.0-or-later
# Additive organization/provenance, using existing Project, Manifest, Portable and Lifecycle authorities.
namespace eval ::GX {variable projectTransactionDepth 0}
proc ::GX::_projectJournal {} {return [file join [file dirname [projectRegistryPath]] project_transaction.json]}
proc ::GX::_projectTransactionHost {action args} {
    set python [auto_execok python3];if {$python eq {}} {set python [auto_execok python]}
    if {$python eq {}} {error {Project transaction recovery requires Python.}}
    return [exec {*}$python -B [file join $::GX::scriptDir core python project_transactions.py] $action [_projectJournal] [pid] {*}$args]
}
proc ::GX::_projectAtomic {paths script {moves {}}} {
    variable projectTransactionDepth
    if {$projectTransactionDepth} {return [uplevel 1 $script]}
    set saved {};foreach a {projectCatalog projectMembership cfg} {dict set saved $a [array get ::GX::$a]}
    set arguments [lsort -unique [concat [list [projectRegistryPath]] $paths]]
    if {$moves ne {}} {lappend arguments --move {*}$moves}
    _projectTransactionHost begin {*}$arguments
    incr projectTransactionDepth
    try {
        set result [uplevel 1 $script]
        _projectTransactionHost commit
        return $result
    } on error {message options} {
        set rollback [catch {_projectTransactionHost rollback} problem]
        dict for {a values} $saved {array unset ::GX::$a *;array set ::GX::$a $values}
        catch {projectRefreshExperimentUi};catch {updateSessionUi}
        if {$rollback} {append message "\nRollback requires recovery: $problem"}
        return -options $options $message
    } finally {incr projectTransactionDepth -1}
}
proc ::GX::_projectIniWrite {path data} {
    set out {};set last {}
    dict for {full value} $data {
        if {![regexp {^(.+)\.([^.]+)$} $full -> section key]} {error "Invalid INI key '$full'."}
        if {$section ne $last} {append out "\n\[$section\]\n";set last $section}
        appendKV out $key $value
    }
    resourceLifecycleWriteBytes $path [encoding convertto utf-8 $out]
}
proc ::GX::_originUnknown {} {return [dict create version 1 creator_installation unknown created_at {} creation_kind unknown parent {} events {}]}
proc ::GX::_originCreate {kind {parent {}}} {
    return [dict create version 1 creator_installation [installationIdentityCurrent] created_at [projectTimestamp] creation_kind $kind parent $parent events {}]
}
proc ::GX::sessionOriginRead {{session {}}} {
    set session [_sessionInspectionRequire $session]
    set data [parseIni [file join $session metadata manifest.ini]]
    set origin [datasetPublicationV2DictDefault $data origin.definition {}]
    if {$origin eq {}} {return [_originUnknown]}
    if {[catch {dict size $origin}] || ![dict exists $origin creator_installation]} {error {Invalid declared Session origin.}}
    return $origin
}
proc ::GX::projectOriginRead {id} {
    if {![projectExists $id]} {error "Unknown Project '$id'."}
    set origin [projectField $id origin {}]
    if {$origin eq {}} {return [_originUnknown]}
    return $origin
}
proc ::GX::projectDefaultId {} {return project-default-unassigned}
proc ::GX::projectEnsureDefault {} {
    projectEnsureRegistryLoaded
    set id [projectDefaultId]
    if {[projectExists $id]} {return $id}
    set storage [file join [file dirname [projectRegistryPath]] default_project]
    _projectAtomic [list [file join $storage project.ini]] {
        foreach {key value} [list id $id name {Default / Unassigned} description {Built-in organization for Sessions outside named Projects.} tags {} author {} storage_path $storage created_at [projectTimestamp] updated_at [projectTimestamp] origin [_originCreate project]] {set ::GX::projectCatalog($id,$key) $value}
        projectSaveRegistry;projectWriteMetadata $id
    }
    return $id
}
proc ::GX::projectExperimentResolve {eid} {
    projectEnsureRegistryLoaded
    set path [projectMembershipField $eid session_path {}]
    if {$path eq {} || ![file isdirectory $path]} {error "Experiment '$eid' has a missing recorded Session: $path"}
    set path [_sessionInspectionRequire $path]
    if {![file isdirectory [file join $path channels]]} {error {Recorded path is not a GX-TXT Session.}}
    set data [parseIni [file join $path metadata manifest.ini]]
    if {[datasetPublicationV2DictDefault $data project_link.experiment_id {}] ne $eid} {error {Recorded Experiment identity disagrees with the Session Manifest.}}
    if {[datasetPublicationV2DictDefault $data project_link.project_id {}] ne [projectMembershipField $eid project_id {}]} {error {Recorded Project membership disagrees with the Session Manifest.}}
    return $path
}
proc ::GX::projectExperimentReassign {eid projectId} {
    if {![projectExists $projectId]} {error "Unknown Project '$projectId'."}
    set session [projectExperimentResolve $eid];set manifest [file join $session metadata manifest.ini]
    _projectAtomic [list $manifest] {
        set data [parseIni $manifest]
        dict set data project_link.project_id $projectId
        # Legacy free text is recoverable even after default reassignment.
        dict set data experiment.project [projectField $projectId name]
        _projectIniWrite $manifest $data
        projectAssociateExperiment $projectId $eid $session [datasetPublicationV2DictDefault $data experiment.name [file tail $session]]
    }
    if {$::GX::currentSession eq $session} {
        set ::GX::cfg(experiment_project_id) $projectId;set ::GX::cfg(experiment_project) [projectField $projectId name]
        projectRefreshExperimentUi;updateSessionUi
    }
    return $projectId
}
proc ::GX::projectExperimentRename {eid name} {
    set name [string trim $name]
    if {$name eq {} || [regexp {[\r\n]} $name]} {error {Enter a nonempty single-line Session/Experiment name.}}
    set session [projectExperimentResolve $eid];set manifest [file join $session metadata manifest.ini]
    _projectAtomic [list $manifest] {
        set data [parseIni $manifest];dict set data experiment.name $name
        _projectIniWrite $manifest $data
        projectAssociateExperiment [projectMembershipField $eid project_id] $eid $session $name
    }
    if {$::GX::currentSession eq $session} {set ::GX::cfg(experiment_name) $name;updateSessionUi;projectRefreshExperimentUi}
    return $eid
}
# Existing public detach contracts become a nondestructive reassignment to Default.
proc ::GX::projectDetachExperiment {experimentId} {return [projectExperimentReassign $experimentId [projectEnsureDefault]]}
proc ::GX::projectDetachCurrentExperiment {} {return [projectDetachExperiment [projectEnsureCurrentExperimentId]]}
proc ::GX::projectAssociateCurrentExperiment {projectId} {
    set session [_sessionInspectionRequire];set eid [projectEnsureCurrentExperimentId]
    set manifest [file join $session metadata manifest.ini]
    _projectAtomic [list $manifest] {
        set data [parseIni $manifest]
        if {[datasetPublicationV2DictDefault $data project_link.project_id {}] eq {} && ![dict exists $data project_link.legacy_project]} {dict set data project_link.legacy_project [datasetPublicationV2DictDefault $data experiment.project {}]}
        dict set data project_link.experiment_id $eid;dict set data project_link.project_id $projectId
        dict set data experiment.project [projectField $projectId name]
        _projectIniWrite $manifest $data
        projectAssociateExperiment $projectId $eid $session [datasetPublicationV2DictDefault $data experiment.name [file tail $session]]
    }
    set ::GX::cfg(experiment_project_id) $projectId;set ::GX::cfg(experiment_project) [projectField $projectId name]
    set ::GX::cfg(experiment_project_legacy) [datasetPublicationV2DictDefault $data project_link.legacy_project {}]
    projectRefreshExperimentUi
    return $projectId
}
proc ::GX::_projectEncounterSession {session} {
    set manifest [file join $session metadata manifest.ini];set data [parseIni $manifest]
    set project [datasetPublicationV2DictDefault $data project_link.project_id {}]
    set eid [datasetPublicationV2DictDefault $data project_link.experiment_id {}]
    if {$project ne {} && ![projectExists $project]} {
        # Foreign/missing Project link is kept as provenance and assigned to Default locally.
        set prior $project;set project {}
    } else {set prior {}}
    if {$eid eq {}} {set eid [experimentGenerateId]}
    set recorded [projectMembershipField $eid session_path {}]
    if {$recorded ne {} && [file normalize $recorded] ne [file normalize $session] && [file exists $recorded]} {error {Experiment ID collision: use Portable Import to create an independent organizational identity.}}
    if {$project eq {}} {
        set project [projectEnsureDefault]
        _projectAtomic [list $manifest] {
            dict set data project_link.api_version 1;dict set data project_link.project_id $project;dict set data project_link.experiment_id $eid
            if {[datasetPublicationV2DictDefault $data project_link.legacy_project {}] eq {}} {dict set data project_link.legacy_project [datasetPublicationV2DictDefault $data experiment.project {}]}
            if {$prior ne {}} {dict set data project_link.previous_project_id $prior}
            # Preserve legacy experiment.project text on encounter; identity is additive.
            _projectIniWrite $manifest $data
            projectAssociateExperiment $project $eid $session [datasetPublicationV2DictDefault $data experiment.name [file tail $session]]
        }
    } else {
        _projectAtomic {} {projectAssociateExperiment $project $eid $session [datasetPublicationV2DictDefault $data experiment.name [file tail $session]]}
    }
    if {$::GX::currentSession eq $session} {
        set ::GX::cfg(experiment_id) $eid;set ::GX::cfg(experiment_project_id) $project
        set ::GX::cfg(experiment_name) [datasetPublicationV2DictDefault $data experiment.name [file tail $session]]
        set ::GX::cfg(experiment_project_legacy) [datasetPublicationV2DictDefault $data project_link.legacy_project {}]
        projectRefreshExperimentUi;updateSessionUi
    }
    return $eid
}
# The synchronization callback is used inside legacy opening. Propagate through
# our outer controller below so errors are never silently swallowed by that chain.
proc ::GX::projectSynchronizeCurrentExperiment {} {projectRefreshExperimentUi}
rename ::GX::openSessionPath ::GX::openSessionPath_before_projects083
proc ::GX::openSessionPath {path} {
    set path [file normalize $path]
    # Refuse cross-linked identities before replacing the active Session.
    set data [parseIni [file join $path metadata manifest.ini]]
    set eid [datasetPublicationV2DictDefault $data project_link.experiment_id {}]
    set recorded [projectMembershipField $eid session_path {}]
    if {$eid ne {} && $recorded ne {} && [file normalize $recorded] ne $path && [file exists $recorded]} {error {Experiment ID collision: independent copies must use Portable Import.}}
    set result [openSessionPath_before_projects083 $path]
    if {$::GX::currentSession eq $path} {_projectEncounterSession $path}
    return $result
}
rename ::GX::defaults ::GX::defaults_before_projects083
proc ::GX::defaults {} {defaults_before_projects083;set ::GX::cfg(session_origin) {};projectEnsureDefault}
rename ::GX::manifestStringV2 ::GX::manifestStringV2_before_projects083
proc ::GX::manifestStringV2 {} {
    set out [manifestStringV2_before_projects083]
    set origin [expr {[info exists ::GX::cfg(session_origin)] ? $::GX::cfg(session_origin) : {}}]
    # An existing object's persisted origin wins over configuration-only loads.
    # Creation uses the issued origin only before its first authoritative Manifest.
    if {$::GX::currentSession ne {} && [file isfile [file join $::GX::currentSession metadata manifest.ini]]} {
        set stored [parseIni [file join $::GX::currentSession metadata manifest.ini]]
        set origin [datasetPublicationV2DictDefault $stored origin.definition {}]
    }
    if {$origin ne {}} {append out "\n\[origin\]\n";appendKV out api_version 1;appendKV out definition $origin}
    return $out
}
rename ::GX::loadManifestV2 ::GX::loadManifestV2_before_projects083
proc ::GX::loadManifestV2 {path} {
    set result [loadManifestV2_before_projects083 $path]
    set data [parseIni $path];set ::GX::cfg(session_origin) [datasetPublicationV2DictDefault $data origin.definition {}]
    return $result
}
rename ::GX::makeSession ::GX::makeSession_before_projects083
proc ::GX::makeSession {} {
    # Note-directory initialization may persist a Manifest; issue creation state
    # before that first write, keeping a fresh ID already reserved by New Session.
    set ::GX::cfg(session_origin) [_originCreate session_experiment]
    set eid [expr {[info exists ::GX::cfg(experiment_id)] ? $::GX::cfg(experiment_id) : {}}]
    if {$eid eq {} || [projectMembershipField $eid session_path {}] ne {}} {set ::GX::cfg(experiment_id) [experimentGenerateId]}
    if {[projectCurrentId] eq {}} {set ::GX::cfg(experiment_project_id) [projectEnsureDefault]}
    if {[string trim $::GX::cfg(session_name)] ne {}} {set ::GX::cfg(experiment_name) $::GX::cfg(session_name)}
    set result [makeSession_before_projects083]
    if {[string trim $::GX::cfg(experiment_name)] eq {}} {set ::GX::cfg(experiment_name) [file tail $result]}
    return $result
}

# Current Manifest persistence keeps membership in the same recoverable transaction.
rename ::GX::writeManifest ::GX::writeManifest_before_projects083
proc ::GX::writeManifest {path} {
    if {$::GX::currentSession ne {} && [file normalize $path] eq [file join $::GX::currentSession metadata manifest.ini]} {
        return [_projectAtomic [list $path] {
            if {[projectCurrentId] eq {}} {set ::GX::cfg(experiment_project_id) [projectEnsureDefault]}
            projectAssociateExperiment [projectCurrentId] [projectEnsureCurrentExperimentId] $::GX::currentSession $::GX::cfg(experiment_name)
            set state [manifestString]
            resourceLifecycleWriteBytes $path [encoding convertto utf-8 $state]
            set written {}
        }]
    }
    set state [manifestString]
    resourceLifecycleWriteBytes $path [encoding convertto utf-8 $state]
    return {}
}
rename ::GX::sessionPersistenceCommit ::GX::sessionPersistenceCommit_before_projects083
proc ::GX::sessionPersistenceCommit {} {
    set session [_sessionInspectionRequire];set path [file join $session metadata manifest.ini]
    return [_projectAtomic [list $path] {
        projectAssociateExperiment [projectCurrentId] [projectEnsureCurrentExperimentId] $session $::GX::cfg(experiment_name)
        sessionPersistenceCommit_before_projects083
    }]
}
proc ::GX::projectExportExperiment {eid archive} {return [sessionPortableExport [projectExperimentResolve $eid] $archive]}
proc ::GX::projectImportExperiment {projectId archive destination} {
    if {![projectExists $projectId]} {error {Select an existing receiving Project.}}
    set destination [file normalize $destination]
    if {[file exists $destination]} {error {Import destination already exists; it will never be overwritten.}}
    foreach registeredProject [projectIds] {
        foreach record [projectListExperiments $registeredProject] {
            set owned [dict get $record session_path]
            if {$owned ne {} && [_datasetDeletePathWithin $destination $owned]} {error {Import destination must be outside every existing registered Session.}}
        }
    }
    set stage [file join [file dirname $destination] .gxtxt-import-[file tail $destination]-[pid]-[clock clicks]]
    set result [sessionPortableStageImport $archive $destination $stage]
    try {
        set manifest [file join $stage metadata manifest.ini];set data [parseIni $manifest]
        set origin [sessionOriginRead $stage]
        set sourceEid [datasetPublicationV2DictDefault $data project_link.experiment_id {}]
        set sourceProject [datasetPublicationV2DictDefault $data project_link.project_id {}]
        set eid [experimentGenerateId]
        dict lappend origin events [dict create kind import installation_id [installationIdentityCurrent] at [projectTimestamp] source_experiment_id $sourceEid source_project_id $sourceProject]
        dict set data origin.api_version 1;dict set data origin.definition $origin
        dict set data project_link.api_version 1;dict set data project_link.experiment_id $eid;dict set data project_link.project_id $projectId
        dict set data project_link.imported_experiment_id $sourceEid;dict set data project_link.imported_project_id $sourceProject
        dict set data experiment.project [projectField $projectId name]
        _projectAtomic [list $manifest] {
            _projectIniWrite $manifest $data
            projectAssociateExperiment $projectId $eid $destination [datasetPublicationV2DictDefault $data experiment.name [file tail $destination]]
            file rename -- $stage $destination
        } [list $stage $destination]
    } on error {message options} {
        # Only the uniquely owned private import staging is removed on failure.
        if {[file exists $stage]} {file delete -force -- $stage}
        return -options $options $message
    }
    dict set result session $destination;dict set result destination $destination
    dict set result experiment_id $eid;dict set result project_id $projectId;dict set result origin $origin
    return $result
}
rename ::GX::sessionPortableImport ::GX::sessionPortableImport_before_projects083
proc ::GX::sessionPortableImport {archive destination} {return [projectImportExperiment [projectEnsureDefault] $archive $destination]}
proc ::GX::projectExperimentDelete {eid} {
    set session [projectExperimentResolve $eid]
    return [resourceLifecycleDeleteSession $session]
}
# Preserve Resource Lifecycle checks, add reversible quarantine before membership
# commit so a failed deletion never destroys part of the scientific Session.
rename ::GX::resourceLifecycleDeleteSession ::GX::resourceLifecycleDeleteSession_before_projects083
proc ::GX::resourceLifecycleDeleteSession {path} {
    set info [resourceLifecycleSessionInspect $path];set path [dict get $info path]
    set recoveryRoot [file join [file dirname $path] .gxtxt-deleted-sessions];file mkdir $recoveryRoot
    set recovery [file join $recoveryRoot [file tail $path]-[clock clicks]]
    _projectAtomic {} {
        file rename -- $path $recovery
        foreach id [projectIds] {
            foreach record [projectListExperiments $id] {
                if {[dict get $record session_path] eq $path} {
                    set eid [dict get $record experiment_id]
                    foreach key [array names ::GX::projectMembership "$eid,*"] {unset ::GX::projectMembership($key)}
                }
            }
        }
        projectSaveRegistry
    } [list $path $recovery]
    if {$::GX::currentSession eq $path} {
        set root $::GX::cfg(output_root);set export $::GX::cfg(export_dir)
        if {[llength [info commands winfo]]} {catch {sessionInstrumentCloseNotes}}
        set ::GX::currentSession {}
        defaults;loadModuleCatalog
        set ::GX::cfg(output_root) $root;set ::GX::cfg(export_dir) $export
        updateSessionUi
        catch {refreshNativeInstrumentationGui};catch {refreshNativeVariablesGui}
        catch {sessionFileExplorerPopulate};catch {refreshResults};catch {refreshGraphs};catch {scriptAnalysisRefresh}
    }
    dict set info recovery_path $recovery
    catch {projectGuiRefresh};return $info
}
rename ::GX::resourceLifecycleDeleteProject ::GX::resourceLifecycleDeleteProject_before_projects083
proc ::GX::resourceLifecycleDeleteProject {id} {
    if {$id eq [projectDefaultId]} {error {The built-in Default / Unassigned Project cannot be deleted.}}
    set info [resourceLifecycleProjectInspect $id]
    if {[dict get $info unexpected_resources] ne {}} {error {Resolve unclassified Project resources before deletion.}}
    set records [projectListExperiments $id];set paths [list [file join [projectStoragePath $id] project.ini]]
    foreach record $records {lappend paths [file join [projectExperimentResolve [dict get $record experiment_id]] metadata manifest.ini]}
    _projectAtomic $paths {
        foreach record $records {projectExperimentReassign [dict get $record experiment_id] [projectEnsureDefault]}
        foreach key [array names ::GX::projectCatalog "$id,*"] {unset ::GX::projectCatalog($key)}
        projectSaveRegistry
        set metadata [lindex $paths 0];if {[file exists $metadata]} {file delete -- $metadata}
    }
    catch {projectRefreshExperimentUi};return $info
}
rename ::GX::projectUpdate ::GX::projectUpdate_before_projects083
proc ::GX::projectUpdate {id fields} {
    if {$id eq [projectDefaultId]} {error {The built-in Default Project metadata is managed by CORE.}}
    return [_projectAtomic [list [file join [projectStoragePath $id] project.ini]] {projectUpdate_before_projects083 $id $fields}]
}
rename ::GX::projectAssociateExperiment ::GX::projectAssociateExperiment_before_projects083
proc ::GX::projectAssociateExperiment {projectId experimentId sessionPath experimentName} {
    if {![projectExists $projectId]} {error "Unknown Project '$projectId'."}
    if {$::GX::projectTransactionDepth} {return [projectAssociateExperiment_before_projects083 $projectId $experimentId $sessionPath $experimentName]}
    set manifest [file join $sessionPath metadata manifest.ini]
    if {![file isfile $manifest]} {error {Persist a valid Session Manifest before associating its Experiment.}}
    return [_projectAtomic [list $manifest] {
        set data [parseIni $manifest]
        set savedId [datasetPublicationV2DictDefault $data project_link.experiment_id {}]
        if {$savedId ne {} && $savedId ne $experimentId} {error {Experiment identity disagrees with Session Manifest.}}
        set prior [projectMembershipField $experimentId session_path {}]
        if {$prior ne {} && [file normalize $prior] ne [file normalize $sessionPath] && [file exists $prior]} {error {Experiment ID collision.}}
        if {[datasetPublicationV2DictDefault $data project_link.project_id {}] eq {} && ![dict exists $data project_link.legacy_project]} {dict set data project_link.legacy_project [datasetPublicationV2DictDefault $data experiment.project {}]}
        dict set data project_link.api_version 1;dict set data project_link.experiment_id $experimentId;dict set data project_link.project_id $projectId
        _projectIniWrite $manifest $data
        projectAssociateExperiment_before_projects083 $projectId $experimentId $sessionPath $experimentName
    }]
}
rename ::GX::projectSessionsRoot ::GX::projectSessionsRoot_before_projects083
proc ::GX::projectSessionsRoot {id} {
    if {$id eq [projectDefaultId] && [info exists ::GX::cfg(output_root)] && [string trim $::GX::cfg(output_root)] ne {}} {
        set root [file normalize $::GX::cfg(output_root)];file mkdir $root;return $root
    }
    return [projectSessionsRoot_before_projects083 $id]
}
rename ::GX::createNewSession ::GX::createNewSession_before_projects083
proc ::GX::createNewSession {name {projectId {}}} {
    set priorSession $::GX::currentSession
    set root $::GX::cfg(output_root)
    if {$projectId ne {}} {set root [projectSessionsRoot $projectId]}
    set target [file normalize [file join $root [sanitize [string trim $name]]]]
    if {[file exists $target]} {error {New Session destination already exists.}}
    set savedArrays {};set savedScalars {}
    foreach variable [info vars ::GX::*] {
        if {[array exists $variable]} {dict set savedArrays $variable [array get $variable]} elseif {$variable ni {::GX::projectTransactionDepth} && [info exists $variable]} {dict set savedScalars $variable [set $variable]}
    }
    try {
        return [_projectAtomic [list [file join $target metadata manifest.ini]] {createNewSession_before_projects083 $name $projectId}]
    } on error {message options} {
        # Only the new reserved Session is ours to remove on creation failure.
        if {[file exists $target]} {file delete -force -- $target}
        dict for {variable values} $savedArrays {array unset $variable *;array set $variable $values}
        dict for {variable value} $savedScalars {set $variable $value}
        set ::GX::currentSession $priorSession
        catch {updateSessionUi};catch {projectRefreshExperimentUi}
        return -options $options $message
    }
}
rename ::GX::loadManifest ::GX::loadManifest_before_projects083
proc ::GX::loadManifest {path} {
    set current [file join $::GX::currentSession metadata manifest.ini]
    set configurationOnly [expr {$::GX::currentSession ne {} && [file isfile $current] && [file normalize $path] ne [file normalize $current]}]
    if {$configurationOnly} {set authoritative [parseIni $current]}
    set result [loadManifest_before_projects083 $path]
    set data [parseIni $path]
    if {$configurationOnly} {
        set data $authoritative
        foreach {key field fallback} [list experiment_id project_link.experiment_id {} experiment_project_id project_link.project_id {} experiment_project_legacy project_link.legacy_project {} experiment_project experiment.project {} experiment_name experiment.name [file tail $::GX::currentSession]] {
            set ::GX::cfg($key) [datasetPublicationV2DictDefault $data $field $fallback]
        }
    }
    set ::GX::cfg(session_origin) [datasetPublicationV2DictDefault $data origin.definition {}]
    return $result
}
# Startup recovery precedes the first Project registry load.
::GX::_projectTransactionHost recover

# Read-only inspection belongs to the existing Project/Session authority, not Tk.
proc ::GX::projectExperimentInspect {eid} {
    set path [projectExperimentResolve $eid]
    set summary [sessionInspectionSummary $path];set data [parseIni [file join $path metadata manifest.ini]]
    set counts {};set used {};set diagnostics {};set datasets {}
    foreach id [sessionInspectionDatasetIds $path] {
        set d [sessionInspectionDataset $id $path]
        set type [datasetPublicationV2DictDefault $d kind unknown];set format [datasetPublicationV2DictDefault $d format unknown]
        dict incr counts "$type / $format"
        set owner [datasetPublicationV2DictDefault $d source_module {}]
        if {$owner ne {}} {lappend used $owner}
        if {[catch {sessionInspectionDatasetLocation $id $path} problem]} {lappend diagnostics "Dataset $id: $problem";dict set d availability Missing} else {dict set d availability {Present; integrity not checked}}
        dict set d dataset_id $id;lappend datasets $d
    }
    set configured {}
    foreach key [dict keys $data] {if {[regexp {^module_config\.(.+)\.[^.]+$} $key -> mid]} {lappend configured $mid}}
    set enabled [splitList [datasetPublicationV2DictDefault $data module_state.enabled {}]]
    set run [splitList [datasetPublicationV2DictDefault $data module_state.run {}]]
    set scripts [scriptRegistryList session $path]
    set documents [sessionInspectionMarkdownDocuments $path]
    return [dict create experiment_id $eid project_id [projectMembershipField $eid project_id] session_path $path summary $summary origin [sessionOriginRead $path] datasets $datasets dataset_counts $counts configured_modules [lsort -unique $configured] enabled_modules $enabled run_modules $run used_modules [lsort -unique $used] used_evidence {Dataset source_module records only; other execution history unknown} scripts $scripts markdown_documents $documents diagnostics $diagnostics]
}
proc ::GX::projectExperimentDocumentRead {eid relative expectedSha} {
    if {[string tolower [file extension $relative]] ne {.md}} {error {Select a Markdown document.}}
    set resource [sessionInspectionResolveResource $relative [projectExperimentResolve $eid] $expectedSha]
    if {[dict get $resource size_bytes]>2097152} {error {Document exceeds the 2 MiB preview limit.}}
    return [noteReadUtf8 [dict get $resource path]]
}
