# SPDX-License-Identifier: GPL-3.0-or-later
# Organizational namespaces are private metadata, never Dataset IDs or paths.
proc ::GX::datasetNamespaceNormalize {value} {
    set value [string trim $value]
    if {[string length $value]>512} {error {Dataset namespace is too long (maximum512 characters).}}
    set parts {}
    foreach part [split $value /] {
        set part [string trim $part]
        if {$part eq {}} continue
        if {$part in {. ..}||![regexp {^[[:alnum:]_-][[:alnum:]_.-]*$} $part]} {error {Namespace components use letters, digits, underscores, hyphens and dots; slash separates levels.}}
        lappend parts $part
    }
    if {$parts eq {}||[llength $parts]>32} {error {A namespace requires1–32 nonempty components.}}
    # Legacy organizational metadata is projected without rewriting source
    # records on read. The next normal metadata/Manifest save writes base.
    if {[lindex $parts 0] eq "current"} {lset parts 0 base}
    return [join $parts /]
}
proc ::GX::datasetNamespaceCurrentGet {{session {}}} {
    variable currentSession;variable cfg
    if {$session eq {}} {set session $currentSession}
    if {$session eq {}} {return base}
    set session [file normalize $session]
    if {![file isdirectory $session]} {error {Dataset namespace requires an existing Session directory.}}
    if {$currentSession ne {}&&[file normalize $currentSession] eq $session&&[info exists cfg(dataset_namespace_current)]} {return [datasetNamespaceNormalize $cfg(dataset_namespace_current)]}
    if {![file isfile [file join $session metadata manifest.ini]]} {return base}
    set manifest [parseIni [file join $session metadata manifest.ini]]
    return [datasetNamespaceNormalize [datasetPublicationV2DictDefault $manifest dataset_organization.current_namespace base]]
}
proc ::GX::datasetNamespaceCurrentSet {session value} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Only user/admin operations may change the current Dataset namespace.}}
    variable cfg
    set session [_sessionInspectionRequire $session]
    if {$session ne [sessionInspectionCurrentSession]} {error {Open the Session before changing its current Dataset namespace.}}
    set value [datasetNamespaceNormalize $value]
    set prior [datasetNamespaceCurrentGet $session]
    set cfg(dataset_namespace_current) $value
    try {sessionPersistenceCommit} on error {message options} {set cfg(dataset_namespace_current) $prior;return -options $options $message}
    datasetCatalogObserve $session namespace
    return $value
}
proc ::GX::datasetNamespaceGet {session datasetId} {
    return [_datasetNamespaceFromMetadata $session [datasetPrivateMetadataRead $session $datasetId]]
}
proc ::GX::_datasetNamespaceFromMetadata {session metadata} {
    if {[dict exists $metadata _gxtxt.framework.dataset_namespace]} {return [datasetNamespaceNormalize [dict get $metadata _gxtxt.framework.dataset_namespace]]}
    return base
}
proc ::GX::datasetNamespaceSet {session datasetId value} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetNamespaceSet $session $datasetId $value]}
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Only user/admin operations may move Datasets between namespaces.}}
    set value [datasetNamespaceNormalize $value]
    if {[lindex [split $value /] 0] eq "pending"} {error {Pending is reserved for unimported sources.}}
    if {[datasetField $datasetId id {}] eq {}} {error {Only canonical Datasets may be moved. Pending sources remain pending until successful import.}}
    _datasetFrameworkMetadataUpdate $session $datasetId [dict create dataset_namespace $value]
    return $value
}
proc ::GX::datasetNamespaceCreate {session value} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Only user/admin operations may create Dataset namespaces.}}
    variable cfg
    set session [_sessionInspectionRequire $session]
    if {$session ne [sessionInspectionCurrentSession]} {error {Open the Session before creating a Dataset namespace.}}
    set value [datasetNamespaceNormalize $value]
    if {[lindex [split $value /] 0] eq "pending"} {error {Pending is an acquisition context, not a published namespace.}}
    if {$value in [datasetNamespaceList $session]} {return $value}
    set prior $cfg(dataset_namespace_created)
    set cfg(dataset_namespace_created) [lsort -dictionary -unique [linsert $prior end $value]]
    try {sessionPersistenceCommit} on error {message options} {set cfg(dataset_namespace_created) $prior;return -options $options $message}
    datasetCatalogObserve $session namespace
    return $value
}
proc ::GX::datasetNamespaceList {{session {}}} {
    variable currentSession;variable cfg
    if {$session eq {}} {set session $currentSession}
    set namespaces [list base pending [datasetNamespaceCurrentGet $session]]
    if {$session ne {}&&$currentSession ne {}&&[file normalize $session] eq [file normalize $currentSession]&&[info exists cfg(dataset_namespace_created)]} {
        foreach item $cfg(dataset_namespace_created) {lappend namespaces [datasetNamespaceNormalize $item]}
    } elseif {$session ne {}&&[file isfile [file join $session metadata manifest.ini]]} {
        set parsed [parseIni [file join $session metadata manifest.ini]]
        set count [datasetPublicationV2DictDefault $parsed dataset_organization.namespace_count 0]
        if {![string is integer -strict $count]||$count<0||$count>10000} {error {Invalid Dataset namespace count in Session Manifest}}
        for {set i 1} {$i<=$count} {incr i} {
            set key dataset_namespace.$i.name
            if {![dict exists $parsed $key]} {error "Missing $key in Session Manifest"}
            lappend namespaces [datasetNamespaceNormalize [dict get $parsed $key]]
        }
    }
    foreach item [dict get [datasetCatalogSnapshot $session] datasets] {lappend namespaces [dict get $item namespace]}
    set result {}
    foreach namespace $namespaces {
        set prefix {}
        foreach part [split $namespace /] {lappend prefix $part;dict set result [join $prefix /] 1}
    }
    return [lsort -dictionary [dict keys $result]]
}
proc ::GX::datasetNamespaceForModule {moduleId} {
    if {$moduleId eq {}} {error {Module namespace requires an identity.}}
    if {[catch {datasetNamespaceNormalize module/$moduleId} namespace]} {set namespace module/m[binary encode hex [encoding convertto utf-8 $moduleId]]}
    return $namespace
}
proc ::GX::_datasetPublicationNamespace {session moduleId definition} {
    if {[dict exists $definition dataset_namespace]} {
        set requested [datasetNamespaceNormalize [dict get $definition dataset_namespace]]
        set grants [datasetNamespaceSharedInputs $session]
        if {![dict exists $grants $requested]||$moduleId ni [dict get $grants $requested]} {error {Producer is not authorized for this shared scientific input namespace}}
        if {![dict exists $definition dataset_id]||[datasetField [dict get $definition dataset_id] id {}] ne {}||[datasetPublicationV2DictDefault $definition replace_owned 0]} {error {Shared scientific input publication is CREATE-only}}
        return $requested
    }
    return [datasetNamespaceForModule $moduleId]
}
proc ::GX::_datasetNamespaceRequireModuleWrite {session moduleId datasetId} {
    if {[datasetAuthorityActive $session]} {
        set metadata [_datasetMetadataFilter [_datasetMetadataReadRegistered $session $datasetId] 1]
    } else {set metadata [datasetPrivateMetadataRead $session $datasetId]}
    set assigned [datasetNamespaceForModule $moduleId]
    if {[dict exists $metadata _gxtxt.framework.dataset_namespace]} {
        if {[dict get $metadata _gxtxt.framework.dataset_namespace] eq $assigned} {return $assigned}
    } elseif {[datasetField $datasetId producer_module [datasetField $datasetId source_module {}]] eq $moduleId} {
        # Pre-namespace Sessions keep working for their recorded producer. The
        # next publication pins the automatically assigned module namespace.
        return $assigned
    }
    error "Module '$moduleId' may write only in its assigned Dataset namespace '$assigned'."
}
proc ::GX::datasetNamespaceApiInfo {} {
    return [dict create api_id DATASET_NAMESPACE_API_v1 api_version 1 separator / metadata_key _gxtxt.framework.dataset_namespace stable_identity canonical_dataset_id current_namespace_store Session_Manifest empty_namespace_store Session_Manifest missing_namespace base user_admin_create host_only]
}

proc ::GX::datasetNamespaceMigrationPlan {{session {}}} {
    set session [_sessionInspectionRequire $session]
    set changes {}
    foreach id [datasetRegistryIds] {
        set metadata [datasetPrivateMetadataRead $session $id]
        if {[dict exists $metadata _gxtxt.framework.dataset_namespace]} {
            set old [dict get $metadata _gxtxt.framework.dataset_namespace]
            set new [datasetNamespaceNormalize $old]
            if {$old ne $new} {dict set changes $id [list $old $new]}
        }
    }
    set manifest [parseIni [file join $session metadata manifest.ini]]
    set legacy {}
    dict for {key value} $manifest {
        if {$key eq "dataset_organization.current_namespace"||[regexp {^dataset_namespace\.[0-9]+\.name$} $key]} {
            if {$value ne [datasetNamespaceNormalize $value]} {dict set legacy $key $value}
        }
    }
    return [dict create datasets $changes manifest_fields $legacy fallback base read_projection_only 1]
}
proc ::GX::datasetNamespaceMigrate {session backupArchive} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Namespace migration is a user/admin operation.}}
    set session [_sessionInspectionRequire $session]
    if {$session ne [sessionInspectionCurrentSession]} {error {Open the Session before migration.}}
    set backupArchive [file normalize $backupArchive]
    if {[file exists $backupArchive]||[string match "$session/*" $backupArchive]} {error {Choose a new backup archive outside the Session.}}
    set plan [datasetNamespaceMigrationPlan $session]
    sessionPortableExport $session $backupArchive
    sessionPortableValidate $backupArchive
    return [datasetCatalogTransaction ::GX::_datasetNamespaceMigrateApply $session $plan $backupArchive]
}
proc ::GX::_datasetNamespaceMigrateApply {session plan backup} {
    variable cfg;variable datasetRegistry
    set oldRegistry [array get datasetRegistry];set oldCurrent $cfg(dataset_namespace_current);set oldCreated $cfg(dataset_namespace_created)
    set paths [list [file join $session metadata manifest.ini] [datasetRegistryPath $session]]
    dict for {id change} [dict get $plan datasets] {lappend paths [lindex [_datasetMetadataPath $session $id] 1]}
    set snapshots {}
    foreach path $paths {
        if {[file isfile $path]} {set f [open $path rb];try {dict set snapshots $path [read $f]} finally {close $f}}
    }
    try {
        dict for {id change} [dict get $plan datasets] {_datasetFrameworkMetadataUpdate $session $id [dict create dataset_namespace [lindex $change 1]]}
        set cfg(dataset_namespace_current) [datasetNamespaceNormalize $oldCurrent]
        set cfg(dataset_namespace_created) [lsort -unique [lmap value $oldCreated {datasetNamespaceNormalize $value}]]
        sessionPersistenceCommit
    } on error {message options} {
        dict for {path bytes} $snapshots {set temporary "$path.rollback.[pid]";set f [open $temporary wb];puts -nonewline $f $bytes;close $f;file rename -force $temporary $path}
        array unset datasetRegistry;array set datasetRegistry $oldRegistry
        set cfg(dataset_namespace_current) $oldCurrent;set cfg(dataset_namespace_created) $oldCreated
        return -options $options $message
    }
    return [dict merge $plan [dict create read_projection_only 0 backup_archive $backup recovery {Import the backup into a new directory with Portable Session Import.}]]
}

# User/admin policy remains in the existing Session Manifest namespace authority.
proc ::GX::datasetNamespaceSharedInputs {session} {
    if {$session eq $::GX::currentSession&&[info exists ::GX::cfg(dataset_namespace_shared_inputs)]} {return $::GX::cfg(dataset_namespace_shared_inputs)}
    set result {}
    if {![file isfile [file join $session metadata manifest.ini]]} {return $result}
    set ini [parseIni [file join $session metadata manifest.ini]]
    set count [datasetPublicationV2DictDefault $ini dataset_organization.namespace_count 0]
    if {![string is integer -strict $count]||$count<0||$count>10000} {error {Invalid namespace count}}
    for {set i 1} {$i<=$count} {incr i} {
        if {[dict exists $ini dataset_namespace.$i.shared_input_producers]} {
            dict set result [datasetNamespaceNormalize [dict get $ini dataset_namespace.$i.name]] [splitList [dict get $ini dataset_namespace.$i.shared_input_producers]]
        }
    }
    return $result
}
proc ::GX::datasetNamespaceAuthorizeSharedInput {session namespace producers} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Shared namespace authorization is user/admin only}}
    set session [_sessionInspectionRequire $session]
    if {$session ne [sessionInspectionCurrentSession]} {error {Open the Session before authorizing shared inputs}}
    set namespace [datasetNamespaceNormalize $namespace]
    if {[lindex [split $namespace /] 0] in {module pending}} {error {Private module and pending namespaces cannot be shared}}
    foreach producer $producers {datasetPublicationV2ValidateId module $producer}
    datasetNamespaceCreate $session $namespace
    set prior [datasetNamespaceSharedInputs $session]
    dict set ::GX::cfg(dataset_namespace_shared_inputs) $namespace [lsort -unique $producers]
    try {sessionPersistenceCommit} on error {message options} {set ::GX::cfg(dataset_namespace_shared_inputs) $prior;return -options $options $message}
    return [dict create namespace $namespace producers $producers policy create_only authority Session_Manifest]
}
