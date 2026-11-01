#!/usr/bin/env tclsh
# Existing Acquisition/Dataset authorities, in an owned auxiliary process.
# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework requestPath
if {![file isfile $requestPath] || [file type $requestPath] eq {link} || [file size $requestPath]>1048576} {puts [dict create ok 0 error {Invalid Acquisition managed request}];exit 0}
set ch [open $requestPath r];fconfigure $ch -encoding utf-8;try {set request [read $ch]} finally {close $ch}
set argv0 __managed_acquisition__
source [file join $framework gxtxt_pipeline.tcl]
if {[catch {
    ::GX::defaults;::GX::configurationLoad;::GX::loadModuleCatalog
    set session [dict get $request session]
    set ::GX::currentSession $session
    if {[file isfile [file join $session metadata manifest.ini]]} {::GX::loadManifest [file join $session metadata manifest.ini]}
    set ::GX::currentSession $session
    set ::GX::cfg(acquisition_source_storage) [dict get $request source_storage]
    dict for {tool executable} [dict get $request tools] {::GX::configurationSet runtime.$tool $executable}
    ::GX::configurationSet computation.default_workers [dict get $request workers]
    ::GX::parallelExecutionConfigure [dict get $request parallel_policy]
    set ::env(GXTXT_PARALLEL_DEPTH) [dict get $request parallel_depth]
    # Advisory derived work belongs to the selected host after commit, never
    # an auxiliary import/recovery process. This is process-local, not saved.
    ::GX::datasetPreviewCacheInit
    ::GX::configurationSet preview.cache_enabled 0
    ::GX::loadDatasetRegistry $session
    set ::GX::AcquisitionManaged::worker $request
    dict set ::GX::AcquisitionManaged::worker owner_pid [pid]
    set ::GX::acquisitionHandlerCancelFlag 0
    if {[dict get $request operation] eq {recover}} {
        set result [::GX::datasetPublicationRecover $session]
        ::GX::_acquisitionManagedRecoverStages $request
        set result [::GX::_acquisitionManagedCompletion $request]
    } else {
        dict for {key value} [dict get $request config] {set ::GX::moduleCfg($key) $value}
        set module [dict get $request module]
        if {[::GX::sha256File [::GX::moduleField $module descriptor {}]] ne [dict get $request module_sha256]} {error {Acquisition module changed since review; reopen import}}
        ::GX::_acquisitionManagedWorkerProgress $module [dict create phase preflight message {Verifying reviewed source and preparing import} mode indeterminate]
        set result [::GX::datasetAuthorityTransaction $session ::GX::_acquisitionManagedExecute $request]
    }
} reason options]} {
    puts [dict create ok 0 error $reason error_code [::GX::datasetPublicationV2DictDefault $options -errorcode {}]]
} else {puts [dict create ok 1 result $result]}
exit 0
