# SPDX-License-Identifier: GPL-3.0-or-later
# Interaction/presentation only. Native2D owns placements, reference sharing,
# closure, retained creation and persistent rules; existing history owns Undo.
proc ::GX::CurveWorkbench::_installCommandLayout {w} {
    
    _commandLayout $w [winfo width $w.toolbar]
    ::GX::native2DToolbarLayout $w.publish [winfo width $w.publish]

}
proc ::GX::CurveWorkbench::_buildCommandMenus {w} {
    variable st
    foreach group {objects points view} title {Objects {Points / ranges} View} {
        ttk::menubutton $w.toolbar.$group -text $title -menu $w.toolbar.$group.menu
        menu $w.toolbar.$group.menu -tearoff 0
    }
    foreach key {duplicate split reverse visibility lock remove} {
        $w.toolbar.objects.menu add command -label [$w.toolbar.$key cget -text] -command [$w.toolbar.$key cget -command]
    }
    foreach key {keep remove before after delete spline linear fragment earlier later snap convert} {
        $w.toolbar.points.menu add command -label [$w.editbar.$key cget -text] -command [$w.editbar.$key cget -command]
    }
    $w.toolbar.objects.menu add separator
    foreach {label visible} {Show 1 Hide 0} {$w.toolbar.objects.menu add command -label $label -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_setVisibility $w $visible]]}
    foreach {label mode} {Select select {Insert Native point} add Pan pan} {$w.toolbar.view.menu add command -label $label -command [list ::GX::CurveWorkbench::_scienceTool $w $mode]}
    $w.toolbar.view.menu add command -label {Fit all} -command [$w.toolbar.fit cget -command]
    $w.toolbar.view.menu add command -label {Fit active} -command [$w.toolbar.fitSelected cget -command]
    foreach {label id} {{Axis display units…} view.axis_units {Dataset coordinates…} view.dataset_coordinates {Align Dataset working axes…} view.align_axes} {
        $w.toolbar.view.menu add command -label $label -command [list ::GX::CurveWorkbench::_commandInvoke $w $id]
    }
    $w.toolbar.view.menu add command -label {Source Dataset Preview…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_sourcePreviewActive $w]]
    $w.toolbar.view.menu add command -label {More scientific controls} -command [list ::GX::CurveWorkbench::_moreControls $w]
    foreach child [winfo children $w.toolbar] {pack forget $child;grid forget $child}
    bind $w.toolbar <Configure> [list ::GX::CurveWorkbench::_commandLayout $w %w]
    pack forget $w.editbar
    bind $w.sketchbar <Configure> [list ::GX::CurveWorkbench::_sketchBarLayout $w %w]
    $w.sketchbar.finish configure -command [list ::GX::CurveWorkbench::_constructionFinish $w]
    bind $w.right.viewport.canvas <Return> [list ::GX::CurveWorkbench::_constructionFinish $w]
    bind $w.right.viewport.canvas <space> [list ::GX::CurveWorkbench::_constructionFinish $w]
    ttk::menubutton $w.publish.batch -text {Publish selection…} -menu $w.publish.batch.menu
    menu $w.publish.batch.menu -tearoff 0
    $w.publish.batch.menu add command -label {One structured Dataset} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_publishSelectionStructured $w]]
    $w.publish.batch.menu add command -label {Separate Dataset outputs…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_publishBatchOpen $w]]
    pack $w.publish.batch -side left -padx 3 -before $w.publish.save
    foreach child [winfo children $w.publish] {pack forget $child}
    bind $w.publish <Configure> [list ::GX::native2DToolbarLayout $w.publish %w]
    ::GX::native2DToolbarLayout $w.publish [winfo width $w.publish]
    _commandLayout $w [winfo width $w.toolbar]
    _sketchBarLayout $w [winfo width $w.sketchbar]
}
proc ::GX::CurveWorkbench::_scienceTool {w mode} {variable st;_sketchIdle $w;set st($w,tool) $mode;set st($w,toolLabel) "[string totitle $mode] — scientific point interaction. Esc returns to Select."}
proc ::GX::CurveWorkbench::_moreControls {w} {
    variable st;set st($w,moreControls) [expr {!$st($w,moreControls)}]
    if {$st($w,moreControls)} {pack $w.editbar -side top -fill x -before $w.sketchbar} else {pack forget $w.editbar}
    _commandLayout $w [winfo width $w.toolbar]
}
proc ::GX::CurveWorkbench::_commandLayout {w width} {
    variable st;if {![winfo exists $w.toolbar.objects]} return
    set children {};foreach key {add fit fitSelected undo redo objects points view} {lappend children $w.toolbar.$key}
    if {$st($w,moreControls)} {foreach key {duplicate split reverse visibility lock remove select insert pan sourcePreview} {if {[winfo exists $w.toolbar.$key]} {lappend children $w.toolbar.$key}}}
    foreach child [winfo children $w.toolbar] {if {$child ni $children} {pack forget $child;grid forget $child}}
    ::GX::native2DToolbarLayout $w.toolbar $width $children
}
proc ::GX::CurveWorkbench::_sketchBarLayout {w width} {
    variable st
    if {![winfo exists $w.sketchbar.feedback]} return
    set children {};foreach key {create modify constraints represent unitLabel unit snap dimension parameters palette finish} {lappend children $w.sketchbar.$key}
    pack forget $w.sketchbar.select
    grid forget $w.sketchbar.select
    # Only this completed grid layout owns feedback; never pack it here.
    pack forget $w.sketchbar.feedback
    grid forget $w.sketchbar.feedback
    ::GX::native2DToolbarLayout $w.sketchbar $width $children
    # The shared tool readout already carries this instruction beside live
    # coordinates. Leave the legacy row unmapped for every construction tool.

}
proc ::GX::CurveWorkbench::_constraintMenu {w} {
    set menu $w.sketchbar.constraints.menu;$menu delete 0 end
    foreach child [winfo children $menu] {destroy $child}
    dict for {label kinds} [_constraintGroups] {
        set child $menu.[string tolower $label];menu $child -tearoff 0
        $menu add cascade -label $label -menu $child
        set ids [lmap kind $kinds {format constraint.%s $kind}]
        if {$label eq "Fixing"} {lappend ids constraint.unfix}
        _commandMenu $w $child $ids
    }
    set tools $menu.tools;menu $tools -tearoff 0;$menu add cascade -label {Start constraint tool} -menu $tools
    dict for {label kinds} [_constraintGroups] {
        if {$label eq "Dimensional"} continue
        set child $tools.[string tolower $label];menu $child -tearoff 0;$tools add cascade -label $label -menu $child
        _commandMenu $w $child [lmap kind $kinds {format constraint.start.%s $kind}]
    }
    $menu add separator
    foreach id {constraint.inspector constraint.advanced} {
        variable st
        $menu add command -label [dict get $st($w,commands) $id label] -accelerator [dict get $st($w,commands) $id shortcut] -command [list ::GX::CurveWorkbench::_commandInvoke $w $id]
    }
}

rename ::GX::CurveWorkbench::_sketchIdle ::GX::CurveWorkbench::_sketchIdle_interaction055_base
proc ::GX::CurveWorkbench::_sketchIdle {w {message {Select — geometry, handles, constraints or dimensions.}}} {
    variable st;set st($w,constructionPlaces) {};set st($w,chainReferences) {}
    _sketchIdle_interaction055_base $w $message
}
rename ::GX::CurveWorkbench::_sketchTool ::GX::CurveWorkbench::_sketchTool_interaction055_base
proc ::GX::CurveWorkbench::_sketchTool {w family} {
    variable st
    _sketchTool_interaction055_base $w $family
    set st($w,constructionPlaces) {};set st($w,chainReferences) {}
    if {$family eq "line"} {set st($w,toolLabel) {Line — click start, then successive endpoints. Each segment is independent and connected. Esc / Finish stops.}}
}
proc ::GX::CurveWorkbench::_constructionPlacement {w x y} {
    variable st;set excluded {};if {$st($w,toolPreview) ne {}} {lappend excluded $st($w,toolPreview)}
    set placement [::GX::Native2D::core construction_pick $st($w,scene) [list $x $y] 9 $st($w,constructionPlaces) $excluded 1]
    set kind [expr {[dict exists $placement reference]?"attach geometry":[dict exists $placement earlier]?"close / share placed point":"none"}]
    set st($w,snapCandidate) [dict create point [dict get $placement point] kind $kind]
    return $placement
}
# A cursor endpoint at the last placed point may create a degenerate segment.
# Keep the valid placed prefix visible; both paths use Native construction.
proc ::GX::CurveWorkbench::_constructionPreview {w {candidate {}}} {
    variable st
    set places $st($w,constructionPlaces)
    if {$places eq {}} return
    if {$candidate ne {}&&!([dict exists $candidate earlier]&&[dict get $candidate earlier]==[llength $places]-1)} {
        if {![catch {set definition [::GX::Native2D::core construction_preview $st($w,scene) $st($w,canvasTool) [concat $places [list $candidate]]]}]} {
            _toolPreview $w $definition;return
        }
    }
    if {[catch {set definition [::GX::Native2D::core construction_preview $st($w,scene) $st($w,canvasTool) $places]}]} {
        _toolPreviewClear $w
    } else {_toolPreview $w $definition}
}
rename ::GX::CurveWorkbench::_coordinates ::GX::CurveWorkbench::_coordinates_interaction055_base
proc ::GX::CurveWorkbench::_coordinates {w x y} {
    variable st
    if {$st($w,canvasTool) eq "select"} {_pointerMovePart $w $x $y;tailcall _coordinates_interaction055_base $w $x $y}
    if {$st($w,publishBusy)} return
    set st($w,coordinates) [_coordinateReadout $w [list $x $y]]
    set candidate [_constructionPlacement $w $x $y]
    _constructionPreview $w $candidate
    _draw $w
}
proc ::GX::CurveWorkbench::_pointerDownConstruction {w x y state} {
    variable st
    if {$st($w,canvasTool) eq "select"} {return 0}
    if {$st($w,publishBusy)} {return 1}
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {_sketchIdle $w {Session changed — reopen Workbench.};return 1}
    lassign [::GX::Native2D::core view $st($w,scene)] width height left top right bottom
    if {$x<$left||$y<$top||$x>$width-$right||$y>$height-$bottom} {return 1}
    set placement [_constructionPlacement $w $x $y]
    if {$st($w,canvasTool) eq "line"&&[llength $st($w,constructionPlaces)]==1&&[dict exists $placement earlier]&&[dict get $placement earlier]==0} {_constructionFinish $w;return 1}
    lappend st($w,constructionPlaces) $placement
    set st($w,placements) [::GX::Native2D::core construction_points $st($w,scene) $st($w,constructionPlaces)]
    set required [_createCount $st($w,canvasTool)]
    # Every variable-length retained construction uses the same native attachment
    # receipt, including Spline endpoints/interiors. Finish the transaction, not
    # the creation tool; the next click starts another independent primitive.
    set attachedEnd [expr {$st($w,canvasTool) in {path polyline spline}&&[dict exists $placement reference]&&[llength $st($w,constructionPlaces)]>=2}]
    if {$attachedEnd||($required&&[llength $st($w,constructionPlaces)]==$required)||(!$required&&[dict exists $placement earlier]&&[dict get $placement earlier]==0&&[llength $st($w,constructionPlaces)]>=3)} {_createCommit $w} else {_constructionPreview $w;_draw $w}

    return 1
}
proc ::GX::CurveWorkbench::_createCommit {w} {
    variable st
    if {$st($w,canvasTool) eq "select"||$st($w,constructionPlaces) eq {}} return
    set family $st($w,canvasTool);set needed [_createCount $family]
    if {($needed&&[llength $st($w,constructionPlaces)]!=$needed)||(!$needed&&[llength $st($w,constructionPlaces)]<2)} {_notice $w {Place the remaining defining controls, or Esc to cancel.};return}
    set unit $st($w,sketchUnit)
    set placements $st($w,constructionPlaces);set chain $st($w,chainReferences)
    set parents {};dict for {id r} $st($w,curves) {foreach p $placements {if {[dict exists $p reference]&&[dict get $p reference object]==[dict get $r native]} {lappend parents $id}}}
    set before [_snapshotIds $w [lsort -unique $parents]];set oldUndo $st($w,undo);set oldRedo $st($w,redo);set native {};set joined 0
    _toolPreviewClear $w
    try {
        ::GX::unitRegistryHomogeneousCoordinatePlan $unit $unit
        if {$parents ne {}&&[_cadUnits $w [lsort -unique $parents]] ne $unit} {error {Construction attachment requires the same declared working units. Normalize the workspace through Unit Registry before joining geometry.}}
        set symmetry {}
        if {[info exists st($w,symmetryEnabled)]&&$st($w,symmetryEnabled)} {
            set axis [_record $w $st($w,symmetryAxis)]
            if {[lindex [_coordinateUnits $axis] 0] ne $unit} {error {Symmetry axis and new geometry require the same working unit}}
            set symmetry [list [::GX::Native2D::core interaction_reference $st($w,scene) [dict get $axis native] segment 0]]
        }
        dict for {image record} $st($w,images) {
            foreach placement $placements {
                if {[dict exists $placement reference]&&[dict get $placement reference object]==[dict get $record native]&&[dict get [::GX::Native2D::core image_get $st($w,scene) [dict get $record native]] length_unit] ne $unit} {error {Image reference attachment requires the same declared working unit}}
            }
        }
        set receipt [::GX::Native2D::core construction_create $st($w,scene) $family $placements 257 $chain {*}$symmetry]
        set native [dict get $receipt id]
        set operation [dict create operation attached_canvas_construction family $family authority Native2D closed [dict get $receipt closed] periodic 0]
        set record [_newRecord $w "[string totitle [string map {_ { }} $family]] [expr {[dict size $st($w,curves)]+1}]" [_sketchSamples $w $native] {} x y {} {} {} {} [lsort -unique $parents] [list $operation]]
        dict set record working_unit $unit;dict set record conversion_provenance $operation
        dict set record materialization_sampling [dict create method uniform_parameter first 0 last 1 total [::GX::Native2D::core count $st($w,scene) $native] geometry_authority retained_sketch]
        set id [dict get $record id];dict set before $id {};_addRecord $w $record $native
        set resultIds [list $id]
        if {[dict exists $receipt mirror_id]} {
            set mirror [dict get $receipt mirror_id]
            set mirrored [_newRecord $w "Mirror — [dict get $record name]" [_sketchSamples $w $mirror] {} x y {} {} {} {} [list $id] [list [dict create operation symmetric_construction]]]
            dict set mirrored working_unit $unit
            set mirroredId [dict get $mirrored id];dict set before $mirroredId {};_addRecord $w $mirrored $mirror;lappend resultIds $mirroredId
        }
        set reverse [_logicalNativeMap $w]
        foreach relationship [dict get $receipt relationships] {
            set logical constraint[incr st($w,nextConstraint)]
            set definition [dict remove $relationship id valid geometry_supported measured_value residual angular_residual enforcement general_solver]
            foreach key {a b axis} {if {[dict get $definition $key]==0} {dict unset definition $key} else {dict set definition $key [dict get $reverse [dict get $definition $key]]}}
            dict set st($w,constraints) $logical [dict create id $logical name [_constraintTitle [dict get $definition kind]] native [dict get $relationship id] definition $definition]
        }
        # Endpoint attachment is the user's connection gesture. Adopt the
        # exact Native2D Path in this same creation/history transaction, with
        # no independent constituent rows or manual Join step.
        if {$parents ne {}&&![dict exists $receipt mirror_id]} {
            set nativeSeeds [lmap candidate [concat $parents [list $id]] {dict get [_record $w $candidate] native}]
            set reverse [_logicalNativeMap $w];set candidates {}
            foreach connected [::GX::native2DConnectedObjects $st($w,scene) $nativeSeeds] {lappend candidates [dict get $reverse $connected]}
            set eligible 1
            foreach candidate $candidates {
                set source [_record $w $candidate]
                if {![dict exists $source sketch_definition]||[dict get $source sketch_definition family] ni {line path polyline spline quadratic_bezier cubic_bezier arc circle ellipse rectangle composite_path}||[dict get $source locked]} {set eligible 0;break}
            }
            if {$eligible&&![catch {set path [_compositionApply $w $st($w,token) $candidates auto_path [dict create name Path tolerance 1e-9] 0]}]} {
                dict set before $path {};set id $path;set resultIds [concat $candidates [list $id]];set joined 1
            }
        }
        set st($w,active) $id
        set members {};foreach resultId $resultIds {if {[dict exists $st($w,curves) $resultId]} {lappend members [dict create kind object id [dict get [_record $w $resultId] native] index 0]}}
        _semanticApply $w $members
        set st($w,constructionPlaces) {};set st($w,placements) {};set st($w,snapCandidate) {}
        _selectionScene $w;_history $w $before $resultIds
    } on error {message options} {
        _restoreSnapshot $w $before
        if {[info exists receipt]&&[dict exists $receipt mirror_id]&&[dict get $receipt mirror_id] in [::GX::Native2D::core ids $st($w,scene)]} {::GX::Native2D::core delete $st($w,scene) [dict get $receipt mirror_id]}
        if {$native ne {}&&$native in [::GX::Native2D::core ids $st($w,scene)]} {::GX::Native2D::core delete $st($w,scene) $native}
        set st($w,undo) $oldUndo;set st($w,redo) $oldRedo
        _sketchIdle $w
        if {$message eq "invalid input"} {set message "[string totitle [string map {_ { }} $family]] needs distinct defining points and a compatible attachment."}
        _notice $w "Construction rejected: $message"
        return {}
    }
    # A committed primitive ends only this placement transaction. The tool
    # remains active until Escape, consistently for every creation family.
    _sketchTool $w $family
    set st($w,status) [expr {$joined?"Connected geometry committed as one editable Path. Continue drawing; Escape returns to Select.":"Primitive committed. Continue drawing; Escape returns to Select."}]
    return $id
}
proc ::GX::CurveWorkbench::_constructionFinish {w} {
    variable st
    if {$st($w,canvasTool) in {path polyline spline}} {
        if {$st($w,constructionPlaces) ne {}} {_createCommit $w} else {_sketchIdle $w}
    } elseif {$st($w,canvasTool) eq "line"} {_sketchIdle $w {Line chain finished. Segments and connections retained.}} else {_createCommit $w}
}
proc ::GX::CurveWorkbench::_drawConstructionPlaces {w} {
    variable st
        if {![winfo exists $w.right.viewport.canvas]||$st($w,canvasTool) eq "select"||$st($w,constructionPlaces) eq {}} return
    foreach point [::GX::Native2D::core construction_points $st($w,scene) $st($w,constructionPlaces)] {
        lassign [::GX::Native2D::core device $st($w,scene) $point] x y
        $w.right.viewport.canvas create oval [expr {$x-3}] [expr {$y-3}] [expr {$x+3}] [expr {$y+3}] -fill #237a6a -outline white -tags construction_placement
    }
    ::GX::native2DCanvasViewportClip $w.right.viewport.canvas $st($w,scene)
}
rename ::GX::CurveWorkbench::undo ::GX::CurveWorkbench::undo_interaction055_base
proc ::GX::CurveWorkbench::undo {w} {_sketchIdle $w;undo_interaction055_base $w}
rename ::GX::CurveWorkbench::redo ::GX::CurveWorkbench::redo_interaction055_base
proc ::GX::CurveWorkbench::redo {w} {_sketchIdle $w;redo_interaction055_base $w}
proc ::GX::CurveWorkbench::_selectionTargets {w} {variable st;set ids [_cadSelected $w];if {$ids eq {}} {set ids [list [_active $w]]};return $ids}

# Explicit multi-selection publication delegates to existing scientific/primitive
# controllers inside the common Publication v2 reviewed batch transaction.
proc ::GX::CurveWorkbench::_publishSelectionStructured {w} {
    variable st
    set ids [_selectionTargets $w]
    return [publish $w $st($w,resultId) $ids]
}
rename ::GX::CurveWorkbench::_publishSelected ::GX::CurveWorkbench::_publishSelected_interaction055_base
proc ::GX::CurveWorkbench::_publishSelected {w} {
    variable st;set ids [_selectionTargets $w]
    if {[llength $ids]>1} {return [_publishSelectionStructured $w]}
    return [_publishSelected_interaction055_base $w]
}
proc ::GX::CurveWorkbench::_publishBatchOpen {w} {
    variable st
    set ids [_commandSelection $w];set publishable {}
    if {[llength $ids]==1} {
        set r [_record $w [lindex $ids 0]]
        if {[dict exists $r sketch_definition]&&[dict get $r sketch_definition family] ni {compound composite_path}} {set st($w,active) [lindex $ids 0];tailcall _primitivePublishOpen $w}
    }
    foreach id $ids {
        set r [_record $w $id]
        if {[::GX::Native2D::core identity_geometry_role $st($w,scene) [dict get $r native]] ne "regular"} {error {Separate publication requires regular objects; change construction/reference roles explicitly first}}
        _sourceSnapshotRequire $w $r
        if {[dict exists $r sketch_definition]&&[dict get $r sketch_definition family] in {compound composite_path}} {
            set index 0
            foreach part [dict get $r sketch_definition parts] {lappend publishable [dict create object $id part_index $index];incr index}
        } else {lappend publishable [dict create object $id]}
    }
    set fields {};set values {};set index 0;set retained 0
    foreach output $publishable {
        set id [dict get $output object];set record [_record $w $id];set field output[incr index]
        set label "Dataset ID — [dict get $record name]"
        if {[dict exists $output part_index]} {append label " / part [expr {[dict get $output part_index]+1}]"}
        dict set fields $field [dict create type string required 1 label $label]
        dict set values $field "$st($w,resultId)_$index"
        if {[dict exists $record sketch_definition]} {set retained 1}
    }
    if {$retained} {
        dict set fields samples {type integer min 2 max 65536 label {Samples per curved constituent (straight vertices stay exact)}}
        dict set values samples 257
    }
    ::GX::uiFieldFormCreate $w.publishBatch {Review separate Dataset outputs — source objects preserved} $fields $values [list ::GX::CurveWorkbench::_publishBatchApply $w $st($w,token) $publishable] $w
    $w.publishBatch.actions.apply configure -text {Publish reviewed batch}
}
proc ::GX::CurveWorkbench::_publishBatchMember {w token ids session module request} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]||$session ne [file normalize [_session]]} {error {Session changed during reviewed batch publication}}
    set id [dict get $request workspace_object];set record [_record $w $id]
    if {[dict exists $record sketch_definition]} {
        set definition [::GX::Native2D::core sketch_definition $st($w,scene) [dict get $record native]]
        set sampling [dict create first 0 last 1 total [dict get $request samples] curved_samples [dict get $request samples] forward [dict get [::GX::Native2D::core direction_marker $st($w,scene) [dict get $record native]] forward]]
        if {[dict exists $request part_index]} {
            set index [dict get $request part_index]
            set part [::GX::Native2D::core composition_part $st($w,scene) [dict get $record native] $index]
            set state [lindex [::GX::Native2D::core composition_states $st($w,scene) [dict get $record native]] $index]
            dict set sampling conversion_provenance [dict create representation separate_constituents compound_definition $definition part_index $index part_id [dict get $state part_id] direction [dict get $state direction] source_logical_identity $id]
            dict set sampling forward [expr {[dict get $sampling forward] == [dict get $state direction forward]}]
            set definition [dict get $part definition]
        }
        switch -- [dict get $definition family] {
            line {dict set sampling total 2}
            polyline {dict set sampling total [llength [dict get $definition controls]]}
            rectangle {dict set sampling total 5}
        }
        set sources {};foreach ancestor [concat [list $record] [dict get $record ancestors]] {if {[dict get $ancestor source] ne {}} {lappend sources [dict get $ancestor source]}}
        dict set sampling source_dataset_ids [lsort -unique $sources]
        return [::GX::native2DPrimitivePublish $session [dict get $request dataset_id] $definition [lindex [_coordinateUnits $record] 0] $sampling $id [dict get $record name] viewer.curve_workbench]
    }
    return [publish $w [dict get $request dataset_id] [list $id]]
}
proc ::GX::CurveWorkbench::_publishBatchApply {w token ids values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen reviewed batch}}
    set requests {};set index 0
    foreach output $ids {
        set id [dict get $output object];set record [_record $w $id];_sourceSnapshotRequire $w $record
        # Native2D supplies geometry; Workbench remains the publishing module
        # for every member, including exact Compound constituents.
        set request [dict create dataset_id [dict get $values output[incr index]] workspace_object $id samples [::GX::datasetPublicationV2DictDefault $values samples 257]]
        if {[dict exists $output part_index]} {dict set request part_index [dict get $output part_index]}
        lappend requests $request
    }
    set result [::GX::datasetPublicationV2PublishBatch [_session] viewer.curve_workbench $requests [list ::GX::CurveWorkbench::_publishBatchMember $w $token $ids]]
    set st($w,status) "Published [dict get $result output_count] separate Datasets: [join [dict get $result dataset_ids] {, }]. Source objects preserved."
    return $result
}
