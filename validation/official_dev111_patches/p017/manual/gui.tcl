# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv framework out mode
if {[llength $argv]!=3 || $mode ni {worksheet curve replicate fit}} {error {usage: gui.tcl FRAMEWORK NEW_OUTPUT worksheet|curve|replicate|fit}}
set framework [file normalize $framework];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT TMPDIR} {set ::env($key) [file join $out $key];file mkdir $::env($key)}
set ::env(PYTHONDONTWRITEBYTECODE) 1
set argv0 __DEV111_P017_MANUAL_CONSUMERS__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog;package require Tk;wm withdraw .
::GX::configurationSet storage.cache_dir [file join $out cache]
::GX::configurationSet storage.temp_dir [file join $out temp]
set ::GX::cfg(output_root) [file join $out Sessions]
::GX::createNewSession SYNTHETIC_MANUAL_HISTORY
source [file join [file dirname [info script]] common.tcl]
set sourcePins {}
foreach relative {gxtxt_pipeline.tcl core/history/libgxtxt_history.so core/tcl/scientific_history_native.tcl core/tcl/scientific_recipe_history.tcl core/tcl/interactive_document_api_v1.tcl plugins/modules/viewer.scientific_worksheet/ui/worksheet_ux_v3.tcl plugins/modules/viewer.curve_viewer/api/curve_viewer_api_v1.tcl plugins/modules/viewer.curve_viewer/api/curve_viewer_integrated.tcl plugins/modules/viewer.dataset_curve_fit/api/curve_fit_history.tcl plugins/modules/viewer.dataset_curve_fit/api/curve_fit_workspace_v2.tcl plugins/modules/viewer.replicate_curve_analysis/api/replicate_viewer.tcl} {dict set sourcePins $relative [::GX::sha256File [file join $framework $relative]]}
::P017Manual::emit source_pins $sourcePins
proc bgerror {message} {lappend ::P017Manual::background [dict create message $message errorInfo $::errorInfo];::P017Manual::emit background $::P017Manual::background;puts stderr "BACKGROUND: $message"}
after 110000 {::P017Manual::emit WATCHDOG {GUI watchdog elapsed};catch {::P017Manual::shot failure_watchdog $::w};exit 124}
try {
    source [file join [file dirname [info script]] $mode.tcl]
    ::P017Manual::run
    ::P017Manual::check {$::P017Manual::background eq {}} {No Tcl/Tk background errors}
    ::P017Manual::emit input $::P017Manual::input
    ::P017Manual::emit receipt [dict create status PASS_MANUAL_HISTORY mode $mode framework $framework checks $::P017Manual::checks scope {Actual mapped private GUI; pointer/keyboard where recorded; automated focused acceptance, final human acceptance remains open}]
} on error {message options} {
    ::P017Manual::emit FIRST_FAILURE [dict create message $message options $options]
    ::P017Manual::emit input $::P017Manual::input
    if {[info exists ::w] && [winfo exists $::w]} {catch {::P017Manual::shot FIRST_FAILURE $::w}}
    puts stderr [dict get $options -errorinfo];exit 1
} finally {catch {destroy .}}
exit 0
