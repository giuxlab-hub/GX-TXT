# SPDX-License-Identifier: GPL-3.0-or-later
proc settle {{ms 220}} {after $ms [list set ::settled 1];vwait ::settled;update}
proc treePointer {tree id} {
 raise [winfo toplevel $tree];$tree see $id;update
 lassign [$tree bbox $id] x y width height
 exec xdotool mousemove [expr {[winfo rootx $tree]+$x+40}] [expr {[winfo rooty $tree]+$y+$height/2}]
 exec xdotool click 1;settle 80
}
::GX::viewerOpen viewer.interface_builder interface_builder
settle 300
set ::galleryModelBefore $::GX::InterfaceBuilder::s(model)
set ::galleryDirtyBefore [::GX::InterfaceBuilder::dirty]
set ::galleryCatalog [::GX::viewerGuiComponentDemoCatalog]
record gallery_runtime_catalog $::galleryCatalog
capture .gxInterfaceDesigner builder_gallery_entry
# Actual shortcut/menu button traversal is retained; Gallery itself is a public Builder client.
::GX::InterfaceBuilder::gallery
settle
capture .gxComponentGallery gallery_initial
set ::galleryCases {}
foreach type [dict keys $::galleryCatalog] {
 if {[dict get $::galleryCatalog $type capability status] ne {AVAILABLE}} continue
 treePointer .gxComponentGallery.body.list.types $type
 click .gxComponentGallery.controls.show
 settle 500
 if {$type eq {native3d}} {
  set handle [dict get $::GX::ViewerGui::instances .gxComponentDemo native3d example]
  set deadline [expr {[clock seconds]+50}]
  while {[dict get [::GX::native3DViewportInspect $handle] status] ne {ready}} {
   set r [::GX::native3DViewportInspect $handle]
   if {[dict get $r status] in {error stale_source}||[clock seconds]>$deadline} {error "Gallery Native3D failed to render: $r"}
   settle 80
  }
 }
 if {![winfo exists .gxComponentDemo]} {error "No actual $type demonstration"}
 capture .gxComponentDemo gallery_${type}_demo
 record gallery_${type}_inspection [::GX::viewerGuiRuntimeInspect .gxComponentDemo]
 if {[llength [info commands ::GX::viewerGuiTestPlan]]} {
  set plan [::GX::viewerGuiTestPlan .gxComponentDemo {structure demo}]
  set ::gallerySuiteDone 0
  set id [::GX::viewerGuiTestsStart .gxComponentDemo $plan {apply {{result} {set ::gallerySuite $result;set ::gallerySuiteDone 1}}}]
  while {!$::gallerySuiteDone} {settle 40}
  record gallery_${type}_suite $::gallerySuite
 }
 lappend ::galleryCases $type
 if {$::GX::InterfaceBuilder::s(model) ne $::galleryModelBefore||[::GX::InterfaceBuilder::dirty] ne $::galleryDirtyBefore} {error {Gallery changed the actual Builder project}}
}
record gallery_mounted_types $::galleryCases
capture .gxComponentGallery gallery_complete_inventory
click .gxComponentGallery.controls.close
if {$::GX::InterfaceBuilder::s(model) ne $::galleryModelBefore} {error {Demo→Design changed project model/Undo/Redo}}
capture .gxInterfaceDesigner builder_return_from_gallery
record gallery_finished [dict create count [llength $::galleryCases] session $::GX::currentSession project_unchanged 1]
