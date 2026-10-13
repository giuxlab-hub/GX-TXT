#!/usr/bin/env tclsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Generate the installed plugin/contract reference from descriptor metadata.
set here [file dirname [file normalize [info script]]]
set root [file dirname $here]
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
set out [expr {[llength $argv] ? [file normalize [lindex $argv 0]] : [file join $root docs reference INSTALLED_PLUGIN_REFERENCE.md]}]
puts [::GX::generateInstalledReference $out]
