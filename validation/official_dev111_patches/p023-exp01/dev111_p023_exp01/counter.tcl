# SPDX-License-Identifier: GPL-3.0-or-later
# Temporary validation instrumentation only; no scientific mutation.
namespace eval ::EXP01Counter {variable counts {};variable samples {};variable spans {};variable stack {};variable targets {};variable mode count;variable entered 0}
proc ::EXP01Counter::native {command op} {
 variable counts;variable samples;variable entered
 incr entered
 set key [lindex $command 1]
 if {![dict exists $counts $key] && [dict size $counts]>=512} {set key @other}
 dict incr counts $key
 if {![dict exists $samples $key]} {
  set chain {};for {set i 1} {$i<=6} {incr i} {if {[catch {info frame -$i} frame]} break;foreach k {cmd proc method class file line} {if {[dict exists $frame $k]} {dict set frame $k [string range [dict get $frame $k] 0 220]}};lappend chain $frame}
  dict set samples $key $chain
 }
}
proc ::EXP01Counter::span {command args} {
 variable stack;variable spans
 set key [lindex $command 0];set op [lindex $args end]
 if {$op eq {enter}} {dict lappend stack $key [clock microseconds];return}
 if {![dict exists $stack $key] || ![llength [dict get $stack $key]]} return
 set all [dict get $stack $key];set start [lindex $all end];dict set stack $key [lrange $all 0 end-1];set elapsed [expr {[clock microseconds]-$start}]
 if {![dict exists $spans $key]} {dict set spans $key [dict create calls 0 inclusive_us 0 maximum_us 0]}
 set row [dict get $spans $key];dict incr row calls;dict incr row inclusive_us $elapsed;dict set row maximum_us [expr {max([dict get $row maximum_us],$elapsed)}];dict set spans $key $row
}
proc ::EXP01Counter::start {{selection count}} {
 variable counts;variable samples;variable spans;variable stack;variable targets;variable entered;variable mode
 if {[llength $targets]} {error {Counter already active}}
 set counts {};set samples {};set spans {};set stack {};set entered 0;set mode $selection
 if {$selection in {count both} && ![llength [info commands ::GX::Native2D::core]]} {::GX::native2DEnsure}
 if {$selection in {count both}} {trace add execution ::GX::Native2D::core enter ::EXP01Counter::native;lappend targets [list ::GX::Native2D::core enter ::EXP01Counter::native]}
 if {$selection in {span both}} {
  foreach command {::GX::nativeCadSketchCreate ::GX::interactiveDocumentRead ::GX::_interactiveDocumentRegistryRead ::GX::sha256File ::GX::native3DGeometryOpen ::GX::native3DGeometryCall ::GX::native3DGeometryCall_organization_base ::GX::scientificHistoryContextAttach ::GX::Engine3D::rpc ::GX::Engine3D::rerender ::GX::Engine3D::displayNativePng ::GX::_native3DViewportPresentFrame ::GX::native2DPresentationObjectSnapshot ::GX::interactiveDocumentReadCached ::GX::nativeCadSketchQuickOpenPublish ::GX::nativeCadSketchQuickOpenPresentation ::GX::_native2DCadMenuBuild ::GX::native2DCadStockIcon ::GX::viewerGuiIconCatalog ::GX::viewerGuiIconImport ::GX::viewerGuiIconPhoto ::GX::_viewerGuiIconPathPhoto ::GX::viewerGuiIconsValidate} {
   if {[llength [info commands $command]]} {trace add execution $command {enter leave} ::EXP01Counter::span;lappend targets [list $command {enter leave} ::EXP01Counter::span]}
  }
 }
 return $selection
}
proc ::EXP01Counter::stop {} {
 variable counts;variable samples;variable spans;variable targets;variable entered;variable mode
 foreach row $targets {lassign $row command operations callback;trace remove execution $command $operations $callback};set targets {}
 return [dict create mode $mode calls $entered operations $counts caller_samples $samples inclusive_spans $spans truncation 0 bounded_keys 512]
}
