# SPDX-License-Identifier: GPL-3.0-or-later
# Project Portable is transport over the existing Project/Session authorities.
proc ::GX::_projectPortableHost {action args} {
    return [_sessionPortableParseOutput [exec [runtimeToolRequired python] -B [file join $::GX::scriptDir core python project_portable_v1.py] $action {*}$args 2>@1]]
}
proc ::GX::projectPortableValidate {archive} {return [_projectPortableHost validate [file normalize $archive]]}
proc ::GX::projectPortableExport {projectId archive} {
    if {![projectExists $projectId]} {error {Select an existing Project to export.}}
    set archive [file normalize $archive]
    if {[file exists $archive]} {error {Export destination already exists; choose a new package filename.}}
    set root [projectStoragePath $projectId]
    if {[_datasetDeletePathWithin $archive $root]} {error {Export package must be outside the source Project.}}
    set stage [file join [file dirname [projectRegistryPath]] .gxtxt-project-export-[pid]-[clock clicks]]
    file mkdir [file join $stage source];file mkdir [file join $stage sessions]
    try {
        set data {};dict for {key value} [projectGet $projectId] {dict set data project.$key $value}
        dict set data project.carrier_installation [installationIdentityCurrent]
        set i 0
        foreach record [projectListExperiments $projectId] {
            incr i;set path [projectExperimentResolve [dict get $record experiment_id]]
            if {[_datasetDeletePathWithin $archive $path]} {error {Export package must be outside every source Session.}}
            foreach ds [sessionInspectionDatasetIds $path] {sessionInspectionDatasetPayload $ds $path}
            sessionPortableExport $path [file join $stage sessions $i.zip]
            dict for {key value} $record {dict set data experiment.$i.$key $value}
        }
        _projectIniWrite [file join $stage source transfer.ini] $data
        file copy -- [file join $root project.ini] [file join $stage source project.ini]
        return [_projectPortableHost export $stage $archive $::GX::scriptDir]
    } finally {file delete -force -- $stage}
}
proc ::GX::projectPortableImport {archive {name {}}} {
    variable projectCatalog
    # Extract and verify ALL nested scientific packages before registry mutation.
    set scratch [file join [file dirname [projectRegistryPath]] .gxtxt-project-read-[pid]-[clock clicks]]
    set stage {};set committed 0
    try {
        set package [_projectPortableHost extract [file normalize $archive] $scratch]
        set data [parseIni [file join $scratch source transfer.ini]]
        set source [dict get $data project.id]
        if {[string trim $name] eq {}} {set name [dict get $data project.name]}
        set name [string trim $name];if {$name eq {}} {error {Enter a Project name.}}
        set id [projectGenerateId];while {$id eq $source} {set id [projectGenerateId]};set destination [projectDefaultStoragePath $id]
        if {[file exists $destination]} {error {Import Project destination already exists; nothing will be overwritten.}}
        foreach p [projectIds] {
            if {[_datasetDeletePathWithin $destination [projectStoragePath $p]]} {error {Import root must be outside every existing Project.}}
            foreach r [projectListExperiments $p] {
                if {[_datasetDeletePathWithin $destination [dict get $r session_path]]} {error {Import root must be outside existing Sessions.}}
            }
        }
        file mkdir [file dirname $destination]
        set stage [file join [file dirname $destination] .gxtxt-project-import-[pid]-[clock clicks]]
        if {[file exists $stage]} {error {Private Project staging already exists.}}
        file mkdir $stage
        if {[file isdirectory [file join $scratch resources]]} {
            foreach f [glob -nocomplain -directory [file join $scratch resources] * .*] {
                if {[file tail $f] ni {. ..}} {file copy -- $f $stage}
            }
        }
        # Source metadata and runtime code are inert snapshots, not installation state.
        set carrier [file join $stage .gxtxt-project-transport $id]
        if {[file exists $carrier]} {error {Project transport resource collision.}}
        file mkdir $carrier
        foreach f {source dependencies} {
            if {[file isdirectory [file join $scratch $f]]} {file copy -- [file join $scratch $f] $carrier}
        }
        set origin [datasetPublicationV2DictDefault $data project.origin {}]
        if {$origin eq {}} {set origin [_originUnknown]}
        if {[catch {dict size $origin}] || ![dict exists $origin creator_installation]} {error {Invalid Project origin.}}
        dict lappend origin events [dict create kind project_import installation_id [installationIdentityCurrent] at [projectTimestamp] source_project_id $source package_sha256 [dict get $package sha256]]
        set mappings {};set diagnostics {};set count [dict get $package experiment_count]
        set sourceIds {};for {set i 1} {$i<=$count} {incr i} {lappend sourceIds [dict get $data experiment.$i.experiment_id]}
        for {set i 1} {$i<=$count} {incr i} {
            set old [dict get $data experiment.$i.experiment_id];set eid [experimentGenerateId]
            while {$eid in $sourceIds || [projectMembershipField $eid experiment_id {}] ne {} || [dict exists $mappings $eid]} {set eid [experimentGenerateId]}
            set relative [file join Sessions "session-$i-[sanitize [file tail [dict get $data experiment.$i.session_path]]]"]
            set final [file join $destination $relative];set temporary [file join $stage $relative]
            if {[file exists $temporary]} {error {Project resource and Session destination collision.}}
            set r [sessionPortableStageImport [file join $scratch sessions $i.zip] $final $temporary]
            set mf [file join $temporary metadata manifest.ini];set sd [parseIni $mf]
            set so [sessionOriginRead $temporary]
            dict lappend so events [dict create kind import installation_id [installationIdentityCurrent] at [projectTimestamp] source_experiment_id $old source_project_id $source package_sha256 [dict get $package sha256]]
            dict set sd origin.api_version 1;dict set sd origin.definition $so
            foreach {field value} [list api_version 1 project_id $id experiment_id $eid imported_project_id $source imported_experiment_id $old] {dict set sd project_link.$field $value}
            dict set sd experiment.project $name
            _projectIniWrite $mf $sd
            dict set mappings $eid [dict create source_experiment_id $old session_path $final experiment_name [dict get $data experiment.$i.experiment_name]]
            dict set diagnostics $eid [dict get $r diagnostics]
        }
        # The existing journal owns registry preimages and the single directory move.
        # Recovery reverses the move before restoring metadata/registry, avoiding a
        # partially visible Project even on interrupted publication.
        _projectAtomic [list [file join $destination project.ini]] {
            # Refresh under the existing writer lock so another process's commit
            # made while packages were being checked is never overwritten.
            projectLoadRegistry
            if {[projectExists $id] || [file exists $destination]} {error {Concurrent Project destination collision.}}
            dict for {eid rec} $mappings {if {[projectMembershipField $eid experiment_id {}] ne {}} {error {Concurrent Experiment identifier collision.}}}
            foreach field {description tags author created_at} {set projectCatalog($id,$field) [datasetPublicationV2DictDefault $data project.$field {}]}
            foreach {key value} [list id $id name $name storage_path $destination updated_at [projectTimestamp] origin $origin] {set projectCatalog($id,$key) $value}
            dict for {eid rec} $mappings {projectAssociateExperiment $id $eid [dict get $rec session_path] [dict get $rec experiment_name]}
            file rename -- $stage $destination
            projectWriteMetadata $id;projectSaveRegistry
        } [list $stage $destination]
        set committed 1
        return [dict create project_id $id storage_path $destination source_project_id $source snapshots_path [file join $destination .gxtxt-project-transport $id] origin $origin experiments $mappings diagnostics $diagnostics package_info $package]
    } finally {
        if {[file exists $scratch]} {file delete -force -- $scratch}
        if {!$committed && ![file exists [_projectJournal]] && $stage ne {} && [file exists $stage]} {file delete -force -- $stage}
    }
}
