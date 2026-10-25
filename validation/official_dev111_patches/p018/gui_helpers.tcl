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
