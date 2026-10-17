# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {![string match */_private_dev104/* $out] || [file exists $out]} {error {New private output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev104_request_contract__;source [file join $root gxtxt_pipeline.tcl]
set fixture [file join [file dirname [info script]] request_fixture.py]
set ticks 0;set worst 0;set last [clock milliseconds]
proc heartbeat {} {set now [clock milliseconds];set ::worst [expr {max($::worst,$now-$::last)}];set ::last $now;incr ::ticks;set ::beat [after 10 heartbeat]}
proc completed {response} {incr ::callbacks;set ::answer $response;set ::done 1}
heartbeat
set results {}
foreach mode {ok timeout stubborn cancelled flood} {
    set callbacks 0;set done 0;set start [clock milliseconds]
    set receipt [file join $out $mode.json]
    set request [::GX::scriptJobAsync [list python3 -B $fixture $mode $receipt] {} completed {timeout_ms 700 max_bytes 32768 process_group 1 label {Private managed request}}]
    if {$mode eq {cancelled}} {after 300 [list ::GX::scriptJobRequestCancel $request]}
    set deadline [after 4000 {set ::done timeout}];vwait done;after cancel $deadline
    if {$done eq {timeout}} {error "Fixture did not complete: $mode"}
    set elapsed [expr {[clock milliseconds]-$start}]
    if {$callbacks!=1 || [dict exists $::GX::scriptJobRequests $request]} {error {Callback/request lifetime failure}}
    set expected [dict get {ok {} timeout timeout stubborn timeout cancelled cancelled flood output_limit} $mode]
    if {$expected eq {}} {if {![dict get $answer ok]} {error $answer}} elseif {[dict get $answer ok] || [dict get $answer error_type] ne $expected} {error $answer}
    dict set results $mode [dict create response $answer callbacks $callbacks elapsed_ms $elapsed]
}
after cancel $beat
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS requests $results heartbeat_ms $worst ticks $ticks remaining $::GX::scriptJobRequests];close $f
puts "PASS managed request contract; max heartbeat $worst ms"
