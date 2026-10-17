# SPDX-License-Identifier: GPL-3.0-or-later
set root [lindex $argv 0];set request [read stdin];set argv0 __results_inspection__
if {[catch {
    source [file join $root gxtxt_pipeline.tcl]
    ::GX::defaults;::GX::loadModuleCatalog
    set ::GX::currentSession [dict get $request session];set ::env(GXTXT_JOB_ROOT) [dict get $request root]
    set result [::GX::sessionInspectionResults $::GX::currentSession [dict get $request offset] 500]
} reason]} {puts [dict create ok 0 error $reason]} else {puts [dict create ok 1 result $result]}
