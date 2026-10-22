# SPDX-License-Identifier: GPL-3.0-or-later
# Definitions and their geometry belong to Native2D; this file owns reviewable
# parameters, logical identity, publication descriptors and semantic history.
proc ::GX::CurveWorkbench::_sketchSamples {w native} {
    variable st
    set samples {};set i 0
    foreach xy [::GX::Native2D::core points $st($w,scene) $native] {
        lassign $xy x y;lappend samples [dict create x $x y $y row -1 order $i point_id "native_sample[incr i]"]
    }
    return $samples
}
proc ::GX::CurveWorkbench::_sketchOpen {w {edit 0}} {
    variable st
    set fields [dict create name {type string label {Geometry name}} family [dict create type choice label {Primitive family} values {point path construction_line polyline rectangle circle arc ellipse quadratic_bezier cubic_bezier spline}] closed {type boolean label {Close retained Line/path}} controls {type string label {Controls: {X Y} pairs in working units}} working_unit {type string required 1 label {Common working unit (for example V, kg or m/s)}} radius_x {type number label {Circle/arc radius or ellipse X radius}} radius_y {type number label {Ellipse Y radius}} rotation {type number label {Local rotation (degrees)}} angle_start {type number label {Arc start (degrees)}} angle_sweep {type number label {Arc signed sweep (degrees)}} samples {type integer min 1 max 65536 label {Complete parameter sampling count}}]
    set initial [dict create name {Native circle} family circle closed 0 controls {{0 0}} working_unit mm radius_x 2 radius_y 1 rotation 0 angle_start 0 angle_sweep 90 samples 257]
    set id {}
    if {$edit} {
        if {[llength [_commandSelection $w]]!=1} {error {Select one primitive to review its exact parameters.}}
        set id [_active $w];set record [_record $w $id]
        if {![dict exists $record sketch_definition]} {error "Select a retained sketch primitive"}
        set definition [::GX::Native2D::core sketch_definition $st($w,scene) [dict get $record native]]
        if {[dict get $definition family] in {composite_path compound}} {error {This object retains exact constituent primitives. Use Modify > Separate exact constituents, then edit a constituent's parameters. The original composition is preserved.}}
        dict set initial name [dict get $record name];dict set initial working_unit [lindex [_coordinateUnits $record] 0]
        dict set initial samples [dict get $record sketch_samples]
        foreach key {family controls closed radius_x radius_y rotation angle_start angle_sweep} {
            set value [::GX::datasetPublicationV2DictDefault $definition $key 0]
            if {$key in {rotation angle_start angle_sweep}} {set value [expr {$value*180/acos(-1)}]}
            dict set initial $key $value
        }
        dict unset fields working_unit
        lassign [_coordinateUnits $record] xUnit yUnit
        dict set fields controls label "Local native controls: X ($xUnit), Y ($yUnit); before the retained world transform"
    }
    dict unset fields working_unit
    dict unset initial working_unit
    set frame [_sketchCoordinateContext $w $id]
    lassign [dict get $frame units] xUnit yUnit
    dict set fields controls label "Local native controls: X ($xUnit), Y ($yUnit); before the retained world transform"
    dict set fields radius_x label "Circle/arc numeric plane radius; ellipse native X radius ($xUnit)"
    dict set fields radius_y label "Ellipse native Y radius ($yUnit)"
    dict set fields rotation label {Numeric plane rotation (degrees)}
    ::GX::uiFieldFormCreate $w.sketch "Retained Native2D primitive — X $xUnit / Y $yUnit" $fields $initial [list ::GX::CurveWorkbench::_sketchReviewedApply $w $st($w,token) $id $frame] $w
    ttk::label $w.sketch.hint -text {Controls: point/center 1 pair; line or opposite rectangle corners 2; quadratic Bezier 3; cubic Bezier 4; Line/path or spline 2 or more. X and Y use the Workspace coordinate frame. A circle radius or rotation in an unlike-axis plane is a numeric plane parameter, not a physical distance or angle. Configure axes in Workspace Configuration.} -wraplength 600 -padding 8
    pack $w.sketch.hint -side top -fill x -before $w.sketch.viewport
    bind $w.sketch.hint <Configure> [list ::GX::CurveWorkbench::_sketchHintLayout $w.sketch.hint %w]
}
proc ::GX::CurveWorkbench::_sketchHintLayout {label width} {
    if {[winfo exists $label]} {$label configure -wraplength [expr {max(100,$width-20)}]}
}
proc ::GX::CurveWorkbench::_sketchCoordinateContext {w id} {
    variable st
    set parents {}
    if {$id ne {}} {set parents [list $id]} elseif {$st($w,active) ne {}&&[dict exists $st($w,curves) $st($w,active)]} {set parents [list $st($w,active)]}
    if {$parents ne {}} {_coordinatePlaneAdmit $w $parents;set units [_coordinateUnits [_record $w [lindex $parents 0]]]} else {set units [list [dict get $st($w,coordinateConfiguration) x_unit] [dict get $st($w,coordinateConfiguration) y_unit]];_coordinateAxesAdmit $w $units}
    return [dict create units $units parents $parents key [_coordinateControlKey $w $parents] configuration $st($w,coordinateConfiguration)]
}
proc ::GX::CurveWorkbench::_sketchReviewedApply {w token id frame values} {
    if {$frame ne [_sketchCoordinateContext $w $id]} {error {Coordinate frame changed; reopen primitive parameters}}
    return [_sketchApply $w $token $id $values]
}
proc ::GX::CurveWorkbench::_sketchApply {w token id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen primitive parameters"}
    set frame [_sketchCoordinateContext $w $id]
    _cancelGesture $w;_pointSyncApply $w
    set definition [dict create family [dict get $values family] controls [dict get $values controls]]
    foreach key {radius_x radius_y rotation angle_start angle_sweep} {
        set value [dict get $values $key];if {$key in {rotation angle_start angle_sweep}} {set value [expr {$value*acos(-1)/180}]}
        dict set definition $key $value
    }
    if {[dict get $values family] eq "path"} {dict set definition closed [dict get $values closed]}
    set n [llength [dict get $values controls]];set family [dict get $values family]
    set required [dict get {point 1 line 2 construction_line 2 rectangle 2 circle 1 arc 1 ellipse 1 quadratic_bezier 3 cubic_bezier 4 path 0 polyline 0 spline 0} $family]
    if {($required&&$n!=$required)||(!$required&&$n<2)} {error "The $family primitive requires [expr {$required ? $required : {at least 2}}] XY control pairs"}
    set samples [dict get $values samples];set name [string trim [dict get $values name]]
    if {$name eq {}} {error "Enter a geometry name"}
    set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    if {$id eq {}} {
        set native [::GX::Native2D::core sketch_create $st($w,scene) $definition $samples]
        try {
            set record [_newRecord $w $name [_sketchSamples $w $native] {} x y {} {} {} {} {} [list [dict create operation create_primitive family [dict get $definition family]]]]
            dict set record coordinate_units [dict get $frame units]
            set record [_coordinateRetainFrame $w $record [dict get $frame parents]]
            set id [dict get $record id];set before [_snapshotIds $w [list $id]]
            _addRecord $w $record $native
        } on error {message options} {::GX::Native2D::core delete $st($w,scene) $native;return -options $options $message}
    } else {
        set before [_snapshotIds $w [list $id]];set record [_record $w $id]
        if {[dict get $record locked]} {error "The primitive is locked"}
        # Preserve the existing world transform when editing local parameters.
        dict set definition matrix [dict get [::GX::Native2D::core sketch_definition $st($w,scene) [dict get $record native]] matrix]
        ::GX::Native2D::core sketch_update $st($w,scene) [dict get $record native] $definition $samples
        dict set record samples [_sketchSamples $w [dict get $record native]];dict set record name $name
        dict set record sketch_definition [::GX::Native2D::core sketch_definition $st($w,scene) [dict get $record native]]
        dict set record sketch_samples [::GX::Native2D::core count $st($w,scene) [dict get $record native]]
        dict lappend record operations [dict create operation edit_primitive_parameters family [dict get $definition family]]
        dict set st($w,curves) $id $record
    }
    set record [_record $w $id]
    dict set record materialization_sampling [dict create method uniform_parameter first 0 last 1 total [dict get $record sketch_samples] geometry_authority retained_sketch]
    dict set st($w,curves) $id $record
    set st($w,active) $id;set st($w,objectSelection) [list $id]
    try {_selectionScene $w;_history $w $before [list $id]} on error {message options} {
        _restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;_curveList $w;_pointList $w;_draw $w
        return -options $options $message
    }
    set st($w,status) "Retained primitive committed. Edit its parameters or explicitly explode an editable point curve."
    return $id
}
proc ::GX::CurveWorkbench::_sketchExplode {w} {
    variable st
    set source [_active $w];set record [_record $w $source]
    if {![dict exists $record sketch_definition]} {error "Select a retained sketch primitive"}
    if {[dict get $record sketch_definition family] eq "construction_line"} {error "Use Sample finite range… to materialize an infinite construction line"}
    return [_sketchSampleApply $w $st($w,token) $source [dict create name "[dict get $record name] exploded" first 0 last 1 total [dict get $record sketch_samples]]]
}
rename ::GX::CurveWorkbench::_editable ::GX::CurveWorkbench::_editable_sketch_base
proc ::GX::CurveWorkbench::_editable {w} {
    set id [_editable_sketch_base $w]
    if {[dict exists [_record $w $id] sketch_definition]} {error "Retained primitive points are sampled geometry. Use Parameters… or Explode points to edit an independent point curve."}
    return $id
}
rename ::GX::CurveWorkbench::publish ::GX::CurveWorkbench::publish_sketch_base
proc ::GX::CurveWorkbench::publish {w datasetId {ids {}}} {
    if {$ids eq {}} {set ids [list [_active $w]]}
    foreach id $ids {
        set record [_record $w $id]
        if {[dict exists $record sketch_definition]&&[dict get $record sketch_definition family] eq "construction_line"} {error "Infinite construction geometry requires an explicit finite sampling range before Dataset publication"}
    }
    return [publish_sketch_base $w $datasetId $ids]
}
rename ::GX::CurveWorkbench::_metrics ::GX::CurveWorkbench::_metrics_sketch_base
proc ::GX::CurveWorkbench::_metrics {w} {
    variable st
    if {$st($w,active) ne {}} {
        set record [_record $w $st($w,active)]
        if {[dict exists $record sketch_definition]} {
            if {[dict get $record sketch_definition family] eq "point"} {set st($w,metricText) "Native point — finite location; curve length and enclosed area are not applicable";return}
            if {[dict get $record sketch_definition family] eq "construction_line"} {set st($w,metricText) "Infinite construction line — finite length, area and bounds are undefined";return}
            _metrics_sketch_base $w
            set st($w,metricText) [string map [list " · [_pointCount $record] exact controls/points" { · retained mathematical definition}] $st($w,metricText)]
            return
        }
    }
    _metrics_sketch_base $w
}
proc ::GX::CurveWorkbench::_seriesOpen {w} {
    variable st
    set ids [_cadTargets $w];_coordinatePlaneAdmit $w $ids
    lassign [_coordinateUnits [_record $w [lindex $ids 0]]] xUnit yUnit
    foreach id $ids {if {[_bulkRecord [_record $w $id]]} {error "Convert an explicit exact range to Native before creating an editable Workbench series"}}
    set fields [dict create column_y [dict create type number label "Column step: native Y ($yUnit; optional basis)"] row_x [dict create type number label "Row step: native X ($xUnit; optional basis)"] name {type string label {Series name}} circular {type boolean label {Circular series (otherwise rectangular)}} rows {type integer min 1 max 10000 label {Rectangular rows}} columns {type integer min 1 max 10000 label {Rectangular columns}} spacing_x [dict create type number label "Column spacing: native X ($xUnit)"] spacing_y [dict create type number label "Row spacing: native Y ($yUnit)"] positions {type integer min 2 max 10000 label {Circular positions, including position zero}} angle_step {type number label {Numeric plane angular step (degrees)}} pivot_x [dict create type number label "Circular pivot: native X ($xUnit)"] pivot_y [dict create type number label "Circular pivot: native Y ($yUnit)"] rotate_geometry {type boolean label {Rotate geometry around circular pivot}} include_origin {type boolean label {Also create a copy at source position zero}}]
    ::GX::uiFieldFormCreate $w.series "Native2D series — originals preserved; one undo action" $fields [dict create column_y 0 row_x 0 name series circular 0 rows 2 columns 2 spacing_x 5 spacing_y 5 positions 4 angle_step 90 pivot_x 0 pivot_y 0 rotate_geometry 1 include_origin 0] [list ::GX::CurveWorkbench::_seriesReviewedApply $w $st($w,token) $ids [_coordinateControlKey $w $ids]] $w
}
proc ::GX::CurveWorkbench::_seriesReviewedApply {w token ids key values} {
    _coordinateControlCheck $w $ids $key
    return [_seriesApply $w $token $ids $values]
}
proc ::GX::CurveWorkbench::_seriesApply {w token ids values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen the series form"}
    if {$ids ne [_cadTargets $w]} {error "Series targets changed; reopen the form"}
    foreach id $ids {if {[_bulkRecord [_record $w $id]]} {error "Convert an explicit range to Native before editable series creation"}}
    _cancelGesture $w;_pointSyncApply $w;_coordinatePlaneAdmit $w $ids
    set parameters [dict remove $values name pivot_x pivot_y]
    dict set parameters angle_step [expr {[dict get $values angle_step]*acos(-1)/180}]
    dict set parameters pivot [list [dict get $values pivot_x] [dict get $values pivot_y]]
    set nativeIds {};set map {}
    foreach id $ids {set native [dict get [_record $w $id] native];lappend nativeIds $native;dict set map $native $id}
    set receipt [::GX::Native2D::core series $st($w,scene) $nativeIds $parameters]
    set before [_snapshotIds $w {}];set results {};set oldUndo $st($w,undo);set oldRedo $st($w,redo);set ordinal 0
    try {
        foreach native [dict get $receipt object_ids] sourceNative [dict get $receipt source_ids] {
            set parent [dict get $map $sourceNative];set source [_record $w $parent]
            set record [_newRecord $w "[dict get $values name] [incr ordinal] — [dict get $source name]" [dict get $source samples] [dict get $source source] [dict get $source x] [dict get $source y] [dict get $source filter] [dict get $source filter_value] [dict get $source family] [dict get $source order] [list $parent] [list [dict create operation series parameters $parameters ordinal $ordinal originals_preserved 1]] [dict get $source representation]]
            foreach key {working_unit attributes source_descriptor materialization_sampling} {if {[dict exists $source $key]} {dict set record $key [dict get $source $key]}}
            dict set record breaks [dict get $source breaks]
            set id [dict get $record id];dict set before $id {};lappend results $id
            _addRecord $w $record $native;_syncSamples $w $id
        }
        set st($w,active) [lindex $results 0];set st($w,objectSelection) $results;set st($w,cadTarget) selected
        _selectionScene $w;_history $w $before $results
    } on error {message options} {
        _restoreSnapshot $w $before
        set live [::GX::Native2D::core ids $st($w,scene)]
        foreach native [dict get $receipt object_ids] {if {$native in $live} {::GX::Native2D::core delete $st($w,scene) $native}}
        set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;_curveList $w;_pointList $w;_draw $w
        return -options $options $message
    }
    set st($w,status) "Series committed: [llength $results] independent Native objects; originals preserved."
    return $results
}
proc ::GX::CurveWorkbench::_sketchSampleOpen {w} {
    variable st
    set id [_active $w];set record [_record $w $id]
    if {![dict exists $record sketch_definition]} {error "Select a retained primitive to sample"}
    ::GX::uiFieldFormCreate $w.sample "Explicit finite sampling — creates an independent Native point curve" [dict create name {type string label {Result geometry name}} first {type number label {First parameter (construction lines may extend beyond 0)}} last {type number label {Last parameter (construction lines may extend beyond 1)}} total {type integer min 1 max 65536 label {Complete result points (Workbench limit 65536)}}] [dict create name "[dict get $record name] sampled" first 0 last 1 total 257] [list ::GX::CurveWorkbench::_sketchSampleApply $w $st($w,token) $id] $w
}
proc ::GX::CurveWorkbench::_sketchSampleApply {w token source values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error "Session changed; reopen sampling parameters"}
    _coordinatePlaneAdmit $w [list $source]
    set original [_record $w $source];set first [dict get $values first];set last [dict get $values last];set total [dict get $values total]
    set native [::GX::Native2D::core sketch_materialize $st($w,scene) [dict get $original native] $first $last $total]
    set sampling [dict create method uniform_parameter first $first last $last total $total]
    set oldUndo $st($w,undo);set oldRedo $st($w,redo);set before [_snapshotIds $w {}]
    try {
        set record [_newRecord $w [dict get $values name] [_sketchSamples $w $native] {} x y {} {} {} {} [list $source] [list [dict create operation explicit_sketch_materialization sampling $sampling definition [dict get $original sketch_definition]]]]
        dict set record sketch_attributes gx.geometry_role regular
        dict set record materialization_sampling $sampling
        set id [dict get $record id];dict set before $id {}
        _addRecord $w $record $native;set st($w,active) $id;set st($w,objectSelection) [list $id];_selectionScene $w
        _history $w $before [list $id]
    } on error {message options} {
        _restoreSnapshot $w $before
        if {$native in [::GX::Native2D::core ids $st($w,scene)]} {::GX::Native2D::core delete $st($w,scene) $native}
        set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;_curveList $w;_pointList $w;_draw $w
        return -options $options $message
    }
    set st($w,status) "Created complete explicit parameter sample. Publish it with a new Dataset ID when ready."
    return $id
}
proc ::GX::CurveWorkbench::_buildSketchMenu {w} {
    
    ttk::menubutton $w.cad.sketch -text "Sketch…" -menu $w.cad.sketch.menu
    menu $w.cad.sketch.menu -tearoff 0
    foreach {label command} [list {Create primitive…} [list _sketchOpen $w] {Edit parameters…} [list _sketchOpen $w 1] {Create series…} [list _seriesOpen $w] {Explode editable points} [list _sketchExplode $w] {Sample finite range…} [list _sketchSampleOpen $w]] {
        set callback [lreplace $command 0 0 ::GX::CurveWorkbench::[lindex $command 0]]
        $w.cad.sketch.menu add command -label $label -command [list ::GX::CurveWorkbench::_safe $w $callback]
    }
    pack $w.cad.sketch -side left -padx 3
}
