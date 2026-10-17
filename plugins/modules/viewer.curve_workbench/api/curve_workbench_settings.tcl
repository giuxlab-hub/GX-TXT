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
        object.declare_axes {Declare scientific axis meaning…} {} selection {_coordinateDeclareOpen} {}
        object.native_tools {Native point operations / groups…} {} none {_cadDetails} {}
        object.selectable {Include in selection} {} selection {_selectableSet 1} {}
        object.reference {Visible reference only} {} selection {_selectableSet 0} {}
        create.numeric {Exact numeric creation…} {} none {_sketchOpen} {}
        create.scientific {Scientific point curve…} {} none {_coordinateDeclareOpen 1} {}
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
        view.axis_units {Axis display units…} {} none {_coordinateOpen} {}
        view.dataset_coordinates {Dataset coordinates…} {} none {_coordinateDatasetOpen} {}
        view.align_axes {Align Dataset working axes…} {} none {_coordinateAlignOpen} {}
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
    return [::GX::viewerShortcutNormalize $value]
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
    return [::GX::viewerShortcutsValidate viewer.curve_workbench $overrides]
}
proc ::GX::CurveWorkbench::_shortcutSettingsFields {} {
    return [::GX::viewerShortcutFields viewer.curve_workbench]
}
::GX::viewerCommandCatalogRegister viewer.curve_workbench [::GX::CurveWorkbench::_shortcutCommands] modules.curve_workbench.shortcuts
