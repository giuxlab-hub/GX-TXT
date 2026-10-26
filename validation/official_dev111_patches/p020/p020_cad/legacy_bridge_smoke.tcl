# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv]!=2} {error {Usage: legacy_bridge_smoke.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework output
set framework [file normalize $framework];set output [file normalize $output]
if {[file exists $output]} {error {Use a fresh output directory}}
file mkdir $output
set ::env(XDG_CONFIG_HOME) [file join $output config]
set ::env(XDG_DATA_HOME) [file join $output data]
set ::env(XDG_CACHE_HOME) [file join $output cache]
set argv0 __legacy_sketch_smoke__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk
set ::GX::cfg(output_root) [file join $output sessions]
::GX::createNewSession p020_legacy_sketch
::GX::configurationSet viewers.native3d.execution Software
::GX::configurationSet storage.cache_dir [file join $output cache]
if {[string first "$output/" [file normalize $::GX::currentSession]]!=0 || [string first "$output/" [::GX::configurationPath]]!=0 || [::GX::configurationCacheDirectory] ne [file join $output cache]} {error {Legacy fixture escaped its private roots}}
proc assert {expression message} {if {![uplevel 1 [list expr $expression]]} {error $message};puts "PASS $message"}
set ::backgroundErrors {}
proc bgerror {message} {lappend ::backgroundErrors [list $message $::errorInfo]}
proc settleOwner {} {
    set deadline [expr {[clock milliseconds]+15000}]
    while {$::GX::Engine3D::workerBusy && [clock milliseconds]<$deadline} {update;after 20}
    if {$::GX::Engine3D::workerBusy} {error {Legacy renderer did not become idle}}
}
::GX::viewerOpen viewer.3d_workbench workbench_3d
update;settleOwner
::GX::viewerSceneSet viewer.3d_workbench workbench_3d {working_plane_origin {2;3;4} working_plane_normal {0;1;1} working_plane_u_axis {1;0;0}}
set parent [dict get [::GX::Workbench3D::guiInspect] document_id]
set receipt [::GX::Workbench3D::guiCommand sketch_create]
set sketch [dict get $receipt component]
assert {[::GX::nativeCadSketchIsManaged $sketch]} {legacy finite create uses the same public managed CORE Sketch}
assert {[dict get $receipt workbench_document_id] eq $parent && [dict get [$sketch get plane] origin] eq {2.0 3.0 4.0}} {legacy owner and oriented working plane are retained}
assert {[$sketch get working_unit] eq [dict get [::GX::Workbench3D::guiInspect] working_unit]} {legacy working unit is retained}
set advanced [$sketch get advanced]
$advanced construction start rectangle
$advanced construction adopt {{point {0 0}} {point {5 3}}}
$advanced construction commit
set exact [$sketch get model];set child [$sketch get document_id]
$sketch save
settleOwner
::GX::Workbench3D::guiCommand sketch_close
set receipt [::GX::Workbench3D::guiCommand sketch_open [dict create document_id $child]]
set sketch [dict get $receipt component]
assert {[$sketch get model] eq $exact} {legacy finite open restores the exact same Sketch Document}
assert {[dict get [::GX::Workbench3D::guiInspect] document_id] eq $parent} {Sketch reopen preserves the canonical legacy parent}
settleOwner
::GX::Engine3D::close
set deadline [expr {[clock milliseconds]+3000}]
while {[dict get [::GX::native3DGuiHostApiInfoV2] retiring_workers]>0 && [clock milliseconds]<$deadline} {update;after 20}
assert {![llength [info commands $sketch]]} {legacy Workbench close closes its managed Sketch component}
if {[llength $::backgroundErrors]} {puts stderr $::backgroundErrors}
assert {![llength $::backgroundErrors]} {legacy bridge has no asynchronous GUI errors}
puts {PASS legacy Sketch bridge complete}
destroy .
exit 0
