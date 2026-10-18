# SPDX-License-Identifier: GPL-3.0-or-later
proc settle {{ms 180}} {after $ms [list set ::settled 1];vwait ::settled;update}
proc n3wait {h} {
 set deadline [expr {[clock milliseconds]+50000}]
 while 1 {
  set r [::GX::native3DViewportInspect $h]
  if {[dict get $r status] in {error stale_source}} {record native3d_failure $r;error [dict get $r error]}
  if {[dict get $r status] eq {ready} && [dict get $r pending]==0 && [dict get $r busy] eq {}} {return $r}
  if {[clock milliseconds]>$deadline} {error {Timed out waiting for real native frame}}
  settle 80
 }
}
set ::n3events {}
proc n3event {h event detail} {lappend ::n3events [list $h $event $detail]}
foreach {w title geometry} {.n3a {Native3D component · RAM cube and axes} 850x620+40+70 .n3b {Independent Native3D component · RAM demo} 850x620+930+100} {
 toplevel $w;wm title $w $title;wm geometry $w $geometry
 set h [::GX::native3DViewportCreate $w.viewport]
 pack $w.viewport -fill both -expand 1
 set ::n3($w) $h
 foreach event {ready view_changed selected error released} {::GX::native3DViewportSubscribe $h $event n3event}
 ::GX::native3DViewportBind $h {kind demo}
}
foreach w {.n3a .n3b} {record [string trim $w .]_initial [n3wait $::n3($w)];capture $w [string trim $w .]_initial}
set first [::GX::native3DViewportCamera $::n3(.n3a)];set second [::GX::native3DViewportCamera $::n3(.n3b)]
set c .n3a.viewport.canvas;raise .n3a;update
set x [expr {[winfo rootx $c]+350}];set y [expr {[winfo rooty $c]+260}]
exec xdotool mousemove $x $y;exec xdotool mousedown 1;exec xdotool mousemove [expr {$x+110}] [expr {$y+55}];exec xdotool mouseup 1;update
record orbit [n3wait $::n3(.n3a)];capture .n3a n3a_orbit
if {$first eq [::GX::native3DViewportCamera $::n3(.n3a)]} {error {Real orbit did not change camera}}
if {$second ne [::GX::native3DViewportCamera $::n3(.n3b)]} {error {Independent camera changed}}
exec xdotool mousemove $x $y;exec xdotool keydown Shift_L;exec xdotool mousedown 1;exec xdotool mousemove [expr {$x+40}] [expr {$y-20}];exec xdotool mouseup 1;exec xdotool keyup Shift_L;update
record pan [n3wait $::n3(.n3a)];capture .n3a n3a_pan
exec xdotool mousemove $x $y;exec xdotool click 4;update
record zoom [n3wait $::n3(.n3a)];capture .n3a n3a_zoom
click .n3a.viewport.tools.fit;record fit [n3wait $::n3(.n3a)];capture .n3a n3a_fit
wm geometry .n3a 620x440;settle 400;record small [n3wait $::n3(.n3a)];capture .n3a n3a_small
wm geometry .n3a 1100x760;settle 400;record large [n3wait $::n3(.n3a)];capture .n3a n3a_large
::GX::native3DViewportCommand $::n3(.n3a) preset front;n3wait $::n3(.n3a)
set c .n3a.viewport.canvas
click $c
set picked [n3wait $::n3(.n3a)]
record native3d_actual_pick $picked
if {![dict get $picked selection hit]||[dict get $picked selection layer_id] ne {ram_cube}} {error {Actual native cube pick did not identify its RAM layer}}
capture .n3a n3a_actual_selection
set ::n3firstpids [dict get [::GX::native3DViewportInspect $::n3(.n3a)] worker_pids]
destroy .n3a;settle 300
if {[dict exists $::GX::Native3DCanvas::instances $::n3(.n3a)]} {error {Destroyed component retained handle}}
key .n3b.viewport.canvas Right;record survivor [n3wait $::n3(.n3b)];capture .n3b n3b_survives_close
foreach process $::n3firstpids {if {[file exists /proc/$process]} {error {Closed component worker remains alive}}}
record native3d_events $::n3events
record native3d_component_finished [dict create result PASS scope {public two-instance RAM rendering/navigation/lifetime only} instances [dict size $::GX::Native3DCanvas::instances] session $::GX::currentSession]
