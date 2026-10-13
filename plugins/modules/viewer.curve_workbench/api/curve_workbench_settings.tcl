# SPDX-License-Identifier: GPL-3.0-or-later
# Lightweight command/settings schema. No canvas or scientific runtime is loaded.
namespace eval ::GX::CurveWorkbench {}
proc ::GX::CurveWorkbench::_commandRows {} {return {
        select {Select} v none {_selectionShape click} select
        select.local {Local Geometry Selection} {} none {_selectionTarget local} {}
        select.object {Select Entire Curve / Path} {} none {_selectionTarget object} {}
        object.select {Select} {} none {_objectListSelect} {}
        select.window {Rectangle selection} {} none {_selectionShape window} {}
        select.polygon {Polygon selection} {} none {_selectionShape polygon} {}
        object.delete {Delete selection} Delete selection {_deleteCurve} {}
        object.duplicate {Duplicate selection} Ctrl+d selection {_duplicate} {}
        object.split {Split selected Path / entity…} {} selection {_pathSplit} {}
        object.reverse {Reverse selection traversal} {} selection {_reverseSelection} {}
        object.parameters {Exact parameters…} {} selection {_sketchOpen 1} {}
        object.units {Working units…} {} selection {_unitsOpen} {}
        object.native_tools {Native point operations / groups…} {} none {_cadDetails} {}
        object.selectable {Include in selection} {} selection {_selectableSet 1} {}
        object.reference {Visible reference only} {} selection {_selectableSet 0} {}
        create.numeric {Exact numeric creation…} {} none {_sketchOpen} {}
        constraint.unfix Unfix {} selection {_unfix} {}
        constraint.inspector {Inspector / dimensions…} {} none {_constraintOpen} {}
        constraint.advanced {Advanced reference editor…} {} none {_constraintForm} {}
        constraint.dimension Dimension d none {_dimensionTool} {}
        object.show {Show selection} {} selection {_setVisibility 1} {}
        object.hide {Hide selection} h selection {_setVisibility 0} {}
        object.lock {Lock selection} {} selection {_setLock 1} {}
        object.unlock {Unlock selection} {} selection {_setLock 0} {}
        object.join {Join Path…} j selection {_compositionOpen auto_path} {}
        object.combine {Combine / Compound…} Shift+j selection {_compositionOpen compound} {}
        object.separate {Separate exact constituents} {} selection {_compositionSeparate} {}
        object.publish {Publish selection…} {} selection {_publishBatchOpen} {}
        object.promote {Dataset to retained geometry (review)…} {} selection {_promoteOpen} {}
        history.undo Undo Ctrl+z undo {undo} {}
        history.redo Redo Ctrl+y redo {redo} {}
        view.fit_all {Fit all} f none {_fit 0} {}
        view.fit_selection {Fit selection} Shift+f selection {_fit 1} {}
        view.pan Pan p none {_scienceTool pan} {}
        workspace.save {Save workspace} Ctrl+s none {_saveExplicit} {}
}}
proc ::GX::CurveWorkbench::_creationRows {} {return {line Line l rectangle Rectangle r circle Circle c arc Arc a spline Spline s quadratic_bezier {Quadratic Bézier} {} cubic_bezier {Cubic Bézier} b polyline Polyline {} ellipse Ellipse {} point Point {} construction_line {Construction axis} {}}}
proc ::GX::CurveWorkbench::_constraintGroups {} {
    return [dict create Directions {horizontal vertical parallel perpendicular collinear} Connections {coincident tangent midpoint concentric point_on_line point_on_curve} Shape {equal_length equal_radius symmetry curvature} Fixing {fixed} Dimensional {distance horizontal_distance vertical_distance point_line_distance line_distance angle axis_angle radius diameter lock_x lock_y}]
}
proc ::GX::CurveWorkbench::_constraintTitle {kind} {
    return [dict get {fixed Fix distance {Distance / Length} angle Angle parallel Parallel perpendicular Perpendicular coincident Coincident horizontal Horizontal vertical Vertical equal_length {Equal Length} equal_radius {Equal Radius} tangent Tangent concentric Concentric collinear Collinear midpoint Midpoint point_on_line {Point on Line} point_on_curve {Point on Curve} symmetry Symmetry radius Radius diameter Diameter lock_x {X Dimension} lock_y {Y Dimension} horizontal_distance {Horizontal Distance} vertical_distance {Vertical Distance} point_line_distance {Point-Line Distance} line_distance {Parallel Line Distance} axis_angle {Axis Angle} curvature {Curvature / G2}} $kind]
}
proc ::GX::CurveWorkbench::_shortcutNormalize {value} {
    set value [string trim $value]
    if {$value eq {}} {return {}}
    set parts [split $value +];set key [lindex $parts end];set mods [lrange $parts 0 end-1]
    foreach modifier $mods {if {$modifier ni {Ctrl Shift}} {error {Use Ctrl and/or Shift; Alt and platform combinations are reserved.}}}
    if {[regexp {^[A-Z]$} $key]} {lappend mods Shift;set key [string tolower $key]}
    if {![regexp {^([a-z0-9]|Delete|F([2-9]|1[0-2]))$} $key]} {error {Use one letter/digit, Delete or F2–F12. Enter, Escape, Space, Tab and editing/navigation keys are reserved.}}
    set result {};foreach modifier {Ctrl Shift} {if {$modifier in $mods} {lappend result $modifier}}
    lappend result $key;set result [join $result +]
    if {$result in {Ctrl+a Ctrl+c Ctrl+v Ctrl+x Ctrl+Shift+a Ctrl+Shift+c Ctrl+Shift+v Ctrl+Shift+x}} {error {That shortcut is reserved for standard text/clipboard operations.}}
    return $result
}

proc ::GX::CurveWorkbench::_shortcutCommands {} {
    set result {}
    foreach {id label shortcut requirement handler icon} [_commandRows] {dict set result $id [dict create label $label default $shortcut]}
    foreach {family label shortcut} [_creationRows] {dict set result create.$family [dict create label $label default $shortcut]}
    dict for {group kinds} [_constraintGroups] {
        foreach kind $kinds {
            dict set result constraint.$kind [dict create label [_constraintTitle $kind] default {}]
            if {$group ne "Dimensional"} {dict set result constraint.start.$kind [dict create label "Start [_constraintTitle $kind]" default {}]}
        }
    }
    foreach {id label key} {transform {Transform / pivot} m transform.translate Translate {} transform.rotate Rotate {}} {dict set result $id [dict create label $label default $key]}
    return $result
}
proc ::GX::CurveWorkbench::_shortcutSettingsValidate {overrides} {
    if {[catch {dict size $overrides}]} {error {Shortcut settings must be a command-to-key dictionary}}
    set commands [_shortcutCommands];set used {};set result {}
    foreach id [dict keys $overrides] {if {![dict exists $commands $id]} {error "Unknown shortcut command '$id'"}}
    dict for {id command} $commands {
        set value [_shortcutNormalize [::GX::datasetPublicationV2DictDefault $overrides $id [dict get $command default]]]
        if {$value ne {} && [dict exists $used $value]} {error "Shortcut $value conflicts: [dict get $used $value] and $id. No bindings changed."}
        if {$value ne {}} {dict set used $value $id}
        dict set result $id $value
    }
    return $result
}
proc ::GX::CurveWorkbench::_shortcutSettingsFields {} {
    set fields {}
    dict for {id command} [_shortcutCommands] {dict set fields $id [dict create type string label "[dict get $command label] ($id)" default [dict get $command default]]}
    return $fields
}
