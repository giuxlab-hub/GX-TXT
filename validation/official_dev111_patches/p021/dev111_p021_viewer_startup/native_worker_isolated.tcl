# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework output
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output;set output [file normalize $output];file attributes $output -permissions 0700
set framework [file normalize $framework]
source [file join $framework core tcl stderr_diagnostics_v1.tcl]
proc write {name content} {set f [open [file join $::output $name] w];puts -nonewline $f $content;close $f}
proc pause {} {after 20 {set ::ready 1};vwait ::ready}
set library [file join $framework plugins modules viewer.test_cad_1 native viewer.so]
set worker [file join $framework core python gxtxt_viewer_native_worker.py]
set exitCode 0
try {
 foreach mode {off on} {
  unset -nocomplain ::env(GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR) ::env(GXTXT_STDERR_DIAGNOSTICS_LIBRARY)
  if {$mode eq {on}} {
   ::GX::stderrDiagnostics start [dict create log_directory [file join $output logs]]
   set deadline [expr {[clock milliseconds]+4000}]
   while {[dict get [::GX::stderrDiagnostics status] state] eq {starting} && [clock milliseconds]<$deadline} {pause}
   set descriptor [::GX::StderrDiagnostics::producerDescriptor]
   if {[dict get $descriptor descriptor] eq {}} {error {ON collector supplied no active endpoint}}
   set ::env(GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR) [dict get $descriptor descriptor]
   set ::env(GXTXT_STDERR_DIAGNOSTICS_LIBRARY) [dict get $descriptor library]
  }
  write $mode-status.tcldict [::GX::stderrDiagnostics status]
  set request [format {{"library":"%s","native_output_path":"%s","event":{"kind":4,"component":0,"value":0},"state":{"values":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"counter":0}}} $library [file join $output $mode-native-output.log]]
  set result [exec /usr/bin/python3 -I -B $worker << $request]
  write $mode-worker.json $result
  if {![string match {*"ok":true*} $result] || ![string match {*"done":true*} $result]} {error "$mode isolated native worker did not complete"}
 }
 write RESULT.txt {PASS: exact distributed Test CAD 1 close event completes via normal isolated -I native worker with capture OFF and ON; typed stdout remains intact. No stderr payload was emitted by this event, so this is import/lifecycle qualification only.}
} on error {message options} {
 write failure.tcldict [dict create message $message options $options];puts stderr [dict get $options -errorinfo];set exitCode 1
} finally {
 unset -nocomplain ::env(GXTXT_STDERR_DIAGNOSTICS_DESCRIPTOR) ::env(GXTXT_STDERR_DIAGNOSTICS_LIBRARY)
 ::GX::stderrDiagnostics stop
 set deadline [expr {[clock milliseconds]+4000}]
 while {[dict get [::GX::stderrDiagnostics status] state] eq {stopping} && [clock milliseconds]<$deadline} {pause}
 write final-status.tcldict [::GX::stderrDiagnostics status]
}
exit $exitCode
