# SPDX-License-Identifier: GPL-3.0-or-later
# Host-only plugin lifecycle extension of Plugin Install API. State here is
# transient loader state, never a second installed-package registry.
namespace eval ::GX {
    variable pluginRuntimeLoaded {}
    variable pluginRuntimePending {}
    variable pluginRuntimeHooks {}
    variable pluginRuntimeReceipts {}
    variable pluginRuntimeDeferActivation 0
}

proc ::GX::pluginLifecycleRegister {moduleId commandPrefix} {
    pluginSafeId $moduleId
    set context [datasetPrivateMetadataContext]
    if {[dict get $context module_id] ne $moduleId} {error {A lifecycle command can only register for its activating module}}
    if {![llength $commandPrefix] || ![llength [info commands [lindex $commandPrefix 0]]]} {error {A callable lifecycle command is required}}
    dict set ::GX::pluginRuntimeHooks $moduleId $commandPrefix
}

proc ::GX::pluginRuntimeNoteLoaded {moduleId} {
    if {![dict exists $::GX::pluginRuntimeLoaded $moduleId]} {
        dict set ::GX::pluginRuntimeLoaded $moduleId [moduleField $moduleId version {}]
    }
}

proc ::GX::pluginRuntimeModuleLoaded {moduleId} {
    if {[dict exists $::GX::pluginRuntimeLoaded $moduleId]} {return 1}
    if {[array exists ::GX::acquisitionHandlerRegistry]} {
        foreach handler [array names ::GX::acquisitionHandlerRegistry] {
            set registration $::GX::acquisitionHandlerRegistry($handler)
            if {[dict exists $registration kind] && [dict get $registration kind] eq "plugin" &&
                [dict exists $registration module_id] && [dict get $registration module_id] eq $moduleId} {return 1}
        }
    }
    if {[array exists ::GX::modulePublicApiActivated] && [llength [array names ::GX::modulePublicApiActivated "$moduleId,*"]]} {return 1}
    foreach provider [viewerProviderList] {
        if {[dict get $provider module_id] eq $moduleId && [info exists ::GX::viewerBackend([dict get $provider backend])]} {return 1}
    }
    return 0
}

proc ::GX::pluginRuntimeCheckQuiescent {target} {
    if {[info exists ::GX::analysisPipe] && $::GX::analysisPipe ne {}} {error {A scientific Analysis calculation is active; finish or cancel it before updating plugins.}}
    if {[info exists ::GX::acquisitionHandlerAsyncActive] && $::GX::acquisitionHandlerAsyncActive} {
        error {An Acquisition is active; finish or cancel it before updating plugins.}
    }
    if {[file isfile [file join [scriptJobRoot] jobs.sqlite]]} {
        # This public projection includes the full active lifecycle, independent
        # of presentation pagination or hidden terminal Jobs.
        set jobs [scriptJobPresentationCall view_list [dict create scope all filter Active show_hidden 1 sort created descending 1 offset 0 limit 1 hidden_ids {}]]
        if {[llength [dict get $jobs lifecycle]]} {error {Scientific Jobs are active; finish or cancel them before updating plugins.}}
    }
    set target [file normalize $target]
    foreach entry [info loaded] {
        set library [lindex $entry 0]
        if {$library ne {} && [string first "$target/" "[file normalize $library]/"]==0} {
            error {A native library from this plugin is loaded. Close GX-TXT and update from a fresh instance before using the plugin.}
        }
    }
    # A loaded plugin may have launched a worker outside its own directory.
    # Unknown live child lifetimes cannot certify safe package replacement.
    if {$::tcl_platform(os) eq "Linux"} {
        set childrenPath /proc/[pid]/task/[pid]/children
        if {[file readable $childrenPath]} {
            set f [open $childrenPath];set children [string trim [read $f]];close $f
            if {$children ne {}} {error {A framework child process is active; close its Viewer or wait for it before updating plugins.}}
        }
    }
}

proc ::GX::pluginRuntimePrepareUpdate {type id target} {
    pluginRuntimeCheckQuiescent $target
    if {[array exists ::GX::modulePublicApiActivated]} {
        foreach key [array names ::GX::modulePublicApiActivated "$id,*"] {
            if {$::GX::modulePublicApiActivated($key) eq "loading"} {error {Plugin activation is still in progress; wait before updating it.}}
        }
    }
    if {$type ne "module" || ![pluginRuntimeModuleLoaded $id]} {return [dict create mode cold active_version {}]}
    pluginRuntimeNoteLoaded $id
    set plan [dict create mode restart active_version [dict get $::GX::pluginRuntimeLoaded $id] reason {The loaded implementation has no certified quiescent reload contract.}]
    if {[dict exists $::GX::pluginRuntimeHooks $id]} {
        set hook [dict get $::GX::pluginRuntimeHooks $id]
        set admission [_datasetPrivateWithModule $id [list uplevel #0 [list {*}$hook prepare_update]]]
        if {![dict exists $admission safe] || ![string is boolean -strict [dict get $admission safe]]} {error {Plugin lifecycle admission must return a boolean safe field}}
        if {[dict get $admission safe]} {dict set plan mode hot;dict set plan hook $hook;dict set plan reason {Provider-certified quiescent Tcl lifecycle.}} else {
            dict set plan reason [datasetPublicationV2DictDefault $admission reason {The current Viewer/document is still active.}]
        }
    }
    if {$::GX::pluginRuntimeDeferActivation && [dict get $plan mode] eq "hot"} {
        dict set plan mode restart
        dict set plan reason {Activation is deferred until the complete bundle transaction commits. Reopen the quiescent provider to activate it.}
    }
    return $plan
}

proc ::GX::pluginRuntimeActivate {id target version plan} {
    if {[dict get $plan mode] eq "hot"} {
        # The provider owns removal/rebinding of its own procedures and state.
        # CORE never blanket-sources Tcl or hot-unloads native libraries.
        _datasetPrivateWithModule $id [list uplevel #0 [list {*}[dict get $plan hook] activate $target $version]]
        dict set ::GX::pluginRuntimeLoaded $id $version
    }
    if {[dict get $plan mode] eq "restart"} {
        dict set ::GX::pluginRuntimePending $id [dict create target $target version $version reason [dict get $plan reason]]
        set status {Updated — restart required}
    } else {
        dict unset ::GX::pluginRuntimePending $id
        set status {Updated and active}
    }
    dict set ::GX::pluginRuntimeReceipts $id [dict create status $status installed_version $version active_version [expr {[dict get $plan mode] eq "restart" ? [dict get $plan active_version] : $version}] reason [datasetPublicationV2DictDefault $plan reason {New implementation is available through its ordinary lazy loader.}]]
    return [dict get $::GX::pluginRuntimeReceipts $id]
}

proc ::GX::pluginRuntimeTryPending {moduleId} {
    if {$::GX::pluginRuntimeDeferActivation || ![dict exists $::GX::pluginRuntimePending $moduleId] || ![dict exists $::GX::pluginRuntimeHooks $moduleId]} return
    set pending [dict get $::GX::pluginRuntimePending $moduleId]
    if {[dict exists $pending activation_failed]} return
    if {[catch {set plan [pluginRuntimePrepareUpdate module $moduleId [dict get $pending target]]}]} return
    if {[dict get $plan mode] ne "hot"} return
    if {[catch {pluginRuntimeActivate $moduleId [dict get $pending target] [dict get $pending version] $plan} reason]} {
        if {[dict exists $pending previous_root]} {
            if {[catch {_datasetPrivateWithModule $moduleId [list uplevel #0 [list {*}[dict get $plan hook] rollback [dict get $pending previous_root] [dict get $pending previous_version]]]} rollbackReason]} {append reason "; lifecycle rollback failed: $rollbackReason"}
        }
        dict set ::GX::pluginRuntimePending $moduleId activation_failed 1
        dict set ::GX::pluginRuntimeReceipts $moduleId reason "Activation failed; restart required: $reason"
    } elseif {[dict exists $pending previous_root]} {catch {file delete -force [dict get $pending previous_root]}}
}

proc ::GX::pluginRuntimeGuardNewLoad {moduleId} {
    if {[dict exists $::GX::pluginRuntimePending $moduleId]} {error "Plugin '$moduleId' was updated; restart required before loading another entrypoint. Existing active instances retain their implementation."}
}

proc ::GX::pluginRuntimeInfo {id} {
    if {[dict exists $::GX::pluginRuntimeReceipts $id]} {return [dict get $::GX::pluginRuntimeReceipts $id]}
    set installed [pluginInstalledField $id version {}]
    set active [expr {[dict exists $::GX::pluginRuntimeLoaded $id] ? [dict get $::GX::pluginRuntimeLoaded $id] : $installed}]
    return [dict create status {Available} installed_version $installed active_version $active reason {}]
}
