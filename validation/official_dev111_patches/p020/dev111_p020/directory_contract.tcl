# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework output expected
set framework [file normalize $framework];set output [file normalize $output]
if {[file exists $output]} {error {Use a new private output}}
file mkdir $output
source [file join $framework core tcl stderr_diagnostics_v1.tcl]
set path [file join $output state gxtxt_pipeline diagnostics stderr]
::GX::stderrDiagnostics configure [dict create log_directory $path]
if {[file exists [file join $output state]]} {error {OFF created directories}}
::GX::stderrDiagnostics start
set deadline [expr {[clock milliseconds]+5000}]
while {[dict get [set status [::GX::stderrDiagnostics status]] state] in {starting stopping}} {
    if {[clock milliseconds]>$deadline} {error {Collector startup timed out}}
    after 2;update
}
if {$expected eq {expect_error}} {
    if {[dict get $status state] ne {error} || [file exists $path]} {error {Original missing-parent failure was not reproduced}}
    puts "REPRODUCED [dict get $status last_error]"
} else {
    if {[dict get $status state] ne {running}} {error "Expected running: $status"}
    foreach relative {state state/gxtxt_pipeline state/gxtxt_pipeline/diagnostics state/gxtxt_pipeline/diagnostics/stderr} {
        set dir [file join $output $relative]
        if {![file isdirectory $dir] || ([file attributes $dir -permissions]&0077)!=0} {error "Unsafe created directory: $dir"}
    }
    puts {PASS OFF has no path side effect; ON creates private missing parents}
}
set f [open [file join $output receipt.tcldict] w];puts $f $status;close $f
::GX::stderrDiagnostics stop
set deadline [expr {[clock milliseconds]+5000}]
while {[dict get [::GX::stderrDiagnostics status] state] eq {stopping}} {
    if {[clock milliseconds]>$deadline} {error {Collector shutdown timed out}}
    after 2;update
}
