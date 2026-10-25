# Focused genuine XTEST editing scenarios, same retained fixture before/after.
proc canvasClick {xy {modifier {}}} {
 movePointer $xy
 if {$modifier ne {}} {exec xdotool keydown $modifier}
 exec xdotool click 1
 if {$modifier ne {}} {exec xdotool keyup $modifier}
 pause 150
}
proc popupEntry {menu pattern} {
 set i [menuIndex $menu $pattern];set h [expr {[font metrics [$menu cget -font] -linespace]+6}]
 if {$i<[$menu index end]} {set h [expr {[$menu yposition [expr {$i+1}]]-[$menu yposition $i]}]}
 exec xdotool mousemove [expr {[winfo rootx $menu]+[winfo width $menu]/2}] [expr {[winfo rooty $menu]+[$menu yposition $i]+$h/2}] click 1
 pause 100
}
proc selectMode {pattern} {
 set button [::GX::native2DViewportPanelWidget $::canvas controls].body.select
 click $button;exec xdotool click 3;pause 100
 popupEntry $::w.toolContext $pattern
}
proc xy {point} {return [::GX::Native2D::core device $::scene $point]}
proc native {id} {return [dict get [::GX::CurveWorkbench::_record $::w $id] native]}
proc curvePoints {id} {return [::GX::Native2D::core points $::scene [native $id]]}
proc fixture {name family controls} {
 ::GX::CurveWorkbench::_sketchApply $::w $::GX::CurveWorkbench::st($::w,token) {} [dict create family $family controls $controls radius_x 1 radius_y 1 rotation 0 angle_start 0 angle_sweep 360 closed 0 samples 64 name $name]
 return $::GX::CurveWorkbench::st($::w,active)
}
set a [lindex $ids 0];set b [lindex $ids 2]
if {![info exists ::env(P018_TOPOLOGY_ONLY)] && ![info exists ::env(P018_RELATIONS_ONLY)] && ![info exists ::env(P018_JOIN_ONLY)]} {
set a [lindex $ids 0];set b [lindex $ids 2]
if {![info exists ::env(P018_SKIP_SELECTION)]} {
set selectionHistory [dict get [::GX::scientificHistoryViewerStatus $w] count]
selectCurve $a;::GX::CurveWorkbench::_fit $w 1;pause 150
selectMode {Select Entire*}
set cp [curvePoints $a];set mid [list [expr {([lindex $cp 1 0]+[lindex $cp 2 0])/2}] [expr {([lindex $cp 1 1]+[lindex $cp 2 1])/2}]]
canvasClick [xy $mid]
check {[dict get [lindex [::GX::CurveWorkbench::_semanticMembers $w] 0] kind] eq {object}} {actual entire-object pick and corresponding selection highlight}
shot selected-object
# Fit all enables additive/subtractive picks on separate existing paths.
::GX::CurveWorkbench::_fit $w;pause 120
canvasClick [xy [lindex [curvePoints $b] 0]] Control_L
check {[llength [::GX::CurveWorkbench::_semanticMembers $w]]==2} {actual additive selection}
canvasClick [xy [lindex [curvePoints $b] 0]] Shift_L
check {[llength [::GX::CurveWorkbench::_semanticMembers $w]]==1} {actual subtractive selection}
selectCurve $a;::GX::CurveWorkbench::_fit $w 1;pause 100
selectMode {Rectangle selection}
set view [::GX::Native2D::core view $scene];lassign $view cw ch left top right bottom
movePointer [list [expr {$left+12}] [expr {$top+35}]];exec xdotool mousedown 1
movePointer [list [expr {$cw-$right-10}] [expr {$ch-$bottom-10}]];exec xdotool mouseup 1;pause 150
check {[llength [::GX::CurveWorkbench::_semanticMembers $w]]>=1} {actual area-selection operation}
selectMode {Local Geometry*}
canvasClick [xy $mid]
set ref [lindex [::GX::CurveWorkbench::_semanticMembers $w] 0]
check {[dict get $ref kind] eq {segment}} {actual interior-segment selection}
shot selected-segment
check {[dict get [::GX::scientificHistoryViewerStatus $w] count]==$selectionHistory} {object segment additive subtractive region selection and repaint add no scientific History step}
 }
selectCurve $a;::GX::CurveWorkbench::_fit $w 1;pause 120
selectMode {Local Geometry*}
set control [dict get [lindex [::GX::Native2D::core interaction_controls $scene [native $a]] 3] point]
canvasClick [xy $control]
check {[dict get [lindex [::GX::CurveWorkbench::_semanticMembers $w] 0] kind] eq {control}} {actual defining-control selection}
shot selected-control
# A real retained spline control is dragged, not a sampled display point.
set spline [lindex $ids 1];selectCurve $spline;::GX::CurveWorkbench::_fit $w 1;pause 120
set handles [::GX::Native2D::core interaction_controls $scene [native $spline]]
set start [xy [dict get [lindex $handles 3] point]];set before [curvePoints $spline];set unrelated [curvePoints $b]
movePointer $start;exec xdotool mousedown 1;pause 50
movePointer [list [expr {[lindex $start 0]+16}] [expr {[lindex $start 1]-20}]];pause 90;exec xdotool mouseup 1;pause 150
check {[curvePoints $spline] ne $before && [curvePoints $b] eq $unrelated && ![::GX::Native2D::core drag_active $scene]} {real spline control drag changes only intended geometry}
set edited [curvePoints $spline];shot spline-edited
click $w.toolbar.undo;check {[curvePoints $spline] eq $before} {spline control Undo}
click $w.toolbar.redo;check {[curvePoints $spline] eq $edited} {spline control Redo}
click $w.toolbar.undo
# Dataset spline is presentation only; original rows and source identity survive.
selectCurve $datasetCurve
menuChoose $w.sketchbar.represent {Dataset display: spline}
check {[dict get [::GX::CurveWorkbench::_record $w $datasetCurve] display_style] eq {spline} && [::GX::sessionInspectionDatasetPayload source018] eq $sourceBefore} {Dataset spline display uses actual menu and leaves original Dataset unchanged}
::GX::CurveWorkbench::_fit $w 1;pause 100;shot dataset-spline
menuChoose $w.sketchbar.represent {Dataset display: straight}
}
if {![info exists ::env(P018_RELATIONS_ONLY)] && ![info exists ::env(P018_JOIN_ONLY)]} {
# Native retained shapes supplement the50path stress workspace.
set lineA [fixture {Join A} line {{22 0} {24 0}}]
set lineB [fixture {Join B} quadratic_bezier {{24 0} {25 1} {26 0}}]
set circle [fixture Circle circle {{22 3}}]
set rect [fixture Rectangle rectangle {{25 2} {27 4}}]
selectCurve $lineA
# Selection through the real tree's extended-selection gesture.
set tree $w.leftScroll.viewport.content.curves;$tree see $lineB;pause 70;lassign [$tree bbox $lineB name] x y width height
exec xdotool keydown Control_L mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1 keyup Control_L;pause 150
menuChoose $w.sketchbar.modify {Join Path*}
check {[winfo ismapped $w.pathJoin]} {Join Path opens actual reviewed composition form}
click $w.pathJoin.actions.apply
check {$::GX::UiField::formStatus($w.pathJoin) eq {Applied.}} {Join Path completes through GUI review}
click $w.pathJoin.actions.close
set joined $::GX::CurveWorkbench::st($w,active)
check {[dict get [::GX::CurveWorkbench::_record $w $joined] sketch_definition family] eq {composite_path} && ![dict exists $::GX::CurveWorkbench::st($w,curves) $lineA]} {connected exact constituents become one logical Path}
selectCurve $joined;::GX::CurveWorkbench::_fit $w 1;pause 120
set states [::GX::Native2D::core composition_states $scene [native $joined]]
set part [dict get [lindex $states 0] part_id]
# Actual context menu exposes a constituent's direction command.
set marker [::GX::Native2D::core part_marker_render $scene [native $joined] $part]
if {$marker eq {}} {
 set pp [::GX::Native2D::core part_render $scene [native $joined] $part]
 movePointer [lindex $pp [expr {[llength $pp]/2}]];exec xdotool click 3;pause 150
 popupEntry $w.right.viewport.canvasContext {Show direction for this subpath}
 set states [::GX::Native2D::core composition_states $scene [native $joined]]
 set marker [::GX::Native2D::core part_marker_render $scene [native $joined] $part]
}
if {$marker ne {}} {
 movePointer [dict get $marker tip];exec xdotool click 3;pause 100
 popupEntry $w.right.viewport.canvasContext {Flip this subpath}
 set now [::GX::Native2D::core part_direction $scene [native $joined] $part]
 check {[dict get $now forward] != [dict get [lindex $states 0] direction forward]} {constituent direction Flip through real canvas context menu}
 shot constituent-arrow
} else {error {Constituent direction marker unavailable in fixture}}
set sourceGeometry [curvePoints $joined]
menuChoose $w.sketchbar.modify {Separate exact constituents}
set separated $::GX::CurveWorkbench::st($w,objectSelection)
check {[llength $separated]==2 && [curvePoints $joined] eq $sourceGeometry} {Separate creates exact constituent copies and preserves original Path}
set constituent [lindex $separated 0]
selectCurve $constituent;::GX::CurveWorkbench::_fit $w 1;pause 120
set tree $w.leftScroll.viewport.content.points;$tree see h1;pause 40;lassign [$tree bbox h1] x y width height
exec xdotool mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1;pause 80
set before [curvePoints $constituent]
typeInto $w.leftScroll.viewport.content.numeric.editY 0.2;click $w.leftScroll.viewport.content.numeric.apply
check {[curvePoints $constituent] ne $before && [curvePoints $joined] eq $sourceGeometry} {supported separated-constituent edit leaves original composite unchanged}
click $w.toolbar.undo;check {[curvePoints $constituent] eq $before} {separated constituent edit Undo}
# Additional relationship tests are appended by the finite driver below.
}
if {![info exists ::env(P018_JOIN_ONLY)]} {
# Horizontal and fixed relations through the existing constraint menus/Inspector.
proc cascadeChoose {button parent label} {
 click $button;set menu [$button cget -menu];set i [menuIndex $menu $parent]
 set sub [$menu entrycget $i -menu]
 exec xdotool mousemove [expr {[winfo rootx $menu]+70}] [expr {[winfo rooty $menu]+[$menu yposition $i]+10}]
 pause 500
 check {[winfo ismapped $sub]} {existing constraint submenu opens}
 popupEntry $sub $label
}
# Use an isolated straight primitive: the original composite and its separated
# copy intentionally overlap, so native picking correctly sees both.
set constituent [fixture {Constraint line} line {{30 4} {34 4}}]
selectCurve $constituent;::GX::CurveWorkbench::_fit $w 1;pause 100
selectMode {Local Geometry*}
set handles [::GX::Native2D::core interaction_controls $scene [native $constituent]]
set p [dict get [lindex $handles 0] point];set q [dict get [lindex $handles 1] point]
canvasClick [xy [list [expr {([lindex $p 0]+[lindex $q 0])/2}] [expr {([lindex $p 1]+[lindex $q 1])/2}]]]
cascadeChoose $w.sketchbar.constraints Directions Horizontal
set horizontal [lindex [dict keys $::GX::CurveWorkbench::st($w,constraints)] end]
check {[dict get [::GX::Native2D::core constraint_get $scene [dict get $::GX::CurveWorkbench::st($w,constraints) $horizontal native]] valid]} {actual Horizontal constraint valid}
selectMode {Local Geometry*}
canvasClick [xy $p]
puts "FIX OPTIONS: [::GX::CurveWorkbench::_constraintOptions $w]";flush stdout
cascadeChoose $w.sketchbar.constraints Fixing Fix
if {$::GX::CurveWorkbench::st($w,constraintTool) eq {fixed}} {canvasClick [xy {32 4}]}
puts "FIX STATE: $::GX::CurveWorkbench::st($w,status), tool=$::GX::CurveWorkbench::st($w,constraintTool), constraints=$::GX::CurveWorkbench::st($w,constraints)";flush stdout
set fixed [lindex [dict keys $::GX::CurveWorkbench::st($w,constraints)] end]
check {[dict get $::GX::CurveWorkbench::st($w,constraints) $fixed definition kind] eq {fixed}} {actual fixed relationship created}
menuChoose $w.sketchbar.constraints {Inspector / dimensions*}
set inspector [::GX::CurveWorkbench::_constraintPanel $w]
check {[winfo ismapped $inspector] && [llength [$inspector.tree children {}]]>=2} {constraint Inspector shows actual relationships}
shot constraints
# Close Inspector before dragging a fixed endpoint; the original native owner rejects it.
click [::GX::native2DViewportPanelWidget $canvas palette].header.toggle
selectMode {Local Geometry*}
set before [curvePoints $constituent];movePointer [xy $p];exec xdotool mousedown 1;pause 50
set start [xy $p];movePointer [list [expr {[lindex $start 0]+20}] [expr {[lindex $start 1]-25}]];pause 100;exec xdotool mouseup 1;pause 150
check {[curvePoints $constituent] eq $before && ![::GX::Native2D::core drag_active $scene]} {fixed/horizontal enforcement rejects invalid real control drag and releases transaction}
menuChoose $w.sketchbar.constraints {Inspector / dimensions*}
set tree $inspector.tree;$tree see $fixed;pause 40;lassign [$tree bbox $fixed] x y width height
exec xdotool mousemove [expr {[winfo rootx $tree]+$x+20}] [expr {[winfo rooty $tree]+$y+$height/2}] click 1;pause 80
click $inspector.actions.toggle
check {[dict get [::GX::Native2D::core constraint_get $scene [dict get $::GX::CurveWorkbench::st($w,constraints) $fixed native]] disabled]} {actual Inspector disables fixed constraint}
click $inspector.actions.remove
check {![dict exists $::GX::CurveWorkbench::st($w,constraints) $fixed]} {actual Inspector removes fixed relation}
click [::GX::native2DViewportPanelWidget $canvas palette].header.toggle
}
proc stockCombo {widget value} {
 click $widget
 set wanted [lsearch -exact [$widget cget -values] $value]
 check {$wanted>=0} {actual form offers target logical identity}
 exec xdotool key Home
 for {set i 0} {$i<$wanted} {incr i} {exec xdotool key Down}
 exec xdotool key Return;pause 120
 check {[$widget get] eq $value} {native readonly form selection committed}
}
# Join point is a coincidence relationship, distinct from the logical Join Path.
set joinSource [fixture {Coincidence A} line {{30 0} {32 0}}]
set joinTarget [fixture {Coincidence B} line {{32 0} {34 0}}]
selectCurve $joinSource;::GX::CurveWorkbench::_fit $w 1;pause 100
selectMode {Local Geometry*};canvasClick [xy {32 0}]
# This established native-tools dialog contains the actual numeric Join command.
menuChoose $w.sketchbar.modify {Native point operations*}
set commands $w.cad.sketch
click $commands;popupEntry [$commands cget -menu] {Join point numerically*}
check {[winfo ismapped $w.join]} {actual Join point review opens}
# The target logical ID stays the native relationship identity, never display text.
stockCombo $w.join.viewport.content.field1.entry $joinTarget
typeInto $w.join.viewport.content.field2.entry 0
click $w.join.actions.apply
check {$::GX::UiField::formStatus($w.join) eq {Applied.}} {Join point commits native coincidence through GUI}
click $w.join.actions.close
set coincidence [lindex [dict keys $::GX::CurveWorkbench::st($w,constraints)] end]
check {[dict get $::GX::CurveWorkbench::st($w,constraints) $coincidence definition kind] eq {coincident}} {Join point creates coincidence rather than replacing logical topology}
if {[winfo manager $w.cad] ne {}} {menuChoose $w.sketchbar.modify {Native point operations*}}
# Baseline and patched scientific topology results are persisted for comparison.
if {![info exists ::env(P018_RELATIONS_ONLY)] && ![info exists ::env(P018_JOIN_ONLY)]} {write [file join $output topology.tcldict] [dict create joined_definition [dict get [::GX::CurveWorkbench::_record $w $joined] sketch_definition] source_preserved [expr {[curvePoints $joined] eq $sourceGeometry}] constraints $::GX::CurveWorkbench::st($w,constraints)]}

if {![info exists ::env(P018_RELATIONS_ONLY)] && ![info exists ::env(P018_JOIN_ONLY)]} {}
