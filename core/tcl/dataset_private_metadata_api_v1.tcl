# SPDX-License-Identifier: GPL-3.0-or-later
# Reserved metadata extends the canonical Dataset Metadata resource. Capabilities
# are ephemeral caller identities, never a second metadata or Dataset store.
namespace eval ::GX::DatasetPrivate {
    variable owners {}
    variable moduleCapabilities {}
    variable activeContext {}
    variable publicationActors {}
}
proc ::GX::_datasetMetadataPublicationWrite {session id metadata module suppliedKeys} {
    variable ::GX::DatasetPrivate::publicationActors
    if {[moduleField $module descriptor {}] eq {}} {error {Unknown publication metadata contributor}}
    set prior $publicationActors
    set publicationActors [dict create default System]
    foreach key $suppliedKeys {dict set publicationActors $key module:$module}
    try {return [datasetMetadataWrite $session $id $metadata]} finally {set publicationActors $prior}
}
proc ::GX::_datasetMetadataReserved {key} {
    expr {$key eq "_gxtxt"||[string match {_gxtxt.*} $key]}
}
proc ::GX::_datasetMetadataUserKey {key} {
    set key [_datasetMetadataValidateKey $key]
    if {[_datasetMetadataReserved $key]} {error {The _gxtxt namespace is reserved. Use the private metadata API with your module context.}}
    return $key
}
proc ::GX::_datasetMetadataFilter {metadata private} {
    set result {}
    dict for {key value} $metadata {if {[_datasetMetadataReserved $key]==$private} {dict set result $key $value}}
    return $result
}
proc ::GX::datasetPrivateMetadataRead {session datasetId} {
    return [_datasetMetadataFilter [_datasetMetadataReadAll $session $datasetId] 1]
}
proc ::GX::_datasetPrivateOwnerPrefix {moduleId} {
    if {$moduleId eq {}} {error {Private metadata requires a module identity.}}
    # UTF-8 hex is reversible, case-sensitive and contains no key separators.
    return _gxtxt.module.m[binary encode hex [encoding convertto utf-8 $moduleId]].
}
# Privileged issuer: called by CORE module activation/viewer dispatch and the
# Script Bridge host, never exposed as a bridge operation or owner argument.
proc ::GX::_datasetPrivateModuleContext {moduleId} {
    variable ::GX::DatasetPrivate::owners
    variable ::GX::DatasetPrivate::moduleCapabilities
    if {[moduleField $moduleId descriptor {}] eq {}} {error "Unknown module identity '$moduleId'."}
    if {![dict exists $moduleCapabilities $moduleId]} {
        set capability dataset-owner#[parallelOctaveRandomToken]
        dict set moduleCapabilities $moduleId $capability
        dict set owners $capability $moduleId
    }
    return [dict create dataset_namespace [datasetNamespaceForModule $moduleId] module_id $moduleId capability [dict get $moduleCapabilities $moduleId] owner_prefix [_datasetPrivateOwnerPrefix $moduleId]]
}
proc ::GX::_datasetPrivateWithModule {moduleId command args} {
    variable ::GX::DatasetPrivate::activeContext
    set prior $activeContext
    set activeContext [_datasetPrivateModuleContext $moduleId]
    try {return [uplevel 1 [list {*}$command {*}$args]]} finally {set activeContext $prior}
}
# During activation a Tcl module may retain this bound context for asynchronous
# callbacks. Viewers additionally receive it in their CORE-created scene context.
proc ::GX::datasetPrivateMetadataContext {} {
    variable ::GX::DatasetPrivate::activeContext
    if {$activeContext eq {}} {error {No active module context. Retain the context supplied by CORE at module activation/open.}}
    return $activeContext
}
proc ::GX::_datasetPrivateCapabilityPrefix {capability} {
    variable ::GX::DatasetPrivate::owners
    if {![dict exists $owners $capability]} {error {Invalid module metadata capability.}}
    return [_datasetPrivateOwnerPrefix [dict get $owners $capability]]
}
proc ::GX::_datasetPrivateRelativeKey {key} {
    set key [_datasetMetadataValidateKey $key]
    if {[_datasetMetadataReserved $key]} {error {Private updates use relative keys inside the caller's own namespace. Absolute reserved keys are forbidden.}}
    return $key
}
proc ::GX::_datasetPrivateUpdate {session datasetId prefix updates unsetKeys} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::_datasetPrivateUpdate $session $datasetId $prefix $updates $unsetKeys]}
    set normalized {};set removals {}
    dict for {key value} $updates {dict set normalized $prefix[_datasetPrivateRelativeKey $key] $value}
    foreach key $unsetKeys {lappend removals $prefix[_datasetPrivateRelativeKey $key]}
    set metadata [_datasetMetadataReadAll $session $datasetId]
    dict for {key value} $normalized {dict set metadata $key $value}
    foreach key $removals {dict unset metadata $key}
    _datasetMetadataWriteAll $session $datasetId $metadata
    return [datasetPrivateMetadataRead $session $datasetId]
}
proc ::GX::datasetPrivateMetadataUpdate {capability session datasetId updates} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetPrivateMetadataUpdate $capability $session $datasetId $updates]}
    set prefix [_datasetPrivateCapabilityPrefix $capability]
    _datasetNamespaceRequireModuleWrite $session [dict get $::GX::DatasetPrivate::owners $capability] $datasetId
    return [_datasetPrivateUpdate $session $datasetId $prefix $updates {}]
}
proc ::GX::datasetPrivateMetadataUnset {capability session datasetId keys} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetPrivateMetadataUnset $capability $session $datasetId $keys]}
    set prefix [_datasetPrivateCapabilityPrefix $capability]
    _datasetNamespaceRequireModuleWrite $session [dict get $::GX::DatasetPrivate::owners $capability] $datasetId
    return [_datasetPrivateUpdate $session $datasetId $prefix {} $keys]
}
# Framework organization APIs use this privileged path; modules have no
# framework capability and cannot select this prefix through public operations.
proc ::GX::_datasetFrameworkMetadataUpdate {session datasetId updates {unsetKeys {}}} {
    return [_datasetPrivateUpdate $session $datasetId _gxtxt.framework. $updates $unsetKeys]
}
