# SPDX-License-Identifier: GPL-3.0-or-later
proc rtWait {expression {seconds 70}} {set end [expr {[clock seconds]+$seconds}];while {![uplevel 1 [list expr $expression]]} {if {[clock seconds]>$end} {error "Roundtrip timed out: $expression"};settle 80}}
proc rt3Ready {h} {
 set end [expr {[clock seconds]+50}]
 while 1 {set r [::GX::native3DViewportInspect $h];if {[dict get $r status] in {error stale_source}||[clock seconds]>$end} {error "Native roundtrip frame: $r"};if {[dict get $r status] eq {ready}&&[dict get $r busy] eq {}&&[dict get $r pending]==0} {return $r};settle 80}
}
proc rtChooser {path {attempt 0}} {
 set entry {}
 foreach row [widgets] {
  set w [lindex $row 0]
  if {[string match {*.__tk_*dialog.contents.f2.ent} $w]||[string match {*.__tk_choosedir.contents.f2.ent} $w]} {if {[winfo ismapped $w]} {set entry $w;break}}
 }
 if {$entry eq {}} {if {$attempt<40} {after 100 [list rtChooser $path [expr {$attempt+1}]];return};record roundtrip_chooser_missing [widgets];return}
 set dialog [winfo toplevel $entry]
 capture $dialog roundtrip_chooser_[clock microseconds]
 click $entry;key $entry End shift+Home;exec xdotool type --clearmodifiers -- $path;update;key $entry Return
 settle 150
 if {[string match {*__tk_choosedir} $dialog]&&[winfo exists $dialog.contents.f2.ok]&&[winfo ismapped $dialog]} {click $dialog.contents.f2.ok}
}
proc rtNotice {{attempt 0}} {
 set dialog .__tk__messagebox
 if {![winfo exists $dialog]} {if {$attempt<100} {after 100 [list rtNotice [expr {$attempt+1}]]};return}
 set ::roundtripNotice [wm title $dialog]
 capture $dialog roundtrip_plugin_notice
 if {[winfo exists $dialog.ok]} {click $dialog.ok}
}
proc rtButton {action} {return [dict get $::GX::ViewerCommands::windows .gxInterfaceDesigner toolbar buttons $action]}
proc rtOrbit {w component} {
 set handle [dict get $::GX::ViewerGui::instances $w native3d $component]
 set widget [dict get $::GX::ViewerGui::instances $w widgets $component].canvas
 set camera [::GX::native3DViewportCamera $handle]
 raise $w;update;set x [expr {[winfo rootx $widget]+[winfo width $widget]/2}];set y [expr {[winfo rooty $widget]+[winfo height $widget]/2}]
 exec xdotool mousemove $x $y mousedown 1;update;exec xdotool mousemove [expr {$x+75}] [expr {$y+35}];update;exec xdotool mouseup 1;update
 rt3Ready $handle
 if {[::GX::native3DViewportCamera $handle] eq $camera} {error {Actual generated/Preview orbit did not change camera}}
 return [::GX::native3DViewportInspect $handle]
}
