#!/usr/bin/env tclsh
# Normal Analysis subprocess for a packaged Script Module.
# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv] != 6} {
    puts stderr "usage: script_module_cli.tcl FRAMEWORK SESSION MODULE_ID RUNTIME_TEMPLATE MODULE_OUTPUT STATUS_FILE"
    exit 2
}
lassign $argv framework session moduleId runtimeTemplate moduleOutput statusPath
set argv0 __not_main__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
set ::GX::currentSession [file normalize $session]
if {[catch {::GX::scriptExecutionRunPackaged $moduleId $runtimeTemplate $moduleOutput} reason options]} {
    set sf [open $statusPath w]
    try { puts $sf FAILED } finally { close $sf }
    puts stderr $reason
    exit 1
}
set sf [open $statusPath w]
try { puts $sf PASS } finally { close $sf }
puts "$moduleId completed"
exit 0
