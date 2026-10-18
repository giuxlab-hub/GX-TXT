# SPDX-License-Identifier: GPL-3.0-or-later
# Disposable presentation scenes over the existing Native2D engine and host.
namespace eval ::GX::Temporary2D {variable instances {};variable mode;variable serial 0}
proc ::GX::native2DTemporaryDisplayApiInfo {} {return [dict create api_id NATIVE2D_TEMPORARY_DISPLAY_API_v1 api_version 1 operations {create inspect reset mode navigate cancel destroy} commands {native2DTemporaryDisplayCreate native2DTemporaryDisplayInspect native2DTemporaryDisplayReset native2DTemporaryDisplayMode native2DTemporaryDisplayNavigate native2DTemporaryDisplayCancel native2DTemporaryDisplayDestroy} renderer NATIVE2D_API_v1 provenance display_only_RAM publication 0 instance_limit 8]}
proc ::GX::native2DTemporaryDisplayCreate {widget {callback {}}} {
    if {[dict size $::GX::Temporary2D::instances]>=8} {error {Temporary Native2D display limit reached}}
    native2DEnsure
    ttk::frame $widget;ttk::frame $widget.tools
    set ::GX::Temporary2D::mode($widget) move
    foreach {id label} {move {Select / Move} pan Pan} {
        ttk::radiobutton $widget.tools.$id -text $label -value $id -variable ::GX::Temporary2D::mode($widget) -command [list ::GX::native2DTemporaryDisplayCancel $widget]
        pack $widget.tools.$id -side left -padx 4 -pady 3
    }
    ttk::button $widget.tools.fit -text Fit -command [list ::GX::native2DTemporaryDisplayNavigate $widget fit]
    ttk::button $widget.tools.reset -text Reset -command [list ::GX::native2DTemporaryDisplayReset $widget]
    ttk::label $widget.status -text {DEMO / synthetic content · Move the orange shape; wheel zooms · Esc cancels} -anchor w -wraplength 550
    pack $widget.tools.fit $widget.tools.reset -side left -padx 3
    canvas $widget.canvas -width 600 -height 380 -background white -highlightthickness 0 -takefocus 1
    pack $widget.tools -side top -fill x;pack $widget.status -side bottom -fill x;pack $widget.canvas -fill both -expand 1
    dict set ::GX::Temporary2D::instances $widget [dict create scene {} callback $callback pending {} drag {} events {} generation 0]
    bind $widget <Destroy> [list ::GX::_temporary2DDispose $widget %W]
    try {native2DTemporaryDisplayReset $widget} on error {message opts} {destroy $widget;return -options $opts $message}
    bind $widget.canvas <Configure> [list ::GX::_temporary2DSchedule $widget]
    bind $widget.canvas <ButtonPress-1> [list ::GX::_temporary2DPress $widget %x %y]
    bind $widget.canvas <B1-Motion> [list ::GX::_temporary2DMotion $widget %x %y]
    bind $widget.canvas <ButtonRelease-1> [list ::GX::_temporary2DEnd $widget]
    bind $widget.canvas <Escape> [list ::GX::native2DTemporaryDisplayCancel $widget]
    bind $widget.canvas <Button-4> [list ::GX::native2DTemporaryDisplayNavigate $widget zoom 1.2 %x %y]
    bind $widget.canvas <Button-5> [list ::GX::native2DTemporaryDisplayNavigate $widget zoom 0.833333333333 %x %y]
    return $widget
}
proc ::GX::_temporary2DRecord {w} {if {![dict exists $::GX::Temporary2D::instances $w]} {error {Temporary Native2D display is closed}};return [dict get $::GX::Temporary2D::instances $w]}
proc ::GX::native2DTemporaryDisplayReset {w} {
    set r [_temporary2DRecord $w]
    native2DTemporaryDisplayCancel $w
    if {[dict get $r scene] ne {}} {::GX::Native2D::core destroy [dict get $r scene]}
    set scene [::GX::Native2D::core scene]
    dict set ::GX::Temporary2D::instances $w scene $scene
    ::GX::Native2D::core aspect $scene auto
    ::GX::Native2D::core grid $scene {enabled 1 visible 1 snap_enabled 0}
    set curve [::GX::Native2D::core add $scene {{0 1} {1 1.4} {2 2.1} {3 2.6} {4 2.2} {5 3.1} {6 3.5} {7 3.3} {8 4.2} {9 4.5} {10 4.1}}]
    set markers [::GX::Native2D::core pointset $scene {{1 1.4} {3 2.6} {5 3.1} {7 3.3} {9 4.5}}]
    set shape [::GX::Native2D::core add $scene {{3 5} {5 5} {5 7} {3 7} {3 5}}]
    foreach id [list $curve $markers] {::GX::Native2D::core object_style $scene $id {color {0.12 0.35 0.68 1} line_width 2 marker 1 visible 1 locked 1}}
    ::GX::Native2D::core object_style $scene $shape {color {0.85 0.33 0.05 1} line_width 3 marker 1 visible 1 locked 0}
    ::GX::Native2D::core fit_bounds $scene {-1 0 11 8}
    dict set r scene $scene;dict set r shape $shape;dict set r drag {};dict incr r generation
    dict set ::GX::Temporary2D::instances $w $r
    if {[dict exists $::GX::ViewportHost::hosts $w.canvas]} {dict set ::GX::ViewportHost::hosts $w.canvas scene $scene} else {native2DViewportHostCreate $w $w.canvas $scene [list ::GX::_temporary2DSchedule $w]}
    _temporary2DEmit $w reset {};_temporary2DSchedule $w
}
proc ::GX::_temporary2DSchedule {w} {
    if {![dict exists $::GX::Temporary2D::instances $w]||[dict get $::GX::Temporary2D::instances $w pending] ne {}} return
    dict set ::GX::Temporary2D::instances $w pending [after idle [list ::GX::_temporary2DDraw $w]]
}
proc ::GX::_temporary2DDraw {w} {
    if {![dict exists $::GX::Temporary2D::instances $w]||![winfo exists $w.canvas]} return
    dict set ::GX::Temporary2D::instances $w pending {}
    if {[winfo width $w.canvas]<160||[winfo height $w.canvas]<120} return
    set scene [dict get [_temporary2DRecord $w] scene]
    set view [::GX::Native2D::core view_requested $scene]
    lset view 0 [winfo width $w.canvas];lset view 1 [winfo height $w.canvas];set view [lreplace $view 2 5 68 38 24 55]
    ::GX::Native2D::core view $scene $view
    native2DCanvasSnapshot $w.canvas [native2DPresentationSnapshot $scene {title {DEMO · synthetic response and movable shape} x_label {Display X (demo units)} y_label {Display Y (demo units)} point_budget 256}]
}
proc ::GX::native2DTemporaryDisplayMode {w mode} {if {$mode ni {move pan}} {error {Choose move or pan}};_temporary2DRecord $w;native2DTemporaryDisplayCancel $w;set ::GX::Temporary2D::mode($w) $mode}
proc ::GX::_temporary2DPress {w x y} {
    set r [_temporary2DRecord $w];set scene [dict get $r scene];focus $w.canvas
    if {$::GX::Temporary2D::mode($w) eq {pan}} {dict set r drag [dict create kind pan device [list $x $y]]} else {
        set hit [::GX::Native2D::core hit_point_device $scene [dict get $r shape] [list $x $y] 9]
        if {$hit eq {}} {_temporary2DEmit $w miss [dict create device [list $x $y]];return}
        ::GX::Native2D::core select_object $scene [dict get $r shape] replace
        ::GX::Native2D::core drag_begin $scene
        dict set r drag [dict create kind move world [::GX::Native2D::core world $scene [list $x $y]] device [list $x $y]]
    }
    dict set ::GX::Temporary2D::instances $w $r
    _temporary2DEmit $w start [dict get $r drag]
}
proc ::GX::_temporary2DMotion {w x y} {
    set r [_temporary2DRecord $w];set drag [dict get $r drag];if {$drag eq {}} return
    set scene [dict get $r scene];lassign [dict get $drag device] px py
    if {[dict get $drag kind] eq {pan}} {
        ::GX::Native2D::core pan $scene [expr {$x-$px}] [expr {$y-$py}]
        dict set ::GX::Temporary2D::instances $w drag device [list $x $y]
        set detail [dict create kind pan device [list $x $y] device_delta [list [expr {$x-$px}] [expr {$y-$py}]]]
    } else {
        lassign [dict get $drag world] wx wy;lassign [::GX::Native2D::core world $scene [list $x $y]] nx ny
        set dx [expr {$nx-$wx}];set dy [expr {$ny-$wy}]
        ::GX::Native2D::core drag_translate $scene $dx $dy
        set detail [dict create kind move object [dict get $r shape] device [list $x $y] world [list $nx $ny] world_delta [list $dx $dy]]
    }
    _temporary2DEmit $w update $detail;_temporary2DSchedule $w
}
proc ::GX::_temporary2DEnd {w} {
    set r [_temporary2DRecord $w];set drag [dict get $r drag];if {$drag eq {}} return
    if {[dict get $drag kind] eq {move}} {::GX::Native2D::core drag_commit [dict get $r scene]}
    dict set ::GX::Temporary2D::instances $w drag {}
    _temporary2DEmit $w end [dict create kind [dict get $drag kind] object [dict get $r shape]];_temporary2DSchedule $w
}
proc ::GX::native2DTemporaryDisplayCancel {w} {
    set r [_temporary2DRecord $w];if {[dict get $r drag] eq {}} return
    if {[dict get $r drag kind] eq {move}} {::GX::Native2D::core drag_cancel [dict get $r scene]}
    dict set ::GX::Temporary2D::instances $w drag {};_temporary2DEmit $w cancel {};_temporary2DSchedule $w
}
proc ::GX::native2DTemporaryDisplayNavigate {w operation args} {
    set r [_temporary2DRecord $w];native2DTemporaryDisplayCancel $w
    set scene [dict get $r scene]
    switch $operation {
        fit {::GX::Native2D::core fit_bounds $scene {-1 0 11 8}}
        zoom {lassign $args factor x y;if {![string is double -strict $factor]||$factor<0.1||$factor>10} {error {Invalid temporary view zoom}};::GX::Native2D::core zoom $scene $factor [list $x $y]}
        default {error {Temporary Native2D navigation supports fit and zoom}}
    }
    _temporary2DEmit $w view_changed [dict create operation $operation];_temporary2DSchedule $w
}
proc ::GX::_temporary2DEmit {w phase detail} {
    set r [_temporary2DRecord $w]
    set event [dict create author demo_fixture source_identity {} provenance display_only_RAM phase $phase detail $detail generation [dict get $r generation]]
    dict lappend r events $event;dict set r events [lrange [dict get $r events] end-127 end]
    dict set ::GX::Temporary2D::instances $w $r
    if {[dict get $r callback] ne {}} {catch {{*}[dict get $r callback] $w $event}}
}
proc ::GX::native2DTemporaryDisplayInspect {w} {
    set r [_temporary2DRecord $w];set scene [dict get $r scene]
    return [dict create api_id NATIVE2D_TEMPORARY_DISPLAY_API_v1 provenance display_only_RAM publication 0 mode $::GX::Temporary2D::mode($w) scene $scene object [dict get $r shape] points [::GX::Native2D::core points $scene [dict get $r shape]] view [::GX::Native2D::core view $scene] drag [dict get $r drag] events [dict get $r events]]
}
proc ::GX::_temporary2DDispose {w actual} {
    if {$actual ne $w||![dict exists $::GX::Temporary2D::instances $w]} return
    set r [_temporary2DRecord $w]
    if {[dict get $r pending] ne {}} {after cancel [dict get $r pending]}
    catch {::GX::Native2D::core drag_cancel [dict get $r scene]}
    catch {::GX::Native2D::core destroy [dict get $r scene]}
    dict unset ::GX::Temporary2D::instances $w;unset -nocomplain ::GX::Temporary2D::mode($w)
}
proc ::GX::native2DTemporaryDisplayDestroy {w} {if {[winfo exists $w]} {destroy $w}}
