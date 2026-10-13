#!/usr/bin/env tclsh
# GX-TXT Parallel Execution API v1 - standard_octave transport client
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This process is only a loopback transport adapter. It never schedules workers.

foreach name {GXTXT_PARALLEL_BINDING_HOST GXTXT_PARALLEL_BINDING_PORT GXTXT_PARALLEL_BINDING_TOKEN} {
    if {![info exists ::env($name)] || [string trim $::env($name)] eq ""} {
        puts stderr "Parallel Execution standard_octave binding is unavailable: missing $name."
        exit 2
    }
}
set host $::env(GXTXT_PARALLEL_BINDING_HOST)
set port $::env(GXTXT_PARALLEL_BINDING_PORT)
set token $::env(GXTXT_PARALLEL_BINDING_TOKEN)
if {$host ni {127.0.0.1 ::1}} {
    puts stderr "Parallel Execution binding endpoint must be loopback-only."
    exit 2
}
if {![string is integer -strict $port] || $port < 1 || $port > 65535} {
    puts stderr "Parallel Execution binding endpoint has an invalid port."
    exit 2
}
if {[catch {set sock [socket $host $port]} message]} {
    puts stderr "Cannot connect to CORE Parallel Execution binding: $message"
    exit 2
}
fconfigure stdin -blocking 1 -buffering line -encoding utf-8 -translation lf
fconfigure stdout -buffering line -encoding utf-8 -translation lf
fconfigure $sock -blocking 1 -buffering line -encoding utf-8 -translation lf
puts $sock "AUTH\t$token"
flush $sock
# Each invocation carries one request. Read READY before accepting that
# request, then stream the reply. Windows Tcl does not reliably dispatch a
# fileevent for Octave's anonymous stdin pipe, leaving the old duplex loop
# waiting indefinitely after READY even though the loopback socket is live.
if {[gets $sock line] < 0} { puts stderr "CORE Parallel Execution binding closed before READY."; exit 2 }
puts stdout $line
flush stdout
if {[lindex [split $line "\t"] 0] ne "READY"} { exit 2 }
set requestSent 0
while {[gets stdin line] >= 0} {
    if {[catch {puts $sock $line; flush $sock} message]} {
        puts stderr "Cannot forward Parallel Execution request: $message"
        exit 2
    }
    if {$line eq "EXEC" || [string match "CANCEL\t*" $line]} {
        set requestSent 1
        break
    }
}
if {!$requestSent} { catch {close $sock}; exit 0 }
while {[gets $sock line] >= 0} {
    puts stdout $line
    flush stdout
    if {[lindex [split $line "\t"] 0] in {END ERROR CANCELRESULT}} {
        catch {close $sock}
        exit 0
    }
}
puts stderr "CORE Parallel Execution binding closed before a terminal response."
exit 2
