# SPDX-License-Identifier: GPL-3.0-or-later
# Configuration and trusted producer integration; no capture is activated by a
# reader or by opening its Viewer. Existing Job streams retain their owners.
namespace eval ::GX::StderrDiagnostics {variable bgOriginal {};variable bgInstalled 0;variable applyError {}}
proc ::GX::stderrDiagnosticsApiInfo {} {
    return [dict create api_id STDERR_DIAGNOSTICS_API_v1 api_version 1 host_only 1 operations {info status read meta request cancel subscribe unsubscribe export} configuration_owner CONFIGURATION_API_v1 capture_default off]
}
proc ::GX::configurationGuiDiagnosticDirectory {id} {
    set path [tk_chooseDirectory -title {Global STDERR diagnostic directory} -initialdir $::GX::configurationUi($id) -mustexist 0]
    if {$path ne {}} {set ::GX::configurationUi($id) $path}
}
proc ::GX::stderrDiagnosticsDirectoryValidate {path} {
    if {$path eq {} || [file pathtype $path] ne {absolute}} {error {Use an absolute diagnostic directory}}
    if {[llength [info commands ::GX::_sessionStorageProfileSessionOwnedPath]] && [_sessionStorageProfileSessionOwnedPath $path]} {error {Diagnostic logs must remain outside scientific Sessions and their Dataset resources}}
    set ancestor [file normalize $path]
    while {1} {
        if {[file isfile [file join $ancestor gxtxt_pipeline.tcl]] || [file isfile [file join $ancestor plugin-package.ini]]} {error {Diagnostic logs must remain outside framework and plugin release packages}}
        set next [file dirname $ancestor];if {$next eq $ancestor} break
        set ancestor $next
    }
    if {[file exists $path]} {
        if {[file type $path] eq {link} || ![file isdirectory $path] || ![file writable $path]} {error {Diagnostic directory must be a writable directory, not a symbolic link}}
        if {$::tcl_platform(platform) eq {unix}} {
            set permissions [file attributes $path -permissions]
            if {($permissions&0022)!=0 || [file attributes $path -owner] ne $::tcl_platform(user)} {error {Diagnostic directory must belong to the current user and not be group/world writable}}
        }
    } else {
        set parent [file dirname $path]
        while {![file exists $parent] && [file dirname $parent] ne $parent} {set parent [file dirname $parent]}
        if {![file isdirectory $parent] || ![file writable $parent]} {error {Diagnostic directory parent is not writable}}
    }
    return $path
}
proc ::GX::stderrDiagnosticsConfigurationApply {} {
    variable ::GX::StderrDiagnostics::applyError
    # Headless public-owner requests inherit their caller's producer capability;
    # they must not launch a second collector while loading user preferences.
    if {![llength [info commands winfo]] || ![winfo exists .]} {return}
    set config [dict create log_directory [configurationGet diagnostics.stderr_log_directory] max_file_bytes [expr {1048576*wide([configurationGet diagnostics.stderr_max_file_mib])}] max_files [configurationGet diagnostics.stderr_max_files] ring_bytes [expr {1048576*wide([configurationGet diagnostics.stderr_ram_buffer_mib])}]]
    set applyError {}
    # A collector/filesystem failure is diagnostic state, never a reason to
    # roll back unrelated Configuration or scientific execution.
    if {[catch {
        stderrDiagnostics configure $config
        if {[configurationGet diagnostics.stderr_capture_enabled]} {stderrDiagnostics start} else {stderrDiagnostics stop}
        if {![configurationGet diagnostics.stderr_capture_enabled] || [dict get [stderrDiagnostics status] state] ne {running}} {_stderrDiagnosticsStopNativeRoutes}
        _stderrDiagnosticsBackgroundHook [configurationGet diagnostics.stderr_capture_enabled]
        stderrDiagnosticsProducerEnvironment
    } message]} {set applyError $message;lappend ::GX::configurationWarnings "STDERR diagnostics: $message"}
}
proc ::GX::_stderrDiagnosticsStopNativeRoutes {} {
    if {![info exists ::GX::ViewerDevelopment::windows]} return
    dict for {window record} $::GX::ViewerDevelopment::windows {
        if {[dict exists $record compiled_service] && [datasetPublicationV2DictDefault $record compiled_service_diagnostics 0]} {
            # A busy native callback finishes under its existing event budget;
            # cleanup then restores fd2 and retires its optional drain thread.
            # Global IPC acceptance has already stopped, without waiting here.
            if {![catch {scriptJobRequestSend [dict get $record compiled_service] {{"control":"diagnostics_stop"}}}]} {dict set ::GX::ViewerDevelopment::windows $window compiled_service_diagnostics 0}
        }
    }
}
proc ::GX::stderrDiagnosticsProducerEnvironment {} {
    if {![llength [info commands winfo]] && ![llength [info commands ::GX::StderrDiagnostics::_native]]} {
        return [dict create descriptor [expr {[info exists ::env(GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR)]?$::env(GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR):{}}]]
    }
    foreach key {GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR GXTXT_STDERR_DIAGNOSTICS_LIBRARY} {unset -nocomplain ::env($key)}
    if {![llength [info commands ::GX::StderrDiagnostics::producerDescriptor]]} {return {}}
    set descriptor [::GX::StderrDiagnostics::producerDescriptor]
    if {[dict get $descriptor descriptor] ne {}} {
        set ::env(GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR) [dict get $descriptor descriptor]
        set ::env(GXTXT_STDERR_DIAGNOSTICS_LIBRARY) [dict get $descriptor library]
    }
    return $descriptor
}
proc ::GX::stderrDiagnosticsGuiAttach {} {
    stderrDiagnosticsConfigurationApply
    bind . <Destroy> +[list ::GX::_stderrDiagnosticsGuiDestroyed %W]
}
proc ::GX::_stderrDiagnosticsGuiDestroyed {actual} {
    if {$actual ne {.}} return
    _stderrDiagnosticsBackgroundHook 0
    stderrDiagnostics stop
    foreach key {GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR GXTXT_STDERR_DIAGNOSTICS_LIBRARY} {unset -nocomplain ::env($key)}
}
proc ::GX::_stderrDiagnosticsBackgroundHook {enabled} {
    variable ::GX::StderrDiagnostics::bgInstalled
    variable ::GX::StderrDiagnostics::bgOriginal
    if {$enabled && !$bgInstalled} {
        set bgOriginal [interp bgerror {}]
        interp bgerror {} [list ::GX::_stderrDiagnosticsBackgroundError $bgOriginal]
        set bgInstalled 1
    } elseif {!$enabled && $bgInstalled} {
        if {[interp bgerror {}] eq [list ::GX::_stderrDiagnosticsBackgroundError $bgOriginal]} {interp bgerror {} $bgOriginal}
        set bgInstalled 0
    }
}
proc ::GX::_stderrDiagnosticsBackgroundError {original message options} {
    set bytes [encoding convertto utf-8 "$message\n[datasetPublicationV2DictDefault $options -errorinfo {}]"]
    for {set i 0} {$i<[string length $bytes]} {incr i 32768} {
        catch {stderrDiagnostics emit [dict create source tcl_tk_callback component CORE process_id [pid] stream callback_error severity error] [string range $bytes $i [expr {$i+32767}]]}
    }
    # Preserve the installed handler, including its ordinary dialog/reporting.
    tailcall {*}$original $message $options
}
