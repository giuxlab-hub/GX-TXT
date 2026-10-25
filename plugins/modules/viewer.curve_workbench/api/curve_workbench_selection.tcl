# SPDX-License-Identifier: GPL-3.0-or-later
# One Native selection set owns semantic membership across all logical curves.
# Legacy controller lists below are derived adapters for established dimension,
# constraint and tangent consumers; they never own a separate selection.
proc ::GX::CurveWorkbench::_cadController {w} {
    variable st
    if {[info exists st($w,cadController)] && [llength [info commands $st($w,cadController)]] && (![dict get [$st($w,cadController) state] alive] || [dict get [$st($w,cadController) state] scene]!=$st($w,scene))} {::GX::native2DCadDispose $st($w,cadController);unset st($w,cadController);set st($w,semanticSet) 0}
    if {![info exists st($w,cadController)] || ![llength [info commands $st($w,cadController)]]} {
        set st($w,cadController) [::GX::native2DCadCreate $st($w,scene) [expr {[info exists st($w,semanticSet)]?$st($w,semanticSet):0}] $w]
    }
    $st($w,cadController) selection adopt [expr {[info exists st($w,semanticSet)]?$st($w,semanticSet):0}]
    return $st($w,cadController)
}
proc ::GX::CurveWorkbench::_semanticMembers {w} {
    variable st
    set selection [[_cadController $w] selection get]
    set st($w,semanticSet) [dict get $selection id]
    return [dict get $selection members]
}
proc ::GX::CurveWorkbench::_semanticSync {w} {
    variable st
    set snapshot [[_cadController $w] selection snapshot]
    set st($w,semanticSet) [dict get $snapshot id]
    set reverse [_logicalNativeMap $w];set refs {};set objects {}
    foreach ref [dict get $snapshot references] {
        set native [dict get $ref object]
        if {![dict exists $reverse $native]} continue
        dict set ref logical [dict get $reverse $native];lappend refs $ref
    }
    foreach native [dict get $snapshot objects] {if {[dict exists $reverse $native]} {lappend objects [dict get $reverse $native]}}
    # Derived UI/Document adapters; the CORE native selection set owns membership.
    set st($w,sketchSelection) $refs;set st($w,objectSelection) [lsort -unique $objects]
}
proc ::GX::CurveWorkbench::_semanticApply {w members {mode replace}} {
    variable st
    set st($w,semanticSet) [[_cadController $w] selection apply $members $mode]
    _semanticSync $w;_planarSelectionChanged $w
}
proc ::GX::CurveWorkbench::_semanticClear {w} {
    variable st
    if {[info exists st($w,scene)]} {_semanticApply $w {}} else {set st($w,sketchSelection) {}}
}
proc ::GX::CurveWorkbench::_selectionScope {w} {
    variable st
    # Visible selectable logical curves are the deterministic current sketch
    # scope. Primary property focus and representation never restrict it.
    set ids {}
    dict for {id record} $st($w,curves) {
        if {[_curveVisible $w $record]} {lappend ids [dict get $record native]}
    }
    return $ids
}
proc ::GX::CurveWorkbench::_selectionMode {state} {
    if {$state&0x1} {return subtract}
    if {$state&0x4} {return add}
    return replace
}
proc ::GX::CurveWorkbench::_sketchPick {w x y {target detail}} {
    variable st
    set ref [[_cadController $w] selection pick [_selectionScope $w] [list $x $y] 9 $target]
    if {$ref eq {}} {
        if {$st($w,constraintTool) eq "dimension"} {
            dict for {id record} $st($w,images) {
                set ref [::GX::Native2D::core interaction_pick $st($w,scene) [dict get $record native] [list $x $y] 10]
                if {$ref ne {}&&[dict get $ref entity] eq "control"&&[dict get $ref index]>=1000000002} {dict set ref logical $id;dict set ref semantic_kind control;return $ref}
            }
        }
        return {}
    }
    dict set ref logical [dict get [_logicalNativeMap $w] [dict get $ref object]]
    return $ref
}
proc ::GX::CurveWorkbench::_selectReference {w ref additive} {
    variable st
    set kind [::GX::datasetPublicationV2DictDefault $ref semantic_kind [dict get $ref entity]]
    _semanticApply $w [list [dict create kind $kind id [dict get $ref object] index [expr {$kind eq "object"?0:[dict get $ref index]}]]] [expr {$additive?"add":"replace"}]
    set st($w,active) [dict get $ref logical]
    _selectionScene $w;_curveList $w;_pointList $w;_draw $w
}
proc ::GX::CurveWorkbench::_pointerDownSelection {w x y state} {
    variable st
    if {$st($w,publishBusy)||$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {return 1}
    if {$st($w,canvasTool) ne "select"||$st($w,cadTool) ne "none"||$st($w,tool) ne "select"||$st($w,constraintTool) ne {}||$st($w,imageCalibration) ne {}||$st($w,zoomBox) ne {}||$st($w,joinPending) ne {}} {return 0}
    if {[winfo exists $w.inline]} {return 1}
    if {[info exists st($w,selectionShape)] && $st($w,selectionShape) in {polygon window}} {
        set host [_cadCanvas $w];$host tool [dict get {window rectangle polygon polygon} $st($w,selectionShape)]
        return [$host event down $x $y $state]
    }
    # Existing tangent and relationship interaction keeps its established
    # priority. Their scientific references use the same Native scene.
    foreach handle [_tangentHandles $w] {lassign [dict get $handle device] hx hy;if {hypot($x-$hx,$y-$hy)<=9} {return 0}}
    set ref [_sketchPick $w $x $y $st($w,selectionTarget)]
    if {[info exists st($w,selectionShape)]&&$st($w,selectionShape) eq "window"} {set ref {}}
    if {($ref eq {}||"direction_marker" in [$w.right.viewport.canvas gettags current])&&$st($w,active) ne {}&&[::GX::Native2D::core marker_hit $st($w,scene) [dict get [_record $w $st($w,active)] native] [list $x $y] 5]&&($ref eq {}||[dict get $ref semantic_kind] in {object segment})} {return 0}
    if {[_relationshipPick $w $x $y] ne {}&&($ref eq {}||("constraint_marker" in [$w.right.viewport.canvas gettags current]&&[dict get $ref entity] ne "control"))} {return 0}
    if {"direction_flip" in [$w.right.viewport.canvas gettags current]} {return 0}
    set host [_cadCanvas $w]
    $host tool [dict get {click select window rectangle polygon polygon} $st($w,selectionShape)]
    return [$host event down $x $y $state]
}

proc ::GX::CurveWorkbench::_pointerMoveSelection {w x y} {
    variable st
    if {![info exists st($w,cadCanvas)]} {return 0}
    return [$st($w,cadCanvas) event move $x $y]
}
proc ::GX::CurveWorkbench::_pointerUpSelection {w x y} {
    variable st
    if {![info exists st($w,cadCanvas)]} {return 0}
    return [$st($w,cadCanvas) event up $x $y]
}
proc ::GX::CurveWorkbench::_selectionShape {w shape} {
    variable st
    _sketchIdle $w;set st($w,selectionShape) $shape
    [_cadCanvas $w] tool [dict get {click select window rectangle polygon polygon} $shape]
    focus $w.right.viewport.canvas;set st($w,toolLabel) [_selectionPrompt $w $shape]
}
rename ::GX::CurveWorkbench::_constructionFinish ::GX::CurveWorkbench::_constructionFinish_selection057_base
proc ::GX::CurveWorkbench::_constructionFinish {w} {
    variable st
    if {[info exists st($w,cadCanvas)] && [dict get [$st($w,cadCanvas) state] polygon] ne {}} {$st($w,cadCanvas) event key Return;return}
    tailcall _constructionFinish_selection057_base $w
}
rename ::GX::CurveWorkbench::_sketchIdle ::GX::CurveWorkbench::_sketchIdle_selection057_base
proc ::GX::CurveWorkbench::_sketchIdle {w {message {}}} {
    variable st
    if {$message eq {}} {set message [_selectionPrompt $w click]}
    # Polygon clicks do not mutate selection until Finish, so Escape restores
    # the exact previous semantic membership without synthesizing a replacement.
    set st($w,polygonVertices) {};set st($w,selectionShape) click
    if {[info exists st($w,semanticPointDrag)]&&$st($w,semanticPointDrag) ne {}} {[_cadController $w] gesture cancel;set st($w,semanticPointDrag) {}}
    _sketchIdle_selection057_base $w $message
    _semanticSync $w;_pointList $w;_draw $w
}
proc ::GX::CurveWorkbench::_installSelectionCommands {w} {
    variable st
    # Interaction preference is local to this Workbench, not Workspace geometry.
    set st($w,selectionTarget) local
    if {$st($w,canvasTool) eq "select"} {set st($w,toolLabel) [_selectionPrompt $w click]}
    
    $w.toolbar.view.menu add separator
    foreach {label shape} {{Select / window} window {Select polygon…} polygon} {$w.toolbar.view.menu add command -label $label -command [list ::GX::CurveWorkbench::_selectionShape $w $shape]}
    $w.toolbar.objects.menu add separator
    # Actual row clicks remain semantic input even when the row was focused
    # programmatically; queued list refresh events remain advisory.
    set tree $w.leftScroll.viewport.content.curves
    bind $tree <Button-1> "[list ::GX::CurveWorkbench::_objectListClick $w %x %y %s]; break"
    bind $tree <Button-3> "[list ::GX::CurveWorkbench::_objectListContext $w %x %y %X %Y]; break"
    foreach {label enabled} {{Include in selection} 1 {Visible reference only} 0} {$w.toolbar.objects.menu add command -label $label -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_selectableSet $w $enabled]]}

}
proc ::GX::CurveWorkbench::_selectableSet {w enabled} {
    variable st
    set ids [_commandSelection $w]
    set before [_snapshotIds $w $ids]
    foreach id $ids {set record [_record $w $id];dict set record selectable $enabled;dict set st($w,curves) $id $record;::GX::Native2D::core object_style $st($w,scene) [dict get $record native] [dict create selectable $enabled]}
    _semanticApply $w {} add
    _history $w $before $ids
}

# Table selection updates the same semantic membership while preserving points
# outside the displayed page and references belonging to other logical curves.
proc ::GX::CurveWorkbench::_pointSyncApply {w} {
    variable st
    if {![info exists st($w,pointSyncAfter)]} return
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {_pointSyncCancel $w;return}
    if {$st($w,pointSyncAfter) ne {}} {after cancel $st($w,pointSyncAfter);set st($w,pointSyncAfter) {}}
    if {$st($w,pointSyncRunning)||$st($w,pointSyncPending) eq {}} return
    lassign $st($w,pointSyncPending) active epoch indices
    if {$active ne $st($w,active)||$epoch!=$st($w,selectionEpoch)||$st($w,selectionObject) eq {}} {_pointSyncCancel $w;return}
    if {[::GX::Native2D::core drag_active $st($w,scene)]} return
    set st($w,pointSyncRunning) 1
    try {
        if {$indices ne [_pointTableSelected $w]} {
            set record [_record $w $active];set native [dict get $record native]
            set first $st($w,pointPageStart);set last [expr {$first+min(200,[_pointCount $record]-$first)}]
            set members {}
            foreach member [_semanticMembers $w] {
                if {[dict get $member id]==$native&&([dict get $member kind] eq "object"||([dict get $member kind] eq "point"&&[dict get $member index]>=$first&&[dict get $member index]<$last))} continue
                lappend members [dict remove $member topology_epoch valid missing]
            }
            foreach index $indices {lappend members [dict create kind point id $native index $index]}
            _semanticApply $w $members;incr st($w,pointSyncCommits)
        }
        set st($w,pointSyncPending) {};_pointList $w;_draw $w
    } finally {set st($w,pointSyncRunning) 0}
}
rename ::GX::CurveWorkbench::_pointTreeSelect ::GX::CurveWorkbench::_pointTreeSelect_selection057_base
proc ::GX::CurveWorkbench::_pointTreeSelect {w} {
    variable st
    if {$st($w,active) eq {}||![dict exists [_record $w $st($w,active)] sketch_definition]} {tailcall _pointTreeSelect_selection057_base $w}
    if {$st($w,pointSyncRunning)} return
    set native [dict get [_record $w $st($w,active)] native];set members {};set expected {}
    foreach member [_semanticMembers $w] {if {[dict get $member valid]&&[dict get $member id]==$native&&[dict get $member kind] eq "control"} {lappend expected h[expr {[dict get $member index]-1000000000+1}]}}
    if {[lsort [$w.leftScroll.viewport.content.points selection]] eq [lsort $expected]} return
    foreach member [_semanticMembers $w] {if {[dict get $member id]!=$native||[dict get $member kind] ni {object control}} {lappend members [dict remove $member topology_epoch valid missing]}}
    foreach row [$w.leftScroll.viewport.content.points selection] {lappend members [dict create kind control id $native index [expr {1000000000+[string range $row 1 end]-1}]]}
    _semanticApply $w $members;_pointList $w;_draw $w
}
rename ::GX::CurveWorkbench::_sketchTool ::GX::CurveWorkbench::_sketchTool_path057_base
proc ::GX::CurveWorkbench::_sketchTool {w family} {
    variable st
    if {$family eq "line"} {set family path}
    _sketchTool_path057_base $w $family
    if {$family eq "path"} {set st($w,toolLabel) {Line — click start and successive vertices of one retained path. Enter / Finish commits; click start to close.}}
}


# Point/table presentation reads semantic entities, not the temporary whole-
# object masks used by Native's existing gizmo executor during CAD gestures.
proc ::GX::CurveWorkbench::_semanticPointIndices {w logical {start 0} {count -1}} {
    variable st
    set record [_record $w $logical];set native [dict get $record native]
    set last [expr {$count<0?[_pointCount $record]:$start+$count}];set indices {}
    foreach member [_semanticMembers $w] {
        if {![dict get $member valid]} continue
        if {[dict get $member kind] eq "point"&&[dict get $member id]==$native} {
            set index [dict get $member index];if {$index>=$start&&$index<$last} {dict set indices $index 1}
        } elseif {[dict get $member kind] eq "fragment"} {
            set fragment [::GX::Native2D::core fragment_get $st($w,scene) [dict get $member id]]
            if {[dict get $fragment parent]!=$native} continue
            set a [dict get $fragment first];set b [dict get $fragment last]
            if {[dict get $fragment parameter]} {set a [expr {$a*([_pointCount $record]-1)}];set b [expr {$b*([_pointCount $record]-1)}]}
            for {set i [expr {max($start,int(ceil(min($a,$b))))}]} {$i<min($last,floor(max($a,$b))+1)} {incr i} {dict set indices $i 1}
        }
    }
    return [lsort -integer [dict keys $indices]]
}
proc ::GX::CurveWorkbench::_pointTableSelected {w} {
    variable st
    if {$st($w,active) eq {}} {return {}}
    return [_semanticPointIndices $w $st($w,active) $st($w,pointPageStart) 200]
}
proc ::GX::CurveWorkbench::_selected {w} {
    variable st
    if {$st($w,active) eq {}} {return {}}
    if {[_bulkRecord [_record $w $st($w,active)]]} {return [_pointTableSelected $w]}
    return [_semanticPointIndices $w $st($w,active)]
}

# The legacy selection-scene name aliases the main scene. Cancel a semantic
# point transaction through its own ledger before legacy gesture dispatch.
rename ::GX::CurveWorkbench::_cancelPointDrag ::GX::CurveWorkbench::_cancelPointDrag_selection057_base
proc ::GX::CurveWorkbench::_cancelPointDrag {w} {
    variable st
    if {[info exists st($w,semanticPointDrag)]&&$st($w,semanticPointDrag) ne {}} {
        if {[::GX::Native2D::core drag_active $st($w,scene)]} {[_cadController $w] gesture cancel}
        set st($w,semanticPointDrag) {};_pointSyncCancel $w;return
    }
    tailcall _cancelPointDrag_selection057_base $w
}

rename ::GX::CurveWorkbench::_fit ::GX::CurveWorkbench::_fit_selection057_base
proc ::GX::CurveWorkbench::_fit {w {selected 0}} {
    variable st
    if {!$selected||[_semanticMembers $w] eq {}} {tailcall _fit_selection057_base $w $selected}
    _coordinateRequireFrame $w [_cadSelected $w]
    # Fit uses the semantic set's complete logical owners, not primary focus.
    # The Native authority includes real controls/segments without sample masks.
    set bounds [::GX::Native2D::core selection_set_bounds $st($w,scene) $st($w,semanticSet)]
    ::GX::Native2D::core fit_bounds $st($w,scene) $bounds
    _coordinateMagnify $w 1
    _draw $w;_save $w
}

# Object-list membership is a projection of the Native semantic set. Property
# focus may survive an empty selection; it must never repopulate that selection.
proc ::GX::CurveWorkbench::_curveList {w} {
    variable st
    set tree $w.leftScroll.viewport.content.curves
    if {![winfo exists $tree]} return
    _cadSyncGroups $w
    _semanticSync $w
    set rows {}
    dict for {id r} $st($w,curves) {
        set count [_pointCount $r]
        if {[dict exists $r sketch_definition]} {
            set count [llength [::GX::Native2D::core interaction_controls $st($w,scene) [dict get $r native]]]
            set state "Retained [string map {_ { }} [dict get $r sketch_definition family]] · exact"
            if {[dict exists $r sketch_definition parts]} {set count "[llength [dict get $r sketch_definition parts]] parts"}
        } elseif {[dict get $r source] ne {}&&![dict get $r edited]} {set state {Dataset source · immutable}} else {set state {Native point curve · editable}}
        if {![::GX::datasetPublicationV2DictDefault $r selectable 1]} {append state { · reference only}}
        if {![_coordinateInFrame $w $r]} {append state { · other axis frame}}
        if {[dict get $r locked]} {append state { · locked}}
        if {[dict exists $r source_state]&&[dict get $r source_state] ne "current"} {append state " · Dataset [dict get $r source_state]"}
        dict for {group record} $st($w,groups) {if {$id in [dict get $record members]} {append state " · [dict get $record name]"}}
        set role [::GX::Native2D::core identity_geometry_role $st($w,scene) [dict get $r native]]
        if {$role ne "regular"} {append state " · $role"}
        lappend rows $id
        set values [list [expr {[_curveVisible $w $r]?"●":"○"}] [dict get $r name] [dict get $r source] $count $state]
        if {[$tree exists $id]} {$tree item $id -values $values} else {$tree insert {} end -id $id -values $values}
    }
    foreach id [$tree children {}] {if {$id ni $rows} {$tree delete $id}}
    $tree heading points -text {Points / handles}
    foreach column [$tree cget -columns] {
        set minimum [expr {[font measure TkHeadingFont [$tree heading $column -text]]+24}]
        $tree column $column -minwidth $minimum
        if {[$tree column $column -width]<$minimum} {$tree column $column -width $minimum}
    }
    # This table projects curves only. Native image references remain selected
    # in the authoritative scene, but have no row in the curve table.
    set st($w,curveTableSelection) [lmap id $st($w,objectSelection) {if {$id ni $rows} continue;set id}]
    if {[lsort [$tree selection]] ne [lsort $st($w,curveTableSelection)]} {$tree selection set $st($w,curveTableSelection)}
    if {$st($w,active) in $rows&&$st($w,active) in $st($w,objectSelection)&&(![info exists st($w,curveTableFocus)]||$st($w,curveTableFocus) ne $st($w,active))} {$tree see $st($w,active)}
    set st($w,curveTableFocus) $st($w,active)
    _comparisonRefresh $w
    _propertyFocusRefresh $w
    if {[winfo exists $w.cad.group]} {
        set values {};set map {};set st($w,cadGroupLabel) {}
        dict for {id group} $st($w,groups) {
            set label "[dict get $group name] · $id";lappend values $label;dict set map $label $id
            if {$id eq $st($w,cadGroup)} {set st($w,cadGroupLabel) $label}
        }
        set st($w,cadGroupMap) $map;$w.cad.group configure -values $values
    }
}
proc ::GX::CurveWorkbench::_propertyFocusRefresh {w} {
    variable st
    if {[dict exists $st($w,curves) $st($w,active)]} {
        set name [dict get [_record $w $st($w,active)] name]
        set st($w,activeLabel) "ACTIVE: $name";set st($w,rename) $name
    } else {set st($w,activeLabel) {ACTIVE: none};set st($w,rename) {}}
    catch {_metrics $w}
}
proc ::GX::CurveWorkbench::_treeSelect {w {explicit 0}} {
    variable st
    if {$st($w,publishBusy)||$st($w,token) ne [::GX::interactiveDocumentSessionToken]} return
    set tree $w.leftScroll.viewport.content.curves;set ids [$tree selection]
    if {!$explicit&&[info exists st($w,curveTableSelection)]&&[lsort $ids] eq [lsort $st($w,curveTableSelection)]} return
    if {$st($w,cadDrag) ne {}} {set st($w,cadSelectionPending) $ids;return}
    set members {}
    foreach id $ids {if {[dict exists $st($w,curves) $id]} {lappend members [dict create kind object id [dict get [_record $w $id] native] index 0]}}
    _semanticApply $w $members
    set st($w,curveTableSelection) $ids
    set id [$tree focus]
    if {$id ni $ids} {set id [lindex $ids 0]}
    if {$id ne {}&&$id ne $st($w,active)} {set st($w,active) $id;_selectionScene $w}
    _propertyFocusRefresh $w
    if {$st($w,cadTool) ne "none"&&$ids ne {}} {_cadSelectNative $w}
    _pointList $w;_draw $w
    if {[info exists st($w,comparisonEnabled)]&&$st($w,comparisonEnabled)} {_comparisonRefresh $w}
}
proc ::GX::CurveWorkbench::_objectListClick {w x y state} {
    variable st
    set tree $w.leftScroll.viewport.content.curves
    if {[$tree identify region $x $y] ni {tree cell}} return
    set id [$tree identify row $x $y];if {$id eq {}} return
    focus $tree
    set mode [_selectionMode $state]
    set members [list [dict create kind object id [dict get [_record $w $id] native] index 0]]
    _semanticApply $w $members $mode
    set st($w,active) $id;$tree focus $id
    _selectionScene $w;_curveList $w;_pointList $w
    if {$st($w,cadTool) ne "none"&&$st($w,objectSelection) ne {}} {_cadSelectNative $w}
    _draw $w
}
proc ::GX::CurveWorkbench::_objectListContext {w x y X Y} {
    variable st
    set tree $w.leftScroll.viewport.content.curves
    set id [$tree identify row $x $y];if {$id eq {}} return
    set st($w,contextObject) $id
    _semanticSync $w
    if {$id ni $st($w,objectSelection)} {_objectListClick $w $x $y 0}
    _objectContextMenu $w $X $Y
}

# Point-backed segment ordinals overlap point ordinals. Preserve Native's
# explicit semantic kind while adapting to an interaction reference.
proc ::GX::CurveWorkbench::_semanticReference {w native kind index} {
    return [[_cadController $w] selection reference $native $kind $index]
}

# Presentation/input routing only: Native queries choose entities and the one
# semantic set owns membership. Whole-object commands never infer a segment
# from two selected controls.
proc ::GX::CurveWorkbench::_selectionPrompt {w shape} {
    variable st
    set target [expr {[info exists st($w,selectionTarget)]?$st($w,selectionTarget):"local"}]
    if {$shape ne "click"} {return "Select — $shape, whole objects; Ctrl adds; Shift subtracts."}
    set label [expr {$target eq "object"?"Entire Curve / Path":"Local Geometry"}]
    return "Select — $label; click geometry or defining handles. Ctrl adds; Shift subtracts."
}
proc ::GX::CurveWorkbench::_selectionTarget {w target} {
    variable st
    if {$target ni {local object}} {error {Unknown Select mode}}
    set st($w,selectionTarget) $target
    _selectionShape $w click
}
proc ::GX::CurveWorkbench::_objectListSelect {w} {
    variable st
    set id $st($w,contextObject)
    set record [_record $w $id]
    _semanticApply $w [list [dict create kind object id [dict get $record native] index 0]]
    set st($w,active) $id
    _selectionScene $w;_curveList $w;_pointList $w;_draw $w
    set st($w,status) "Selected complete object: [dict get $record name]."
}
