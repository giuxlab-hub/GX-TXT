# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {![string match */_private_dev104/* $out] || [file exists $out]} {error {New private output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set fixture [file join $out backend];file mkdir [file join $fixture bin]
set f [open [file join $fixture .private-cups-fixture] w];puts $f private;close $f
foreach name {lpstat lpoptions lp cancel} {set path [file join $fixture bin $name];file copy [file join [file dirname [info script]] cups_fixture.py] $path;file attributes $path -permissions 0755}
set ::env(GXTXT_CUPS_FIXTURE_ROOT) $fixture;set ::env(PATH) [file join $fixture bin]:$::env(PATH)
set argv0 __dev104_cups_contract__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog;::GX::configurationSet printing.cups_timeout_ms 300
proc mode {value} {set f [open [file join $::fixture mode] w];puts $f $value;close $f}
proc check {expression name} {if {![uplevel 1 [list expr $expression]]} {error "FAIL $name"};dict set ::checks $name PASS}
proc callback {response} {set ::answer $response;set ::done 1}
proc await {} {set ::done 0;set timer [after 7000 {set ::done timeout}];vwait ::done;after cancel $timer;if {$::done eq {timeout}} {error {CUPS fixture deadline exceeded}};return $::answer}
set last [clock milliseconds];set worst 0;set checks {};set receipts {}
proc beat {} {set now [clock milliseconds];set ::worst [expr {max($::worst,$now-$::last)}];set ::last $now;set ::beat [after 10 beat]};beat
mode normal
::GX::printCupsRequest discover {} callback;set discovery [await]
check {[dict get $discovery ok] && [dict get $discovery result printers] eq {QueueA QueueB}} discovery
::GX::printCupsRequest capabilities {printer QueueA} callback;set a [await]
check {[dict get $a ok] && [dict get $a result duplex] eq {auto simplex long short}} actual_duplex
::GX::printCupsRequest capabilities {printer QueueB} callback;set b [await]
check {[dict get $b ok] && [dict get $b result duplex] eq {auto} && ![dict exists $b result options Duplex]} foreign_capabilities_not_reused
foreach failure {authorization offline no_printers hang_discovery hang_options flood} {
 mode $failure
 set operation [expr {$failure eq {hang_options} ? {capabilities} : {discover}}]
 set arguments [expr {$operation eq {capabilities} ? {printer QueueA} : {}}]
 ::GX::printCupsRequest $operation $arguments callback;set result [await];dict set receipts $failure $result
 if {$failure eq {no_printers}} {check {[dict get $result ok] && [dict get $result result status] eq {no_printers}} $failure} else {check {![dict get $result ok] && [dict get $result error_type] eq [dict get {authorization authorization offline offline hang_discovery timeout hang_options timeout flood output_limit} $failure]} $failure}
}
mode late_a
set ::delivered {};proc latest {response} {lappend ::delivered $response;set ::answer $response;set ::done 1}
::GX::printCupsQuery capabilities capabilities {printer QueueA} latest
after 80 {::GX::printCupsQuery capabilities capabilities {printer QueueB} latest}
set result [await]
check {[llength $::delivered]==1 && [dict get $result result printer] eq {QueueB} && [dict get [::GX::printCupsState] ignored_stale_responses]>0} generation_safe_replacement
mode normal
set pdf [file join $out transport_only.pdf];set f [open $pdf w];puts $f {%PDF-1.4};close $f
set request [dict create printer QueueA capability_sha256 [dict get $a result fingerprint] pdf $pdf pdf_sha256 [::GX::sha256File $pdf] copies 2 duplex long options {PageSize A4} pages 1]
::GX::printCupsRequest submit $request callback;set submitted [await]
check {[dict get $submitted ok] && [dict get $submitted result status] eq {accepted} && [dict get $submitted result physical_completion] eq {unknown}} sandbox_submission_only
::GX::printCupsRequest job_status {printer QueueA job_id QueueA-104} callback;set status [await]
check {[dict get $status ok] && [dict get $status result status] eq {queued}} cups_acceptance_not_physical_completion
::GX::printCupsRequest cancel_job {job_id QueueA-104} callback;set cancelled [await]
check {[dict get $cancelled ok] && [file isfile [file join $fixture cancelled]]} explicit_sandbox_cancel
dict set request pdf_sha256 [string repeat 0 64]
::GX::printCupsRequest submit $request callback;set stale [await]
check {![dict get $stale ok] && [dict get $stale error_type] eq {stale_document}} changed_pdf_refused
after cancel $beat
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS cases $checks failures $receipts heartbeat_ms $worst stale [::GX::printCupsState] remaining_requests $::GX::scriptJobRequests transport_fixture {Header-only PDF; this test verifies the CUPS adapter, not PDF composition.}];close $f
puts "PASS [dict size $checks] bounded CUPS contracts; max heartbeat $worst ms"
