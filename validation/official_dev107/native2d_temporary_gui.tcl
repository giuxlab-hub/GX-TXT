# SPDX-License-Identifier: GPL-3.0-or-later
proc settle {{ms 200}} {after $ms [list set ::settled 1];vwait ::settled;update}
toplevel .temporary;wm geometry .temporary 900x650+70+70;wm title .temporary {Native2D · display-only RAM interaction}
::GX::native2DTemporaryDisplayCreate .temporary.demo
pack .temporary.demo -fill both -expand 1
settle 450
set initial [::GX::native2DTemporaryDisplayInspect .temporary.demo]
record initial $initial
capture .temporary temporary_initial
set ::n2scene [dict get [::GX::native2DTemporaryDisplayInspect .temporary.demo] scene]
lassign [::GX::Native2D::core device $::n2scene {3 5}] px py
set ::n2x [expr {int([winfo rootx .temporary.demo.canvas]+$px)}];set ::n2y [expr {int([winfo rooty .temporary.demo.canvas]+$py)}]
exec xdotool mousemove $::n2x $::n2y;exec xdotool mousedown 1;update
exec xdotool mousemove [expr {$::n2x+75}] [expr {$::n2y-45}];settle 120
capture .temporary temporary_dragging 0
exec xdotool mouseup 1;settle
record dragged [::GX::native2DTemporaryDisplayInspect .temporary.demo]
capture .temporary temporary_dragged
lassign [lindex [dict get [::GX::native2DTemporaryDisplayInspect .temporary.demo] points] 0] movedX movedY
if {abs($movedX-4.247524752475248)>0.03 || abs($movedY-5.7798839458413926)>0.03} {error {Native move does not match independently mapped pointer delta}}
set before [dict get [::GX::native2DTemporaryDisplayInspect .temporary.demo] points]
if {$before eq [dict get $initial points]} {error {Real shape drag did not change native coordinates}}
click .temporary.demo.tools.pan
exec xdotool mousemove $::n2x $::n2y;exec xdotool mousedown 1;exec xdotool mousemove [expr {$::n2x+40}] [expr {$::n2y+30}];exec xdotool mouseup 1;settle
if {[dict get [::GX::native2DTemporaryDisplayInspect .temporary.demo] points] ne $before} {error {Pan incorrectly changed RAM object geometry}}
record panned [::GX::native2DTemporaryDisplayInspect .temporary.demo]
exec xdotool mousemove $::n2x $::n2y;exec xdotool click 4;settle
record zoomed [::GX::native2DTemporaryDisplayInspect .temporary.demo]
capture .temporary temporary_zoomed
click .temporary.demo.tools.fit;click .temporary.demo.tools.reset;settle
record reset [::GX::native2DTemporaryDisplayInspect .temporary.demo]
capture .temporary temporary_reset
wm geometry .temporary 620x440;settle;capture .temporary temporary_small
wm geometry .temporary 1100x800;settle;capture .temporary temporary_large
record temporary_finished 1
