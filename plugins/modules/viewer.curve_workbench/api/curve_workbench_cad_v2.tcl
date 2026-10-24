# SPDX-License-Identifier: GPL-3.0-or-later
# Native2D is the only geometry/manipulator authority. This controller owns
# logical identities, reviewable workflow and one semantic undo boundary.
proc ::GX::CurveWorkbench::_cadCloseGroups {w} {
    variable st
    set live [::GX::Native2D::core ids $st($w,scene)]
    dict for {id native} $st($w,groupNative) {if {$native in $live} {::GX::Native2D::core delete $st($w,scene) $native}}
    set st($w,groupNative) {}
}
proc ::GX::CurveWorkbench::_cadSyncGroups {w} {
    variable st
    if {[::GX::Native2D::core drag_active $st($w,scene)]} return
    set live [::GX::Native2D::core ids $st($w,scene)]
    dict for {id native} $st($w,groupNative) {
        if {![dict exists $st($w,groups) $id]||$native ni $live} {
            if {$native in $live} {::GX::Native2D::core delete $st($w,scene) $native}
            dict unset st($w,groupNative) $id
        }
    }
    dict for {id group} $st($w,groups) {
        set members {};set nativeMembers {}
        foreach member [dict get $group members] {
            if {[dict exists $st($w,curves) $member]} {lappend members $member;lappend nativeMembers [dict get [_record $w $member] native]}
        }
        if {$members eq {}} {
            dict unset st($w,groups) $id
            if {[dict exists $st($w,groupNative) $id]} {::GX::Native2D::core delete $st($w,scene) [dict get $st($w,groupNative) $id];dict unset st($w,groupNative) $id}
            continue
        }
        dict set st($w,groups) $id members $members
        if {[dict exists $st($w,groupNative) $id]} {
            set native [dict get $st($w,groupNative) $id]
            set oldMembers [::GX::Native2D::core group_members $st($w,scene) $native]
            # Restore owns structural state; temporarily unlock the container
            # while restoring membership, then restore its declared lock.
            ::GX::Native2D::core object_style $st($w,scene) $native {locked 0}
            foreach member $nativeMembers {if {$member ni $oldMembers} {::GX::Native2D::core group_add $st($w,scene) $native $member}}
            foreach member $oldMembers {if {$member ni $nativeMembers} {::GX::Native2D::core group_remove $st($w,scene) $native $member}}
        } else {set native [::GX::Native2D::core group $st($w,scene) $nativeMembers]}
        ::GX::Native2D::core object_style $st($w,scene) $native [dict create locked [dict get $group locked] visible [dict get $group visible]]
        dict set st($w,groupNative) $id $native
    }
    if {$st($w,cadGroup) ne ""&&![dict exists $st($w,groups) $st($w,cadGroup)]} {set st($w,cadGroup) "";set st($w,cadTarget) selected}
}
rename ::GX::CurveWorkbench::_snapshotIds ::GX::CurveWorkbench::_snapshotIds_cad_base
proc ::GX::CurveWorkbench::_snapshotIds {w ids} {
    set result [_snapshotIds_cad_base $w $ids];dict set result @cad [_cadState $w];return $result
}
rename ::GX::CurveWorkbench::_restoreSnapshot ::GX::CurveWorkbench::_restoreSnapshot_cad_base
proc ::GX::CurveWorkbench::_restoreSnapshot {w snapshot} {
    _cadCloseGroups $w
    _restoreSnapshot_cad_base $w [dict remove $snapshot @cad]
    if {[dict exists $snapshot @cad]} {_cadRestoreState $w [dict get $snapshot @cad]} else {_cadSyncGroups $w}
    _selectionScene $w
}
proc ::GX::CurveWorkbench::_cadSelected {w} {
    variable st
    set selected [lmap id $st($w,objectSelection) {if {![dict exists $st($w,curves) $id]} continue;set id}]
    if {$selected eq {}&&$st($w,active) ne ""} {set selected [list [_active $w]]}
    return $selected
}
proc ::GX::CurveWorkbench::_cadTargets {w} {
    variable st
    if {$st($w,cadTarget) eq "group"} {
        if {$st($w,cadGroup) eq ""||![dict exists $st($w,groups) $st($w,cadGroup)]} {error "Select a named group"}
        if {[dict get $st($w,groups) $st($w,cadGroup) locked]} {error "The selected group is locked"}
        set ids [dict get $st($w,groups) $st($w,cadGroup) members];_coordinateRequireFrame $w $ids;return $ids
    }
    set ids [_cadSelected $w];if {$ids eq {}} {error "Select one or more curves"};_coordinateRequireFrame $w $ids;return $ids
}
proc ::GX::CurveWorkbench::_cadSelectNative {w {ids {}}} {
    variable st
    if {[::GX::Native2D::core drag_active $st($w,scene)]} {error "Finish or cancel the native transform gesture before changing object selection"}
    ::GX::Native2D::core clear $st($w,scene)
    if {$ids eq {}} {
        if {$st($w,cadTarget) ne "group"&&$st($w,objectSelection) eq {}} {return}
        set ids [_cadTargets $w]
    }
    foreach id $ids {::GX::Native2D::core object_style $st($w,scene) [dict get [_record $w $id] native] {selected 1}}
    if {$st($w,cadTarget) eq "group"} {::GX::Native2D::core object_style $st($w,scene) [dict get $st($w,groupNative) $st($w,cadGroup)] {selected 1}}
}
proc ::GX::CurveWorkbench::_cadToolChoice {w} {
    variable st
    _cancelGesture $w
    if {$st($w,cadTool) eq "none"} {::GX::Native2D::core gizmo $st($w,scene) {visible 0}} else {
        _cadSelectNative $w
        # An empty selection has no bounds/centroid. Establish a usable pivot
        # in the viewport once; a placed custom pivot survives target changes.
        if {[catch {::GX::Native2D::core pivot $st($w,scene)}]} {
            lassign [::GX::Native2D::core view $st($w,scene)] width height left top right bottom
            ::GX::Native2D::core pivot $st($w,scene) custom [::GX::Native2D::core world $st($w,scene) [list [expr {($left+$width-$right)/2.0}] [expr {($top+$height-$bottom)/2.0}]]]
        }
        set grid [::GX::Native2D::core grid $st($w,scene)]
        ::GX::Native2D::core gizmo $st($w,scene) [dict create visible 1 mode $st($w,cadTool) axes_angle [dict get $grid angle]]
    }
    _draw $w;_save $w
}
proc ::GX::CurveWorkbench::_drawGizmo {w} {
    variable st
        if {[winfo exists $w.right.viewport.canvas]&&[info exists st($w,cadTool)]&&$st($w,cadTool) ne "none"} {
        set background [::GX::uiFieldColorComposite [::GX::uiFieldColorFromRGBA [::GX::Native2D::core background $st($w,scene)]] #FFFFFF]
        ::GX::native2DCanvasDrawGizmo $w.right.viewport.canvas $st($w,scene) [dict get $background rgb]
    }
}
proc ::GX::CurveWorkbench::_cadFreeze {w} {
    set saved {}
    foreach widget [_publicationWidgets $w] {dict set saved $widget [$widget state];$widget state disabled}
    return $saved
}
proc ::GX::CurveWorkbench::_cadThaw {w saved} {
    dict for {widget state} $saved {if {[winfo exists $widget]} {$widget state !disabled;$widget state $state}}
}
proc ::GX::CurveWorkbench::_cadApplyQueuedSelection {w} {
    variable st
    if {![info exists st($w,cadSelectionPending)]||$st($w,cadSelectionPending) eq {}} return
    set selected $st($w,cadSelectionPending);set st($w,cadSelectionPending) {}
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {set st($w,status) "Session lifetime changed; reopen Curve Workbench before changing selection.";return}
    set st($w,objectSelection) $selected
    $w.leftScroll.viewport.content.curves selection set $selected
    _treeSelect $w 1
    if {$st($w,cadTool) ne "none"} {_cadSelectNative $w}
}
proc ::GX::CurveWorkbench::_cadCancel {w} {
    variable st
    if {![info exists st($w,cadDrag)]||$st($w,cadDrag) eq {}} return
    set drag $st($w,cadDrag);set st($w,cadDrag) {}
    [_cadController $w] gesture cancel
    _cadThaw $w [dict get $drag widgets]
    _cadApplyQueuedSelection $w
    set st($w,status) "Native CAD gesture cancelled; exact starting geometry restored."
}
rename ::GX::CurveWorkbench::_cancelGesture ::GX::CurveWorkbench::_cancelGesture_cad_base
proc ::GX::CurveWorkbench::_cancelGesture {w} {_cadCancel $w;_cancelGesture_cad_base $w}
proc ::GX::CurveWorkbench::_cadGestureBegin {w x y state} {
    variable st
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error "Session lifetime changed; reopen Curve Workbench"}
    _cadSelectNative $w
    set handle [::GX::Native2D::core gizmo_hit $st($w,scene) [list $x $y] 5]
    if {$handle eq "none"} {
        set world [::GX::Native2D::core world $st($w,scene) [list $x $y]]
        lassign [::GX::Native2D::core tolerance $st($w,scene) 8] tx ty
        set hit [_hitCurve $w $world [expr {max($tx,$ty)}]]
        if {$hit ne {}} {
            set id [lindex $hit 0]
            switch -- [_selectionMode $state] {
                add {$w.leftScroll.viewport.content.curves selection add $id}
                subtract {$w.leftScroll.viewport.content.curves selection remove $id}
                default {$w.leftScroll.viewport.content.curves selection set $id}
            }
            $w.leftScroll.viewport.content.curves focus $id
        } else {
            set before [_snapshotIds $w {}]
            ::GX::Native2D::core pivot $st($w,scene) custom $world
            _history $w $before {};_draw $w
            set st($w,status) {Pivot placed. Select a curve and use this pivot to transform it.}
        }
        return
    }
    set ids {}
    if {$handle ni {pivot mirror_a mirror_b}} {set ids [_cadTargets $w];_coordinatePlaneAdmit $w $ids}
    if {$handle ni {pivot mirror_a mirror_b}} {
        foreach id $ids {set r [_record $w $id];if {[_bulkRecord $r]||[dict get $r locked]} {error "Unlock the targets or Convert to Native before a CAD drag"}}
    }
    _pointSyncApply $w
    set before [_snapshotIds $w $ids]
    set drag [dict create handle $handle ids $ids before $before active $st($w,active) selected_indices [_selected $w] delta {}]
    [_cadController $w] gesture begin $handle [list $x $y] [lmap id $ids {dict get [_record $w $id] native}]
    dict set drag widgets [_cadFreeze $w];set st($w,cadDrag) $drag;set st($w,cadSelectionPending) {}
}
proc ::GX::CurveWorkbench::_pointerDownTransform {w x y state} {
    variable st
    if {$st($w,publishBusy)} {return 1}
    if {$st($w,cadTool) eq "none"} {return 0}
    _safe $w [list ::GX::CurveWorkbench::_cadGestureBegin $w $x $y $state]

    return 1
}
proc ::GX::CurveWorkbench::_pointerMoveTransform {w x y} {
    variable st
    if {$st($w,cadDrag) eq {}} {return 0}
    if {[catch {_cadGestureMove $w $x $y} message options]} {
        _cadCancel $w
        _draw $w
        _safe $w [list return -options $options $message]
    }

    return 1
}
proc ::GX::CurveWorkbench::_cadGestureMove {w x y} {
    variable st
    set handle [dict get $st($w,cadDrag) handle]
    set delta [[_cadController $w] gesture plan [list $x $y] $st($w,cadObjectSnap)]
    if {[dict exists $delta snap_target]} {
        set candidate [dict get $delta snap_target];set target {}
        dict for {id record} $st($w,curves) {if {[dict get $record native]==[dict get $candidate object]} {set target $id;break}}
        if {$target eq {}} {error {Object snap reference has no logical curve identity}}
        # This scientific-frame admission belongs to the Workbench's explicit
        # X/Y declaration workflow, before CORE applies its native proposal.
        _coordinatePlaneAdmit $w [concat [dict get $st($w,cadDrag) ids] [list $target]]
        dict set delta snap_target [dict merge [dict remove $candidate object] [dict create curve_id $target]]
        set st($w,status) "Object snap: [dict get [_record $w $target] name], original Native point [dict get $candidate index]"
    }
    [_cadController $w] gesture apply
    dict set st($w,cadDrag) delta $delta
    _draw $w
}
proc ::GX::CurveWorkbench::_cadGestureCommit {w} {
    variable st
    set drag $st($w,cadDrag);set handle [dict get $drag handle]
    if {[catch {[_cadController $w] gesture commit} message options]} {_cadCancel $w;_draw $w;return -options $options "Transform rejected: $message. Original geometry restored."}
    set st($w,cadDrag) {};_cadThaw $w [dict get $drag widgets]
    if {$handle in {pivot mirror_a mirror_b}} {
        _history $w [dict get $drag before] [dict get $drag ids]
        _cadApplyQueuedSelection $w
        _draw $w
        set st($w,status) "Native $handle updated as one undoable action."
        return
    }
    set ids [dict get $drag ids];foreach logical [dict keys [dict get $drag before]] {if {[dict exists $st($w,curves) $logical]&&[dict exists [_record $w $logical] sketch_definition]&&$logical ni $ids} {lappend ids $logical}};set changed 0
    foreach id $ids {_syncSamples $w $id;if {[dict get [_record $w $id] samples] ne [dict get $drag before $id samples]} {set changed 1}}
    if {$changed} {
        set operation [dict create operation gizmo_$handle api_id NATIVE2D_API_v1 targets $ids parameters [dict get $drag delta] lifecycle absolute_native_drag]
        foreach id $ids {set r [_record $w $id];dict lappend r operations $operation;dict set st($w,curves) $id $r}
        _selectionScene $w
        if {$st($w,active) eq [dict get $drag active]} {::GX::Native2D::core selection_replace $st($w,selectionScene) $st($w,selectionObject) [dict get $drag selected_indices]}
        _history $w [dict get $drag before] $ids
    } else {_pointList $w;_draw $w}
    _cadApplyQueuedSelection $w
    _draw $w
    set st($w,status) "Native CAD gesture committed as one action."
}
proc ::GX::CurveWorkbench::_pointerUpTransform {w x y} {
    variable st
    if {$st($w,cadDrag) eq {}} {return 0}
    _safe $w [list ::GX::CurveWorkbench::_cadGestureCommit $w]

    return 1
}
proc ::GX::CurveWorkbench::_cadGroupChoice {w} {
    variable st
    if {[dict exists $st($w,cadGroupMap) $st($w,cadGroupLabel)]} {set st($w,cadGroup) [dict get $st($w,cadGroupMap) $st($w,cadGroupLabel)]}
}
proc ::GX::CurveWorkbench::_cadGroupAction {w action} {
    variable st
    set before [_snapshotIds $w {}]
    if {$action eq "create"} {
        set members [_cadSelected $w];if {$members eq {}} {error "Select curves to group"}
        set name [string trim $st($w,cadGroupName)];if {$name eq ""} {error "Enter a group name"}
        set id "group[incr st($w,nextGroup)]"
        dict set st($w,groups) $id [dict create name $name members $members visible 1 locked 0]
        set st($w,cadGroup) $id;set st($w,cadTarget) group
    } else {
        set id $st($w,cadGroup)
        if {$id eq ""||![dict exists $st($w,groups) $id]} {error "Choose a named group"}
        if {[dict get $st($w,groups) $id locked]} {error "Unlock the group before changing membership"}
        switch -- $action {
            ungroup {dict unset st($w,groups) $id;set st($w,cadGroup) "";set st($w,cadTarget) selected}
            add {
                set members [dict get $st($w,groups) $id members]
                foreach member [_cadSelected $w] {if {$member ni $members} {lappend members $member}}
                dict set st($w,groups) $id members $members
            }
            remove {
                set selected [_cadSelected $w];set members [lmap member [dict get $st($w,groups) $id members] {if {$member in $selected} continue;set member}]
                if {$members eq {}} {dict unset st($w,groups) $id;set st($w,cadGroup) "";set st($w,cadTarget) selected} else {dict set st($w,groups) $id members $members}
            }
            default {error "Unknown group action"}
        }
    }
    _cadSyncGroups $w;_history $w $before {}
}
proc ::GX::CurveWorkbench::_cadUnits {w ids} {
    set common __unset__
    foreach id $ids {
        set units [_coordinateUnits [_record $w $id]]
        if {[lindex $units 0] ne [lindex $units 1]||($common ne "__unset__"&&$common ne [lindex $units 0])} {error "Metric CAD operations require equal native X/Y units and equal units across targets; normalize explicitly with Dataset Transform / Unit Registry."}
        set common [lindex $units 0]
    }
    if {$common ni {__unset__ ""}} {::GX::unitRegistryHomogeneousCoordinatePlan $common $common}
    return [expr {$common in {__unset__ ""} ? "coordinate units (unspecified)" : $common}]
}
proc ::GX::CurveWorkbench::_cadTransformOpen {w kind} {
    variable st
    set ids [_cadTargets $w];_cadTransformUnits $w $kind $ids
    set basis [lindex $ids 0];set xUnit [dict get [_coordinateAxis $w $basis x] display_unit];set yUnit [dict get [_coordinateAxis $w $basis y] display_unit]
    _cadSelectNative $w $ids
    set pivot [dict get [::GX::Native2D::core pivot $st($w,scene)] point]
    switch -- $kind {
        translate {set fields [dict create dx [dict create type number label "X displacement ($xUnit)"] dy [dict create type number label "Y displacement ($yUnit)"]];foreach axis {x y} {_coordinateControlPlan $w $basis $axis inverse};set initial {dx 1 dy 0}}
        rotate {set fields [dict create degrees [dict create type number label {Numeric plane rotation (degrees)}]];set initial {degrees 90}}
        scale {set fields [dict create sx [dict create type number label {Coordinate scale X (dimensionless)} min 1e-12] sy [dict create type number label {Coordinate scale Y (dimensionless)} min 1e-12]];set initial {sx 1 sy 1}}
        mirror {
            set fields [dict create ax [dict create type number label "Axis point A: X ($xUnit)"] ay [dict create type number label "Axis point A: Y ($yUnit)"] bx [dict create type number label "Axis point B: X ($xUnit)"] by [dict create type number label "Axis point B: Y ($yUnit)"]]
            set gizmo [::GX::Native2D::core gizmo $st($w,scene)]
            lassign [_coordinatePoint $w $basis [dict get $gizmo mirror_a]] ax ay
            lassign [_coordinatePoint $w $basis [dict get $gizmo mirror_b]] bx by
            set initial [dict create ax $ax ay $ay bx $bx by $by]
        }
        default {error "Unknown CAD transform"}
    }
    ::GX::uiFieldFormCreate $w.cadTransform "$kind — [llength $ids] curve(s) — X $xUnit / Y $yUnit" $fields $initial [list ::GX::CurveWorkbench::_cadTransformDisplayedApply $w $kind $ids $pivot [_coordinateControlKey $w $ids]] $w
}
proc ::GX::CurveWorkbench::_cadTransformApply {w kind ids pivot values} {
    if {![_timelineEditable $w]} return
    variable st
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error "Session lifetime changed; reopen Curve Workbench"}
    if {$ids ne [_cadTargets $w]} {error "Transform targets changed; reopen the action form"}
    foreach id $ids {
        set r [_record $w $id]
        if {[_bulkRecord $r]} {error "Use Convert to Native to transform an explicit editable exact range of a large Dataset source"}
        if {$kind ne "mirror"&&[dict get $r locked]} {error "A target is locked; the complete transform was rejected"}
    }
    _cadTransformUnits $w $kind $ids;_cadSelectNative $w $ids
    _pointSyncApply $w
    set selectedIndices [_selected $w];set previousActive $st($w,active)
    set before [_snapshotIds $w $ids];set nativeIds [lmap id $ids {dict get [_record $w $id] native}]
    set created {};set resultIds $ids
    switch -- $kind {
        translate {set matrix [list 1 0 0 1 [dict get $values dx] [dict get $values dy]]}
        rotate {set matrix [::GX::Native2D::core rotation_matrix_degrees $st($w,scene) $pivot [dict get $values degrees]]}
        scale {set matrix [::GX::Native2D::core scaling_matrix $st($w,scene) $pivot [list [dict get $values sx] [dict get $values sy]]]}
        mirror {set matrix [::GX::Native2D::core reflection_matrix $st($w,scene) [list [dict get $values ax] [dict get $values ay]] [list [dict get $values bx] [dict get $values by]]]}
    }
    set operation [dict create operation $kind api_id NATIVE2D_API_v1 targets $ids matrix $matrix pivot $pivot parameters $values]
    if {$kind eq "mirror"} {
        set result [::GX::Native2D::core affine $st($w,scene) $nativeIds $matrix 1]
        set nativeCopies [dict get $result object_ids];set resultIds {};set before [_snapshotIds $w {}]
        try {
            foreach source $ids native $nativeCopies {
                set original [_record $w $source]
                set derived [_newRecord $w "[dict get $original name] mirror" [dict get $original samples] [dict get $original source] [dict get $original x] [dict get $original y] [dict get $original filter] [dict get $original filter_value] [dict get $original family] [dict get $original order] [list $source] [list [dict merge $operation [dict create copy_policy editable_result originals_preserved 1]]] [dict get $original representation]]
                set id [dict get $derived id];dict set before $id ""
                dict set derived visible [dict get $original visible];dict set derived breaks [dict get $original breaks]
                dict set derived direction [::GX::Native2D::core direction_marker $st($w,scene) $native]
                foreach field {source_descriptor working_unit attributes} {if {[dict exists $original $field]} {dict set derived $field [dict get $original $field]}}
                _addRecord $w $derived $native;lappend created $id;lappend resultIds $id;_syncSamples $w $id
            }
        } on error {message options} {
            foreach id $created {_removeRecord $w $id}
            set live [::GX::Native2D::core ids $st($w,scene)]
            foreach native $nativeCopies {if {$native in $live} {::GX::Native2D::core delete $st($w,scene) $native}}
            return -options $options $message
        }
        set st($w,active) [lindex $resultIds 0];set st($w,objectSelection) $resultIds;set st($w,cadTarget) selected
        set members {};foreach resultId $resultIds {lappend members [dict create kind object id [dict get [_record $w $resultId] native] index 0]};_semanticApply $w $members
    } else {
        if {$kind eq "translate"} {::GX::Native2D::core translate $st($w,scene) [dict get $values dx] [dict get $values dy]} elseif {$kind eq "rotate"} {::GX::Native2D::core rotate_degrees $st($w,scene) $pivot [dict get $values degrees]} else {::GX::Native2D::core affine $st($w,scene) $nativeIds $matrix}
        foreach id $ids {_syncSamples $w $id;set r [_record $w $id];dict lappend r operations $operation;dict set st($w,curves) $id $r}
    }
    _selectionScene $w
    if {$kind ne "mirror"&&$previousActive eq $st($w,active)} {
        ::GX::Native2D::core selection_replace $st($w,selectionScene) $st($w,selectionObject) $selectedIndices
    }
    _history $w $before $resultIds
    set st($w,status) "$kind committed for [llength $resultIds] curve(s) as one undoable action; source Datasets remain unchanged."
    return $resultIds
}
proc ::GX::CurveWorkbench::_cadPivotOpen {w} {
    variable st
    set ids [_cadTargets $w];_cadSelectNative $w $ids;set pivot [::GX::Native2D::core pivot $st($w,scene)]
    set p [dict get $pivot point];if {$p eq {}} {set p {0 0}}
    set ids [_cadTargets $w];set basis [lindex $ids 0]
    set p [_coordinatePoint $w $basis $p]
    set xUnit [dict get [_coordinateAxis $w $basis x] display_unit];set yUnit [dict get [_coordinateAxis $w $basis y] display_unit]
    set fields [dict create mode [dict create type choice label {Pivot policy} values {bounds centroid origin custom}] x [dict create type number label "Custom pivot X ($xUnit)"] y [dict create type number label "Custom pivot Y ($yUnit)"]]
    ::GX::uiFieldFormCreate $w.cadPivot "Native2D transform pivot" $fields [dict create mode [dict get $pivot mode] x [lindex $p 0] y [lindex $p 1]] [list ::GX::CurveWorkbench::_cadPivotDisplayedApply $w $ids [_coordinateControlKey $w $ids]] $w
}
proc ::GX::CurveWorkbench::_cadPivotApply {w values} {
    variable st
    set before [_snapshotIds $w {}]
    if {[dict get $values mode] eq "custom"} {::GX::Native2D::core pivot $st($w,scene) custom [list [dict get $values x] [dict get $values y]]} else {::GX::Native2D::core pivot $st($w,scene) [dict get $values mode]}
    _history $w $before {}
}
proc ::GX::CurveWorkbench::_buildCad {w} {
    variable st
    foreach capability {gizmo_snap_translation gizmo rotation_transaction pivot flat_group_lifecycle affine_objects copy_reflect} {
        if {$capability ni [dict get [::GX::Native2D::core api_info] capabilities]} {error "Native2D CORE requires $capability; restart with the candidate adapter"}
    }
    set st($w,cadGroupMap) {};set st($w,cadGroupLabel) ""
    ttk::frame $w.cad -padding 4
    pack $w.cad -side top -fill x -before $w.main
    ttk::label $w.cad.label -text "CAD target"
    ttk::combobox $w.cad.target -state readonly -values {selected group} -width 8 -textvariable ::GX::CurveWorkbench::st($w,cadTarget)
    ttk::combobox $w.cad.group -state readonly -width 20 -textvariable ::GX::CurveWorkbench::st($w,cadGroupLabel)
    bind $w.cad.group <<ComboboxSelected>> [list ::GX::CurveWorkbench::_cadGroupChoice $w]
    ttk::entry $w.cad.name -width 12 -textvariable ::GX::CurveWorkbench::st($w,cadGroupName)
    foreach {key text action} {create {Group selected} create ungroup Ungroup ungroup add {Add members} add remove {Remove members} remove} {
        ttk::button $w.cad.$key -text $text -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_cadGroupAction $w $action]]
    }
    foreach key {label target group name create ungroup add remove} {pack $w.cad.$key -side left -padx 3}
    foreach {key text kind} {translate Move… translate rotate Rotate… rotate scale {Physical scale…} scale mirror {Mirror copy…} mirror} {
        ttk::button $w.cad.$key -text $text -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_cadTransformOpen $w $kind]]
        pack $w.cad.$key -side left -padx 3
    }
    ttk::button $w.cad.pivot -text "Pivot…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_cadPivotOpen $w]]
    pack $w.cad.pivot -side left -padx 3
    ttk::label $w.cad.toolLabel -text Gizmo
    ttk::combobox $w.cad.tool -state readonly -values {none translate rotate mirror} -width 9 -textvariable ::GX::CurveWorkbench::st($w,cadTool)
    pack $w.cad.toolLabel $w.cad.tool -side left -padx 3
    bind $w.cad.tool <<ComboboxSelected>> [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_cadToolChoice $w]]
    ttk::checkbutton $w.cad.objectSnap -text "Object snap (8 px)" -variable ::GX::CurveWorkbench::st($w,cadObjectSnap)
    pack $w.cad.objectSnap -side left -padx 3
    bind $w.cad <Configure> [list ::GX::native2DToolbarLayout $w.cad %w]
}
