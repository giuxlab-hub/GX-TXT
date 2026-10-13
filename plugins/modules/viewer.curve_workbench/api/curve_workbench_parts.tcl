# Gesture routing only. Native identities, geometry, markers and recipe snapshots
# remain authoritative; targets below are transient focus, not a topology store.
proc ::GX::CurveWorkbench::_partHit {w x y} {
    variable st
    dict for {logical r} $st($w,curves) {
        if {![_curveVisible $w $r]||![dict exists $r sketch_definition]||[dict get $r sketch_definition family] ni {compound composite_path}} continue
        foreach part [::GX::Native2D::core composition_states $st($w,scene) [dict get $r native]] {
            if {![dict get $part direction visible]} continue
            if {[::GX::Native2D::core part_marker_hit $st($w,scene) [dict get $r native] [dict get $part part_id] [list $x $y] 7]} {return [list $logical [dict get $part part_id]]}
        }
    }
    return {}
}
proc ::GX::CurveWorkbench::_partDraw {w} {
    variable st;set canvas $w.right.viewport.canvas
    dict for {logical r} $st($w,curves) {
        if {![_curveVisible $w $r]||![dict exists $r sketch_definition]||[dict get $r sketch_definition family] ni {compound composite_path}} continue
        foreach part [::GX::Native2D::core composition_states $st($w,scene) [dict get $r native]] {
            set id [dict get $part part_id]
            if {[info exists st($w,partTarget)]&&$st($w,partTarget) eq [list $logical $id]} {
                set points [::GX::Native2D::core part_render $st($w,scene) [dict get $r native] $id]
                if {[llength $points]>=2} {$canvas create line {*}[concat {*}$points] -fill #c97800 -width 4 -tags part_highlight}
            }

        }
    }
}
proc ::GX::CurveWorkbench::_partMenu {w menu logical x y} {
    variable st;set native [dict get [_record $w $logical] native]
    set hit [_partHit $w $x $y]
    if {$hit ne {}&&[lindex $hit 0] eq $logical} {set part [lindex $hit 1]} else {set part [::GX::Native2D::core part_pick $st($w,scene) $native [list $x $y] 10]}
    if {$part eq {}} return
    set st($w,partTarget) [list $logical $part]
    set direction [::GX::Native2D::core part_direction $st($w,scene) $native $part]
    $menu add separator
    $menu add command -label "[expr {[dict get $direction visible]?"Hide":"Show"}] direction for this subpath" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_partAction $w $logical $part toggle]]
    $menu add command -label {Flip this subpath} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_partAction $w $logical $part flip]]
    $menu add command -label {Edit subpath arrow properties…} -command [list ::GX::CurveWorkbench::_partProperties $w $logical $part]
    _draw $w
}
proc ::GX::CurveWorkbench::_partAction {w logical part action} {
    variable st;if {![_partEditable $w]} return
    set native [dict get [_record $w $logical] native]
    set before [_snapshotIds $w [list $logical]]
    set direction [::GX::Native2D::core part_direction $st($w,scene) $native $part]
    set key [expr {$action eq "flip"?"forward":"visible"}]
    ::GX::Native2D::core part_direction $st($w,scene) $native $part [dict create $key [expr {![dict get $direction $key]}]]
    set st($w,partTarget) [list $logical $part];_history $w $before [list $logical];_draw $w
}
proc ::GX::CurveWorkbench::_partProperties {w logical part} {
    variable st;set marker [::GX::Native2D::core part_direction $st($w,scene) [dict get [_record $w $logical] native] $part]
    set fields [dict create fraction {type number min 0 max 1 label {Position along subpath (0–1)}} offset_px {type number min -4096 max 4096 label {Normal offset (px)}} length_px {type number min 4 max 4096 label {Arrow length (px)}} line_width {type number min .1 max 64 label {Line width (px)}} head_scale {type number min .01 max 4 label {Arrowhead size}} color {type color alpha 1 label {Arrow color / opacity}}]
    dict set marker color [::GX::uiFieldColorFromRGBA [dict get $marker color]]
    ::GX::uiFieldFormCreate $w.partProperties {Subpath direction arrow} $fields $marker [list ::GX::CurveWorkbench::_partPropertiesApply $w $logical $part] $w
}
proc ::GX::CurveWorkbench::_partPropertiesApply {w logical part values} {
    variable st;if {![_partEditable $w]} return
    set before [_snapshotIds $w [list $logical]]
    dict set values color [::GX::uiFieldColorToRGBA [dict get $values color]]
    ::GX::Native2D::core part_direction $st($w,scene) [dict get [_record $w $logical] native] $part $values
    _history $w $before [list $logical];_draw $w
}
proc ::GX::CurveWorkbench::_pointerDownPart {w x y state} {
    variable st
    if {$st($w,tool) ne "select"||$st($w,canvasTool) ne "select"||$st($w,cadTool) ne "none"||$st($w,constraintTool) ne {}||$st($w,imageCalibration) ne {}||$st($w,zoomBox) ne {}} {return 0}
    set target [_partHit $w $x $y];if {$target eq {}} {return 0}
    if {![_partEditable $w]} {return 1}
    lassign $target logical part
    set st($w,partTarget) $target;set st($w,partDrag) [dict create logical $logical part $part before [_snapshotIds $w [list $logical]]]
    set st($w,active) $logical;focus $w.right.viewport.canvas;_draw $w;return 1
}
proc ::GX::CurveWorkbench::_pointerMovePart {w x y} {
    variable st
    if {[info exists st($w,partDrag)]&&$st($w,partDrag) ne {}} {
        set drag $st($w,partDrag)
        ::GX::Native2D::core part_marker_place $st($w,scene) [dict get [_record $w [dict get $drag logical]] native] [dict get $drag part] [list $x $y]
        _draw $w;return 1
    }
    set target [_partHit $w $x $y]
    if {![info exists st($w,partTarget)]||$target ne $st($w,partTarget)} {set st($w,partTarget) $target;_draw $w}
    return 0
}
proc ::GX::CurveWorkbench::_pointerUpPart {w x y} {
    variable st
    if {![info exists st($w,partDrag)]||$st($w,partDrag) eq {}} {return 0}
    set drag $st($w,partDrag);set st($w,partDrag) {}
    _history $w [dict get $drag before] [list [dict get $drag logical]];_draw $w;return 1
}

proc ::GX::CurveWorkbench::_partCancel {w} {
    variable st
    if {[info exists st($w,partDrag)]&&$st($w,partDrag) ne {}} {
        set before [dict get $st($w,partDrag) before];set st($w,partDrag) {};set st($w,partTarget) {}
        _restoreSnapshot $w $before
    }
    set st($w,partTarget) {}
}
proc ::GX::CurveWorkbench::_directionMenu {w menu logical x y} {
    variable st;set record [_record $w $logical]
    if {[dict exists $record sketch_definition]&&[dict get $record sketch_definition family] in {compound composite_path}} {tailcall _partMenu $w $menu $logical $x $y}
    set marker [::GX::Native2D::core direction_marker $st($w,scene) [dict get $record native]]
    $menu add separator
    $menu add command -label "[expr {[dict get $marker visible]?{Hide}:{Show}}] direction arrow" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_pathDirectionAction $w $logical visible]]
    $menu add command -label {Flip direction} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_pathDirectionAction $w $logical forward]]
    $menu add command -label {Edit arrow properties…} -command [list ::GX::CurveWorkbench::_pathDirectionProperties $w $logical]
}
proc ::GX::CurveWorkbench::_pathDirectionAction {w logical key} {
    variable st;if {![_partEditable $w]} return
    set before [_snapshotIds $w [list $logical]];set native [dict get [_record $w $logical] native]
    set marker [::GX::Native2D::core direction_marker $st($w,scene) $native]
    ::GX::Native2D::core direction_marker $st($w,scene) $native [dict create $key [expr {![dict get $marker $key]}]]
    _history $w $before [list $logical];_draw $w
}
proc ::GX::CurveWorkbench::_pathDirectionProperties {w logical} {
    variable st;set st($w,active) $logical;_directionOpen $w
}
# Rendering selected state derives exclusively from the existing controller.
proc ::GX::CurveWorkbench::_toolStateChanged {w args} {
    if {[winfo exists $w]} {_toolStates $w}
}
proc ::GX::CurveWorkbench::_toolStateDispose {w destroyed} {
    variable st;if {$destroyed ne $w} return
    foreach key {tool canvasTool cadTool constraintTool imageCalibration zoomBox} {catch {trace remove variable ::GX::CurveWorkbench::st($w,$key) write [list ::GX::CurveWorkbench::_toolStateChanged $w]}}
    if {[info exists st($w,toolStatePending)]} {after cancel $st($w,toolStatePending);unset st($w,toolStatePending)}
}
proc ::GX::CurveWorkbench::_toolStates {w} {
    variable st;catch {unset st($w,toolStatePending)}
    if {![winfo exists $w]||![info exists st($w,canvasTool)]} return
    if {![info exists st($w,toolStateInstalled)]} {
        set st($w,toolStateInstalled) 1
        foreach key {tool canvasTool cadTool constraintTool imageCalibration zoomBox} {trace add variable ::GX::CurveWorkbench::st($w,$key) write [list ::GX::CurveWorkbench::_toolStateChanged $w]}
        bind $w <Destroy> +[list ::GX::CurveWorkbench::_toolStateDispose $w %W]
    }
    set select [expr {$st($w,tool) eq "select"&&$st($w,canvasTool) eq "select"&&$st($w,cadTool) eq "none"&&$st($w,constraintTool) eq {}&&$st($w,imageCalibration) eq {}&&$st($w,zoomBox) eq {}}]
    set controls [::GX::native2DViewportPanelWidget $w.right.viewport.canvas controls].body
    foreach {widget active} [list $controls.select $select $controls.pan [expr {$st($w,tool) eq "pan"}] $controls.transform [expr {$st($w,cadTool) ne "none"}] $controls.zoom_box [expr {$st($w,zoomBox) ne {}}] $w.sketchbar.select $select $w.sketchbar.create [expr {$st($w,canvasTool) ne "select"}] $w.sketchbar.modify [expr {$st($w,cadTool) ne "none"}] $w.sketchbar.dimension [expr {$st($w,constraintTool) eq "dimension"}] $w.sketchbar.constraints [expr {$st($w,constraintTool) ne {}&&$st($w,constraintTool) ne "dimension"}]] {
        if {[winfo exists $widget]} {::GX::native2DViewportToolState $widget $active}
    }
    set panel [::GX::native2DViewportPanelWidget $w.right.viewport.canvas palette]
    if {$panel eq {}||![winfo exists $panel]} return
    set palette $panel.body
    if {[winfo exists $panel.body.scroll.content]} {set palette $panel.body.scroll.content}
    foreach widget [winfo children $palette] {
        if {[winfo class $widget] ni {TButton TMenubutton}} continue
        set action [lindex [split $widget .] end];set active 0
        if {[string match create_* $action]} {set active [expr {[string range $action 7 end] eq $st($w,canvasTool)}]}
        if {$action eq "dimension"} {set active [expr {$st($w,constraintTool) eq "dimension"}]}
        if {$action eq "constraints"} {set active [expr {$st($w,constraintTool) ne {}&&$st($w,constraintTool) ne "dimension"}]}
        ::GX::native2DViewportToolState $widget $active
    }
}

proc ::GX::CurveWorkbench::_partEditable {w} {
    variable st
    if {$st($w,publishBusy)||$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error {Workspace is busy or its Session changed; reopen before editing}}
    return [_timelineEditable $w]
}
