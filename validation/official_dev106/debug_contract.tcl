# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out language
set root [file normalize $root];set out [file normalize $out]
if {![string match */_private_dev106/* $out] || [file exists $out] || $language ni {Python Octave}} {error {Fresh private output and supported debugger language required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __debug_contract__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out Sessions];::GX::createNewSession private_debug
::GX::configurationSet scripts.user_root [file join $out user_scripts]
if {$language eq {Python}} {set code "def twice(x):\n    y = x * 2\n    return y\na = 3\nb = twice(a)\nprint('DEBUG_RESULT', b)\n";set breaks {5}} else {set code "a = 3;\nb = a * 2;\nc = b + 1;\ndisp(c);\n";set breaks {2}}
set metadata [::GX::scriptRegistrySave session native_debug {Native debug fixture} $code [dict create language $language]]
set job [::GX::scriptJobDebugSubmit session:native_debug {} [dict create debug_breakpoints $breaks]]
set id [dict get $job id];set sha [dict get $metadata sha256];set events {}
proc tick {} {after 100 {set ::tick 1};vwait ::tick}
proc waitstop {id previous} {
    set until [expr {[clock milliseconds]+90000}]
    while {[clock milliseconds]<$until} {
        set job [::GX::scriptJobDescribe $id]
        if {[dict get $job state] in {FAILED CANCELLED COMPLETED INTERRUPTED}} {error "Job ended before expected native stop: $job"}
        set state [::GX::scriptJobDebugRead $id]
        if {[dict get $state state] eq {PAUSED} && [dict get $state sequence]>$previous} {lappend ::events $state;return $state}
        tick
    }
    error {Native debugger stop timed out}
}
set first [waitstop $id 0];puts "PAUSED [dict get $first line]";flush stdout
if {[dict get $first source_sha256] ne $sha || ![llength [dict get $first stack]]} {error {Native stop did not match immutable source/stack}}
if {![catch {::GX::scriptJobDebugControl $id over [string repeat 0 64]}]} {error {Stale-source command was accepted}}
::GX::scriptJobDebugControl $id over $sha
set second [waitstop $id [dict get $first sequence]];puts "STEPPED [dict get $second line]";flush stdout
if {[dict get $second line]==[dict get $first line]} {error {Step did not advance an actual native source line}}
::GX::scriptJobDebugControl $id continue $sha
set until [expr {[clock milliseconds]+90000}]
while {[clock milliseconds]<$until} {
    set state [::GX::scriptJobDebugRead $id]
    if {[dict get $state state] eq {PAUSED}} {lappend events $state;::GX::scriptJobDebugControl $id continue $sha}
    set job [::GX::scriptJobDescribe $id]
    if {[dict get $job state] in {COMPLETED FAILED CANCELLED INTERRUPTED}} break
    tick
}
if {[dict get $job state] ne {COMPLETED}} {error "Debugger completion failed: $job"}
set output [::GX::scriptJobStreamRead $id stdout]
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS language $language source_sha256 $sha events $events job $job stdout $output stale_control REFUSED];close $f
puts "PASS $language native managed debugger"
