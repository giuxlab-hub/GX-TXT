# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root private receipt
set root [file normalize $root];set private [file normalize $private];set receipt [file normalize $receipt]
if {![string match */_private_dev104/project_gui_* $private] || [file exists $receipt]} {error {Private Project console and new receipt required}}
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $private $key]}
set argv0 __dev104_project_scale__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $private scale_sessions]
if {[file exists $::GX::cfg(output_root)]} {error {New scale fixture required}}
set start [clock milliseconds];set projects {};set experiments {}
# The writer runs outside Tk. The existing transaction owns all new Session
# manifest preimages as well as the registry; no alternate bulk registry exists.
set paths {};for {set i 0} {$i<200} {incr i} {foreach k {0 1} {lappend paths [file join $::GX::cfg(output_root) scale_${i}_$k metadata manifest.ini]}}
::GX::_projectAtomic $paths {
    for {set i 0} {$i<200} {incr i} {
        set project [::GX::projectCreate [format {Scale Project %03d} $i]];lappend projects $project
        foreach k {0 1} {
            set session [::GX::createNewSession scale_${i}_$k]
            ::GX::projectAssociateCurrentExperiment $project
            lappend experiments $::GX::cfg(experiment_id)
        }
    }
}
set data [dict create status PASS projects $projects experiments $experiments actual_sessions [llength $experiments] elapsed_ms [expr {[clock milliseconds]-$start}] generation [::GX::projectOrganizationGeneration]]
set f [open $receipt {WRONLY CREAT EXCL}];puts $f $data;close $f
puts "Created [llength $projects] Projects / [llength $experiments] real empty Sessions"
