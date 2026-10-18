# SPDX-License-Identifier: GPL-3.0-or-later
toplevel .plotdemo;wm title .plotdemo {Plot v4 · display-only RAM demonstration};wm geometry .plotdemo 900x650+130+90
set model {title {DEMO · synthetic laboratory response} panels {{id main title {RAM model · no Dataset} axes {x {label {Display time (demo units)}} left {label {Response (demo units)}}} annotations {} series {{id demo_signal kind line_marker label {Synthetic response} axis left points {{0 1} {1 1.4} {2 2.1} {3 2.6} {4 2.2} {5 3.1} {6 3.5} {7 3.3} {8 4.2} {9 4.5} {10 4.1}} source_rows {0 1 2 3 4 5 6 7 8 9 10} full_bounds {0 1 10 4.5} style {color #245caa marker circle}}}}}}
::GX::nativePlotDisplayCreate .plotdemo.plot $model
pack .plotdemo.plot -fill both -expand 1
settle 450;capture .plotdemo plot_display_initial
record plot_initial [::GX::nativePlotDisplayInspect .plotdemo.plot]
set x [expr {[winfo rootx .plotdemo.plot]+450}];set y [expr {[winfo rooty .plotdemo.plot]+320}]
exec xdotool mousemove $x $y;exec xdotool click 4;settle
capture .plotdemo plot_display_zoom;record plot_zoom [::GX::nativePlotDisplayInspect .plotdemo.plot]
exec xdotool mousemove $x $y;exec xdotool mousedown 2;update;exec xdotool mousemove [expr {$x+40}] [expr {$y+20}];update;exec xdotool mouseup 2;settle
record plot_pan [::GX::nativePlotDisplayInspect .plotdemo.plot]
exec xdotool mousemove $x $y;exec xdotool click --repeat 2 --delay 100 1;settle
record plot_fit [::GX::nativePlotDisplayInspect .plotdemo.plot]
wm geometry .plotdemo 620x440;settle;capture .plotdemo plot_display_small
wm geometry .plotdemo 1100x800;settle;capture .plotdemo plot_display_large
record plot_display_finished [dict create session $::GX::currentSession widget_class [winfo class .plotdemo.plot]]
