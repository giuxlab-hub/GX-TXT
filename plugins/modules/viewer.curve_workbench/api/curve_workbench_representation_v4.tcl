# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit conversion and publication extend the shared geometry/publication
# authorities. Display style never changes immutable Dataset source geometry.
rename ::GX::CurveWorkbench::_primitivePublishOpen ::GX::CurveWorkbench::_primitivePublishOpen_path057_base
proc ::GX::CurveWorkbench::_primitivePublishOpen {w} {
    variable st
    set id [_active $w];set record [_record $w $id]
    if {[dict exists $record sketch_definition]&&[dict get $record sketch_definition family] eq "compound"} {tailcall _publishBatchOpen $w}
    if {[dict exists $record sketch_definition]&&[dict get $record sketch_definition family] eq "composite_path"} {
        if {[::GX::Native2D::core composition_traversal $st($w,scene) [dict get $record native]] ne "continuous"} {tailcall _publishBatchOpen $w}
        ::GX::uiFieldFormCreate $w.primitivePublish {Publish ordered Path — exact straight vertices and explicit curved samples} {
            dataset_id {type string required 1 label {New Canonical Dataset ID}}
            curved_samples {type integer min 2 max 65536 label {Uniform parameter samples per curved constituent}}
            index_variable_id {type string label {Ordering Variable ID (blank omits)}}
            repeat_endpoint {type boolean label {Repeat the start point of a closed Path}}
        } [dict create dataset_id $st($w,resultId) curved_samples 257 index_variable_id index repeat_endpoint 0] [list ::GX::CurveWorkbench::_primitivePublishApply $w $st($w,token) $id] $w
        return
    }
    if {![dict exists $record sketch_definition]||[dict get $record sketch_definition family] ne "path"} {tailcall _primitivePublishOpen_path057_base $w}
    ::GX::uiFieldFormCreate $w.primitivePublish {Publish Line/path — exact ordered vertices} {
        dataset_id {type string required 1 label {New Canonical Dataset ID}}
        index_variable_id {type string label {Ordering Variable ID/name (blank omits; default index)}}
        repeat_endpoint {type boolean label {Repeat the first vertex at the end of a closed path}}
    } [dict create dataset_id $st($w,resultId) index_variable_id index repeat_endpoint 0] [list ::GX::CurveWorkbench::_primitivePublishApply $w $st($w,token) $id] $w
}
proc ::GX::CurveWorkbench::_primitivePublishApply {w token id values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen publication}}
    set record [_record $w $id];set unit [lindex [_coordinateUnits $record] 0]
    set definition [::GX::Native2D::core sketch_definition $st($w,scene) [dict get $record native]]
    set sampling [dict remove $values dataset_id]
    dict set sampling coordinate_units [_coordinateUnits $record]
    dict set sampling coordinate_relations [_coordinateSourceRelations $record]
    dict set sampling forward [dict get [::GX::Native2D::core direction_marker $st($w,scene) [dict get $record native]] forward]
    set sources {};foreach ancestor [concat [list $record] [dict get $record ancestors]] {if {[dict get $ancestor source] ne {}} {lappend sources [dict get $ancestor source]}}
    if {[dict exists $record conversion_provenance source_dataset_id]} {lappend sources [dict get $record conversion_provenance source_dataset_id]}
    foreach ancestor [dict get $record ancestors] {if {[dict exists $ancestor conversion_provenance source_dataset_id]} {lappend sources [dict get $ancestor conversion_provenance source_dataset_id]}}
    dict set sampling source_dataset_ids [lsort -unique $sources]
    dict set sampling conversion_provenance [::GX::datasetPublicationV2DictDefault $record conversion_provenance {}]
    set result [::GX::native2DPrimitivePublish [_session] [dict get $values dataset_id] $definition $unit $sampling $id [dict get $record name] viewer.curve_workbench]
    set st($w,status) "Published [dict get $values dataset_id]; retained topology, direction and source provenance are preserved."
    return $result
}
proc ::GX::CurveWorkbench::_promoteOpen {w} {
    variable st
    set id [_active $w];set record [_record $w $id]
    if {[dict get $record source] eq {}||[dict get $record edited]} {error {Select an untouched Dataset-backed curve}}
    _sourceSnapshotRequire $w $record
    set options {};foreach key {filters order_variable_id} {if {[dict exists $record source_request $key]} {dict set options $key [dict get $record source_request $key]}}
    set receipt [::GX::native2DDatasetPromote [_session] [dict get $record source] [dict get $record x] [dict get $record y] $options]
    set st($w,promotionPreview) [dict create logical $id receipt $receipt coordinate_key [_coordinateControlKey $w [list $id]]]
    _toolPreview $w [dict get $receipt definition];_draw $w
    set method [dict get $receipt method]
    if {$method eq {exact_provenance_reconstruction}} {
        set detail {Exact retained reconstruction verified against original Dataset values.}
    } else {
        set quality [dict get $receipt quality];lassign [dict get $receipt coordinate_units] xUnit yUnit
        set errors [dict get $quality maximum_knot_error_by_axis]
        set norm [dict get $receipt working_unit]
        if {[dict get $quality scope] eq {numeric_plane_interpolation_at_authoritative_knots}} {set norm "numeric plane norm (native X $xUnit / Y $yUnit)"}
        set detail "Spline interpolation through [dict get $quality knot_count] authoritative Dataset knots; maximum knot errors: X [dict get $errors x] $xUnit; Y [dict get $errors y] $yUnit. Combined maximum [dict get $quality maximum_knot_error] $norm. Between knots the result is an explicit derived interpolation."
    }
    ::GX::uiFieldFormCreate $w.promote {Review Dataset → retained geometry; original Dataset preserved} {name {type string required 1 label {New retained geometry name}}} [dict create name "[dict get $record name] retained"] [list ::GX::CurveWorkbench::_promoteApply $w $st($w,token)] $w
    ttk::label $w.promote.review -text $detail -wraplength 570 -padding 8;pack $w.promote.review -fill x -before $w.promote.viewport
    bind $w.promote <Destroy> +[list ::GX::CurveWorkbench::_promotionDisposed $w %W]
}
proc ::GX::CurveWorkbench::_promotionDisposed {w widget} {
    variable st
    if {$widget ne "$w.promote"||![info exists st($w,promotionPreview)]} return
    set st($w,promotionPreview) {};_toolPreviewClear $w
    if {[winfo exists $w.right.viewport.canvas]} {_draw $w}
}
proc ::GX::CurveWorkbench::_promoteApply {w token values} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen conversion}}
    if {$st($w,promotionPreview) eq {}} {error {Preview no longer exists}}
    set context $st($w,promotionPreview);set source [_record $w [dict get $context logical]];_sourceSnapshotRequire $w $source
    _coordinateControlCheck $w [list [dict get $context logical]] [dict get $context coordinate_key]
    set receipt [dict get $context receipt]
    set result [_commitDefinition $w [dict get $receipt definition] [dict get $receipt working_unit] [dict get $values name] $receipt [list [dict get $context logical]]]
    if {[dict exists $receipt direction]} {
        ::GX::Native2D::core direction_marker $st($w,scene) [dict get [_record $w $result] native] [dict get $receipt direction]
        dict set st($w,curves) $result direction [dict get $receipt direction]
        _save $w
    }
    _toolPreviewClear $w;return $result
}
proc ::GX::CurveWorkbench::_datasetDisplay {w style} {
    variable st
    if {$style ni {points straight spline}} {error {Unknown Dataset display style}}
    set id [_active $w];set record [_record $w $id]
    if {[dict get $record source] eq {}||[dict get $record edited]} {error {Select an untouched Dataset-backed curve for reversible display style}}
    if {$style eq "spline"&&([_pointCount $record]>4096||[dict get $record breaks] ne {})} {error {Spline display supports a continuous curve of at most 4096 authoritative points; Dataset backing remains unchanged}}
    set before [_snapshotIds $w [list $id]]
    dict set record display_style $style;dict set st($w,curves) $id $record
    ::GX::Native2D::core direction_marker $st($w,scene) [dict get $record native] [dict create interpolation [expr {$style eq "spline"}]]
    _history $w $before [list $id];set st($w,status) "Dataset display: $style. Source points and default publication remain exact."
}
proc ::GX::CurveWorkbench::_installRepresentationCommands {w} {
    
    $w.sketchbar.represent.menu add separator
    $w.sketchbar.represent.menu add command -label {Dataset → editable points (review)…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_convertOpen $w]]
    $w.sketchbar.represent.menu add command -label {Dataset → retained geometry (review)…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_promoteOpen $w]]
    foreach style {points straight spline} {$w.sketchbar.represent.menu add command -label "Dataset display: $style" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_datasetDisplay $w $style]]}
    $w.sketchbar.modify.menu add separator
    $w.sketchbar.modify.menu add command -label {Join Path…} -command [list ::GX::CurveWorkbench::_commandInvoke $w object.join]
    $w.sketchbar.modify.menu add command -label {Combine / Compound…} -command [list ::GX::CurveWorkbench::_commandInvoke $w object.combine]
    $w.sketchbar.modify.menu add command -label {Separate exact constituents} -command [list ::GX::CurveWorkbench::_commandInvoke $w object.separate]
    $w.sketchbar.modify.menu add command -label {Split retained Path…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_pathSplit $w]]

}
proc ::GX::CurveWorkbench::_pathJoinOpen {w} {_compositionOpen $w auto_path}
proc ::GX::CurveWorkbench::_compositionOpen {w arrangement} {
    variable st
    set ids [_commandSelection $w]
    foreach id $ids {
        set record [_record $w $id]
        if {![dict exists $record sketch_definition]} {
            if {[dict get $record source] ne {}&&[tk_messageBox -parent $w -type yesno -icon question -message {This operation needs retained geometry. Review a new retained copy of the selected Dataset first? The Dataset and the other selected objects will remain unchanged.}] eq "yes"} {
                # Mixed selection may have a different active object. Rebind
                # the existing point-selection scene before conversion takes
                # its history snapshot; its range belongs to the active curve.
                set st($w,active) $id;_selectionScene $w;_pointList $w
                _promoteOpen $w;return
            }
            error {Every selected object must have an exact retained definition. Use reviewed Dataset promotion or exact primitive creation first. No objects changed.}
        }
    }
    set name [expr {$arrangement eq "compound"?"Compound":"Path"}]
    _coordinatePlaneAdmit $w $ids
    lassign [_coordinateUnits [_record $w [lindex $ids 0]]] xUnit yUnit
    set fields {name {type string required 1 label {New logical object name}}}
    set values [dict create name $name tolerance 0]
    if {$arrangement ne "compound"} {
        dict set fields tolerance [dict create type number min 0 label "Numeric plane endpoint tolerance (native X $xUnit / Y $yUnit)"]
        dict set values tolerance 1e-9
    }
    set subtitle [expr {$arrangement eq "compound" ? "$name — exact constituents; source objects preserved" : "$name — exact constituents; selected objects become one Path"}]
    ::GX::uiFieldFormCreate $w.pathJoin $subtitle $fields $values [list ::GX::CurveWorkbench::_compositionReviewedApply $w $st($w,token) $ids $arrangement [_coordinateControlKey $w $ids]] $w
}
proc ::GX::CurveWorkbench::_compositionReviewedApply {w token ids arrangement key values} {
    _coordinateControlCheck $w $ids $key
    return [_compositionApply $w $token $ids $arrangement $values]
}
proc ::GX::CurveWorkbench::_adoptPath {w native name parents operation} {
    variable st
    set record [_newRecord $w $name [_sketchSamples $w $native] {} x y {} {} {} {} $parents [list $operation]]
    set ancestors {};foreach parent $parents {set r [_record $w $parent];lappend ancestors [dict remove $r native samples ancestors];lappend ancestors {*}[dict get $r ancestors]}
    # Snapshot conversion receipts before inputs can be independently deleted.
    # Logical ancestry identifies sources; retained metadata explains the science.
    set receipts {};foreach ancestor $ancestors {
        if {[dict exists $ancestor conversion_provenance]} {lappend receipts [dict get $ancestor conversion_provenance]}
    }
    dict set operation input_provenance $receipts
    dict set record ancestors $ancestors;dict set record conversion_provenance $operation
    return [_addRecord $w $record $native]
}
proc ::GX::CurveWorkbench::_compositionApply {w token ids arrangement values {recordHistory 1}} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen composition}}
    _coordinatePlaneAdmit $w $ids
    set natives [lmap id $ids {dict get [_record $w $id] native}]
    # Join replaces the selected top-level objects with one exact logical Path.
    # The composition owns deep leaf copies and the record keeps their ancestry;
    # undo restores the source objects. Compound retains its separate sources.
    set consumes [expr {$arrangement ne "compound"}]
    set before [_snapshotIds $w [expr {$consumes?$ids:{}}]];
    set mode [expr {$arrangement eq "compound"?0:2}]
    if {[catch {set native [[_cadController $w] object join $natives {} $mode [::GX::datasetPublicationV2DictDefault $values tolerance 0]]} message options]} {
        if {$mode==2} {error {The selection is not one connected retained network within the selected tolerance. No objects changed.}}
        return -options $options $message
    }
    set id {}
    try {
        set id [_adoptPath $w $native [dict get $values name] $ids [dict merge [dict create operation retained_$arrangement inputs $ids inputs_preserved [expr {!$consumes}]] $values]]
        dict set before $id {};set st($w,active) $id
        if {$consumes} {
            [_cadController $w] object retarget $native $natives
            foreach source $ids {_removeRecord $w $source}
            # Native2D deletes relations whose source geometry was deleted;
            # keep the logical constraint inventory in sync before history.
            _constraintCapture $w
        }
        set st($w,active) $id
        _semanticApply $w [list [dict create kind object id $native index 0]]
        _selectionScene $w
        if {$recordHistory} {_history $w $before [expr {$consumes?[concat $ids [list $id]]:[list $id]}]}
        set st($w,status) [expr {$consumes?"Created one exact retained Path; input objects are available through Undo or Separate.":"Created [dict get $values name] with exact retained constituents; source objects are preserved."}]
    } on error {message options} {
        if {$id ne {}} {_removeRecord $w $id} elseif {$native in [::GX::Native2D::core ids $st($w,scene)]} {::GX::Native2D::core delete $st($w,scene) $native}
        _restoreSnapshot $w $before;return -options $options $message
    }
    return $id
}
proc ::GX::CurveWorkbench::_compositionSeparate {w} {
    variable st
    set ids [_commandSelection $w]
    if {[llength $ids]!=1} {error {Select one Path or Compound to separate its exact constituents.}}
    set parent [lindex $ids 0];set record [_record $w $parent]
    if {![dict exists $record sketch_definition]||[dict get $record sketch_definition family] ni {composite_path compound}} {error {Select a heterogeneous Path or Compound.}}
    _coordinatePlaneAdmit $w $ids
    set before [_snapshotIds $w {}];set members {};set created {}
    set natives [[_cadController $w] object separate [dict get $record native]]
    try {
        set ordinal 0
        foreach native $natives {
            set id [_adoptPath $w $native "[dict get $record name] part [incr ordinal]" $ids [dict create operation exact_constituent_copy source $parent part_index [expr {$ordinal-1}] source_preserved 1]]
            dict set before $id {};lappend created $id;lappend members [dict create kind object id $native index 0]
        }
        _semanticApply $w $members;set st($w,active) [lindex $created 0];_selectionScene $w;_history $w $before $created
    } on error {message options} {
        foreach native $natives {catch {::GX::Native2D::core delete $st($w,scene) $native}}
        _restoreSnapshot $w $before;return -options $options $message
    }
    set st($w,status) {Exact constituent copies created; the original logical object remains unchanged.}
}
proc ::GX::CurveWorkbench::_pathSplit {w} {
    variable st
    set ids [_commandSelection $w]
    if {[llength $ids]!=1} {error {Select one retained Path and its split location. No objects changed.}}
    set parent [lindex $ids 0];set record [_record $w $parent]
    if {![dict exists $record sketch_definition]} {tailcall _split $w}
    set family [dict get $record sketch_definition family]
    if {$family eq "compound"} {error {A Compound has no global traversal. Use Separate exact constituents.}}
    if {$family eq "composite_path"} {
        set parts [dict get $record sketch_definition parts];set choices {};set i 0
        foreach part [lrange $parts 0 end-1] {lappend choices "[incr i]: after [dict get $part definition family]"}
        if {$choices eq {}} {error {This Path has one constituent and no interior constituent junction.}}
        ::GX::uiFieldFormCreate $w.pathSplit {Split Path at an exact constituent junction; source preserved} [dict create junction [dict create type choice values $choices label {Reviewed split junction}]] [dict create junction [lindex $choices 0]] [list ::GX::CurveWorkbench::_pathSplitReviewed $w $st($w,token) $parent] $w
        return
    }
    if {$family ne "path"} {error {Select a retained straight or heterogeneous Path.}}
    set refs $st($w,sketchSelection)
    if {[llength $refs]!=1||[dict get [lindex $refs 0] semantic_kind] ne "control"} {error {Select one interior retained Path vertex to Split}}
    set index [expr {[dict get [lindex $refs 0] index]-1000000000}]
    return [_pathSplitCommit $w $st($w,token) $parent path_split $index]
}
proc ::GX::CurveWorkbench::_pathSplitReviewed {w token parent values} {
    set junction [lindex [split [dict get $values junction] :] 0]
    return [_pathSplitCommit $w $token $parent composition_split $junction]
}
proc ::GX::CurveWorkbench::_pathSplitCommit {w token parent operation index} {
    variable st
    if {$token ne $st($w,token)||$token ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen Split}}
    _coordinatePlaneAdmit $w [list $parent]
    set record [_record $w $parent]
    set before [_snapshotIds $w {}];
    set method [dict get {path_split split_path composition_split split_composition} $operation]
    set nativeIds [[_cadController $w] object $method [dict get $record native] $index]
    set created {};set members {}
    try {
        foreach native $nativeIds suffix {A B} {
            set id [_adoptPath $w $native "[dict get $record name] $suffix" [list $parent] [dict create operation $operation source $parent junction $index input_preserved 1]]
            lappend created $id;dict set before $id {};lappend members [dict create kind object id $native index 0]
        }
        _semanticApply $w $members;set st($w,active) [lindex $created 0];_selectionScene $w;_history $w $before $created
    } on error {message options} {
        foreach id $created {_removeRecord $w $id}
        foreach native $nativeIds {if {$native in [::GX::Native2D::core ids $st($w,scene)]} {::GX::Native2D::core delete $st($w,scene) $native}}
        _restoreSnapshot $w $before;return -options $options $message
    }
    set st($w,status) {Created two exact Path copies; source topology and geometry preserved.}
    return $created
}
