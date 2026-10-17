# SPDX-License-Identifier: GPL-3.0-or-later
# Form entries are presentation coordinates; Native2D operations and persisted
# constraints retain their original native frame. CORE owns conversion plans.
proc ::GX::CurveWorkbench::_coordinateControlKey {w ids} {
    set result {};foreach id $ids {lappend result $id [_coordinateKey $w $id]};return $result
}
proc ::GX::CurveWorkbench::_coordinateControlCheck {w ids key} {
    variable st
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]||$key ne [_coordinateControlKey $w $ids]} {error {Coordinate context changed; reopen the action form}}
}
proc ::GX::CurveWorkbench::_coordinateControlPlan {w id axis {direction forward} {target {}}} {
    set info [_coordinateAxis $w $id $axis]
    if {[dict get $info reason] ne {}} {error [dict get $info reason]}
    if {$target eq {}} {set target [dict get $info display_unit]}
    set native [dict get $info native_unit];set context [dict get $info context]
    if {$context ne {}} {
        set plan [::GX::datasetCoordinateSnapshotAffinePlan $context [dict get $info variable_id] $native [_coordinateOptions $info [dict create unit $target direction $direction]]]
    } elseif {$native eq $target} {set plan {affine 1 scale 1.0 offset 0.0}} else {
        set plan [::GX::unitRegistryAffinePlan $native $target {} $direction]
    }
    if {![dict get $plan affine]} {error {A constant displacement or dimension requires an affine display relation; select a linear unit or explicitly normalize the Dataset}}
    return $plan
}
proc ::GX::CurveWorkbench::_coordinateControlDelta {w id axis value {direction forward}} {
    set plan [_coordinateControlPlan $w $id $axis $direction]
    return [::GX::uiFieldNormalize {type number} [expr {$value*[dict get $plan scale]}]]
}
proc ::GX::CurveWorkbench::_cadTransformUnits {w kind ids} {
    _coordinateRequireFrame $w $ids
    if {$kind in {rotate mirror}} {_cadUnits $w $ids}
    if {$kind ni {translate scale rotate mirror}} {error {Unknown CAD transform}}
    return [_coordinateUnits [_record $w [lindex $ids 0]]]
}
proc ::GX::CurveWorkbench::_cadTransformDisplayedApply {w kind ids pivot key values} {
    _coordinateControlCheck $w $ids $key
    set id [lindex $ids 0];set input $values
    if {$kind eq "translate"} {
        foreach axis {x y} {dict set values d$axis [_coordinateControlDelta $w $id $axis [dict get $values d$axis] inverse]}
    } elseif {$kind eq "mirror"} {
        foreach point {a b} {
            lassign [_coordinatePoint $w $id [list [dict get $values ${point}x] [dict get $values ${point}y]] inverse] x y
            dict set values ${point}x $x;dict set values ${point}y $y
        }
    }
    dict set values presentation_input [dict create values $input basis $id coordinate_key $key]
    return [_cadTransformApply $w $kind $ids $pivot $values]
}
proc ::GX::CurveWorkbench::_cadPivotDisplayedApply {w ids key values} {
    _coordinateControlCheck $w $ids $key
    if {$ids ne [_cadTargets $w]} {error {Pivot targets changed; reopen the action form}}
    if {[dict get $values mode] eq "custom"} {
        lassign [_coordinatePoint $w [lindex $ids 0] [list [dict get $values x] [dict get $values y]] inverse] x y
        dict set values x $x;dict set values y $y
    }
    _cadPivotApply $w $values
}
proc ::GX::CurveWorkbench::_constraintCoordinateGuard {w spec} {
    variable st
    set ids {}
    dict for {id record} $st($w,curves) {
        foreach key {a b axis} {if {[dict exists $spec $key]&&[dict get $spec $key] eq [dict get $record native]} {lappend ids $id}}
    }
    set ids [lsort -unique $ids];_coordinateRequireFrame $w $ids
    if {[dict get $spec kind] ni {lock_x lock_y horizontal_distance vertical_distance horizontal vertical}} {_cadUnits $w $ids}
}
proc ::GX::CurveWorkbench::_dimensionCoordinateInfo {w spec} {
    variable st
    set kind [dict get $spec kind]
    if {$kind in {angle axis_angle}} {return {id {} axis x native_unit rad display_unit rad}}
    set axis [expr {$kind in {lock_y vertical_distance}?"y":"x"}]
    dict for {id record} $st($w,curves) {
        if {[dict get $record native] eq [dict get $spec a]} {return [dict merge [_coordinateAxis $w $id $axis] [dict create id $id axis $axis]]}
    }
    set unit $st($w,sketchUnit)
    set image [::GX::Native2D::core image_get $st($w,scene) [dict get $spec a]]
    if {$image ne {}} {set unit [dict get $image length_unit]}
    return [dict create id {} axis $axis native_unit $unit display_unit $unit]
}
proc ::GX::CurveWorkbench::_dimensionDisplayedValue {w spec value {direction forward}} {
    set info [_dimensionCoordinateInfo $w $spec];set id [dict get $info id]
    if {$id eq {}} {return $value}
    if {[dict get $spec kind] in {lock_x lock_y}} {return [lindex [_coordinateValues $w $id [dict get $info axis] [list $value] $direction] 0]}
    return [_coordinateControlDelta $w $id [dict get $info axis] $value $direction]
}
proc ::GX::CurveWorkbench::_dimensionInput {w spec text} {
    set text [string trim $text]
    if {[string is double -strict $text]} {
        set value [_dimensionDisplayedValue $w $spec [::GX::uiFieldNormalize {type number} $text] inverse]
        return [dict create value $value expression $value]
    }
    if {[regexp {^([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)\s+(\S+)$} $text -> number unit]} {
        set info [_dimensionCoordinateInfo $w $spec];set native [dict get $info native_unit];set id [dict get $info id]
        if {$id eq {}} {set plan [::GX::unitRegistryAffinePlan $unit $native]} else {set plan [_coordinateControlPlan $w $id [dict get $info axis] inverse $unit]}
        if {![dict get $plan affine]} {error {Typed dimension units require an affine relation}}
        set value [expr {$number*[dict get $plan scale]}]
        if {[dict get $spec kind] in {lock_x lock_y}} {set value [expr {$value+[dict get $plan offset]}]}
        set value [::GX::uiFieldNormalize {type number} $value]
        return [dict create value $value expression $value]
    }
    # Existing parameter bindings are native-coordinate expressions. Preserve
    # their meaning on reopen or a display-unit change, including legacy files.
    return [dict create value [::GX::parameterEvaluate [_parameterBind $w] $text] expression $text]
}
proc ::GX::CurveWorkbench::_constraintDisplayedApply {w token id ids key values} {
    _coordinateControlCheck $w $ids $key
    set spec [_constraintNativeSpec $w [dict remove $values name]]
    if {[_isDimension [dict get $spec kind]]} {
        set parsed [_dimensionInput $w $spec [dict get $values value]]
        if {![string is double -strict [dict get $parsed expression]]} {error {Use the inline dimension editor to retain a parameter formula}}
        dict set values value [dict get $parsed value]
    }
    return [_constraintApply $w $token $id $values]
}
