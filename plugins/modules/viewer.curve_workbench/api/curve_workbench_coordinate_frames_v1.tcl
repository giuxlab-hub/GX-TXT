# SPDX-License-Identifier: GPL-3.0-or-later
# Native working frames are Workspace state. Canonical Dataset bindings remain
# immutable, and CORE owns every physical conversion and affine operation.
proc ::GX::CurveWorkbench::_coordinateSourceRelations {record} {
    if {![dict exists $record source_descriptor]} {return {}}
    return [::GX::native2DSourceCoordinateRelations [dict get $record source_descriptor] [dict get $record x] [dict get $record y]]
}
proc ::GX::CurveWorkbench::_coordinateFrameKey {record} {
    return [list [_coordinateUnits $record] [_coordinateSourceRelations $record]]
}
proc ::GX::CurveWorkbench::_coordinateInFrame {w record} {
    variable st
    if {$st($w,active) eq {}||![dict exists $st($w,curves) $st($w,active)]} {return 1}
    return [expr {[_coordinateFrameKey $record] eq [_coordinateFrameKey [_record $w $st($w,active)]]}]
}
proc ::GX::CurveWorkbench::_coordinateRequireFrame {w ids} {
    foreach id $ids {if {![_coordinateInFrame $w [_record $w $id]]} {error {The selection spans different coordinate frames; select one frame or explicitly align compatible Dataset axes first}}}
}
proc ::GX::CurveWorkbench::_coordinateSourceFrame {w record} {
    variable st
    set units [_coordinateUnits $record]
    if {[_coordinateSourceRelations $record] ne {}||{} in $units} {return $units}
    # Existing compatible frames take precedence. No existing curve is changed.
    dict for {id candidate} $st($w,curves) {
        if {[_coordinateSourceRelations $candidate] ne {}} continue
        set target [_coordinateUnits $candidate]
        if {{} in $target} continue
        if {![catch {::GX::native2DComparisonFrame x $units $units [dict create output_units $target]}]} {return $target}
    }
    # A new physical geometric frame uses one numeric unit on both axes.
    if {![catch {set plan [::GX::native2DComparisonFrame path $units $units]}]} {return [dict get $plan output_units]}
    return $units
}
proc ::GX::CurveWorkbench::_coordinateNormalizeSource {w id target} {
    variable st
    set record [_record $w $id];set source [_coordinateUnits $record]
    if {$source eq $target} {return {}}
    if {[dict get $record source] eq {}||[dict get $record edited]} {error {Axis alignment requires an untouched Dataset binding}}
    if {[_coordinateSourceRelations $record] ne {}} {error {Variable-specific coordinate relations require explicit Dataset Transform normalization before frame alignment}}
    set plan [::GX::native2DComparisonFrame x $source $source [dict create output_units $target]]
    set matrix [dict get $plan reference_matrix];set native [dict get $record native]
    set locked [dict get $record locked]
    ::GX::Native2D::core locked $st($w,scene) $native 0
    try {
        lassign $matrix a b c d tx ty
        if {$a!=1||$b!=0||$c!=0||$d!=1||$tx!=0||$ty!=0} {::GX::Native2D::core affine $st($w,scene) [list $native] $matrix 0}
    } finally {::GX::Native2D::core locked $st($w,scene) $native $locked}
    if {[_bulkRecord $record]} {
        dict set record geometry_resource [::GX::interactiveDocumentNative2DStore $st($w,document) $st($w,scene) $native]
    } else {
        _syncSamples $w $id;set record [_record $w $id];dict set record edited 0
    }
    dict unset record working_unit
    dict set record coordinate_units $target
    dict lappend record coordinate_conversions [dict create schema_version 1 operation align_dataset_axes source_units $source target_units $target matrix $matrix source_dataset_modified 0]
    dict set st($w,curves) $id $record
    dict unset st($w,coordinateCache) $id
    return $plan
}
proc ::GX::CurveWorkbench::_coordinateFrameSync {w {restoreView 1}} {
    variable st
    if {$st($w,active) eq {}||![dict exists $st($w,curves) $st($w,active)]} {return 0}
    set key [_coordinateFrameKey [_record $w $st($w,active)]]
    set previous {};if {[info exists st($w,coordinateFrameKey)]} {set previous $st($w,coordinateFrameKey)}
    set changed [expr {$previous ne $key}]
    if {$changed&&$previous ne {}} {
        dict set st($w,coordinateFrameViews) $previous [dict create view [::GX::Native2D::core view_requested $st($w,scene)] presentation [::GX::Native2D::core presentation $st($w,scene)] coordinate_view $st($w,coordinateView)]
    }
    set st($w,coordinateFrameKey) $key
    dict for {id record} $st($w,curves) {
        set visible [expr {[dict get $record visible]&&[_coordinateInFrame $w $record]}]
        ::GX::Native2D::core visible $st($w,scene) [dict get $record native] $visible
    }
    if {$restoreView&&$changed&&$previous ne {}} {
        if {[dict exists $st($w,coordinateFrameViews) $key]} {
            set saved [dict get $st($w,coordinateFrameViews) $key]
            ::GX::Native2D::core presentation $st($w,scene) [dict get $saved presentation]
            ::GX::Native2D::core view $st($w,scene) [dict get $saved view]
            set st($w,coordinateView) [dict get $saved coordinate_view]
            _coordinateMagnify $w 0
        } else {
            ::GX::Native2D::core fit $st($w,scene)
            _coordinateMagnify $w 1
        }
    }
    return $changed
}
proc ::GX::CurveWorkbench::_coordinateAlignOpen {w} {
    variable st
    set id [_active $w];set record [_record $w $id]
    if {[dict get $record source] eq {}||[dict get $record edited]} {error {Select an untouched Dataset source to align its working axes}}
    if {[_coordinateSourceRelations $record] ne {}} {error {Normalize variable-specific relations through Dataset Transform first}}
    set fields {};set values {}
    foreach axis {x y} unit [_coordinateUnits $record] {
        if {$unit eq {}} {error {Declare missing units through Dataset Variables before aligning this source}}
        set choices [list $unit]
        foreach candidate [::GX::unitSelectorCandidates] {
            if {![catch {set plan [::GX::unitRegistryAffinePlan $unit $candidate]}]&&[dict get $plan affine]&&[dict get $plan scale]>0} {lappend choices $candidate}
        }
        dict set fields $axis [dict create type choice label "[string toupper $axis] Native working unit" values [lsort -unique $choices]]
        dict set values $axis $unit
    }
    set st($w,coordinateAlignKey) [_coordinateKey $w $id]
    ::GX::uiFieldFormCreate $w.alignaxes {Align Dataset working axes} $fields $values [list ::GX::CurveWorkbench::_coordinateAlignApply $w $st($w,token) $id] $w
    ttk::label $w.alignaxes.note -text {This converts the Workspace's Native coordinates and records the frame. Original Dataset values, units and IDs remain unchanged. Matching working axes can share a viewport. Display units and calibration remain separate.} -wraplength 580
    pack $w.alignaxes.note -side top -fill x -before $w.alignaxes.viewport -padx 10 -pady 8
}
proc ::GX::CurveWorkbench::_coordinateAlignApply {w token id values} {
    variable st
    if {$token ne [::GX::interactiveDocumentSessionToken]||$token ne $st($w,token)||$id ne $st($w,active)||$st($w,coordinateAlignKey) ne [_coordinateKey $w $id]} {error {Source or coordinate context changed; reopen axis alignment}}
    set before [_snapshotIds $w [list $id]];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    try {
        _coordinateNormalizeSource $w $id [list [dict get $values x] [dict get $values y]]
        _coordinateFrameSync $w 0
        _selectionScene $w;::GX::Native2D::core fit $st($w,scene);_coordinateMagnify $w 1
        _history $w $before [list $id]
    } on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    set st($w,coordinateAlignKey) [_coordinateKey $w $id]
    _curveList $w;_pointList $w;_draw $w;_save $w
}
