#!/usr/bin/env tclsh
# Run the normal Analysis queue through the public CORE Script Execution path.
# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv] != 6} {
    puts stderr "usage: script_execution_cli.tcl FRAMEWORK SESSION REFERENCE RUNTIME_TEMPLATE MODULE_OUTPUT STATUS_FILE"
    exit 2
}
lassign $argv framework session reference runtimeTemplate moduleOutput statusPath
set argv0 __not_main__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
set ::GX::currentSession [file normalize $session]
if {[catch {
    set result [::GX::scriptJobSubmit $reference {} [dict create session $session runtime_template $runtimeTemplate module_output $moduleOutput]]
    set id [dict get $result id]
    set jf [open [file join $moduleOutput .registered_job_id] w]
    puts $jf $id;close $jf
    while {[dict get $result state] in {QUEUED PREPARING RUNNING FINALIZING}} {
        after 250
        set result [::GX::scriptJobDescribe $id]
    }
    if {[dict get $result state] ne "COMPLETED"} {error "Job $id [dict get $result state]: [dict get $result error]"}
} reason options]} {
    set sf [open $statusPath w]
    try { puts $sf FAILED } finally { close $sf }
    puts stderr $reason
    exit 1
}
set sf [open $statusPath w]
try { puts $sf PASS } finally { close $sf }
puts "Registered script $reference completed: [dict get $result output_dir]"
exit 0
