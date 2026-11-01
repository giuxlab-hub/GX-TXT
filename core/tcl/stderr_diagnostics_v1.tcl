# SPDX-License-Identifier: GPL-3.0-or-later
# Trusted CORE host dispatcher. Sourcing this file does not start/load capture.
namespace eval ::GX::StderrDiagnostics {
    variable root [file normalize [file join [file dirname [info script]] .. ..]]
    variable configured [dict create log_directory {} max_file_bytes 10485760 max_files 5 ring_bytes 8388608]
    variable desired 0
    variable subscribers {}
    variable serial 0
    variable timer {}
    variable transition {}
    variable subscriptionErrors 0
}
# CORE-only launch attachment. Deliberately absent from stderrDiagnostics and
# from its finite Viewer operation list; querying OFF never loads native code.
proc ::GX::StderrDiagnostics::producerDescriptor {} {
    variable root
    variable desired
    set descriptor {}
    set generation 0
    if {$desired && [llength [info commands ::GX::StderrDiagnostics::_native]]} {
        set descriptor [::GX::StderrDiagnostics::_native producer_descriptor]
        if {$descriptor ne {}} {set generation [dict get [::GX::StderrDiagnostics::_native status] generation]}
    }
    return [dict create descriptor $descriptor library [file join $root core diagnostics bin gxdiagnostics.so] generation $generation max_payload_bytes 32768]
}
proc ::GX::StderrDiagnostics::_ensure {} {
    variable root
    variable configured
    if {[llength [info commands ::GX::StderrDiagnostics::_native]]} {return}
    set library [file join $root core diagnostics bin gxdiagnostics.so]
    if {$::tcl_platform(os) ne {Linux} || ![file isfile $library]} {
        return -code error -errorcode {GX STDERR_DIAGNOSTICS UNAVAILABLE} {Compatible native diagnostics artifacts are unavailable}
    }
    load $library Gxdiagnostics
    if {[dict get $configured log_directory] ne {}} {_native configure $configured}
}
proc ::GX::StderrDiagnostics::_validate {changes} {
    variable configured
    dict size $changes
    set next $configured
    dict for {key value} $changes {
        switch -- $key {
            log_directory {
                if {$value eq {} || [file pathtype $value] ne {absolute} || [string length $value]>4096 || [string first \u0000 $value]>=0} {
                    error {log_directory must be a nonempty absolute path}
                }
                if {[llength [info commands ::GX::stderrDiagnosticsDirectoryValidate]]} {set value [::GX::stderrDiagnosticsDirectoryValidate $value]}
            }
            max_file_bytes {if {![string is entier -strict $value] || $value<4096 || $value>1073741824} {error {max_file_bytes outside4096..1073741824}}}
            max_files {if {![string is entier -strict $value] || $value<1 || $value>100} {error {max_files outside1..100}}}
            ring_bytes {if {![string is entier -strict $value] || $value<65536 || $value>67108864} {error {ring_bytes outside65536..67108864}}}
            default {error "Unknown diagnostics configuration key: $key"}
        }
        dict set next $key $value
    }
    return $next
}
proc ::GX::StderrDiagnostics::_status {} {
    variable configured
    variable subscriptionErrors
    if {[llength [info commands ::GX::StderrDiagnostics::_native]]} {
        set result [_native status]
    } else {
        set result [dict create schema gxtxt.stderr_status.v1 state off enabled 0 helper_pid 0 generation 0 capture_ipc 0 writer 0 config $configured log_directory [dict get $configured log_directory] last_error {} pending_records 0 pending_bytes 0]
        set counters {}
        foreach key {accepted_records accepted_bytes transport_dropped_records transport_dropped_bytes received_records received_bytes ring_dropped_records ring_dropped_bytes disk_dropped_records disk_dropped_bytes written_records written_bytes queue_records queue_bytes queue_high_water_bytes recovered_tail_bytes interrupted_records interrupted_bytes retention_evicted_files retention_evicted_bytes dropped_records dropped_bytes ipc_rejected_records ipc_rejected_wire_bytes producer_attachments producer_failed_records producer_failed_bytes producer_inflight retired_status_pages} {
            dict set counters $key 0
            dict set result $key 0
        }
        dict set result counters $counters
        dict set result generation_counters $counters
    }
    dict set result subscription_errors $subscriptionErrors
    return $result
}
proc ::GX::StderrDiagnostics::_notify {status} {
    variable subscribers
    variable subscriptionErrors
    dict for {token callback} $subscribers {
        if {[catch {uplevel #0 [list {*}$callback $status]}]} {incr subscriptionErrors}
    }
}
proc ::GX::StderrDiagnostics::_tick {} {
    variable timer
    variable subscribers
    variable desired
    set timer {}
    set status [_status]
    _notify $status
    if {$desired && [dict size $subscribers] && [dict get $status state] in {starting running stopping}} {
        set timer [after 100 ::GX::StderrDiagnostics::_tick]
    }
}
proc ::GX::StderrDiagnostics::_transition {} {
    variable transition
    variable desired
    set transition {}
    set status [_status]
    if {[dict get $status state] eq {stopping} || ($desired && [dict get $status state] eq {starting})} {
        set transition [after 10 ::GX::StderrDiagnostics::_transition]
    }
}
proc ::GX::stderrDiagnostics {operation args} {
    variable ::GX::StderrDiagnostics::configured
    variable ::GX::StderrDiagnostics::desired
    variable ::GX::StderrDiagnostics::subscribers
    variable ::GX::StderrDiagnostics::serial
    variable ::GX::StderrDiagnostics::timer
    variable ::GX::StderrDiagnostics::transition
    switch -- $operation {
        info {
            if {[llength $args]} {error {Usage: stderrDiagnostics info}}
            return [dict create schema gxtxt.stderr_api.v1 api_version 1 native_build_id dev111.p026.stderr.v1 max_payload_bytes 32768 capture_default off config_defaults [dict create max_file_bytes 10485760 max_files 5 ring_bytes 8388608] operations {info status start configure stop emit read meta export request cancel subscribe unsubscribe cleanup_preview cleanup}]
        }
        status {
            if {[llength $args]} {error {Usage: stderrDiagnostics status}}
            return [::GX::StderrDiagnostics::_status]
        }
        configure - start {
            if {[llength $args]>1} {error {Usage: stderrDiagnostics start|configure ?configDict?}}
            set next $configured
            if {[llength $args]} {set next [::GX::StderrDiagnostics::_validate [lindex $args 0]]}
            if {$operation eq {start}} {
                if {[dict get $next log_directory] eq {}} {error {Configure log_directory before starting diagnostics}}
                ::GX::StderrDiagnostics::_ensure
                set result [::GX::StderrDiagnostics::_native start $next]
                set desired 1
            } elseif {[llength [info commands ::GX::StderrDiagnostics::_native]]} {
                set result [::GX::StderrDiagnostics::_native configure $next]
                if {$desired && [dict get $result state] in {off error}} {
                    set result [::GX::StderrDiagnostics::_native start]
                }
            }
            set configured $next
            if {![info exists result]} {set result [::GX::StderrDiagnostics::_status]}
            if {$desired && [dict get $result state] in {starting stopping} && $transition eq {}} {
                set transition [after 10 ::GX::StderrDiagnostics::_transition]
            }
            if {$desired && [dict size $subscribers] && $timer eq {}} {set timer [after 0 ::GX::StderrDiagnostics::_tick]}
            return $result
        }
        stop {
            if {[llength $args]} {error {Usage: stderrDiagnostics stop}}
            set desired 0
            if {$timer ne {}} {after cancel $timer;set timer {}}
            if {$transition ne {}} {after cancel $transition;set transition {}}
            if {[llength [info commands ::GX::StderrDiagnostics::_native]]} {
                set result [::GX::StderrDiagnostics::_native stop]
            } else {set result [::GX::StderrDiagnostics::_status]}
            if {[dict get $result state] eq {stopping}} {set transition [after 10 ::GX::StderrDiagnostics::_transition]}
            ::GX::StderrDiagnostics::_notify $result
            return $result
        }
        emit {
            if {[llength $args]!=2} {error {Usage: stderrDiagnostics emit originDict bytearray}}
            if {!$desired} {return [dict create accepted 0 reason off]}
            return [::GX::StderrDiagnostics::_native emit {*}$args]
        }
        subscribe {
            if {[llength $args]!=1 || ![llength [lindex $args 0]]} {error {Usage: stderrDiagnostics subscribe callbackPrefix}}
            if {[dict size $subscribers]>=16} {error {Diagnostics subscription limit reached}}
            set token diagnostics-subscription-[incr serial]
            dict set subscribers $token [lindex $args 0]
            if {$desired && $timer eq {}} {set timer [after 0 ::GX::StderrDiagnostics::_tick]}
            return $token
        }
        unsubscribe {
            if {[llength $args]!=1} {error {Usage: stderrDiagnostics unsubscribe token}}
            dict unset subscribers [lindex $args 0]
            if {![dict size $subscribers] && $timer ne {}} {after cancel $timer;set timer {}}
            return
        }
        read - meta - export - request - cancel - cleanup_preview - cleanup {
            ::GX::StderrDiagnostics::_ensure
            return [::GX::StderrDiagnostics::_native $operation {*}$args]
        }
        default {error "Unknown diagnostics operation: $operation"}
    }
}
