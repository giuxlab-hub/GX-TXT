# SPDX-License-Identifier: GPL-3.0-or-later
# Framework-wide accounting only. Session, Publication and managed-document
# authorities retain their scientific ownership and recovery decisions.
namespace eval ::GX::ResourceManagement {variable requests {}; variable serial 0}

proc ::GX::resourceManagementApiInfo {} {
    return [dict create api_id RESOURCE_MANAGEMENT_API_v1 api_version 1 scope framework \
        operations {allocate observe release inventory reconcile cleanup policy} \
        external_cleanup 0 legacy_cleanup 0]
}
proc ::GX::resourceManagementRoot {} {
    if {[info exists ::env(GXTXT_RESOURCE_ROOT)] && $::env(GXTXT_RESOURCE_ROOT) ne ""} {return $::env(GXTXT_RESOURCE_ROOT)}
    return [file join [file dirname [configurationPath]] resource-management]
}
proc ::GX::resourceManagementCommand {} {
    if {[llength [info commands ::GX::runtimeToolRequired]]} {set python [runtimeToolRequired python]} else {set python [auto_execok python3]}
    set command [list $python -B [file join $::GX::scriptDir core python gxtxt_resource_manager.py] \
        --root [resourceManagementRoot] --caller-pid [pid] --tcl]
    if {[info exists ::env(GXTXT_RESOURCE_STORAGE)] && $::env(GXTXT_RESOURCE_STORAGE) ne ""} {
        lappend command --storage-root $::env(GXTXT_RESOURCE_STORAGE)
    } elseif {[llength [info commands ::GX::configurationTempDirectory]]} {
        lappend command --storage-root [file join [configurationTempDirectory] resources-v1]
    }
    return $command
}
proc ::GX::resourceManagementCall {operation args} {
    return [exec -- {*}[resourceManagementCommand] $operation {*}$args]
}
proc ::GX::resourceManagementAllocate {subsystem {options {}}} {
    return [resourceManagementCall allocate subsystem $subsystem {*}$options]
}
proc ::GX::resourceManagementObserve {path subsystem {options {}}} {
    return [resourceManagementCall observe path $path subsystem $subsystem {*}$options]
}
proc ::GX::resourceManagementRelease {id {state verified_orphan} {retention ""}} {
    set options [list resource_id $id state $state]
    if {$retention ne ""} {lappend options retention_seconds $retention}
    return [resourceManagementCall release {*}$options]
}
proc ::GX::resourceManagementInventory {{rescan 0}} {return [resourceManagementCall inventory rescan $rescan]}
proc ::GX::resourceManagementCleanup {ids} {return [resourceManagementCall cleanup {*}$ids]}
proc ::GX::resourceManagementPolicy {{options {}}} {return [resourceManagementCall policy {*}$options]}

# Legacy inventory is explicit and read-only. Filename patterns never grant
# deletion rights. The current Session is just one reporting association.
proc ::GX::resourceManagementLegacyPaths {} {
    set rows {}
    set root [configurationCacheDirectory]
    foreach {relative subsystem category} {
        gx3de_viewer native3d cache_reusable
    } {
        set path [file join $root $relative]
        if {[file exists $path]} {lappend rows [dict create path $path subsystem $subsystem category $category recovery_required 0]}
    }
    foreach configuredRoot [lsort -unique [list $root [configurationTempDirectory]]] {
        foreach path [glob -nocomplain -directory $configuredRoot * .*] {
            if {[file tail $path] in {. .. gx3de_viewer resources-v1}} continue
            # A registered allocation root has exact records already. Unknown
            # historical files remain visible but never become cleanup targets.
            if {[file normalize $path] eq [file normalize [resourceManagementRoot]]} continue
            lappend rows [dict create path $path subsystem legacy_storage category unknown_legacy]
        }
    }
    if {[info exists ::GX::previewBinaryTaskDir] && $::GX::previewBinaryTaskDir ne ""} {
        lappend rows [dict create path $::GX::previewBinaryTaskDir subsystem dataset_preview category active]
    }
    foreach key [array names ::GX::DatasetViewer::state *,temp] {
        set path $::GX::DatasetViewer::state($key)
        if {$path ne "" && [file exists $path]} {lappend rows [dict create path $path subsystem native3d_preview category active]}
    }
    if {[info exists ::GX::currentSession] && $::GX::currentSession ne ""} {
        set session [file normalize $::GX::currentSession]
        foreach {relative subsystem category} {
            cache/dataset_materializations dataset_materialization cache_reusable
            metadata/interactive_document_resources managed_document protected_authoritative
            datasets datasets protected_authoritative
            analysis analysis_outputs protected_authoritative
        } {
            set path [file join $session $relative]
            if {[file exists $path]} {lappend rows [dict create path $path subsystem $subsystem category $category session $session]}
        }
    }
    return $rows
}

# Long rescans run in a separate local helper with fileevents, never in the Tk
# callback. The response is a Tcl dictionary as data; it is never evaluated.
proc ::GX::resourceManagementAsync {operation arguments callback} {
    variable ::GX::ResourceManagement::requests
    variable ::GX::ResourceManagement::serial
    set token "resource-request#[incr serial]"
    set pipe [open [concat [list |] [resourceManagementCommand] [list $operation] $arguments [list 2>@1]] r]
    fconfigure $pipe -blocking 0 -encoding utf-8 -translation lf
    dict set requests $token [dict create pipe $pipe output {} callback $callback]
    fileevent $pipe readable [list ::GX::resourceManagementReadable $token]
    return $token
}
proc ::GX::resourceManagementReadable {token} {
    variable ::GX::ResourceManagement::requests
    if {![dict exists $requests $token]} return
    set request [dict get $requests $token]
    set pipe [dict get $request pipe]
    dict append request output [read $pipe]
    dict set requests $token $request
    if {![eof $pipe]} return
    fileevent $pipe readable {}
    # At EOF closing the process channel cannot wait on ongoing computation.
    fconfigure $pipe -blocking 1
    set code [catch {close $pipe} problem]
    set output [string trim [dict get $request output]]
    dict unset requests $token
    if {$code && $output eq ""} {set output $problem}
    uplevel #0 [list {*}[dict get $request callback] $code $output]
}
