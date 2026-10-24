# SPDX-License-Identifier: GPL-3.0-or-later
# GUI dispatch/workflow only. Native2D owns construction, defining controls,
# placement snap, reference numbering and relationship compatibility/driving.
proc ::GX::CurveWorkbench::_sketchTool {w family} {
    variable st
    # Switching creation tools must not revive the previous transform gizmo
    # while cancelling it (its pivot may have lost its selected targets).
    _sketchIdle $w
    set st($w,canvasTool) $family;set st($w,cadTool) none;set st($w,tool) select
    if {$family ne "select"} {::GX::Native2D::core aspect $st($w,scene) xy_equal}
    ::GX::Native2D::core gizmo $st($w,scene) {visible 0}
    set hints [dict create path {Line — place successive vertices; Enter / Finish commits one retained path.} select {Select — click geometry or defining handles. Ctrl adds; Shift subtracts. Drag a handle to edit.} point {Point — click position. Esc cancels.} line {Line — click start, then end. Esc cancels.} construction_line {Construction axis — click two points; the retained line is infinite.} rectangle {Rectangle — click opposite corners. Esc cancels.} circle {Circle — click center, then radius. Esc cancels.} arc {Arc — click center, start, then end (counterclockwise). Esc cancels.} ellipse {Ellipse — click center, major axis, then minor radius. Esc cancels.} quadratic_bezier {Quadratic Bézier — place three control points.} cubic_bezier {Cubic Bézier — place four control points.} polyline {Polyline — place controls; Enter finishes. Esc cancels.} spline {Spline — place retained controls; Enter finishes. Esc cancels.}]
    set st($w,toolLabel) [dict get $hints $family]
    # Instructions belong to the shared tool row; status carries results/errors.
    set st($w,status) {}
    focus $w.right.viewport.canvas;_draw $w
    _sketchBarLayout $w [winfo width $w.sketchbar]
}
proc ::GX::CurveWorkbench::_toolPreviewClear {w} {
    variable st
    if {$st($w,toolPreview) ne {}} {::GX::Native2D::core delete $st($w,scene) $st($w,toolPreview);set st($w,toolPreview) {}}
    set st($w,previewDefinition) {}
}
proc ::GX::CurveWorkbench::_toolPreview {w definition} {
    variable st
    _toolPreviewClear $w
    set st($w,toolPreview) [::GX::Native2D::core sketch_create $st($w,scene) $definition 257]
    set st($w,previewDefinition) $definition
    ::GX::Native2D::core object_style $st($w,scene) $st($w,toolPreview) {selectable 0}
}
proc ::GX::CurveWorkbench::_placement {w x y {excluded {}}} {
    variable st
    set result [::GX::Native2D::core interaction_snap $st($w,scene) [list $x $y] 10 $excluded $st($w,cadObjectSnap) 1]
    set st($w,snapCandidate) $result;return [dict get $result point]
}
proc ::GX::CurveWorkbench::_createCount {family} {
    return [dict get {point 1 line 2 construction_line 2 rectangle 2 circle 2 arc 3 ellipse 3 quadratic_bezier 3 cubic_bezier 4 path 0 polyline 0 spline 0} $family]
}
proc ::GX::CurveWorkbench::_commitDefinition {w definition unit name operation {parents {}}} {
    variable st
    set coordinateUnits [list [dict get $st($w,coordinateConfiguration) x_unit] [dict get $st($w,coordinateConfiguration) y_unit]]
    if {$parents ne {}} {set coordinateUnits [_coordinateUnits [_record $w [lindex $parents 0]]]}
    if {$parents eq {} && $st($w,active) ne {} && [dict exists $st($w,curves) $st($w,active)]} {set coordinateUnits [_coordinateUnits [_record $w $st($w,active)]]}
    set relations {}
    if {$parents ne {}} {set relations [_coordinateSourceRelations [_record $w [lindex $parents 0]]]} elseif {$st($w,active) ne {}&&[dict exists $st($w,curves) $st($w,active)]} {set relations [_coordinateSourceRelations [_record $w $st($w,active)]]}
    _coordinateAxesAdmit $w $coordinateUnits $relations
    if {[dict exists $operation coordinate_units]} {
        if {[dict get $operation coordinate_units] ne $coordinateUnits} {error {Retained conversion does not belong to the selected coordinate plane}}
        set unit [lindex $coordinateUnits 0]
    }
    if {$unit ne [lindex $coordinateUnits 0]} {error {Creation unit differs from the current coordinate frame. Configure an empty workspace or explicitly convert existing geometry first.}}
    set before [_snapshotIds $w {}];set undo $st($w,undo);set redo $st($w,redo);set native {}
    try {
        set native [::GX::Native2D::core sketch_create $st($w,scene) $definition 257]
        set record [_newRecord $w $name [_sketchSamples $w $native] {} x y {} {} {} {} $parents [list $operation]]
        dict set record coordinate_units $coordinateUnits;dict set record conversion_provenance $operation
        if {$parents eq {}&&$st($w,active) ne {}&&[dict exists $st($w,curves) $st($w,active)]} {set record [_coordinateRetainFrame $w $record [list $st($w,active)]]}
        dict set record materialization_sampling [dict create method uniform_parameter first 0 last 1 total [::GX::Native2D::core count $st($w,scene) $native] geometry_authority retained_sketch]
        set id [dict get $record id];dict set before $id {};_addRecord $w $record $native
        set st($w,active) $id;set st($w,objectSelection) [list $id];set st($w,sketchSelection) {}
        _selectionScene $w;_history $w $before [list $id]
    } on error {message options} {
        _restoreSnapshot $w $before
        if {$native ne {}&&$native in [::GX::Native2D::core ids $st($w,scene)]} {::GX::Native2D::core delete $st($w,scene) $native}
        set st($w,undo) $undo;set st($w,redo) $redo;return -options $options $message
    }
    set st($w,status) [_coordinatePlaneParameterLabel $coordinateUnits "$name — exact retained primitive committed"]
    return $id
}
proc ::GX::CurveWorkbench::_createCommit {w} {
    variable st
    if {$st($w,canvasTool) eq "select"||$st($w,placements) eq {}} return
    set needed [_createCount $st($w,canvasTool)]
    if {($needed&&[llength $st($w,placements)]!=$needed)||(!$needed&&[llength $st($w,placements)]<2)} {set st($w,status) "Place the remaining defining controls first.";return}
    set definition [::GX::Native2D::core interaction_construct $st($w,scene) $st($w,canvasTool) $st($w,placements)]
    set family $st($w,canvasTool);set unit $st($w,sketchUnit)
    _toolPreviewClear $w;set st($w,placements) {};set st($w,snapCandidate) {}
    set id [_commitDefinition $w $definition $unit "[string totitle [string map {_ { }} $family]] [expr {[dict size $st($w,curves)]+1}]" [dict create operation canvas_primitive_creation family $family authority Native2D]]
    _sketchTool $w select;return $id
}
rename ::GX::CurveWorkbench::_cancelGesture ::GX::CurveWorkbench::_cancelGesture_interaction_base
proc ::GX::CurveWorkbench::_cancelGesture {w} {
    variable st
    _cancelGesture_interaction_base $w
    if {![info exists st($w,toolPreview)]} return
    _toolPreviewClear $w;set st($w,placements) {};set st($w,handleDrag) {};set st($w,snapCandidate) {}
    set st($w,canvasTool) select;set st($w,toolLabel) {Select — click geometry or defining handles. Ctrl adds; Shift subtracts.}
    if {[winfo exists $w.right.viewport.canvas]} {_draw $w}
}
proc ::GX::CurveWorkbench::_sketchPick {w x y} {
    variable st
    # Active defining controls have priority over intersecting geometry.
    set ids [dict keys $st($w,curves)];if {$st($w,active) in $ids} {set ids [linsert [lsearch -all -inline -not -exact $ids $st($w,active)] 0 $st($w,active)]}
    foreach id $ids {
        set record [_record $w $id];if {![_curveVisible $w $record]} continue
        set ref [::GX::Native2D::core interaction_pick $st($w,scene) [dict get $record native] [list $x $y] 9]
        if {$ref ne {}} {dict set ref logical $id;return $ref}
    }
    return {}
}
proc ::GX::CurveWorkbench::_selectReference {w ref additive} {
    variable st
    if {!$additive} {set st($w,sketchSelection) {}}
    set found 0
    foreach old $st($w,sketchSelection) {if {[dict get $old logical] eq [dict get $ref logical]&&[dict get $old entity] eq [dict get $ref entity]&&[dict get $old index]==[dict get $ref index]} {set found 1}}
    if {!$found} {lappend st($w,sketchSelection) $ref}
    set st($w,objectSelection) [lsort -unique [lmap r $st($w,sketchSelection) {dict get $r logical}]]
    set st($w,active) [dict get $ref logical]
    _selectionScene $w;_curveList $w;_pointList $w;_draw $w
}
proc ::GX::CurveWorkbench::_controlDragStart {w ref x y} {
    variable st
    set ids [list [dict get $ref logical]]
    # Pointer bindings must surface a denied frame through the existing inline
    # notice, before creating a gesture or taking any geometry/History action.
    if {[catch {_coordinatePlaneAdmit $w $ids} message]} {
        _notice $w $message
        return
    }
    # Preserve the pick offset: a rounded screen pixel is not the exact control
    # coordinate. An axis-aligned drag must not perturb a locked other axis.
    set st($w,handleDrag) [dict create reference $ref coordinate_key [_coordinateControlKey $w $ids] before [_snapshotIds $w $ids] target {} origin [::GX::Native2D::core interaction_resolve $st($w,scene) $ref] pointer [::GX::Native2D::core world $st($w,scene) [list $x $y]]]
}
proc ::GX::CurveWorkbench::_pointerDownRetained {w x y state} {
    variable st
    if {$st($w,publishBusy)||$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {return 1}
    if {$st($w,canvasTool) ne "select"} {
        lassign [::GX::Native2D::core view $st($w,scene)] width height left top right bottom
        if {$x<$left||$y<$top||$x>$width-$right||$y>$height-$bottom} {return 1}
        lappend st($w,placements) [_placement $w $x $y]
        set required [_createCount $st($w,canvasTool)]
        if {$required&&[llength $st($w,placements)]==$required} {_safe $w [list ::GX::CurveWorkbench::_createCommit $w]} else {_draw $w}
        return 1
    }
    if {$st($w,cadTool) ne "none"||$st($w,tool) ne "select"||$st($w,joinPending) ne {}} {return 0}
    # dev-054 relationship routing owns generous hit regions and handle priority.
    set ref [_sketchPick $w $x $y]
    if {$ref ne {}&&[dict exists [_record $w [dict get $ref logical]] sketch_definition]} {
        set additive [expr {($state&0x1)||($state&0x4)}];_selectReference $w $ref $additive
        if {!$additive&&[dict get $ref entity] eq "control"&&![dict get [_record $w [dict get $ref logical]] locked]} {
            _controlDragStart $w $ref $x $y
        }
        return 1
    }
    set st($w,sketchSelection) {}
    return 0
    # Scientific point selection still uses the existing coalesced authority.

    return 1
}
rename ::GX::CurveWorkbench::_coordinates ::GX::CurveWorkbench::_coordinates_interaction_base
proc ::GX::CurveWorkbench::_coordinates {w x y} {
    variable st
    _coordinates_interaction_base $w $x $y
    if {$st($w,canvasTool) eq "select"||$st($w,placements) eq {}} return
    set candidate [concat $st($w,placements) [list [_placement $w $x $y]]]
    if {[catch {set definition [::GX::Native2D::core interaction_construct_preview $st($w,scene) $st($w,canvasTool) $candidate]}]} {_toolPreviewClear $w} else {_toolPreview $w $definition}
    _draw $w
}
proc ::GX::CurveWorkbench::_pointerMoveControl {w x y} {
    variable st
    if {$st($w,handleDrag) eq {}} {return 0}
    set ref [dict get $st($w,handleDrag) reference]
    if {[catch {_coordinateControlCheck $w [list [dict get $ref logical]] [dict get $st($w,handleDrag) coordinate_key]} message]} {set st($w,handleDrag) {};_toolPreviewClear $w;_sketchIdle $w $message;return 1}
    set target [_placement $w $x $y [list [dict get $ref object]]]
    if {[dict get $st($w,snapCandidate) kind] eq "none"&&[dict exists $st($w,handleDrag) origin]} {
        set target [lmap now $target start [dict get $st($w,handleDrag) pointer] origin [dict get $st($w,handleDrag) origin] {expr {$origin+($now-$start)}}]
    }
    if {[catch {set definition [::GX::Native2D::core interaction_edit_definition $st($w,scene) $ref $target]} message]} {set st($w,status) "Handle preview: $message";return 1}
    _toolPreview $w $definition;dict set st($w,handleDrag) target $target;_draw $w

    return 1
}
proc ::GX::CurveWorkbench::_pointerUpControl {w x y} {
    variable st
    if {$st($w,canvasTool) ne "select"} {return 1}
    if {$st($w,handleDrag) eq {}} {return 0}
    set drag $st($w,handleDrag);set st($w,handleDrag) {};_toolPreviewClear $w;set st($w,snapCandidate) {}
    if {[dict get $drag target] eq {}} {_draw $w;return 1}
    set ref [dict get $drag reference];set id [dict get $ref logical]
    if {[catch {
        _coordinateControlCheck $w [list $id] [dict get $drag coordinate_key]
        _coordinatePlaneAdmit $w [list $id]
        ::GX::Native2D::core interaction_edit $st($w,scene) $ref [dict get $drag target]
    } message]} {_sketchIdle $w "Edit rejected: $message. Existing geometry and constraints preserved.";return 1}
    set undo $st($w,undo);set redo $st($w,redo)
    try {_syncSamples $w $id;_history $w [dict get $drag before] [list $id]} on error {message options} {_restoreSnapshot $w [dict get $drag before];set st($w,undo) $undo;set st($w,redo) $redo;return -options $options $message}
    set st($w,status) "Defining handle edited; retained primitive and Native constraints preserved."

    return 1
}
rename ::GX::CurveWorkbench::_drawPointMarkers ::GX::CurveWorkbench::_drawPointMarkers_interaction_base
proc ::GX::CurveWorkbench::_drawPointMarkers {w id sampled color} {
    variable st
    set record [_record $w $id]
    if {![dict exists $record sketch_definition]} {tailcall _drawPointMarkers_interaction_base $w $id $sampled $color}
    set selected {}
    foreach ref $st($w,sketchSelection) {if {[dict get $ref logical] eq $id} {lappend selected [dict get $ref index]}}
    ::GX::native2DSpriteSceneControls $w.right.viewport.canvas $st($w,scene) [dict get $record native] $selected $color $id

}
rename ::GX::CurveWorkbench::_pointList ::GX::CurveWorkbench::_pointList_interaction_base
proc ::GX::CurveWorkbench::_pointList {w} {
    variable st
    set tree $w.leftScroll.viewport.content.points
    if {$st($w,active) eq {}||![dict exists $st($w,curves) $st($w,active)]||![dict exists [_record $w $st($w,active)] sketch_definition]} {
        _pointList_interaction_base $w
        $w.leftScroll.viewport.content.points heading index -text Index
        $w.leftScroll.viewport.content.numeric.apply configure -text {Apply X/Y}
        return
    }
    set old $st($w,pointSyncRunning);set st($w,pointSyncRunning) 1
    try {
        set tree $w.leftScroll.viewport.content.points;set record [_record $w $st($w,active)]
        $w.leftScroll.viewport.content.pointFrame configure -text {Retained defining handles}
        foreach axis {x y} {
            set unit [dict get [_coordinateAxis $w $st($w,active) $axis] display_unit]
            set key [string toupper $axis]
            $tree heading $axis -text "$key ($unit)"
            $w.leftScroll.viewport.content.numeric.ledit$key configure -text "$key ($unit)"
        }
        set handles [::GX::Native2D::core interaction_controls $st($w,scene) [dict get $record native]]
        set signature [list handles $st($w,active) $handles [_coordinateKey $w $st($w,active)]]
        if {$signature ne $st($w,pointTableSignature)} {
            $tree delete [$tree children {}];set i 0
            foreach handle $handles {
                lassign [_coordinatePoint $w $st($w,active) [dict get $handle point]] x y
                $tree insert {} end -id h[incr i] -values [list [string map {_ { }} [dict get $handle role]] [format %.9g $x] [format %.9g $y] {retained control}]
            }
            set st($w,pointTableSignature) $signature
        }
        $tree heading index -text {Defining handle};$tree heading source_row -text {Representation}
        $w.leftScroll.viewport.content.numeric.apply configure -text {Apply handle X/Y}
        set selected {};set i 0;set st($w,editX) {};set st($w,editY) {}
        foreach handle $handles {incr i;foreach ref $st($w,sketchSelection) {if {[dict get $ref logical] eq $st($w,active)&&[dict get $ref entity] eq "control"&&[dict get $ref index]==[dict get $handle index]} {lappend selected h$i;lassign [_coordinatePoint $w $st($w,active) [dict get $handle point]] st($w,editX) st($w,editY)}}}
        if {[$tree selection] ne $selected} {$tree selection set $selected}
        if {[dict get $record sketch_definition family] eq "composite_path"} {
            set st($w,pointPageLabel) "[llength [dict get $record sketch_definition parts]] exact Path constituents — [llength $handles] editable defining handles"
        } elseif {[dict get $record sketch_definition family] eq "compound"} {
            set st($w,pointPageLabel) "[llength [dict get $record sketch_definition parts]] exact constituents — use Modify > Separate exact constituents to edit their controls."
        } else {set st($w,pointPageLabel) "[string totitle [dict get $record sketch_definition family]] — [llength $handles] defining handles; display samples are read-only proxies"}
    } finally {set st($w,pointSyncRunning) $old}
}
rename ::GX::CurveWorkbench::_pointTreeSelect ::GX::CurveWorkbench::_pointTreeSelect_interaction_base
proc ::GX::CurveWorkbench::_pointTreeSelect {w} {
    variable st
    if {$st($w,active) eq {}||![dict exists [_record $w $st($w,active)] sketch_definition]} {tailcall _pointTreeSelect_interaction_base $w}
    if {$st($w,pointSyncRunning)} return
    _pointSyncCancel $w
    set handles [::GX::Native2D::core interaction_controls $st($w,scene) [dict get [_record $w $st($w,active)] native]]
    set refs {};foreach row [$w.leftScroll.viewport.content.points selection] {set ref [lindex $handles [expr {[string range $row 1 end]-1}]];dict set ref logical $st($w,active);lappend refs $ref}
    set prior {};foreach ref $st($w,sketchSelection) {if {[dict get $ref logical] eq $st($w,active)&&[dict get $ref entity] eq "control"} {lappend prior [dict get $ref index]}}
    if {[lsort $prior] eq [lsort [lmap ref $refs {dict get $ref index}]]} return
    set st($w,sketchSelection) $refs;_pointList $w;_draw $w
}
rename ::GX::CurveWorkbench::_numericEdit ::GX::CurveWorkbench::_numericEdit_interaction_base
proc ::GX::CurveWorkbench::_numericEdit {w} {
    variable st
    if {![dict exists [_record $w [_active $w]] sketch_definition]} {tailcall _numericEdit_interaction_base $w}
    if {[llength $st($w,sketchSelection)]!=1||[dict get [lindex $st($w,sketchSelection) 0] entity] ne "control"} {error "Select one defining handle"}
    set before [_snapshotIds $w [list [_active $w]]];set undo $st($w,undo);set redo $st($w,redo)
    ::GX::Native2D::core interaction_edit $st($w,scene) [lindex $st($w,sketchSelection) 0] [_coordinatePoint $w [_active $w] [list [_finite $st($w,editX) X] [_finite $st($w,editY) Y]] inverse]
    try {_syncSamples $w [_active $w];_history $w $before [list [_active $w]]} on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $undo;set st($w,redo) $redo;return -options $options $message}
}
proc ::GX::CurveWorkbench::_drawCreationPreview {w} {
    variable st
        if {![winfo exists $w.right.viewport.canvas]||![info exists st($w,toolPreview)]} return
    if {$st($w,toolPreview) ne {}} {
        set object [::GX::native2DPresentationObjectSnapshot $st($w,scene) $st($w,toolPreview)]
        dict set object style color [::GX::uiFieldColorToRGBA #159768]
        dict set object style line_width 2;dict set object style line_style 2
        dict unset object marker
        ::GX::native2DCanvasDrawObject $w.right.viewport.canvas $object white tool_preview
        set previewHandles [::GX::Native2D::core interaction_controls $st($w,scene) $st($w,toolPreview)]
        foreach handle $previewHandles {lassign [::GX::Native2D::core device $st($w,scene) [dict get $handle point]] x y;$w.right.viewport.canvas create rectangle [expr {$x-4}] [expr {$y-4}] [expr {$x+4}] [expr {$y+4}] -outline #159768 -tags tool_preview}
    }
    if {$st($w,previewDefinition) ne {}&&[dict get $st($w,previewDefinition) family] in {circle arc}&&[llength $previewHandles]>=2} {
        set center [::GX::Native2D::core device $st($w,scene) [dict get [lindex $previewHandles 0] point]]
        set radius [::GX::Native2D::core device $st($w,scene) [dict get [lindex $previewHandles 1] point]]
        _renderPath $w.right.viewport.canvas [list $center $radius] #159768 1 {3 3}
        if {![catch {set measured [::GX::Native2D::core measure $st($w,scene) [dict create kind radius a $st($w,toolPreview)]]}]} {
            set units [list [dict get $st($w,coordinateConfiguration) x_unit] [dict get $st($w,coordinateConfiguration) y_unit]]
            lassign $units xUnit yUnit
            if {$xUnit eq {}} {set xUnit numeric};if {$yUnit eq {}} {set yUnit numeric}
            set hint "Plane R [format %.4g [dict get $measured value]] · X $xUnit; Y $yUnit"
            $w.right.viewport.canvas create text {*}$radius -text $hint -anchor sw -fill #159768 -tags tool_preview
        }
    }
    if {$st($w,snapCandidate) ne {}&&[dict get $st($w,snapCandidate) kind] ne "none"} {lassign [::GX::Native2D::core device $st($w,scene) [dict get $st($w,snapCandidate) point]] x y
        $w.right.viewport.canvas create oval [expr {$x-8}] [expr {$y-8}] [expr {$x+8}] [expr {$y+8}] -outline #a45b00 -width 2 -tags snap_candidate
        $w.right.viewport.canvas create text [expr {$x+12}] [expr {$y-12}] -text [dict get $st($w,snapCandidate) kind] -anchor w -fill #805000 -tags snap_candidate
    }
    _constraintMarkers $w
    ::GX::native2DCanvasViewportClip $w.right.viewport.canvas $st($w,scene)
}
proc ::GX::CurveWorkbench::_cadDetails {w} {
    if {[winfo manager $w.cad] eq {}} {pack $w.cad -side top -fill x -before $w.main} else {pack forget $w.cad}
}
proc ::GX::CurveWorkbench::_buildConstruction {w} {
    variable st
    pack forget $w.cad
    ttk::frame $w.sketchbar -padding 4;pack $w.sketchbar -side top -fill x -before $w.main
    ttk::button $w.sketchbar.select -text Select -command [list ::GX::CurveWorkbench::_sketchTool $w select]
    ttk::menubutton $w.sketchbar.create -text Create -menu $w.sketchbar.create.menu;menu $w.sketchbar.create.menu -tearoff 0
    foreach {family label} {point Point line Line construction_line {Construction line} rectangle Rectangle circle Circle arc Arc ellipse Ellipse quadratic_bezier {Quadratic Bézier} cubic_bezier {Cubic Bézier} spline Spline} {$w.sketchbar.create.menu add command -label $label -command [list ::GX::CurveWorkbench::_sketchTool $w $family]}
    $w.sketchbar.create.menu add separator
    $w.sketchbar.create.menu add command -label {Exact numeric creation…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_sketchOpen $w]]
    ttk::menubutton $w.sketchbar.modify -text Modify -menu $w.sketchbar.modify.menu;menu $w.sketchbar.modify.menu -tearoff 0
    foreach {label callback} [list {Move on canvas} [list _sketchModifyTool $w translate] {Rotate on canvas} [list _sketchModifyTool $w rotate] {Exact parameters…} [list _sketchOpen $w 1] {Working units…} [list _unitsOpen $w] {Duplicate} [list _duplicate $w] {Reverse} [list _operation $w reverse] {Native point operations / groups…} [list _cadDetails $w]] {$w.sketchbar.modify.menu add command -label $label -command [list ::GX::CurveWorkbench::_safe $w [lreplace $callback 0 0 ::GX::CurveWorkbench::[lindex $callback 0]]]}
    ttk::menubutton $w.sketchbar.constraints -text Constraints -menu $w.sketchbar.constraints.menu
    menu $w.sketchbar.constraints.menu -tearoff 0 -postcommand [list ::GX::CurveWorkbench::_constraintMenu $w]
    ttk::menubutton $w.sketchbar.represent -text Representation -menu $w.sketchbar.represent.menu;menu $w.sketchbar.represent.menu -tearoff 0
    foreach {label callback} [list {Publish primitive as Dataset…} [list _primitivePublishOpen $w] {Reconstruct exact primitive from Dataset} [list _reconstructPrimitive $w] {Fit to retained primitive…} [list _fitPrimitiveOpen $w] {Dataset → Native editable points…} [list _convertOpen $w] {Primitive → Native sampled points…} [list _sketchSampleOpen $w] {Construction / reference role…} [list _geometryRoleOpen $w]] {$w.sketchbar.represent.menu add command -label $label -command [list ::GX::CurveWorkbench::_safe $w [lreplace $callback 0 0 ::GX::CurveWorkbench::[lindex $callback 0]]]}
    ttk::checkbutton $w.sketchbar.snap -text {Object snap} -variable ::GX::CurveWorkbench::st($w,cadObjectSnap)
    ttk::button $w.sketchbar.finish -text Finish -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_createCommit $w]]
    foreach key {select create modify constraints represent snap finish} {pack $w.sketchbar.$key -side left -padx 3}
    # The feedback label is a real child; its host is gridded only after reflow.
    ttk::frame $w.sketchbar.feedback
    ttk::label $w.sketchbar.feedback.active -textvariable ::GX::CurveWorkbench::st($w,toolLabel) -wraplength 500
    pack $w.sketchbar.feedback.active -fill x -expand 1
    bind $w.right.viewport.canvas <Return> [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_createCommit $w]]
    bind $w.right.viewport.canvas <space> [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_createCommit $w]]
    bind $w.sketchbar <Configure> [list ::GX::native2DToolbarLayout $w.sketchbar %w]
    # Context menu shares the same Native-driven constraints and conversions.
    bind $w.right.viewport.canvas <Button-3> [list ::GX::CurveWorkbench::_sketchContext $w %X %Y]
}
proc ::GX::CurveWorkbench::_sketchModifyTool {w mode} {
    variable st
    _sketchTool $w select;set st($w,cadTool) $mode;_cadToolChoice $w
    set st($w,toolLabel) "[string totitle $mode] — drag the Native gizmo. Esc cancels."
}
proc ::GX::CurveWorkbench::_sketchContext {w x y} {::GX::uiMenuPopup $w.sketchbar.constraints.menu $x $y}
proc ::GX::CurveWorkbench::_constraintReferences {w} {
    variable st
    if {$st($w,sketchSelection) ne {}} {
        foreach ref $st($w,sketchSelection) {
            set image [::GX::Native2D::core image_get $st($w,scene) [dict get $ref object]]
            if {$image ne {}&&![dict get $image calibrated]} {return {}}
        }
        return $st($w,sketchSelection)
    }
    set result {}
    if {$st($w,active) ne {}&&![dict exists [_record $w $st($w,active)] sketch_definition]&&[_selected $w] ne {}} {
        foreach index [_selected $w] {set ref [::GX::Native2D::core interaction_reference $st($w,scene) [dict get [_record $w $st($w,active)] native] control $index];dict set ref logical $st($w,active);lappend result $ref}
    } else {foreach id [_cadSelected $w] {set ref [::GX::Native2D::core interaction_reference $st($w,scene) [dict get [_record $w $id] native] object 0];dict set ref logical $id;lappend result $ref}}
    return $result
}
proc ::GX::CurveWorkbench::_constraintOptions {w} {
    variable st
    set refs [_constraintReferences $w]
    if {[llength $refs]<1||[llength $refs]>3} {return {}}
    return [::GX::Native2D::core interaction_constraints $st($w,scene) $refs]
}
proc ::GX::CurveWorkbench::_constraintMenu {w} {
    set menu $w.sketchbar.constraints.menu;$menu delete 0 end
    if {[catch {set options [_constraintOptions $w]} message]} {set options {};set ::GX::CurveWorkbench::st($w,status) "Selection changed: $message. Select current geometry again."}
    if {$options eq {}} {$menu add command -label {Select geometry or defining handles first} -state disabled}
    foreach kind [dict keys $options] {$menu add command -label [_constraintTitle $kind] -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_constraintSimple $w $kind]]}
    $menu add separator
    $menu add command -label {Inspector / dimensions…} -command [list ::GX::CurveWorkbench::_constraintOpen $w]
    $menu add command -label {Advanced reference editor…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_constraintForm $w]]
}
proc ::GX::CurveWorkbench::_constraintSimple {w kind} {
    variable st
    set options [_constraintOptions $w]
    if {![dict exists $options $kind]} {error "Select compatible geometry for [_constraintTitle $kind]"}
    set spec [dict get $options $kind]
    set spec [dict remove $spec id valid geometry_supported measured_value residual angular_residual enforcement general_solver anchor]
    set refs [_constraintReferences $w];set names [lmap r $refs {dict get [_record $w [dict get $r logical]] name}]
    set unit [_cadUnits $w [lsort -unique [lmap r $refs {dict get $r logical}]]]
    if {$kind in {distance angle radius diameter lock_x lock_y}} {
        if {$kind eq "angle"} {set unit rad}
        ::GX::uiFieldFormCreate $w.dimension "[_constraintTitle $kind] — [join $names { ↔ }]" [dict create value [dict create type number label "Dimension ($unit)"]] [dict create value [dict get $spec value]] [list ::GX::CurveWorkbench::_constraintDimensionApply $w $st($w,token) {} $spec] $w
        return
    }
    return [_constraintCommit $w {} $spec]
}
proc ::GX::CurveWorkbench::_constraintDimensionApply {w token id spec values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen dimension"}
    dict set spec value [dict get $values value]
    return [_constraintCommit $w $id $spec]
}
proc ::GX::CurveWorkbench::_constraintCommit {w id spec} {
    variable st
    set reverse [_logicalNativeMap $w]
    set affected {};set definition $spec
    foreach field {a b axis} {
        if {[dict exists $spec $field]&&[dict get $spec $field]!=0} {
            set number [dict get $spec $field]
            if {![dict exists $reverse $number]} {error "Referenced geometry changed; select current geometry again"}
            set logical [dict get $reverse $number];dict set definition $field $logical;lappend affected $logical
            if {[dict get [_record $w $logical] locked]&&$field eq "a"} {error "Dataset sources and locked geometry are read-only. Convert to Native or unlock the primitive first."}
        } else {dict unset definition $field}
    }
    _cadUnits $w [lsort -unique $affected]
    set before [_snapshotIds $w $affected];set undo $st($w,undo);set redo $st($w,redo)
    set native 0;if {$id ne {}} {set native [dict get $st($w,constraints) $id native]}
    set receipt [::GX::Native2D::core interaction_constraint_apply $st($w,scene) $native $spec]
    if {$id eq {}} {set id constraint[incr st($w,nextConstraint)]}
    dict set st($w,constraints) $id [dict create id $id name [_constraintTitle [dict get $spec kind]] native [dict get $receipt id] definition $definition]
    try {
        _syncSamples $w [dict get $definition a]
        _history $w $before $affected
    } on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $undo;set st($w,redo) $redo;return -options $options $message}
    _constraintRefresh $w;_draw $w
    set st($w,status) "[_constraintTitle [dict get $spec kind]] committed by Native2D; other active constraints validated."
    return $id
}
proc ::GX::CurveWorkbench::_dimensionEdit {w} {
    variable st
    set id [_constraintSelected $w];set record [dict get $st($w,constraints) $id];set spec [dict get $record definition]
    if {[dict get $spec kind] ni {distance angle radius diameter lock_x lock_y}} {error "This relationship has no editable dimension; use Advanced for details"}
    set native [_constraintNativeSpec $w $spec]
    set unit [_cadUnits $w [list [dict get $spec a]]];if {[dict get $spec kind] eq "angle"} {set unit rad}
    ::GX::uiFieldFormCreate $w.dimension "Edit [_constraintTitle [dict get $spec kind]]" [dict create value [dict create type number label "Dimension ($unit)"]] [dict create value [dict get $spec value]] [list ::GX::CurveWorkbench::_constraintDimensionApply $w $st($w,token) $id $native] [::GX::CurveWorkbench::_constraintPanel $w]
}
proc ::GX::CurveWorkbench::_constraintDescription {w record} {
    variable st
    set spec [dict get $record definition];set names {}
    foreach field {a b axis} {if {[dict exists $spec $field]&&[dict exists $st($w,curves) [dict get $spec $field]]} {lappend names [dict get [_record $w [dict get $spec $field]] name]}}
    set kind [dict get $spec kind];set text "[_constraintTitle $kind]  [join [lsort -unique $names] { ↔ }]"
    if {[_isDimension $kind]} {append text " = [_dimensionText $w [_constraintNativeSpec $w $spec] [dict get $spec value] [::GX::datasetPublicationV2DictDefault $spec driven 0]]"}
    return $text
}
proc ::GX::CurveWorkbench::_constraintMarkers {w} {
    variable st
    set ordinals {}
    dict for {id record} $st($w,constraints) {
        set spec [dict get $record definition];if {![dict exists $st($w,curves) [dict get $spec a]]} continue
        # CORE resolves both legacy and defining-control constraint locations.
        if {[catch {set point [::GX::Native2D::core interaction_constraint_location $st($w,scene) [dict get $record native]]}]} continue
        lassign [::GX::Native2D::core device $st($w,scene) $point] x y
        set receipt [::GX::Native2D::core constraint_get $st($w,scene) [dict get $record native]]
        set color [expr {[dict get $receipt disabled]?"#7b7b7b":"#744096"}]
        set object [dict get $spec a];set ordinal [::GX::datasetPublicationV2DictDefault $ordinals $object 0];dict incr ordinals $object
        $w.right.viewport.canvas create text [expr {$x+14}] [expr {$y+18+18*$ordinal}] -text [_constraintDescription $w $record] -anchor nw -fill $color -font TkSmallCaptionFont -tags [list constraint_marker constraint_$id]
    }
}
proc ::GX::CurveWorkbench::_constraintMarkerSelect {w id} {
    _constraintOpen $w
    [::GX::CurveWorkbench::_constraintPanel $w].tree selection set $id;[::GX::CurveWorkbench::_constraintPanel $w].tree see $id
    _constraintHighlight $w
}
proc ::GX::CurveWorkbench::_constraintHighlight {w} {
    variable st
    if {![winfo exists [::GX::CurveWorkbench::_constraintPanel $w].tree]||[[::GX::CurveWorkbench::_constraintPanel $w].tree selection] eq {}} return
    if {![dict exists $st($w,constraints) [lindex [[::GX::CurveWorkbench::_constraintPanel $w].tree selection] 0]]} return
    set id [_constraintSelected $w];set spec [dict get $st($w,constraints) $id definition];set ids {}
    foreach field {a b axis} {if {[dict exists $spec $field]&&[dict exists $st($w,curves) [dict get $spec $field]]} {lappend ids [dict get $spec $field]}}
    set st($w,sketchSelection) {};set st($w,objectSelection) [lsort -unique $ids];set st($w,active) [lindex $ids 0]
    _curveList $w;_pointList $w;_draw $w
    foreach logical $ids {foreach path [::GX::Native2D::core render_paths $st($w,scene) [dict get [_record $w $logical] native]] {_renderPath $w.right.viewport.canvas $path #b85a00 4 {}}}
    ::GX::native2DCanvasViewportClip $w.right.viewport.canvas $st($w,scene)
}
rename ::GX::CurveWorkbench::_constraintOpen ::GX::CurveWorkbench::_constraintOpen_interaction_base
proc ::GX::CurveWorkbench::_constraintOpen {w} {
    _constraintOpen_interaction_base $w
    [::GX::CurveWorkbench::_constraintPanel $w].help configure -text {Select geometry or defining handles on the canvas; the Constraints menu offers Native-compatible relationships. Dimensions drive supported primitive edits and validate all active relationships. Advanced shows exact reference details.}
    [::GX::CurveWorkbench::_constraintPanel $w].actions.create configure -text {From selection…} -command [list ::GX::CurveWorkbench::_sketchContext $w [winfo rootx [::GX::CurveWorkbench::_constraintPanel $w].actions.create] [expr {[winfo rooty [::GX::CurveWorkbench::_constraintPanel $w].actions.create]+30}]]
    [::GX::CurveWorkbench::_constraintPanel $w].actions.edit configure -text {Edit dimension…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_dimensionEdit $w]]
    if {![winfo exists [::GX::CurveWorkbench::_constraintPanel $w].actions.advanced]} {ttk::button [::GX::CurveWorkbench::_constraintPanel $w].actions.advanced -text Advanced… -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_constraintForm $w 1]];pack [::GX::CurveWorkbench::_constraintPanel $w].actions.advanced -side left -padx 4}
    [::GX::CurveWorkbench::_constraintPanel $w].tree column id -width 0 -minwidth 0 -stretch 0
    [::GX::CurveWorkbench::_constraintPanel $w].tree column name -width 360
    bind [::GX::CurveWorkbench::_constraintPanel $w].tree <<TreeviewSelect>> [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_constraintHighlight $w]]
    _constraintRefresh $w
}
rename ::GX::CurveWorkbench::_constraintRefresh ::GX::CurveWorkbench::_constraintRefresh_interaction_base
proc ::GX::CurveWorkbench::_constraintRefresh {w} {
    variable st
    _constraintRefresh_interaction_base $w
    if {![winfo exists [::GX::CurveWorkbench::_constraintPanel $w].tree]} return
    dict for {id record} $st($w,constraints) {set values [[::GX::CurveWorkbench::_constraintPanel $w].tree item $id -values];lset values 1 [_constraintDescription $w $record];[::GX::CurveWorkbench::_constraintPanel $w].tree item $id -values $values}
}
rename ::GX::CurveWorkbench::_restoreSnapshot ::GX::CurveWorkbench::_restoreSnapshot_interaction_base
proc ::GX::CurveWorkbench::_restoreSnapshot {w snapshot} {variable st;set st($w,sketchSelection) {};_restoreSnapshot_interaction_base $w $snapshot}
# The unit selector uses the existing whole-workspace physical reexpression.
# Its pending choice is never treated as a completed coordinate conversion.
proc ::GX::CurveWorkbench::_sketchUnitChoice {w} {
    variable st
    set requested $st($w,sketchUnit)
    if {[dict size $st($w,curves)]==0} {::GX::unitRegistryHomogeneousCoordinatePlan $requested $requested;return}
    set units [_coordinateUnits [_record $w [_active $w]]]
    if {[lindex $units 0] ne [lindex $units 1] || [catch {::GX::unitRegistryHomogeneousCoordinatePlan [lindex $units 0] $requested}]} {set st($w,sketchUnit) [lindex $units 0];error {This control requires a common compatible Euclidean frame. Use Axis display units for independent scientific axes.}}
    set st($w,sketchUnit) [lindex $units 0]
    _unitsOpen $w
    set ::GX::UiField::formValues($w.units,target_unit) $requested
}
rename ::GX::CurveWorkbench::_unitsApply ::GX::CurveWorkbench::_unitsApply_interaction_base
proc ::GX::CurveWorkbench::_unitsApply {w token ids values} {
    variable st
    set result [_unitsApply_interaction_base $w $token $ids $values]
    set st($w,sketchUnit) [dict get $result target_unit]
    return $result
}

rename ::GX::CurveWorkbench::_joinSource ::GX::CurveWorkbench::_joinSource_interaction_base
proc ::GX::CurveWorkbench::_joinSource {w} {
    variable st
    if {[dict exists [_record $w [_active $w]] sketch_definition]} {
        set refs $st($w,sketchSelection)
        if {[llength $refs]!=1||[dict get [lindex $refs 0] entity] ne "control"} {error "Select one defining endpoint for Join"}
        return [list [dict get [lindex $refs 0] logical] [::GX::Native2D::core interaction_point_index $st($w,scene) [lindex $refs 0]]]
    }
    return [_joinSource_interaction_base $w]
}

# Refresh the UI's selected handles after authoritative edits through Native
# descriptors. Parameter epochs describe handle identity, not display rows.
rename ::GX::CurveWorkbench::_syncSamples ::GX::CurveWorkbench::_syncSamples_interaction_base
proc ::GX::CurveWorkbench::_syncSamples {w id} {
    variable st
    _syncSamples_interaction_base $w $id
    if {![dict exists [_record $w $id] sketch_definition]} return
    set handles [::GX::Native2D::core interaction_controls $st($w,scene) [dict get [_record $w $id] native]]
    set refreshed {}
    foreach ref $st($w,sketchSelection) {
        if {[dict get $ref logical] ne $id} {lappend refreshed $ref;continue}
        foreach handle $handles {
            if {[dict get $ref entity] eq "control"&&[dict get $ref index]==[dict get $handle index]} {
                dict set handle logical $id;lappend refreshed $handle;break
            }
        }
    }
    set st($w,sketchSelection) $refreshed
}
