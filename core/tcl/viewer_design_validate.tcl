# SPDX-License-Identifier: GPL-3.0-or-later
# Packaging request: parse inert data through the actual CORE design authority.
lassign $argv framework project operation
set argv0 __gxtxt_viewer_design_validator__
source [file join [file normalize $framework] gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
if {[catch {set design [::GX::viewerGuiDesignRead [file normalize $project]]} message options]} {puts stderr $message;exit 1}
if {$operation eq {describe}} {puts [dict create design $design capabilities [::GX::viewerGuiComponentCapabilities]]} else {puts $design}
