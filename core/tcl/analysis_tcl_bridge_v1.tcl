#!/usr/bin/env tclsh
# GX-TXT CORE standard-Octave companion bridge for public Tcl analysis APIs.
# Plugin code does not source or depend on the desktop host entrypoint.
if {[llength $argv] != 3} {
    error "usage: analysis_tcl_bridge_v1.tcl FRAMEWORK_ROOT MODULE_RUNTIME_TCL RUNTIME_INI"
}
set framework [file normalize [lindex $argv 0]]
set moduleScript [file normalize [lindex $argv 1]]
set configPath [file normalize [lindex $argv 2]]
set allowed [file normalize [file join $framework plugins modules]]
if {[string first "${allowed}/" "${moduleScript}/"] != 0 || ![file isfile $moduleScript]} {
    error "Analysis Tcl Bridge v1: module runtime script must be under framework plugins/modules"
}
if {![file isfile $configPath]} { error "Analysis Tcl Bridge v1: runtime configuration is missing" }
set argv0 __not_main__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
set ::argv [list $framework $configPath]
source $moduleScript
