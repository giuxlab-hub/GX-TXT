# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework output
set framework [file normalize $framework];set output [file normalize $output]
if {[file exists $output]} {error {Use a new isolated output}}
file mkdir $output
foreach kind {CONFIG DATA CACHE STATE} {set ::env(XDG_${kind}_HOME) [file join $output [string tolower $kind]]}
set argv0 __p020_bridge_contract__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk
wm withdraw .
proc check {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message};puts "PASS $message"}
proc until {condition} {
    set deadline [expr {[clock milliseconds]+5000}]
    while {![uplevel 1 [list expr $condition]]} {if {[clock milliseconds]>$deadline} {error "Timed out: $condition"};after 2;update}
}
set input [open [file join $framework plugins modules viewer.test_cad_1 gui design.tcldict]]
set demoDesign [read $input];close $input
::GX::viewerGuiDesignCompose $demoDesign .cad_demo viewer.test_cad_1 test_cad_1 demo
check {[dict get $::GX::ViewerGui::instances .cad_demo demo_bindings sketch provenance] eq {layout_only_RAM} && ![dict exists $::GX::ViewerGui::instances .cad_demo cad_sketches]} {Synthetic Builder layout does not create a scientific Sketch or History}
destroy .cad_demo
set ::reported {}
proc ::bridgeReporter {message options} {set ::reported [list $message $options]}
set original [interp bgerror {}]
interp bgerror {} ::bridgeReporter
::GX::stderrDiagnostics start [dict create log_directory [file join $output logs]]
until {[dict get [::GX::stderrDiagnostics status] state] eq {running}}
::GX::_stderrDiagnosticsBackgroundHook 1
after 0 {error {P020 genuine asynchronous callback Ω}}
until {$::reported ne {} && [dict get [::GX::stderrDiagnostics status] written_records]>0}
check {[lindex $::reported 0] eq {P020 genuine asynchronous callback Ω}} {Original background-error owner still receives the actual error}
::GX::_stderrDiagnosticsBackgroundHook 0
check {[interp bgerror {}] eq {::bridgeReporter}} {Disabling restores the previous interpreter handler}
set token [::GX::stderrDiagnostics read]
until {[dict get [set receipt [::GX::stderrDiagnostics request $token]] state] ne {pending}}
check {[dict get $receipt state] eq {done}} {Callback diagnostics are readable}
set record [lindex [dict get $receipt result records] 0]
check {[string first {P020 genuine asynchronous callback} [encoding convertfrom utf-8 [dict get $record payload]]]>=0} {Original multiline callback and traceback reach the collector}
check {[dict get $record origin source] eq {tcl_tk_callback}} {Callback provenance is authoritative}
toplevel .queue
dict set ::GX::ViewerDevelopment::windows .queue [dict create busy occupied status RUNNING]
for {set i 0} {$i<100} {incr i} {::GX::_viewerDiagnosticsDeliver .queue form changed {} [dict create state running generation 1 written_records $i dropped_records 0]}
set row [dict get $::GX::ViewerDiagnostics::forms [list .queue form]]
check {[llength [dict get $row queue]]==0 && [dict exists $row changed]} {One latest status replaces redundant queued updates}
check {[string first {"written_records":99} [dict get $row changed]]>=0} {Final status is retained}
after cancel [dict get $row delivery]
dict set ::GX::ViewerGui::instances .queue [dict create token {} design {components {}} domain_state {}]
::GX::_viewerDiagnosticsDispatch .queue form
check {![dict exists $::GX::ViewerDiagnostics::forms [list .queue form] delivery]} {Busy native work creates no retry polling timer}
dict set ::GX::ViewerDevelopment::windows .queue busy {}
dict set ::GX::ViewerDevelopment::windows .queue status COMPLETED
::GX::_viewerDiagnosticsResume .queue
set row [dict get $::GX::ViewerDiagnostics::forms [list .queue form]]
check {[dict exists $row delivery]} {Event completion resumes the retained final notification}
after cancel [dict get $row delivery]
dict unset ::GX::ViewerDiagnostics::forms [list .queue form]

# Fixed RPC test double: exercise the real public invocation's event ownership,
# without claiming a native/Viewer GUI acceptance test.
set source [file join $framework plugins modules viewer.stderr_diagnostics source]
dict set ::GX::ViewerDevelopment::windows .queue project $source
dict set ::GX::ViewerDevelopment::windows .queue validated_snapshot [::GX::_viewerDevelopmentSnapshot $source]
dict set ::GX::ViewerDevelopment::windows .queue generation 0
set ::exchanges 0
rename ::GX::_viewerDevelopmentCompiledService ::GX::_bridgeOriginalService
rename ::GX::scriptJobRequestExchange ::GX::_bridgeOriginalExchange
rename ::GX::_viewerDevelopmentRan ::GX::_bridgeOriginalRan
proc ::GX::_viewerDevelopmentCompiledService {window} {return bridge-rpc}
proc ::GX::scriptJobRequestExchange {args} {
    if {[incr ::exchanges]>1} {error {REENTRANT_NATIVE_RPC}}
    set ::nested [::GX::viewerDevelopmentInvoke .queue nested_event]
    return [binary encode base64 [encoding convertto utf-8 {ok 1 result {}}]]
}
proc ::GX::_viewerDevelopmentRan {window args} {dict set ::GX::ViewerDevelopment::windows $window status COMPLETED}
set invoked [::GX::viewerDevelopmentInvoke .queue outer_event]
check {[dict get $invoked status] eq {completed} && $::exchanges==1 && [dict get $::nested status] eq {busy}} {One native event owns its full managed exchange, including nested Tk events}
rename ::GX::_viewerDevelopmentCompiledService {};rename ::GX::_bridgeOriginalService ::GX::_viewerDevelopmentCompiledService
rename ::GX::scriptJobRequestExchange {};rename ::GX::_bridgeOriginalExchange ::GX::scriptJobRequestExchange
rename ::GX::_viewerDevelopmentRan {};rename ::GX::_bridgeOriginalRan ::GX::_viewerDevelopmentRan
dict unset ::GX::ViewerGui::instances .queue
dict unset ::GX::ViewerDevelopment::windows .queue
destroy .queue
::GX::stderrDiagnostics stop
until {[dict get [::GX::stderrDiagnostics status] state] eq {off}}
interp bgerror {} $original
destroy .
puts {PASS typed bridge integration contracts; no Viewer GUI acceptance claim}
