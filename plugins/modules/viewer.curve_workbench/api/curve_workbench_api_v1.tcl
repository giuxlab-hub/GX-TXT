# GX-TXT Curve Workbench. Native2D owns planar geometry, selection and view.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::CurveWorkbench {
    variable version 2.20.0
    variable st
    variable root [file normalize [file join [file dirname [info script]] ../../../..]]
}
proc ::GX::CurveWorkbench::_session {} {::GX::sessionInspectionCurrentSession}
proc ::GX::CurveWorkbench::_native {} {
    ::GX::native2DEnsure
    foreach capability {stable_constituent_identity independent_part_direction compound_subentities truthful_composition_traversal} {if {$capability ni [dict get [::GX::Native2D::core api_info] capabilities]} {error "Curve Workbench requires the dev092 CORE contract: $capability"}}
    if {"atomic_attached_construction" ni [dict get [::GX::Native2D::core api_info] capabilities]} {error {Curve Workbench requires the dev-055 Native2D construction authority}}
}
proc ::GX::CurveWorkbench::_finite {value label} {
    if {![string is double -strict $value] || [catch {set x [expr {double($value)}]}] || $x != $x || abs($x)==Inf} {error "$label must be finite"}
    return $x
}
proc ::GX::CurveWorkbench::datasetIds {} {
    set ids {}
    foreach id [::GX::sessionInspectionDatasetIds] {
        if {[catch {set schema [variables $id]}]} continue
        if {[llength [dict get $schema numeric]] >= 2} {lappend ids $id}
    }
    return [lsort -dictionary $ids]
}
proc ::GX::CurveWorkbench::variables {datasetId} {
    set all {}; set numeric {}; set labels [dict create]
    foreach v [::GX::datasetVariableSchema $datasetId] {
        if {![dict get $v enabled] || ([dict exists $v rank] && [dict get $v rank] != 1)} continue
        set id [dict get $v variable_id]
        set label $id
        foreach key {display_label canonical name} {
            if {[dict exists $v $key] && [string trim [dict get $v $key]] ne ""} {set label [dict get $v $key]; break}
        }
        if {[dict exists $v unit] && [dict get $v unit] ne ""} {append label " ([dict get $v unit])"}
        append label "  ·  $id"
        dict set labels $id $label
        lappend all $id
        if {[dict get $v value_kind] eq "number"} {lappend numeric $id}
    }
    return [dict create all $all numeric $numeric labels $labels]
}
proc ::GX::CurveWorkbench::_datasetLabel {id} {
    set name ""
    catch {set meta [::GX::datasetMetadataRead [_session] $id]; set name [dict get $meta dataset.display_name]}
    if {$name eq ""} {catch {set ds [::GX::sessionInspectionDataset $id]; foreach key {display_name name title} {if {[dict exists $ds $key] && [dict get $ds $key] ne ""} {set name [dict get $ds $key]; break}}}}
    if {$name eq ""} {set name $id}
    return "$name  ·  $id"
}
proc ::GX::CurveWorkbench::_datasetName {id} {
    set label [_datasetLabel $id]
    set mark [string last "  ·  $id" $label]
    return [expr {$mark>=0 ? [string range $label 0 [expr {$mark-1}]] : $label}]
}
proc ::GX::CurveWorkbench::distinctValues {datasetId variableId} {
    set stream [::GX::tableStreamOpenDataset [_session] $datasetId [list $variableId] 4096]
    set seen [dict create]
    try {
        while 1 {
            set chunk [::GX::tableStreamNext $stream]
            foreach value [dict get [dict get $chunk values] $variableId] {dict set seen $value 1}
            if {[dict get $chunk eof]} break
        }
    } finally {::GX::tableStreamClose $stream}
    return [lsort -dictionary [dict keys $seen]]
}
proc ::GX::CurveWorkbench::_xy {samples} {lmap p $samples {list [dict get $p x] [dict get $p y]}}
proc ::GX::CurveWorkbench::_record {w id} {variable st;return [dict get $st($w,curves) $id]}
proc ::GX::CurveWorkbench::_active {w} {
    variable st
    set id $st($w,active)
    if {$id eq "" || ![dict exists $st($w,curves) $id]} {error "Select an active curve"}
    return $id
}
proc ::GX::CurveWorkbench::_editable {w} {
    set id [_active $w];if {[dict get [_record $w $id] locked]} {error "The active curve is locked"};return $id
}
proc ::GX::CurveWorkbench::_addRecord {w record {nativeId ""}} {
    variable st
    set id [dict get $record id]
    if {[dict exists $record source_descriptor]} {dict set record source_state [dict get [::GX::curveSourceValidateSnapshot [_session] [dict get $record source_descriptor]] status]}
    if {$nativeId eq ""} {
        if {[_bulkRecord $record]} {
            set state [::GX::curveSourceValidateSnapshot [_session] [dict get $record source_descriptor]]
            dict set record source_state [dict get $state status]
            set source {}
            if {[dict get $state valid]} {set source [::GX::curveSourceOpen [_session] [dict get $record source_request]]}
            try {set nativeId [::GX::interactiveDocumentNative2DRestoreWithGaps [dict get $record geometry_resource] [dict get $record gap_resource] $st($w,scene)]} on error {message options} {if {$source ne {}} {::GX::curveSourceClose $source};return -options $options $message}
            dict set record source_token $source
        } elseif {[dict exists $record sketch_definition]} {
            set nativeId [::GX::Native2D::core sketch_create $st($w,scene) [dict get $record sketch_definition] [dict get $record sketch_samples]]
        } else {set nativeId [::GX::Native2D::core [expr {[llength [dict get $record samples]]==1 ? "point" : "add"}] $st($w,scene) [_xy [dict get $record samples]]]}
    }
    set definition [::GX::Native2D::core sketch_definition $st($w,scene) $nativeId]
    if {$definition ne {}} {
        dict set record sketch_definition $definition
        dict set record sketch_samples [::GX::Native2D::core count $st($w,scene) $nativeId]
        dict set record geometry_authority retained_sketch
        # Retained topology owns its display breaks. Reapplying a point-curve
        # break mutation would reject Compound restore and lose the Undo boundary.
        dict set record breaks [expr {[dict get $definition family] eq "point"?{}:[::GX::Native2D::core breaks $st($w,scene) $nativeId]}]
    }
    dict set record native $nativeId
    set direction [expr {[dict exists $record direction] ? [dict get $record direction] : {}}]
    dict set direction interpolation [expr {[::GX::datasetPublicationV2DictDefault $record display_style [dict get $record representation]] eq "spline"}]
    dict set record direction [::GX::Native2D::core direction_marker $st($w,scene) $nativeId $direction]
    dict set st($w,curves) $id $record
    ::GX::Native2D::core object_style $st($w,scene) $nativeId [dict create selectable [::GX::datasetPublicationV2DictDefault $record selectable 1]]
    ::GX::Native2D::core visible $st($w,scene) $nativeId [dict get $record visible]
    ::GX::Native2D::core locked $st($w,scene) $nativeId [dict get $record locked]
    if {$definition eq {}&&[dict get $record breaks] ne {}} {
        if {[dict get $record locked]} {::GX::Native2D::core locked $st($w,scene) $nativeId 0}
        ::GX::Native2D::core set_breaks $st($w,scene) $nativeId [dict get $record breaks]
        if {[dict get $record locked]} {::GX::Native2D::core locked $st($w,scene) $nativeId 1}
    }
    return $id
}
proc ::GX::CurveWorkbench::_newId {w} {variable st;return "curve[incr st($w,next)]"}
proc ::GX::CurveWorkbench::_newRecord {w name samples source x y filter value family order parents operations {representation linear}} {
    variable st
    set id [_newId $w]
    set ancestors {}
    foreach parent $parents {
        if {![dict exists $st($w,curves) $parent]} continue
        set pr [_record $w $parent]
        set lineage [dict remove $pr native samples ancestors source_token]
        if {[dict get $pr representation] eq "spline"} {dict set lineage control_points [dict get $pr samples]}
        lappend ancestors $lineage
        if {[dict exists $pr ancestors]} {set ancestors [concat $ancestors [dict get $pr ancestors]]}
    }
    set xName $x;set yName $y
    catch {set v [::GX::datasetVariableById $source $x];set xName [expr {[dict exists $v display_label] && [dict get $v display_label] ne "" ? [dict get $v display_label] : [dict get $v canonical]}]}
    catch {set v [::GX::datasetVariableById $source $y];set yName [expr {[dict exists $v display_label] && [dict get $v display_label] ne "" ? [dict get $v display_label] : [dict get $v canonical]}]}
    return [dict create id $id name $name samples $samples source $source x $x y $y source_x_name $xName source_y_name $yName filter $filter filter_value $value family $family order $order parents $parents ancestors $ancestors operations $operations representation $representation visible 1 locked 0 edited [expr {[llength $parents]>0}] breaks {}]
}
proc ::GX::CurveWorkbench::_syncSamples {w id} {
    variable st
    set record [_record $w $id];set samples [dict get $record samples]
    set coords [::GX::Native2D::core points $st($w,scene) [dict get $record native]]
    if {[llength $coords]!=[llength $samples]} {error "Native2D point count diverged from source identities"}
    for {set i 0} {$i<[llength $samples]} {incr i} {
        set p [lindex $samples $i];lassign [lindex $coords $i] x y
        dict set p x $x;dict set p y $y;lset samples $i $p
    }
    set definition [::GX::Native2D::core sketch_definition $st($w,scene) [dict get $record native]]
    if {$definition ne {}} {dict set record sketch_definition $definition}
    dict set record samples $samples;dict set record edited 1
    if {[::GX::Native2D::core kind $st($w,scene) [dict get $record native]] eq "curve"} {dict set record breaks [::GX::Native2D::core breaks $st($w,scene) [dict get $record native]]} else {dict set record breaks {}}
    dict set st($w,curves) $id $record
}
proc ::GX::CurveWorkbench::_removeRecord {w id} {
    variable st
    if {![dict exists $st($w,curves) $id]} return
    set record [_record $w $id]
    ::GX::Native2D::core delete $st($w,scene) [dict get $record native]
    if {[dict exists $record source_token]&&[dict get $record source_token] ne {}} {::GX::curveSourceClose [dict get $record source_token]}
    dict unset st($w,curves) $id
    if {$st($w,active) eq $id} {set st($w,active) "";_selectionScene $w}
}
proc ::GX::CurveWorkbench::_snapshotIds {w ids} {
    variable st
    set result [dict create]
    foreach id $ids {
        if {[dict exists $st($w,curves) $id]} {
            set record [_record $w $id]
            dict set record direction [::GX::Native2D::core direction_marker $st($w,scene) [dict get $record native]]
            set definition [::GX::Native2D::core sketch_definition $st($w,scene) [dict get $record native]]
            if {$definition ne {}} {dict set record sketch_definition $definition}
            dict set result $id [dict remove $record native source_token]
        } else {dict set result $id ""}
    }
    return $result
}
proc ::GX::CurveWorkbench::_history {w before ids} {
    variable st
    set after [_snapshotIds $w $ids]
    if {$before eq $after} return
    lappend st($w,undo) [list $before $after]
    if {[llength $st($w,undo)]>30} {set st($w,undo) [lrange $st($w,undo) end-29 end]}
    set st($w,redo) {}
    _changed $w
}
proc ::GX::CurveWorkbench::_restoreSnapshot {w snapshot} {
    variable st
    set previousActive $st($w,active)
    dict for {id record} $snapshot {
        if {[dict exists $st($w,curves) $id]} {_removeRecord $w $id}
        if {$record ne ""} {_addRecord $w $record}
    }
    if {[dict exists $st($w,curves) $previousActive]} {set st($w,active) $previousActive} elseif {$st($w,active) eq "" || ![dict exists $st($w,curves) $st($w,active)]} {set st($w,active) [lindex [dict keys $st($w,curves)] 0]}
    _selectionScene $w
}
proc ::GX::CurveWorkbench::undo {w} {
    variable st
    if {![llength $st($w,undo)]} return
    lassign [lindex $st($w,undo) end] before after
    set st($w,undo) [lrange $st($w,undo) 0 end-1]
    _restoreSnapshot $w $before;lappend st($w,redo) [list $before $after];_changed $w
}
proc ::GX::CurveWorkbench::redo {w} {
    variable st
    if {![llength $st($w,redo)]} return
    lassign [lindex $st($w,redo) end] before after
    set st($w,redo) [lrange $st($w,redo) 0 end-1]
    _restoreSnapshot $w $after;lappend st($w,undo) [list $before $after];_changed $w
}
proc ::GX::CurveWorkbench::_load {w} {
    variable st
    variable openingWorkspace
    if {[info exists openingWorkspace]&&$openingWorkspace eq "new"} return
    set docs [::GX::interactiveDocumentList viewer.curve_workbench curve_workbench]
    if {[info exists openingWorkspace]&&$openingWorkspace ne {}} {
        ::GX::sessionWorkspaceValidate $openingWorkspace
        set st($w,document) $openingWorkspace
    } else {
        if {![llength $docs]} return
        set st($w,document) [dict get [lindex $docs 0] id]
    }
    set payload [dict get [::GX::interactiveDocumentRead $st($w,document)] payload]
    if {[dict get $payload version]!=2} {error "Unsupported Curve Workbench workspace version"}
    set st($w,next) [dict get $payload next]
    dict for {id record} [dict get $payload curves] {_addRecord $w $record}
    set st($w,active) [dict get $payload active]
    if {![dict exists $st($w,curves) $st($w,active)]} {set st($w,active) [lindex [dict keys $st($w,curves)] 0]}
    set st($w,reference) [dict get $payload reference]
    set st($w,target) [dict get $payload target]
    set st($w,externalFeedback) [dict get $payload external_feedback]
    if {[dict exists $payload composition_settings]} {
        set settings [dict get $payload composition_settings]
        set st($w,bridgeKind) [dict get $settings bridge_kind]
        set st($w,bridgeSubdivisions) [dict get $settings subdivisions]
        set st($w,bridgeTolerance) [dict get $settings tolerance]
        set st($w,bridge) [expr {$st($w,bridgeKind) eq "straight"}]
    }
    if {[dict exists $payload cad_workspace]} {_cadRestoreState $w [dict get $payload cad_workspace]}
    foreach property {grid background aspect} {
        if {[dict exists $payload $property]} {::GX::Native2D::core $property $st($w,scene) [dict get $payload $property]}
    }
    if {[dict exists $payload presentation]} {::GX::Native2D::core presentation $st($w,scene) [dict get $payload presentation]}
    set restoredView [expr {[dict exists $payload view_requested] ? [dict get $payload view_requested] : [dict get $payload view]}]
    ::GX::Native2D::core view $st($w,scene) $restoredView
    _selectionScene $w
    if {[dict exists $payload cad_workspace semantic_selection]} {
        # The shared semantic set already restored points/controls across all
        # curves. Legacy active-only masks must not overwrite that selection.
    } elseif {$st($w,selectionObject) ne "" && [dict exists $payload selection_descriptor]} {
        _restorePointSelectionDescriptor $w [dict get $payload selection_descriptor]
    } elseif {$st($w,selectionObject) ne "" && [dict exists $payload selected_indices]} {
        ::GX::Native2D::core selection_replace $st($w,selectionScene) $st($w,selectionObject) [dict get $payload selected_indices]
    }
    set st($w,status) "Restored [dict size $st($w,curves)] workspace curves from this Session."
}
proc ::GX::CurveWorkbench::_changed {w} {
    variable st
    if {[catch {_updateCompositionPreview $w} previewError]} {set st($w,status) "Composition preview unavailable: $previewError"}
    _curveList $w;_pointList $w
    catch {_metrics $w}
    _save $w;_draw $w
}
proc ::GX::CurveWorkbench::_selectionScene {w} {
    variable st
    _cancelDirectionDrag $w
    _partCancel $w
    _cancelPointDrag $w
    _pointSyncCancel $w
    incr st($w,selectionEpoch)
    # Compatibility names now alias the authoritative scene and focused object;
    # focus changes never copy geometry or replace multi-curve selection.
    if {$st($w,selectionScene) ne {}&&$st($w,selectionScene)!=$st($w,scene)} {::GX::Native2D::core destroy $st($w,selectionScene)}
    set st($w,selectionScene) $st($w,scene);set st($w,selectionObject) {}
    if {[dict exists $st($w,curves) $st($w,active)]} {set st($w,selectionObject) [dict get [_record $w $st($w,active)] native]}
    set st($w,pointPageStart) 0;set st($w,pointTableSignature) {}
}
proc ::GX::CurveWorkbench::_selected {w} {
    variable st
    if {$st($w,selectionObject) eq ""} {return {}}
    if {[_bulkRecord [_record $w $st($w,active)]]} {return [::GX::Native2D::core selected $st($w,selectionScene) $st($w,selectionObject) $st($w,pointPageStart) [expr {min(200,[_pointCount [_record $w $st($w,active)]]-$st($w,pointPageStart))}]]}
    return [::GX::Native2D::core selected $st($w,selectionScene) $st($w,selectionObject)]
}
proc ::GX::CurveWorkbench::_selectedRange {w} {
    set indices [_selected $w]
    if {![llength $indices]} {error "Select two or more points to define a range"}
    set first [lindex $indices 0];set last [lindex $indices end]
    if {$first==$last} {error "Select at least two points"}
    return [list $first $last]
}
proc ::GX::CurveWorkbench::_operation {w action} {
    variable st
    set id [_editable $w];set record [_record $w $id]
    set native [dict get $record native];set samples [dict get $record samples]
    set n [llength $samples];set before [_snapshotIds $w [list $id]]
    switch -- $action {
        keep - remove - before - after {
            if {$action in {before after}} {
                set indices [_selected $w]
                if {![llength $indices]} {error "Select a trim point"}
                set first [lindex $indices 0];set last [lindex $indices end]
            } else {lassign [_selectedRange $w] first last}
            if {$action eq "keep"} {
                ::GX::Native2D::core keep $st($w,scene) $native $first $last
                set samples [lrange $samples $first $last]
            } elseif {$action eq "remove"} {
                if {$n-($last-$first+1)<2} {error "Removing this range would leave fewer than two points"}
                ::GX::Native2D::core remove_range $st($w,scene) $native $first $last
                set samples [concat [lrange $samples 0 [expr {$first-1}]] [lrange $samples [expr {$last+1}] end]]
            } elseif {$action eq "before"} {
                ::GX::Native2D::core keep $st($w,scene) $native $first [expr {$n-1}]
                set samples [lrange $samples $first end]
            } else {
                ::GX::Native2D::core keep $st($w,scene) $native 0 $last
                set samples [lrange $samples 0 $last]
            }
            dict set record samples $samples
        }
        reverse {
            ::GX::Native2D::core reverse $st($w,scene) $native
            dict set record samples [lreverse $samples]
        }
        delete_points {
            set indices [_selected $w]
            if {![llength $indices]} {error "Select one or more points"}
            if {$n-[llength $indices]<2} {error "A curve needs at least two points"}
            foreach index [lreverse $indices] {
                ::GX::Native2D::core remove_point $st($w,scene) $native $index
                set samples [lreplace $samples $index $index]
            }
            dict set record samples $samples
        }
        default {error "Unknown edit operation $action"}
    }
    dict set record edited 1
    dict lappend record operations $action
    dict set record breaks [::GX::Native2D::core breaks $st($w,scene) $native]
    dict set st($w,curves) $id $record
    _selectionScene $w
    _history $w $before [list $id]
}
proc ::GX::CurveWorkbench::_numericEdit {w} {
    variable st
    set id [_editable $w];set indices [_selected $w]
    if {[llength $indices]!=1} {error "Select exactly one point"}
    set before [_snapshotIds $w [list $id]]
    set p [_coordinatePoint $w $id [list [_finite $st($w,editX) X] [_finite $st($w,editY) Y]] inverse]
    ::GX::Native2D::core set_point $st($w,scene) [dict get [_record $w $id] native] [lindex $indices 0] $p
    ::GX::Native2D::core set_point $st($w,selectionScene) $st($w,selectionObject) [lindex $indices 0] $p
    _syncSamples $w $id
    _history $w $before [list $id]
}
proc ::GX::CurveWorkbench::_reorder {w delta} {
    variable st
    set id [_editable $w];set indices [_selected $w]
    if {[llength $indices]!=1} {error "Select exactly one point to reorder"}
    set from [lindex $indices 0];set r [_record $w $id];set n [llength [dict get $r samples]]
    if {[dict get $r breaks] ne {}} {error "Reorder one connected fragment at a time; split the composition first"}
    set to [expr {$from+$delta}]
    if {$to<0||$to>=$n} {error "Point is already at the end of the path"}
    set before [_snapshotIds $w [list $id]]
    ::GX::Native2D::core move_point $st($w,scene) [dict get $r native] $from $to
    set samples [dict get $r samples];set p [lindex $samples $from]
    set samples [lreplace $samples $from $from];set samples [linsert $samples $to $p]
    dict set r samples $samples
    dict set r edited 1;dict lappend r operations "reorder:$from:$to"
    dict set st($w,curves) $id $r;_selectionScene $w
    ::GX::Native2D::core select $st($w,selectionScene) $st($w,selectionObject) $to replace
    _history $w $before [list $id]
}
proc ::GX::CurveWorkbench::_selectX {w} {
    variable st
    set id [_active $w]
    set lo [_finite $st($w,xMin) "X minimum"];set hi [_finite $st($w,xMax) "X maximum"]
    if {$lo>$hi} {error "X minimum exceeds maximum"}
    lassign [_coordinateValues $w $id x [list $lo $hi] inverse] lo hi
    if {$lo>$hi} {set swap $lo;set lo $hi;set hi $swap}
    ::GX::Native2D::core select_x $st($w,selectionScene) $st($w,selectionObject) $lo $hi replace
    _pointList $w;_draw $w
}
proc ::GX::CurveWorkbench::_snapToReference {w} {
    variable st
    set id [_editable $w];set reference $st($w,reference);set indices [_selected $w]
    if {$reference eq "" || ![dict exists $st($w,curves) $reference] || $reference eq $id} {error "Choose a reference curve"}
    if {[llength $indices]!=1} {error "Select one control point to snap"}
    set r [_record $w $id];set before [_snapshotIds $w [list $id]]
    ::GX::Native2D::core snap_to_curve $st($w,scene) [dict get $r native] [lindex $indices 0] [dict get [_record $w $reference] native]
    _syncSamples $w $id
    set r [_record $w $id];dict lappend r operations "snap_to_reference:$reference:[lindex $indices 0]";dict set st($w,curves) $id $r
    _selectionScene $w
    ::GX::Native2D::core select $st($w,selectionScene) $st($w,selectionObject) [lindex $indices 0] replace
    _history $w $before [list $id]
}
proc ::GX::CurveWorkbench::_split {w} {
    variable st
    set record [_record $w [_active $w]]
    if {[dict exists $record sketch_definition]&&[dict get $record sketch_definition family] eq "path"} {tailcall _pathSplit $w}
    set parent [_editable $w];set r [_record $w $parent];set selected [_selected $w]
    if {[llength $selected]!=1} {error "Select one interior point to split"}
    set index [lindex $selected 0];set n [llength [dict get $r samples]]
    if {$index<1||$index>=$n-1} {error "Split point must be inside the curve"}
    lassign [::GX::Native2D::core split $st($w,scene) [dict get $r native] $index] a b
    set left [_newId $w];set right [_newId $w]
    set ids [list $left $right];set before [_snapshotIds $w $ids]
    set ancestors [concat [list [dict remove $r native samples ancestors]] [dict get $r ancestors]]
    set l [dict replace $r id $left name "[dict get $r name] · A" samples [lrange [dict get $r samples] 0 $index] parents [list $parent] ancestors $ancestors operations [concat [dict get $r operations] "split:0:$index"] edited 1 locked 0 breaks [::GX::Native2D::core breaks $st($w,scene) $a]]
    set q [dict replace $r id $right name "[dict get $r name] · B" samples [lrange [dict get $r samples] $index end] parents [list $parent] ancestors $ancestors operations [concat [dict get $r operations] "split:$index:[expr {$n-1}]"] edited 1 locked 0 breaks [::GX::Native2D::core breaks $st($w,scene) $b]]
    _addRecord $w $l $a;_addRecord $w $q $b
    set st($w,active) $left;_selectionScene $w
    _history $w $before $ids
}
proc ::GX::CurveWorkbench::_addFragment {w} {
    variable st
    set id [_active $w];lassign [_selectedRange $w] first last
    lappend st($w,fragments) [list $id $first $last 0]
    _fragmentList $w;_updateCompositionPreview $w;_draw $w
}
proc ::GX::CurveWorkbench::_fragmentMaterialize {w fragment} {
    variable st
    lassign $fragment id first last reversed
    set r [_record $w $id]
    set controls [dict get $r samples]
    if {$first<0 || $last>=[llength $controls] || $first>=$last} {
        error "A composition fragment is stale; remove and add it again"
    }
    if {[dict get $r representation] ne "spline"} {
        set native [::GX::Native2D::core extract $st($w,scene) [dict get $r native] $first $last]
        return [list $native [lrange $controls $first $last]]
    }
    # Native2D owns spline evaluation. Materialize once when the composition
    # changes; the resulting sampled path is the preview and committed path.
    set subdivisions 16
    set evaluated [::GX::Native2D::core spline $st($w,scene) [dict get $r native] $subdivisions]
    set coords [lrange $evaluated [expr {$first*$subdivisions}] [expr {$last*$subdivisions}]]
    set samples {}
    set i 0
    foreach xy $coords {
        lassign $xy x y
        if {$i%$subdivisions==0} {
            set p [lindex $controls [expr {$first+$i/$subdivisions}]]
            dict set p x $x;dict set p y $y
        } else {
            set p [dict create x $x y $y row -1 order "" point_id "spline_sample:$id:$first:$i"]
        }
        lappend samples $p
        incr i
    }
    set native [::GX::Native2D::core add $st($w,scene) $coords]
    return [list $native $samples]
}
proc ::GX::CurveWorkbench::_updateCompositionPreview {w} {
    variable st
    if {$st($w,previewNative) ne ""} {::GX::Native2D::core delete $st($w,scene) $st($w,previewNative);set st($w,previewNative) ""}
    set st($w,previewBreaks) {}
    if {![llength $st($w,fragments)]} return
    set pieces {};set created {}
    try {
        foreach fragment $st($w,fragments) {
            lassign $fragment id first last reversed
            lassign [_fragmentMaterialize $w $fragment] native samples
            lappend created $native;lappend pieces [list $native $reversed [expr {[llength $pieces]>0 && !$st($w,bridge)}]]
        }
        set st($w,previewNative) [::GX::Native2D::core concat $st($w,scene) $pieces]
        set st($w,previewBreaks) [::GX::Native2D::core breaks $st($w,scene) $st($w,previewNative)]
        ::GX::Native2D::core visible $st($w,scene) $st($w,previewNative) 0
    } finally {foreach native $created {catch {::GX::Native2D::core delete $st($w,scene) $native}}}
}
proc ::GX::CurveWorkbench::_fragmentList {w} {
    variable st
    if {![winfo exists $w.leftScroll.viewport.content.compose.list]} return
    $w.leftScroll.viewport.content.compose.list delete 0 end
    foreach fragment $st($w,fragments) {
        lassign $fragment id first last reversed
        set name [dict get [_record $w $id] name]
        $w.leftScroll.viewport.content.compose.list insert end "$name · $first–$last[expr {$reversed ? " (reversed)" : ""}]"
    }
}
proc ::GX::CurveWorkbench::_fragmentEdit {w action} {
    variable st
    set i [lindex [$w.leftScroll.viewport.content.compose.list curselection] 0]
    if {$i eq ""} {error "Select a fragment in the composition list"}
    if {$action eq "remove"} {set st($w,fragments) [lreplace $st($w,fragments) $i $i]} elseif {$action eq "up" && $i>0} {
        set f [lindex $st($w,fragments) $i];set st($w,fragments) [lreplace $st($w,fragments) $i $i];set st($w,fragments) [linsert $st($w,fragments) [expr {$i-1}] $f]
    } elseif {$action eq "down" && $i<[llength $st($w,fragments)]-1} {
        set f [lindex $st($w,fragments) $i];set st($w,fragments) [lreplace $st($w,fragments) $i $i];set st($w,fragments) [linsert $st($w,fragments) [expr {$i+1}] $f]
    } elseif {$action eq "reverse"} {set f [lindex $st($w,fragments) $i];lset f 3 [expr {![lindex $f 3]}];lset st($w,fragments) $i $f}
    _fragmentList $w;_updateCompositionPreview $w;_draw $w
}
proc ::GX::CurveWorkbench::_compose {w} {
    variable st
    set fragments $st($w,fragments)
    if {![llength $fragments]} {error "Add at least one selected fragment"}
    set pieces {};set samples {};set parents {};set operations {};set created {}
    try {
        foreach fragment $fragments {
            lassign $fragment source first last reversed
            set r [_record $w $source]
            lassign [_fragmentMaterialize $w $fragment] native part
            lappend created $native;lappend pieces [list $native $reversed [expr {[llength $pieces]>0 && !$st($w,bridge)}]]
            if {$reversed} {set part [lreverse $part]}
            set samples [concat $samples $part]
            lappend parents $source;lappend operations "fragment:$source:$first:$last:$reversed:[dict get $r representation]"
        }
        set native [::GX::Native2D::core concat $st($w,scene) $pieces]
    } finally {foreach obj $created {catch {::GX::Native2D::core delete $st($w,scene) $obj}}}
    set source [lindex $parents 0];set base [_record $w $source]
    set r [_newRecord $w $st($w,composeName) $samples [dict get $base source] [dict get $base x] [dict get $base y] "" "" "" "" $parents $operations]
    dict set r breaks [::GX::Native2D::core breaks $st($w,scene) $native]
    if {$st($w,bridge)} {dict lappend r operations explicit_straight_bridge}
    set id [dict get $r id];set before [_snapshotIds $w [list $id]]
    _addRecord $w $r $native;set st($w,active) $id;set st($w,fragments) {};_fragmentList $w;_updateCompositionPreview $w;_selectionScene $w
    _history $w $before [list $id]
}
proc ::GX::CurveWorkbench::_makeSpline {w} {
    variable st
    set source [_active $w];set r [_record $w $source]
    set indices [_selected $w]
    if {[llength $indices]<2} {error "Select at least two source points for spline controls"}
    foreach break [dict get $r breaks] {if {$break>=[lindex $indices 0] && $break<[lindex $indices end]} {error "Spline controls cannot cross a disconnected gap"}}
    set controls [lmap i $indices {lindex [dict get $r samples] $i}]
    set derived [_newRecord $w "[dict get $r name] spline" $controls [dict get $r source] [dict get $r x] [dict get $r y] [dict get $r filter] [dict get $r filter_value] [dict get $r family] [dict get $r order] [list $source] [list "spline_controls:$indices"] spline]
    set id [dict get $derived id];set before [_snapshotIds $w [list $id]]
    _addRecord $w $derived;set st($w,active) $id;set st($w,reference) $source;_selectionScene $w
    _history $w $before [list $id]
}
proc ::GX::CurveWorkbench::_rename {w} {
    variable st
    set id [_active $w];set name [string trim $st($w,rename)]
    if {$name eq ""} {error "Enter a curve name"}
    set before [_snapshotIds $w [list $id]];set r [_record $w $id]
    dict set r name $name;dict set st($w,curves) $id $r;_history $w $before [list $id]
}
proc ::GX::CurveWorkbench::_makeLinear {w} {
    variable st
    set source [_active $w];set r [_record $w $source];set indices [_selected $w]
    if {[llength $indices]<2} {error "Select at least two source points"}
    foreach break [dict get $r breaks] {if {$break>=[lindex $indices 0] && $break<[lindex $indices end]} {error "Linear controls cannot cross a disconnected gap"}}
    set controls [lmap i $indices {lindex [dict get $r samples] $i}]
    set derived [_newRecord $w "[dict get $r name] simplified" $controls [dict get $r source] [dict get $r x] [dict get $r y] [dict get $r filter] [dict get $r filter_value] [dict get $r family] [dict get $r order] [list $source] [list "linear_controls:$indices"] linear]
    set id [dict get $derived id];set before [_snapshotIds $w [list $id]]
    _addRecord $w $derived;set st($w,active) $id;set st($w,reference) $source;_selectionScene $w
    _history $w $before [list $id]
}
proc ::GX::CurveWorkbench::_evaluatedObject {w id} {
    variable st
    set r [_record $w $id]
    if {[dict get $r breaks] ne {}} {error "Comparison of a curve with disconnected fragments requires comparing its fragments separately"}
    if {[dict get $r representation] ne "spline"} {return [list [dict get $r native] 0]}
    set points [::GX::Native2D::core spline $st($w,scene) [dict get $r native] 16]
    return [list [::GX::Native2D::core add $st($w,scene) $points] 1]
}
proc ::GX::CurveWorkbench::_compare {w} {
    variable st
    set active [_active $w];set reference $st($w,reference)
    if {$reference eq "" || ![dict exists $st($w,curves) $reference] || $reference eq $active} {error "Choose a different reference curve"}
    lassign [_evaluatedObject $w $reference] a temporaryA
    try {
        lassign [_evaluatedObject $w $active] b temporaryB
        try {set result [::GX::native2DComparison $st($w,scene) $a $b $st($w,compareMethod) 4096 [_coordinateUnits [_record $w $reference]] [_coordinateUnits [_record $w $active]] [dict create producer viewer.curve_workbench reference $reference target $active evaluated_representation [_comparisonRepresentation $w $reference $active]]]} finally {if {$temporaryB} {::GX::Native2D::core delete $st($w,scene) $b}}
    } finally {if {$temporaryA} {::GX::Native2D::core delete $st($w,scene) $a}}
    set st($w,residual) $result
    _drawResidual $w
    set st($w,status) [::GX::StatisticsV1::report [dict get $result statistics reference] {n max_abs_error mae rmse}]
    _draw $w
    return $result
}
proc ::GX::CurveWorkbench::_metrics {w} {
    variable st
    set id $st($w,active)
    if {$id eq "" || ![dict exists $st($w,curves) $id]} {set st($w,metricText) "No active curve";return}
    set activeRecord [_record $w $id]
    _coordinateMetricPolicy $w
    if {$st($w,metric) eq "signed_y_residual"} {
        set st($w,metricText) {Signed Y residual: choose a reference and Compare by X. No mixed-axis physical length is defined.}
        if {$st($w,residual) ne {}&&[dict exists $st($w,comparisonConfig) method]&&[dict get $st($w,comparisonConfig) method] eq "x"&&[dict get $st($w,comparisonConfig) target] eq $id} {
            set st($w,metricText) "Signed Y residual: [::GX::StatisticsV1::report [dict get $st($w,residual) statistics reference] {n max_abs_error mae rmse}]"
        }
        return
    }
    if {[dict get $activeRecord representation] eq "spline"} {lassign [_evaluatedObject $w $id] native temporary} else {set native [dict get $activeRecord native];set temporary 0}
    set metric $st($w,metric)
    try {
        if {$metric in {length signed_area length_span_ratio}} {
            set displayUnit [dict get [_coordinateAxis $w $id x] display_unit]
            set m [::GX::native2DMetrics $st($w,scene) $native [_coordinateUnits $activeRecord] [dict create output_units [lrepeat 2 $displayUnit]]]
        } else {set m [::GX::Native2D::core metrics $st($w,scene) $native]}
    } finally {if {$temporary} {::GX::Native2D::core delete $st($w,scene) $native}}
    set metric $st($w,metric)
    if {$metric eq "signed_area" && ![dict get $m closed]} {error "Enclosed area is defined only for a connected closed curve"}
    set value [dict get $m $metric]
    set target [string trim $st($w,target)]
    lassign [_coordinateUnits $activeRecord] ux uy
    set unit [expr {$metric eq "span_y"?$uy:$metric eq "length_span_ratio"?"1":$metric eq "signed_area"?"$ux^2":$ux}]
    if {$metric in {length signed_area length_span_ratio}} {set unit [expr {$metric eq "length_span_ratio"?"1":$metric eq "signed_area"?"[dict get $m unit]^2":[dict get $m unit]}]}
    set message "[dict get [_record $w $id] name]: $metric = [format %.7g $value] $unit (geometry coordinates) · [_pointCount [_record $w $id]] exact controls/points"
    if {$target ne ""} {append message " · target error = [format %.7g [expr {$value-[_finite $target Target]}]]"}
    if {$st($w,residual) ne {}} {append message " · max residual [format %.5g [::GX::StatisticsV1::scalarValue [dict get $st($w,residual) statistics reference] max_abs_error]] · RMSE [format %.5g [::GX::StatisticsV1::scalarValue [dict get $st($w,residual) statistics reference] rmse]]"}
    if {[dict get $activeRecord breaks] ne {}} {append message " · disconnected fragments; gaps excluded from length"}
    set st($w,metricText) $message
}
proc ::GX::CurveWorkbench::_declare {writer id unit role {dtype float64}} {
    ::GX::datasetPublicationV2DeclareVariable $writer $id [dict create name $id unit $unit dtype $dtype rank 1 dimension_ids row coordinate_role $role axis_kind explicit]
}
proc ::GX::CurveWorkbench::publish {w datasetId {ids {}}} {
    variable st
    if {[string trim $datasetId] eq ""} {error "Enter a new Dataset ID"}
    set datasetId [::GX::datasetPublicationV2RequestedId $datasetId]
    if {$datasetId in [::GX::sessionInspectionDatasetIds]} {error "Dataset '$datasetId' already exists; choose a new ID to preserve source and previous results"}
    if {$ids eq {}} {set ids [list [_active $w]]}
    set xs {};set ys {};set sourceRows {};set pointIds {};set orders {};set segmentIds {};set sources {};set bindings {};set provenance {};set anySpline 0
    foreach id $ids {
        set r [_record $w $id];set source [dict get $r source]
        if {$source ne "" && $source ni $sources} {lappend sources $source}
        foreach field {x y filter family order} {set v [dict get $r $field];if {$v ne ""} {lappend bindings "$source:$v"}}
        if {[dict exists $r ancestors]} {
            foreach ancestor [dict get $r ancestors] {
                set parentSource [dict get $ancestor source]
                if {$parentSource ne "" && $parentSource ni $sources} {lappend sources $parentSource}
                foreach field {x y filter family order} {set v [dict get $ancestor $field];if {$v ne ""} {lappend bindings "$parentSource:$v"}}
            }
        }
        set samples [dict get $r samples]
        if {[dict get $r representation] eq "spline"} {
            set coords [::GX::Native2D::core spline $st($w,scene) [dict get $r native] 16]
            set samples [lmap p $coords {dict create x [lindex $p 0] y [lindex $p 1] row -1 order "" point_id spline_sample}]
            set anySpline 1
        }
        set original $samples;set samples {};set n [llength $original]
        for {set start 0} {$start<$n} {incr start 4096} {
            foreach index [::GX::Native2D::core marker_order $st($w,scene) [dict get $r native] $n $start [expr {min(4096,$n-$start)}]] {lappend samples [lindex $original $index]}
        }
        set direction [::GX::Native2D::core direction_marker $st($w,scene) [dict get $r native]]
        dict set r direction $direction
        set breaks [dict get $r breaks]
        if {![dict get $direction forward] && [dict get $r representation] ne "spline"} {set breaks [lmap at $breaks {expr {$n-2-$at}}]}
        set part 1;set index 0
        foreach p $samples {
            if {$index>0 && [expr {$index-1}] in $breaks} {incr part}
            lappend xs [dict get $p x];lappend ys [dict get $p y]
            lappend sourceRows [dict get $p row];lappend pointIds [dict get $p point_id];lappend orders [dict get $p order]
            lappend segmentIds "$id:$part";incr index
        }
        lappend provenance [dict remove $r native samples]
    }
    if {![llength $xs]} {error "There are no points to publish"}
    set first [_record $w [lindex $ids 0]]
    lassign [_coordinateUnits $first] xUnit yUnit
    foreach id $ids {
        if {[_coordinateUnits [_record $w $id]] ne [list $xUnit $yUnit]} {error "Selected curves have incompatible coordinate units; convert them to a common working unit before publication"}
    }
    set compared [expr {[llength $ids]==1 && $st($w,comparisonConfig) ne {} && [lindex $ids 0] eq [dict get $st($w,comparisonConfig) target] && $st($w,residual) ne {}}]
    set residualSummary [expr {$compared ? [dict remove $st($w,residual) rows] : {}}]
    set residualMethod [expr {$compared ? $st($w,compareMethod) : {}}]
    set details [dict create workspace_curve_ids $ids curves $provenance comparison_method $residualMethod residual_summary $residualSummary metric $st($w,metric) metric_target $st($w,target) external_feedback $st($w,externalFeedback)]
    set def [dict create dataset_id [::GX::datasetPublicationV2RequestedId $datasetId curve] contract table.generic storage auto expected_rows [llength $xs] estimated_numeric_bytes [expr {32*[llength $xs]}] producer_version [::GX::moduleField viewer.curve_workbench version] source "Curve Workbench" provenance $details source_dataset_ids $sources source_variable_ids [lsort -unique $bindings]]
    dict set def structured_metadata [dict create dataset.display_name "Curve Workbench: [dict get $first name]" curve_workbench.workspace_curve_ids [join $ids {;}] curve_workbench.source_dataset_ids [join $sources {;}] curve_workbench.source_variable_ids [join [lsort -unique $bindings] {;}] curve_workbench.provenance $details curve_workbench.residual_method $residualMethod curve_workbench.residual_max [expr {$compared ? [::GX::StatisticsV1::scalarValue [dict get $st($w,residual) statistics reference] max_abs_error] : ""}] curve_workbench.residual_rmse [expr {$compared ? [::GX::StatisticsV1::scalarValue [dict get $st($w,residual) statistics reference] rmse] : ""}] curve_workbench.external_feedback $st($w,externalFeedback)]
    dict set def structured_metadata [dict merge [dict get $def structured_metadata] [_publicationSketchMetadata $w $ids]]
    dict set def structured_metadata [dict merge [dict get $def structured_metadata] [_coordinatePublicationMetadata $w $ids]]
    if {$compared} {dict set def structured_metadata [dict merge [dict get $def structured_metadata] [::GX::StatisticsV1::publicationMetadata [dict get $st($w,residual) statistics]]]}
    set plan [::GX::datasetPublicationV2Prepare [_session] viewer.curve_workbench $def]
    set writer ""
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 [dict create extendible 1]
        _declare $writer x $xUnit coordinate
        _declare $writer y $yUnit data
        _declare $writer source_row_ordinal "" data int32
        _declare $writer point_identity "" data string
        _declare $writer source_order "" data string
        set values [dict create x $xs y $ys source_row_ordinal $sourceRows point_identity $pointIds source_order $orders]
        if {[llength $ids]>1 || [llength [lsort -unique $segmentIds]]>1} {
            _declare $writer segment_id "" data string
            dict set values segment_id $segmentIds
        }
        ::GX::datasetPublicationV2Append $writer row $values
        set result [::GX::datasetPublicationV2Finalize $writer]
    } on error {err opts} {
        if {$writer ne ""} {catch {::GX::datasetPublicationV2Abort $writer}}
        return -options $opts $err
    }
    set st($w,status) "Published $datasetId: [llength $xs] points from [llength $ids] curve(s)"
    return $result
}
proc ::GX::CurveWorkbench::_publishSelected {w} {
    variable st
    set ids [$w.leftScroll.viewport.content.curves selection]
    if {![llength $ids]} {set ids [list [_active $w]]}
    return [publish $w $st($w,resultId) $ids]
}
proc ::GX::CurveWorkbench::_pointList {w} {
    variable st
    if {![winfo exists $w.leftScroll.viewport.content.points]} return
    set tree $w.leftScroll.viewport.content.points
    if {$st($w,active) eq "" || ![dict exists $st($w,curves) $st($w,active)]} {
        $tree delete [$tree children {}];set st($w,pointTableSignature) {};return
    }
    set selected [_selected $w];set index 0
    set signature [list $st($w,active) [dict get [_record $w $st($w,active)] samples] [_coordinateKey $w $st($w,active)]]
    # Selection-only changes do not destroy/reinsert table rows, preserving
    # scrolling, keyboard range anchors and queued virtual-event consistency.
    if {$signature ne $st($w,pointTableSignature)} {
        $tree delete [$tree children {}]
        foreach p [lindex $signature 1] {
            lassign [_coordinatePoint $w $st($w,active) [list [dict get $p x] [dict get $p y]]] dx dy
            $tree insert {} end -id "p$index" -values [list $index [format %.8g $dx] [format %.8g $dy] [dict get $p row]]
            incr index
        }
        set st($w,pointTableSignature) $signature
    }
    set rows [lmap i $selected {format p%d $i}]
    if {[$tree selection] ne $rows} {$tree selection set $rows}
    if {[llength $selected]} {$tree see "p[lindex $selected 0]"}
    if {[llength $selected]==1} {
        set p [lindex [dict get [_record $w $st($w,active)] samples] [lindex $selected 0]]
        lassign [_coordinatePoint $w $st($w,active) [list [dict get $p x] [dict get $p y]]] st($w,editX) st($w,editY)
    }
}
proc ::GX::CurveWorkbench::_pointTreeSelect {w} {
    variable st
    if {[info exists st($w,token)]&&$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {_pointSyncCancel $w;set st($w,status) "Session lifetime changed; reopen Curve Workbench before selecting points.";return}
    if {![info exists st($w,selectionObject)] || $st($w,selectionObject) eq "" || $st($w,pointSyncRunning)} return
    set indices [lsort -integer [lmap row [$w.leftScroll.viewport.content.points selection] {string range $row 1 end}]]
    # Native -> table virtual events are advisory. In particular, a canvas
    # press begins a native drag before its queued TreeviewSelect is delivered.
    if {$indices eq [_pointTableSelected $w]} {
        _pointSyncCancel $w
        return
    }
    set st($w,pointSyncPending) [list $st($w,active) $st($w,selectionEpoch) $indices]
    _pointSyncSchedule $w
}
proc ::GX::CurveWorkbench::_pointSyncCancel {w} {
    variable st
    if {[info exists st($w,pointSyncAfter)] && $st($w,pointSyncAfter) ne ""} {after cancel $st($w,pointSyncAfter)}
    set st($w,pointSyncAfter) "";set st($w,pointSyncPending) {}
}
proc ::GX::CurveWorkbench::_pointSyncSchedule {w} {
    variable st
    if {$st($w,pointSyncAfter) eq "" && $st($w,pointSyncPending) ne {}} {
        set st($w,pointSyncAfter) [after idle [list ::GX::CurveWorkbench::_pointSyncApply $w]]
    }
}
proc ::GX::CurveWorkbench::_pointSyncApply {w} {
    variable st
    if {![info exists st($w,pointSyncAfter)]} return
    if {$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {_pointSyncCancel $w;set st($w,status) "Session lifetime changed; pending point selection was rejected. Reopen Curve Workbench.";return}
    if {$st($w,pointSyncAfter) ne ""} {after cancel $st($w,pointSyncAfter);set st($w,pointSyncAfter) ""}
    if {$st($w,pointSyncRunning) || $st($w,pointSyncPending) eq {}} return
    lassign $st($w,pointSyncPending) active epoch indices
    if {$active ne $st($w,active) || $epoch != $st($w,selectionEpoch) || $st($w,selectionObject) eq ""} {_pointSyncCancel $w;return}
    # Keep the latest request pending until release/cancel; never spin idle
    # callbacks or mutate the engine's active drag snapshot.
    if {[::GX::Native2D::core drag_active $st($w,selectionScene)]} return
    set st($w,pointSyncRunning) 1
    try {
        if {$indices ne [_pointTableSelected $w]} {
            set r [_record $w $active]
            if {[_pointCount $r]>200} {::GX::Native2D::core selection_patch $st($w,selectionScene) $st($w,selectionObject) $st($w,pointPageStart) [expr {min(200,[_pointCount $r]-$st($w,pointPageStart))}] $indices} else {::GX::Native2D::core selection_replace $st($w,selectionScene) $st($w,selectionObject) $indices}
            incr st($w,pointSyncCommits)
        }
        set st($w,pointSyncPending) {}
        if {[dict get [::GX::Native2D::core selection_summary $st($w,selectionScene) $st($w,selectionObject)] count]==1&&[llength $indices]==1} {
            set p [_sampleAt $w $active [lindex $indices 0]]
            set st($w,editX) [dict get $p x];set st($w,editY) [dict get $p y]
        }
        _pointList $w;_draw $w
    } finally {set st($w,pointSyncRunning) 0}
}
proc ::GX::CurveWorkbench::_cancelPointDrag {w} {
    variable st
    if {![info exists st($w,selectionScene)] || $st($w,selectionScene) eq ""} return
    if {![::GX::Native2D::core drag_active $st($w,selectionScene)]} return
    ::GX::Native2D::core drag_cancel $st($w,selectionScene)
    set id [dict get $st($w,drag) curve_id]
    set r [_record $w $id]
    # Restore the complete candidate atomically, including joined selected
    # points whose relationship would reject a sequential one-point restore.
    ::GX::Native2D::core replace $st($w,scene) [dict get $r native] [_xy [dict get $r samples]]
    set st($w,drag) {}
}
proc ::GX::CurveWorkbench::_cancelGesture {w} {
    variable st
    _partCancel $w
    _cancelPointDrag $w
    _cancelDirectionDrag $w
    set st($w,drag) {};set st($w,box) {}
    _pointSyncApply $w
    _pointList $w
    _draw $w
    set st($w,status) "Gesture cancelled."
}
proc ::GX::CurveWorkbench::_cancelDirectionDrag {w} {
    variable st
    if {![info exists st($w,drag)] || $st($w,drag) eq {} || [dict get $st($w,drag) mode] ne "direction"} return
    set id [dict get $st($w,drag) curve_id]
    set before [dict get $st($w,drag) before $id direction]
    if {[dict exists $st($w,curves) $id]} {
        ::GX::Native2D::core direction_marker $st($w,scene) [dict get [_record $w $id] native] $before
    }
    set st($w,drag) {}
}
proc ::GX::CurveWorkbench::_directionToggle {w} {
    variable st
    set id [_active $w];set before [_snapshotIds $w [list $id]]
    ::GX::Native2D::core direction_marker $st($w,scene) [dict get [_record $w $id] native] [dict create present 1 visible $st($w,directionShown)]
    _history $w $before [list $id]
}
proc ::GX::CurveWorkbench::_directionFlip {w} {
    variable st
    set id [_active $w];set native [dict get [_record $w $id] native]
    set marker [::GX::Native2D::core direction_marker $st($w,scene) $native]
    set before [_snapshotIds $w [list $id]]
    ::GX::Native2D::core direction_marker $st($w,scene) $native [dict create forward [expr {![dict get $marker forward]}]]
    _history $w $before [list $id]
    set st($w,status) "Intended direction flipped. Dataset publication follows this direction."
}
proc ::GX::CurveWorkbench::_directionOpen {w} {
    variable st
    set id [_active $w]
    set marker [::GX::Native2D::core direction_marker $st($w,scene) [dict get [_record $w $id] native]]
    set d $w.direction
    if {[winfo exists $d]} {destroy $d}
    toplevel $d;wm title $d "Curve direction — [dict get [_record $w $id] name]"
    wm transient $d $w
    grid columnconfigure $d 1 -weight 1
    set fields [list visible [dict create type boolean label "Show direction"] forward [dict create type choice label "Intended direction" values {Forward Reverse}] fraction [dict create type number label "Position along path (%)" min 0 max 100] offset_px [dict create type number label "Normal offset (px)" min -4096 max 4096] length_px [dict create type number label "Arrow length (px)" min 4 max 4096] line_width [dict create type number label "Line width (px)" min .1 max 64] color [dict create type color label "Arrow color / opacity" alpha 1]]
    set record [_record $w $id]
    if {[dict exists $record sketch_definition]&&[dict get $record sketch_definition family] in {compound composite_path}} {dict unset fields visible;dict unset fields forward;wm title $d {Default subpath arrow appearance — enable arrows contextually}}
    set row 0
    foreach {key descriptor} $fields {
        set value [dict get $marker $key]
        if {$key eq "forward"} {set value [expr {$value ? "Forward" : "Reverse"}]}
        if {$key eq "fraction"} {set value [expr {100*$value}]}
        if {$key eq "color"} {set value [::GX::uiFieldColorFromRGBA $value]}
        set st($w,direction.$key) $value
        ttk::label $d.l$row -text [dict get $descriptor label]
        ::GX::uiFieldCreate $d.f$row $descriptor ::GX::CurveWorkbench::st($w,direction.$key)
        grid $d.l$row -row $row -column 0 -sticky w -padx 8 -pady 5
        grid $d.f$row -row $row -column 1 -sticky ew -padx 8 -pady 5
        incr row
    }
    ttk::label $d.help -text "Drag the arrow along the curve. Escape cancels the drag. Flip sets the row order of an explicitly published Dataset; source geometry remains unchanged." -wraplength 540
    grid $d.help -row $row -column 0 -columnspan 2 -sticky ew -padx 8 -pady 8;incr row
    ttk::frame $d.actions
    ttk::button $d.actions.apply -text Apply -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_directionApply $w $id $fields]]
    ttk::button $d.actions.close -text Close -command [list destroy $d]
    pack $d.actions.apply $d.actions.close -side left -padx 4
    grid $d.actions -row $row -column 0 -columnspan 2 -sticky e -padx 8 -pady 8
    bind $d <Escape> [list destroy $d]
}
proc ::GX::CurveWorkbench::_directionApply {w id fields} {
    variable st
    if {[_active $w] ne $id} {error "Active curve changed; reopen Direction settings"}
    set changes {};set row 0
    foreach {key descriptor} $fields {
        if {![::GX::uiFieldCommit $w.direction.f$row]} {error $::GX::UiField::errors($w.direction.f$row)}
        set value [::GX::uiFieldNormalize $descriptor $st($w,direction.$key)]
        if {$key eq "forward"} {set value [expr {$value eq "Forward"}]}
        if {$key eq "fraction"} {set value [expr {$value/100.0}]}
        if {$key eq "color"} {set value [::GX::uiFieldColorToRGBA $value]}
        dict set changes $key $value;incr row
    }
    set before [_snapshotIds $w [list $id]]
    ::GX::Native2D::core direction_marker $st($w,scene) [dict get [_record $w $id] native] $changes
    _history $w $before [list $id]
}
proc ::GX::CurveWorkbench::_gridToggle {w property} {
    variable st
    set value [expr {$property eq "visible" ? $st($w,gridShown) : $st($w,gridSnap)}]
    ::GX::Native2D::core grid $st($w,scene) [dict create enabled 1 $property $value]
    _draw $w;_save $w
}
proc ::GX::CurveWorkbench::_gridOpen {w} {
    variable st
    ::GX::native2DGridForm $w.grid $st($w,scene) [list ::GX::CurveWorkbench::_gridChanged $w] $w [_coordinateGridPresentation $w]
}
proc ::GX::CurveWorkbench::_gridChanged {w} {_draw $w;_save $w}
proc ::GX::CurveWorkbench::_referenceSelect {w} {
    variable st
    if {[dict exists $st($w,referenceMap) $st($w,referenceLabel)]} {set st($w,reference) [dict get $st($w,referenceMap) $st($w,referenceLabel)];set st($w,residual) {};_drawResidual $w;_draw $w}
}
proc ::GX::CurveWorkbench::_renderPath {canvas points color width dash} {
    set coords {}
    foreach p $points {lappend coords {*}$p}
    if {[llength $coords]>=4} {$canvas create line {*}$coords -fill $color -width $width -dash $dash}
}
proc ::GX::CurveWorkbench::_drawScene {w} {
    variable st
    if {![winfo exists $w.right.viewport.canvas]} return
    set c $w.right.viewport.canvas;set width [winfo width $c];set height [winfo height $c]
    if {$width<120||$height<96} return
    set view [::GX::Native2D::core view_requested $st($w,scene)]
    if {[lindex $view 0]!=$width||[lindex $view 1]!=$height||[lindex $view 4]<64||[lindex $view 2]<80} {
        lset view 0 $width;lset view 1 $height
        lset view 2 [expr {max(80,[lindex $view 2])}]
        lset view 4 [expr {max(64,[lindex $view 4])}]
        ::GX::Native2D::core view $st($w,scene) $view
    }
    set view [::GX::Native2D::core view $st($w,scene)]
    if {$st($w,active) ne "" && [dict exists $st($w,curves) $st($w,active)]} {
        set currentMarker [::GX::Native2D::core direction_marker $st($w,scene) [dict get [_record $w $st($w,active)] native]]
        set st($w,directionShown) [dict get $currentMarker visible]
    }
    $c delete all
    lassign [lrange $view 2 5] left top right bottom
    lassign [lindex $view 6] x0 y0 x1 y1
    set plotRight [expr {$width-$right}];set plotBottom [expr {$height-$bottom}]
    set background [::GX::uiFieldColorFromRGBA [::GX::Native2D::core background $st($w,scene)]]
    set background [::GX::uiFieldColorComposite $background #FFFFFF]
    set backgroundRgb [dict get $background rgb]
    set textRgb [::GX::uiFieldColorReadableText $background]
    $c configure -background $backgroundRgb
    $c create rectangle $left $top $plotRight $plotBottom -fill $backgroundRgb -outline #9babbc -tags native_plot_background
    set grid [::GX::Native2D::core grid $st($w,scene)]
    set st($w,gridShown) [dict get $grid visible]
    set st($w,gridSnap) [dict get $grid snap_enabled]
    ::GX::native2DCanvasGrid $st($w,scene) $c
    for {set i 0} {$i<=5} {incr i} {
        set x [expr {$x0+($x1-$x0)*$i/5.0}];set y [expr {$y0+($y1-$y0)*$i/5.0}]
        lassign [::GX::Native2D::core device $st($w,scene) [list $x $y0]] sx _
        lassign [::GX::Native2D::core device $st($w,scene) [list $x0 $y]] _ sy
        $c create text $sx [expr {$plotBottom+15}] -text [_coordinateTick $w x $x] -fill $textRgb -font TkSmallCaptionFont -tags {axis_label coordinate_x_tick}
        $c create text [expr {$left-5}] $sy -text [_coordinateTick $w y $y] -anchor e -fill $textRgb -font TkSmallCaptionFont -tags {axis_label coordinate_y_tick}
    }
    set index 0
    dict for {id r} $st($w,curves) {
        if {![_curveVisible $w $r]} continue
        set curveStyle [_coordinateCurveStyle $w $id $index $background];incr index
        set color [dict get [::GX::uiFieldColorFromRGBA [dict get $curveStyle color]] rgb]
        set sampled {} ;# Defining/row markers query their own Native authority.
        # Shared Native presentation supports point objects as filled markers;
        # a singleton is geometry even when it has no selected defining handle.
        set object [::GX::native2DPresentationObjectSnapshot $st($w,scene) [dict get $r native] 4096]
        if {$object ne {}&&[::GX::datasetPublicationV2DictDefault $r display_style straight] ne "points"} {
            dict set object style [dict merge [dict get $object style] $curveStyle]
            # Defining controls / Dataset points have their own semantic marker
            # presenter. Drawing a marker at every retained display sample both
            # implies false controls and creates thousands of redundant Tk items.
            if {[dict get $object kind] eq "curve"} {dict set object style marker 0}
            dict unset object marker
            ::GX::native2DCanvasDrawObject $c $object $backgroundRgb [list curve_$id]
        }
        set marker {}
        if {![dict exists $r sketch_definition]||[dict get $r sketch_definition family] ni {compound composite_path}} {set marker [::GX::Native2D::core render_marker $st($w,scene) [dict get $r native]]}
        if {$marker ne {}} {
            set style [::GX::Native2D::core direction_marker $st($w,scene) [dict get $r native]]
            set markerColor [::GX::uiFieldColorFromRGBA [dict get $style color]]
            set rgb [dict get [::GX::uiFieldColorComposite $markerColor $background] rgb]
            $c create line {*}[dict get $marker tail] {*}[dict get $marker tip] -fill $rgb -width [dict get $style line_width] -tags [list direction_marker direction_$id]
            $c create line {*}[dict get $marker head_left] {*}[dict get $marker tip] {*}[dict get $marker head_right] -fill $rgb -width [dict get $style line_width] -tags [list direction_marker direction_$id]
            if {$id eq $st($w,active)} {
                lassign [dict get $marker bounds] mx0 my0 mx1 my1
                $c create text [expr {$mx1+8}] [expr {($my0+$my1)/2}] -text Flip -anchor w -fill $rgb -font TkDefaultFont -tags direction_flip
            }
        }
        if {[dict get [::GX::Native2D::core object_style $st($w,scene) [dict get $r native]] selectable]||[::GX::datasetPublicationV2DictDefault $r display_style straight] eq "points"} {_drawPointMarkers $w $id $sampled $color}

    }
    if {$st($w,previewNative) ne ""} {
        foreach path [::GX::Native2D::core render_paths $st($w,scene) $st($w,previewNative)] {
            _renderPath $c $path #19a37c 3 {5 4}
        }
    }
    if {$st($w,residual) ne {} && $st($w,reference) ne ""} {
        set row [lindex [dict get $st($w,residual) rows] [dict get $st($w,residual) max_index]]
        foreach point [list [lindex $row 3] [lindex $row 4]] role {reference target} {
            if {$st($w,comparisonConfig) ne {}&&[dict exists $st($w,comparisonConfig) $role]} {
                set logical [dict get $st($w,comparisonConfig) $role]
                if {![dict exists $st($w,curves) $logical]||![_curveVisible $w [_record $w $logical]]} continue
            }
            set p [::GX::native2DComparisonPoint $st($w,residual) $role $point]
            lassign [::GX::Native2D::core device $st($w,scene) $p] sx sy
            $c create oval [expr {$sx-7}] [expr {$sy-7}] [expr {$sx+7}] [expr {$sy+7}] -outline #d52323 -width 2
        }
    }
    if {$st($w,box) ne {}} {$c create rectangle {*}$st($w,box) -outline #234e9b -dash {4 3}}
    ::GX::native2DCanvasViewportClip $c $st($w,scene)
    if {$st($w,active) ne "" && [dict exists $st($w,curves) $st($w,active)]} {
        set xLabel [_coordinateLabel $w $st($w,active) x];set yLabel [_coordinateLabel $w $st($w,active) y]
        $c create text [expr {($left+$plotRight)/2}] [expr {$height-14}] -text $xLabel -fill $textRgb -tags {axis_label coordinate_axis_label}
        $c create text 13 [expr {($top+$plotBottom)/2}] -text $yLabel -angle 90 -fill $textRgb -tags {axis_label coordinate_axis_label}
    }
}
proc ::GX::CurveWorkbench::_drawResidual {w} {
    variable st
    if {![winfo exists $w.right.residual]} return
    set c $w.right.residual;$c delete all
    if {$st($w,residual) eq {}} return
    set rows [dict get $st($w,residual) rows]
    if {[llength $rows]<2} return
    set points [lmap r $rows {list [lindex $r 0] [lindex $r 1]}]
    if {$st($w,residualScene) ne ""} {::GX::Native2D::core destroy $st($w,residualScene)}
    set st($w,residualScene) [::GX::Native2D::core scene]
    set scene $st($w,residualScene)
    set obj [::GX::Native2D::core add $scene $points]
    set width [winfo width $c];set height [winfo height $c]
    if {$width<100} {set width 900};if {$height<80} {set height 150}
    ::GX::Native2D::core view $scene [list $width $height 55 10 20 28 {0 0 1 1}]
    ::GX::Native2D::core fit $scene $obj
    $c create rectangle 55 10 [expr {$width-20}] [expr {$height-28}] -outline #9babbc -fill white
    set coords [::GX::Native2D::core render $scene $obj]
    _renderPath $c $coords #b12535 2 {}
    set index [dict get $st($w,residual) max_index]
    lassign [lindex $coords $index] sx sy
    $c create oval [expr {$sx-5}] [expr {$sy-5}] [expr {$sx+5}] [expr {$sy+5}] -fill #e6b433 -outline #711822
    set unit [::GX::datasetPublicationV2DictDefault $st($w,residual) unit {}]
    set xUnit $unit
    if {$st($w,compareMethod) eq "x"&&[dict exists $st($w,residual) coordinate_frame]} {set xUnit [lindex [dict get $st($w,residual) coordinate_frame output_units] 0]}
    set kind [expr {$st($w,compareMethod) eq "geometry"?"distance":"signed\nresidual"}]
    $c create text 8 [expr {$height/2}] -text "$kind\n($unit)" -anchor w -fill #48566b
    $c create text [expr {$width/2}] [expr {$height-11}] -text "[expr {$st($w,compareMethod) eq "x" ? "reference X" : "reference path distance"}] ($xUnit)" -fill #48566b
}
proc ::GX::CurveWorkbench::_hitCurve {w world tolerance} {
    variable st
    set best {};set distance $tolerance
    dict for {id r} $st($w,curves) {
        if {![_curveVisible $w $r]} continue
        if {[catch {
            if {[::GX::Native2D::core kind $st($w,scene) [dict get $r native]] eq "point"} {
                set hit [::GX::Native2D::core hit $st($w,scene) [dict get $r native] $world $tolerance]
                if {$hit eq {}} continue
                dict set hit segment 0;dict set hit t 0
            } elseif {[dict get $r representation] eq "spline"} {set hit [::GX::Native2D::core nearest_spline $st($w,scene) [dict get $r native] $world 12]} else {set hit [::GX::Native2D::core nearest_segment $st($w,scene) [dict get $r native] $world]}
        }]} continue
        if {[dict get $hit distance]<$distance} {set distance [dict get $hit distance];set best [list $id $hit]}
    }
    return $best
}
proc ::GX::CurveWorkbench::_pointerDownScientific {w x y state} {
    variable st
    if {[info exists st($w,publishBusy)]&&$st($w,publishBusy)} {return 1}
    set st($w,drag) [dict create mode none x $x y $y]
    if {"direction_flip" in [$w.right.viewport.canvas gettags current]} {_directionFlip $w;return 1}
    if {$st($w,tool) eq "pan"} {dict set st($w,drag) mode pan;return 1}
    if {$st($w,tool) eq "select" && $st($w,active) ne ""} {
        set id $st($w,active);set native [dict get [_record $w $id] native]
        if {[::GX::Native2D::core marker_hit $st($w,scene) $native [list $x $y] 5]} {
            set st($w,drag) [dict create mode direction curve_id $id native $native before [_snapshotIds $w [list $id]]]
            return 1
        }
    }
    set world [::GX::Native2D::core world $st($w,scene) [list $x $y]]
    set tolerance [::GX::Native2D::core tolerance $st($w,scene) 8]
    lassign $tolerance tx ty;set radius [expr {max($tx,$ty)}]
    if {$st($w,tool) eq "add"} {
        set hit [_hitCurve $w $world $radius]
        if {$hit eq {}} {set st($w,status) "Click a visible curve segment to insert a point";return 1}
        lassign $hit id segment
        if {[dict get [_record $w $id] locked]} {error "This curve is locked"}
        set st($w,active) $id;set r [_record $w $id];set before [_snapshotIds $w [list $id]]
        if {[dict exists $r sketch_definition]} {set st($w,tool) select;set st($w,status) "Edit primitive parameters or explicitly explode/sample points before inserting a point";return 1}
        set index [expr {[dict get $segment segment]+1}]
        ::GX::Native2D::core insert $st($w,scene) [dict get $r native] $index $world
        set point [dict create x [lindex $world 0] y [lindex $world 1] row -1 order "" point_id "new:[clock clicks]"]
        dict set r samples [linsert [dict get $r samples] $index $point]
        dict set r edited 1;dict lappend r operations "insert:$index"
        dict set st($w,curves) $id $r;_selectionScene $w;set st($w,tool) select
        _history $w $before [list $id];return 1
    }
    if {$st($w,selectionObject) ne ""} {
        set pointHit [::GX::Native2D::core hit_point_device $st($w,scene) [dict get [_record $w $st($w,active)] native] [list $x $y] 8]
        if {$pointHit ne {}} {
            set index [dict get $pointHit index]
            if {[_pointCount [_record $w $st($w,active)]]>200} {set st($w,pointPageStart) [expr {200*($index/200)}]}
            set mode [expr {($state&0x0001) ? "add" : ($state&0x0008) ? "subtract" : "replace"}]
            if {$mode ne "replace" || $index ni [_selected $w]} {
                ::GX::Native2D::core select $st($w,selectionScene) $st($w,selectionObject) $index $mode
            }
            if {$mode eq "replace" && ![dict get [_record $w $st($w,active)] locked] && ![dict exists [_record $w $st($w,active)] sketch_definition]} {
                dict set st($w,drag) mode points
                dict set st($w,drag) curve_id $st($w,active)
                dict set st($w,drag) before [_snapshotIds $w [list $st($w,active)]]
                dict set st($w,drag) world $world
                dict set st($w,drag) pivot [dict get $pointHit point]
                ::GX::Native2D::core drag_begin $st($w,selectionScene)
            }
            _pointList $w;_draw $w;return 1
        }
    }
    set hit [_hitCurve $w $world $radius]
    if {$hit ne {}} {
        set id [lindex $hit 0];set st($w,active) $id;set st($w,residual) {};_drawResidual $w;_selectionScene $w;_curveList $w;_pointList $w;_draw $w;return 1
    }
    dict set st($w,drag) mode box;dict set st($w,drag) select_mode [expr {($state&0x0001)?"add":($state&0x0008)?"subtract":"replace"}]
    set st($w,box) [list $x $y $x $y]

    return 1
}
proc ::GX::CurveWorkbench::_pointerMoveScientific {w x y} {
    variable st
    if {[info exists st($w,publishBusy)]&&$st($w,publishBusy)} {return 1}
    _coordinates $w $x $y
    if {$st($w,drag) eq {}} {return 1}
    set mode [dict get $st($w,drag) mode]
    if {$mode eq "direction"} {
        ::GX::Native2D::core marker_place $st($w,scene) [dict get $st($w,drag) native] [list $x $y]
        _draw $w
    } elseif {$mode eq "pan"} {
        ::GX::Native2D::core pan $st($w,scene) [expr {$x-[dict get $st($w,drag) x]}] [expr {$y-[dict get $st($w,drag) y]}]
        dict set st($w,drag) x $x;dict set st($w,drag) y $y;_viewDrawLater $w
    } elseif {$mode eq "box"} {set st($w,box) [list [dict get $st($w,drag) x] [dict get $st($w,drag) y] $x $y];_draw $w} elseif {$mode eq "points"} {
        set world [::GX::Native2D::core world $st($w,scene) [list $x $y]]
        lassign [dict get $st($w,drag) world] ax ay
        set delta [list [expr {[lindex $world 0]-$ax}] [expr {[lindex $world 1]-$ay}]]
        set grid [::GX::Native2D::core grid $st($w,scene)]
        if {[dict get $grid enabled] && [dict get $grid snap_enabled]} {set delta [::GX::Native2D::core grid_snap_delta $st($w,scene) [dict get $st($w,drag) pivot] $delta 3]}
        ::GX::Native2D::core drag_translate $st($w,selectionScene) {*}$delta
        set native [dict get [_record $w $st($w,active)] native]
        set candidate [::GX::Native2D::core points $st($w,scene) $native]
        foreach row [::GX::Native2D::core selected_records $st($w,selectionScene) $st($w,selectionObject)] {
            lset candidate [dict get $row index] [dict get $row point]
        }
        # Native replace validates the entire candidate once. Moving joined
        # points together must not check a half-applied intermediate state.
        try {::GX::Native2D::core replace $st($w,scene) $native $candidate} on error {message options} {
            _partCancel $w
    _cancelPointDrag $w
            _pointSyncApply $w;_pointList $w;_draw $w
            set st($w,status) "Point move rejected: $message. Previous geometry and selection restored."
            return 1
        }
        _draw $w
    }

    return 1
}
proc ::GX::CurveWorkbench::_coordinates {w x y} {
    variable st
    if {![info exists st($w,scene)]} return
    set st($w,coordinates) [_coordinateReadout $w [list $x $y]]
}
proc ::GX::CurveWorkbench::_pointerUpScientific {w x y} {
    variable st
    if {[info exists st($w,publishBusy)]&&$st($w,publishBusy)} {return 1}
    if {$st($w,drag) eq {}} {return 1}
    set drag $st($w,drag);set mode [dict get $drag mode];set st($w,drag) {}
    if {$mode eq "direction"} {
        _history $w [dict get $drag before] [list [dict get $drag curve_id]]
    } elseif {$mode eq "points"} {
        ::GX::Native2D::core drag_commit $st($w,selectionScene)
        _pointSyncApply $w
        set id $st($w,active)
        set beforeSamples [dict get $drag before $id samples]
        set current [::GX::Native2D::core points $st($w,scene) [dict get [_record $w $id] native]]
        set changed 0;set index 0
        foreach p $beforeSamples {
            lassign [lindex $current $index] px py;incr index
            if {$px != [dict get $p x] || $py != [dict get $p y]} {set changed 1;break}
        }
        if {$changed} {
            _syncSamples $w $id
            set r [_record $w $id];dict lappend r operations move_points;dict set st($w,curves) $id $r
            _history $w [dict get $drag before] [list $id]
        } else {_pointList $w;_draw $w}
    } elseif {$mode eq "box"} {
        set st($w,box) {}
        if {hypot($x-[dict get $drag x],$y-[dict get $drag y])>3 && $st($w,selectionObject) ne ""} {
            set a [::GX::Native2D::core world $st($w,scene) [list [dict get $drag x] [dict get $drag y]]]
            set b [::GX::Native2D::core world $st($w,scene) [list $x $y]]
            ::GX::Native2D::core rect $st($w,selectionScene) [list [expr {min([lindex $a 0],[lindex $b 0])}] [expr {min([lindex $a 1],[lindex $b 1])}] [expr {max([lindex $a 0],[lindex $b 0])}] [expr {max([lindex $a 1],[lindex $b 1])}]] [dict get $drag select_mode]
        }
        _pointList $w;_draw $w
    } elseif {$mode eq "pan"} {_save $w}
    catch {_metrics $w}

    return 1
}
proc ::GX::CurveWorkbench::_wheel {w x y delta} {
    variable st
    ::GX::Native2D::core zoom $st($w,scene) [expr {$delta>0?0.82:1.22}] [list $x $y]
    _viewDrawLater $w;_viewPersistLater $w
}
proc ::GX::CurveWorkbench::_fit {w {selected 0}} {
    variable st
    _coordinateFrameSync $w 0
    if {$selected} {::GX::Native2D::core fit $st($w,scene) [dict get [_record $w [_active $w]] native]} else {::GX::Native2D::core fit $st($w,scene)}
    _coordinateMagnify $w 1
    _draw $w;_save $w
}
proc ::GX::CurveWorkbench::_safe {w command} {
    variable st
    if {[info exists st($w,publishBusy)]&&$st($w,publishBusy)} {set st($w,status) "Publication in progress; Escape cancels before commit.";return}
    if {[catch {uplevel #0 $command} err opts]} {
        set st($w,status) $err
        if {[dict exists $opts -errorcode]&&[dict get $opts -errorcode] in {{GX DATASET_TRANSFORM CANCELLED} {GX CURVE_SOURCE CANCELLED}}} {return}
        tk_messageBox -parent $w -icon error -type ok -title "Curve Workbench" -message $err
        return
    }
}
proc ::GX::CurveWorkbench::_sourceDataset {w} {
    variable st
    set label $st($w,source.datasetLabel)
    if {![dict exists $st($w,source.datasetMap) $label]} return
    set st($w,source.dataset) [dict get $st($w,source.datasetMap) $label]
    set schema [variables $st($w,source.dataset)]
    set st($w,source.varMap) [dict create]
    foreach id [dict get $schema all] {dict set st($w,source.varMap) [dict get [dict get $schema labels] $id] $id}
    set numeric [lmap id [dict get $schema numeric] {dict get [dict get $schema labels] $id}]
    set all [lmap id [dict get $schema all] {dict get [dict get $schema labels] $id}]
    set d $w.source
    $d.x configure -values $numeric;$d.y configure -values $numeric
    set st($w,source.xLabel) [lindex $numeric 0];set st($w,source.yLabel) [lindex $numeric 1]
    foreach {key placeholder} {filter "(all rows)" family "(single curve / none)" order "(source row order)"} {
        $d.$key configure -values [linsert $all 0 $placeholder]
        set st($w,source.${key}Label) $placeholder
    }
    set st($w,source.filterValue) "";set st($w,source.familyValues) {}
    _sourceFilter $w;_sourceFamily $w
}
proc ::GX::CurveWorkbench::_sourceId {w key} {
    variable st
    set label $st($w,source.${key}Label)
    if {[dict exists $st($w,source.varMap) $label]} {return [dict get $st($w,source.varMap) $label]}
    return ""
}
proc ::GX::CurveWorkbench::_sourceFilter {w} {
    variable st
    set d $w.source
    set filter [_sourceId $w filter]
    if {$filter eq ""} {grid remove $d.filterValueLabel $d.filterValue;set st($w,source.filterValue) ""} else {
        grid $d.filterValueLabel $d.filterValue
        set values [distinctValues $st($w,source.dataset) $filter]
        $d.filterValue configure -values $values
        if {$st($w,source.filterValue) ni $values} {set st($w,source.filterValue) [lindex $values 0]}
    }
    _sourceFamily $w
}
proc ::GX::CurveWorkbench::_sourceFamily {w} {
    variable st
    set d $w.source;set family [_sourceId $w family]
    if {$family eq ""} {grid remove $d.familyPanel;grid rowconfigure $d 7 -weight 0;wm geometry $d 750x350;return}
    grid $d.familyPanel
    grid rowconfigure $d 7 -weight 1;wm geometry $d 750x640
    set filter [_sourceId $w filter];set value $st($w,source.filterValue)
    set groups [_familyValues $st($w,source.dataset) $family $filter $value]
    set st($w,source.familyValues) $groups
    $d.familyPanel.list delete 0 end
    foreach group $groups {$d.familyPanel.list insert end $group}
}
proc ::GX::CurveWorkbench::_familyValues {dataset family filter value} {
    if {$family eq ""} {return {}}
    set ids [lsort -unique [concat [list $family] [expr {$filter eq "" ? {} : [list $filter]}]]]
    set stream [::GX::tableStreamOpenDataset [_session] $dataset $ids 4096]
    set seen [dict create]
    try {
        while 1 {
            set chunk [::GX::tableStreamNext $stream];set values [dict get $chunk values]
            for {set i 0} {$i<[dict get $chunk nrows]} {incr i} {
                if {$filter ne "" && [lindex [dict get $values $filter] $i] ne $value} continue
                dict set seen [lindex [dict get $values $family] $i] 1
            }
            if {[dict get $chunk eof]} break
        }
    } finally {::GX::tableStreamClose $stream}
    return [lsort -dictionary [dict keys $seen]]
}
proc ::GX::CurveWorkbench::_sourceDatasetLabels {w} {
    variable st
    set labels {};set mapping [dict create]
    foreach id [datasetIds] {
        set label [_datasetLabel $id]
        lappend labels $label;dict set mapping $label $id
    }
    set st($w,source.datasetMap) $mapping
    return $labels
}
proc ::GX::CurveWorkbench::_sourceOpen {w} {
    variable st
    set d $w.source
    if {[winfo exists $d]} {raise $d;return}
    ::GX::uiFieldDialogCreate $d $w {Add curve to workspace} 750x640
    set labels [_sourceDatasetLabels $w]
    foreach {key value} {dataset "" datasetLabel "" xLabel "" yLabel "" filterLabel "(all rows)" filterValue "" familyLabel "(single curve / none)" orderLabel "(source row order)"} {set st($w,source.$key) $value}
    if {[info exists st($w,preferredDataset)] && $st($w,preferredDataset) ne ""} {
        set preferred $st($w,preferredDataset)
        foreach label $labels {if {[dict get $st($w,source.datasetMap) $label] eq $preferred} {set st($w,source.datasetLabel) $label;break}}
    }
    if {$st($w,source.datasetLabel) eq ""} {set st($w,source.datasetLabel) [lindex $labels 0]}
    grid columnconfigure $d 1 -weight 1
    ttk::label $d.intro -text "Choose an X/Y Dataset. Filter, Family and Order are optional; curves already in the workspace remain available." -wraplength 690
    grid $d.intro -row 0 -column 0 -columnspan 2 -sticky ew -padx 14 -pady 12
    foreach {key title row} {dataset Dataset 1 x X 2 y Y 3 filter "Filter column" 4 filterValue "Filter value" 5 family "Family column" 6 order "Order column" 8} {
        ttk::label $d.${key}Label -text $title
        grid $d.${key}Label -row $row -column 0 -sticky w -padx 14 -pady 5
        ttk::combobox $d.$key -textvariable ::GX::CurveWorkbench::st($w,source.${key}Label) -state readonly -width 60
        if {$key eq "dataset"} {::GX::datasetSelectorAttach $d.$key [list ::GX::CurveWorkbench::_sourceDatasetLabels $w]}
        if {$key eq "filterValue"} {$d.$key configure -textvariable ::GX::CurveWorkbench::st($w,source.filterValue) -state normal}
        grid $d.$key -row $row -column 1 -sticky ew -padx 12 -pady 5
    }
    ttk::labelframe $d.familyPanel -text "Family members (select one, several, or leave unselected for all)" -padding 7
    listbox $d.familyPanel.list -selectmode extended -height 7 -exportselection 0
    ttk::scrollbar $d.familyPanel.scroll -orient vertical -command [list $d.familyPanel.list yview]
    $d.familyPanel.list configure -yscrollcommand [list $d.familyPanel.scroll set]
    pack $d.familyPanel.scroll -side right -fill y;pack $d.familyPanel.list -side left -fill both -expand 1
    grid $d.familyPanel -row 7 -column 0 -columnspan 2 -sticky nsew -padx 14 -pady 7
    grid rowconfigure $d 7 -weight 1
    ttk::frame $d.buttons;grid $d.buttons -row 9 -column 0 -columnspan 2 -sticky e -padx 14 -pady 12
    ttk::button $d.buttons.add -text "Add to workspace" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_sourceAdd $w]]
    ttk::button $d.buttons.cancel -text Cancel -command [list ::GX::CurveWorkbench::_sourceClose $w]
    pack $d.buttons.cancel $d.buttons.add -side right -padx 4
    bind $d.dataset <<ComboboxSelected>> [list ::GX::CurveWorkbench::_sourceDataset $w]
    bind $d.filter <<ComboboxSelected>> [list ::GX::CurveWorkbench::_sourceFilter $w]
    bind $d.filterValue <<ComboboxSelected>> [list ::GX::CurveWorkbench::_sourceFamily $w]
    bind $d.filterValue <Return> [list ::GX::CurveWorkbench::_sourceFamily $w]
    bind $d.family <<ComboboxSelected>> [list ::GX::CurveWorkbench::_sourceFamily $w]
    ttk::label $d.status -textvariable ::GX::CurveWorkbench::st($w,status) -wraplength 650 -anchor w
    grid $d.status -row 10 -column 0 -columnspan 2 -sticky ew -padx 14 -pady 5
    bind $d <Escape> [list ::GX::CurveWorkbench::_sourceClose $w]
    wm protocol $d WM_DELETE_WINDOW [list ::GX::CurveWorkbench::_sourceClose $w]
    _sourceDataset $w
    ::GX::uiFieldDialogPresent $d $d.dataset
}
proc ::GX::CurveWorkbench::_sidebarLayout {w {width {}}} {
    if {![winfo exists $w.leftScroll.viewport]} return
    set viewport $w.leftScroll.viewport
    if {$width eq {}} {set width [winfo width $viewport]}
    $viewport itemconfigure content -width $width
    $viewport configure -scrollregion [$viewport bbox all]
}
proc ::GX::CurveWorkbench::_sidebarFocusBindings {w widget} {
    bind $widget <FocusIn> +[list ::GX::uiFieldScrollSee $w.leftScroll.viewport $w.leftScroll.viewport.content $widget]
    foreach child [winfo children $widget] {_sidebarFocusBindings $w $child}
}
proc ::GX::CurveWorkbench::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "Unsupported Curve Workbench action '$action'"}
    set context [expr {[dict exists $scene open_context] ? [dict get $scene open_context] : [dict create]}]
    return [open $context]
}
source [file join [file dirname [info script]] curve_workbench_source_v2.tcl]
source [file join [file dirname [info script]] curve_workbench_geometry_v2.tcl]
source [file join [file dirname [info script]] curve_workbench_cad_v2.tcl]
source [file join [file dirname [info script]] curve_workbench_workspace_state.tcl]
source [file join [file dirname [info script]] curve_workbench_persistence.tcl]
source [file join [file dirname [info script]] curve_workbench_scene.tcl]
source [file join [file dirname [info script]] curve_workbench_pointer.tcl]
source [file join [file dirname [info script]] curve_workbench_ui.tcl]
source [file join [file dirname [info script]] curve_workbench_units_v2.tcl]
source [file join [file dirname [info script]] curve_workbench_recovery_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_lifecycle_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_sketch_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_constraints_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_measurements_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_identity_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_collections_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_views_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_series_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_extensions_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_roles_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_comparison_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_recipe_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_interaction_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_representation_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_sketch_constraints_v2.tcl]
source [file join [file dirname [info script]] curve_workbench_interaction_v2.tcl]
source [file join [file dirname [info script]] curve_workbench_viewport_v3.tcl]
::GX::viewerBackendRegister curve_workbench_tk ::GX::CurveWorkbench::viewerDispatch

source [file join [file dirname [info script]] curve_workbench_fluidity_v4.tcl]

source [file join [file dirname [info script]] curve_workbench_selection.tcl]
source [file join [file dirname [info script]] curve_workbench_settings.tcl]
source [file join [file dirname [info script]] curve_workbench_commands.tcl]

source [file join [file dirname [info script]] curve_workbench_comparison_v4.tcl]

source [file join [file dirname [info script]] curve_workbench_representation_v4.tcl]

source [file join [file dirname [info script]] curve_workbench_backing_v4.tcl]

source [file join [file dirname [info script]] curve_workbench_parameters.tcl]

source [file join [file dirname [info script]] curve_workbench_datasets.tcl]

source [file join [file dirname [info script]] curve_workbench_history.tcl]

source [file join [file dirname [info script]] curve_workbench_planar_v1.tcl]

source [file join [file dirname [info script]] curve_workbench_parts.tcl]
source [file join [file dirname [info script]] curve_workbench_coordinate_presentation_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_coordinate_frames_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_coordinate_declaration_v1.tcl]
source [file join [file dirname [info script]] curve_workbench_coordinate_controls_v1.tcl]

source [file join [file dirname [info script]] curve_workbench_fit_import_v1.tcl]
