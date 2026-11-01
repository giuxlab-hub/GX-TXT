# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit scientific interpretation of unbound/undeclared coordinates.
# Unit Registry owns dimensions; Native2D owns geometry and canonical data stay intact.
proc ::GX::CurveWorkbench::_coordinateDeclaration {units rationale} {
    if {[llength $units]!=2} {error {Declare exactly one X unit and one Y unit}}
    foreach unit $units {
        if {$unit eq {} || ([dict get [::GX::unitRegistryDefinition $unit] conversion_kind] eq "opaque" && [catch {::GX::unitRegistryIntrinsicScale $unit}])} {error {Choose a registered or validated intrinsic physical unit for each axis, or 1 for dimensionless coordinates}}
    }
    set rationale [string trim $rationale]
    if {$rationale eq {}||[string length $rationale]>1024||[regexp {[\x00-\x1f]} $rationale]} {error {Record a single-line scientific reason for this declaration (1–1024 characters)}}
    return [dict create schema gxtxt.coordinate_declaration.v1 units $units rationale $rationale operation declare_coordinate_meaning numeric_values_changed 0 source_dataset_modified 0]
}
proc ::GX::CurveWorkbench::_coordinateDeclarationSession {w} {
    variable st
    if {![info exists st($w,token)]||$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen Curve Workbench}}
}
proc ::GX::CurveWorkbench::declareCoordinates {w ids units rationale} {
    variable st;_coordinateDeclarationSession $w
    _coordinateAxesAdmit $w $units
    set declaration [_coordinateDeclaration $units $rationale]
    if {$ids eq {}||[llength [lsort -unique $ids]]!=[llength $ids]} {error {Select distinct logical curves for the declaration}}
    set configured [list [dict get $st($w,coordinateConfiguration) x_unit] [dict get $st($w,coordinateConfiguration) y_unit]]
    if {$units ne $configured && ([lsort $ids] ne [lsort [dict keys $st($w,curves)]] || ([info exists st($w,images)] && [dict size $st($w,images)]))} {error {A coordinate declaration must preserve the populated workspace frame; declare the whole eligible frame explicitly or use a separate workspace}}
    _cancelGesture $w;_pointSyncApply $w
    set replacements {}
    foreach id $ids {
        set record [_record $w $id]
        if {([dict get $record locked]&&[dict get $record source] eq {})||[dict get $record parents] ne {}} {error {Declare an original source or unlocked unbound curve; derived geometry retains its parent coordinate meaning}}
        dict for {other candidate} $st($w,curves) {
            if {$id in [dict get $candidate parents]} {error {This curve has dependent geometry; create an independent scientific curve instead of changing its coordinate meaning}}
        }
        dict for {key constraint} $st($w,constraints) {
            foreach field {a b axis} {if {[dict exists $constraint definition $field]&&[dict get $constraint definition $field] eq $id} {error {Coordinate declarations cannot reinterpret an existing geometric constraint; preserve it and create an independent scientific curve}}}
        }
        if {[dict exists $record sketch_attributes gx.source_feature]} {error {Physical 3D planar geometry retains its source frame; create an independent numeric-plane object before declaring another meaning}}
        set previous [_coordinateUnits $record]
        if {[dict get $record source] ne {}} {
            if {[dict get $record x] eq [dict get $record y]&&[lindex $units 0] ne [lindex $units 1]} {error {One canonical Variable cannot acquire two different unit declarations}}
            set cache [_coordinateContext $w $id]
            if {[dict get $cache reason] ne {}} {error [dict get $cache reason]}
            set context [dict get $cache context]
            foreach axis {x y} unit $units old $previous {
                set vid [dict get $record $axis];set canonical [dict get $context variables $vid source unit]
                if {$canonical ne {}||[dict exists $record source_assumed_units $vid]} {
                    if {$unit ne $old} {error {Known source units require a compatible conversion or explicit derived Dataset normalization, not a declaration}}
                } else {
                    if {$old ne {}} {error {This source already has an interpreted working frame; preserve it and normalize explicitly}}
                    dict set record source_assumed_units $vid $unit
                }
            }
        }
        if {[dict get $record source] eq {}} {
            dict lappend record coordinate_frame_origins [dict create units $previous relations [_coordinateSourceRelations $record] snapshot [::GX::datasetPublicationV2DictDefault $record coordinate_snapshot {}] variables [::GX::datasetPublicationV2DictDefault $record coordinate_snapshot_variables {}] assumptions [::GX::datasetPublicationV2DictDefault $record source_assumed_units {}] conversions [::GX::datasetPublicationV2DictDefault $record coordinate_conversions {}]]
            dict unset record coordinate_snapshot
            dict unset record coordinate_snapshot_variables
            dict unset record source_assumed_units
            dict unset record coordinate_conversions
            dict set record coordinate_relations {}
        }
        dict set record coordinate_units $units;dict unset record working_unit
        dict lappend record coordinate_declarations [dict merge $declaration [dict create previous_units $previous]]
        dict lappend record operations [dict merge $declaration [dict create previous_units $previous]]
        dict set replacements $id $record
    }
    set before [_snapshotIds $w $ids];
    try {
        dict for {id record} $replacements {dict set st($w,curves) $id $record;dict unset st($w,coordinatePresentation) $id}
        dict set st($w,coordinateConfiguration) x_unit [lindex $units 0]
        dict set st($w,coordinateConfiguration) y_unit [lindex $units 1]
        set st($w,coordinateCache) {};set st($w,pointTableSignature) {}
        _coordinateFrameSync $w;_selectionScene $w;_history $w $before $ids
        _curveList $w;_pointList $w;_comparisonRefresh $w;_draw $w;_save $w
    } on error {message options} {_restoreSnapshot $w $before;return -options $options $message}
    set st($w,status) {Scientific axis meaning recorded. Geometry values and original Datasets are unchanged. Display conversion and physical scale remain separate.}
    return [dict merge $declaration [dict create curve_ids $ids]]
}
proc ::GX::CurveWorkbench::createCoordinateCurve {w name points units rationale} {
    variable st;_coordinateDeclarationSession $w
    _coordinateAxesAdmit $w $units
    set declaration [_coordinateDeclaration $units $rationale];set name [string trim $name]
    if {$name eq {}||[string length $name]>160||[regexp {[\x00-\x1f]} $name]||[llength $points]<2||[llength $points]>65536} {error {Enter a curve name and 2–65536 explicit physical XY points}}
    set target [_coordinateSourceFrame $w [dict create coordinate_units $units]]
    set before [_snapshotIds $w {}];set id {}
    # Native2D validates and, when needed, converts only the new geometry into
    # the established frame. Existing coordinates are never reinterpreted.
    set native [::GX::Native2D::core add $st($w,scene) $points]
    try {
        set conversion {}
        if {$target ne $units} {
            set conversion [::GX::native2DComparisonFrame x $units $units [dict create output_units $target]]
            ::GX::Native2D::core affine $st($w,scene) [list $native] [dict get $conversion reference_matrix] 0
        }
        if {[_coordinateWorkspaceEmpty $w]} {dict set st($w,coordinateConfiguration) x_unit [lindex $target 0];dict set st($w,coordinateConfiguration) y_unit [lindex $target 1]}
        set record [_newRecord $w $name [_sketchSamples $w $native] {} x y {} {} {} {} {} [list $declaration]]
        dict set record coordinate_units $target;dict set record coordinate_declarations [list $declaration]
        if {$conversion ne {}} {dict set record coordinate_conversions [list [dict create operation normalize_new_scientific_curve source_units $units target_units $target matrix [dict get $conversion reference_matrix] existing_geometry_modified 0]]}
        set id [dict get $record id];dict set before $id {};_addRecord $w $record $native
        set st($w,active) $id;set st($w,objectSelection) [list $id];_selectionScene $w
        ::GX::Native2D::core fit $st($w,scene);_coordinateMagnify $w 1
        _history $w $before [list $id];_save $w
    } on error {message options} {
        if {$id ne {}&&[dict exists $st($w,curves) $id]} {_removeRecord $w $id} elseif {$native in [::GX::Native2D::core ids $st($w,scene)]} {::GX::Native2D::core delete $st($w,scene) $native}
        _restoreSnapshot $w $before;return -options $options $message
    }
    return $id
}
proc ::GX::CurveWorkbench::_coordinateDeclareOpen {w {create 0}} {
    variable st
    set ids {};set units {1 1}
    if {!$create} {set ids [_commandSelection $w];set units [_coordinateUnits [_record $w [lindex $ids 0]]];set units [lmap unit $units {expr {$unit eq {}?"1":$unit}}]}
    set choices [lsort -unique [concat {1} [::GX::unitSelectorCandidates]]]
    set fields {};set values [dict create x [lindex $units 0] y [lindex $units 1] rationale {}]
    if {$create} {dict set fields name {type string label {Scientific curve name} required 1};dict set fields points {type string label {Physical points: {X Y} pairs} required 1};dict set values name {Scientific curve};dict set values points {}}
    foreach axis {x y} {dict set fields $axis [dict create type choice label "[string toupper $axis] declared physical unit" values $choices]}
    dict set fields rationale {type string label {Scientific reason / source of this unit declaration} required 1}
    set st($w,coordinateDeclarationDraft) [_snapshotIds $w $ids]
    ::GX::uiFieldFormCreate $w.declareaxes [expr {$create?{New scientific point curve}:{Declare scientific axis meaning}}] $fields $values [list ::GX::CurveWorkbench::_coordinateDeclareApply $w $st($w,token) $ids $create] $w
    ttk::label $w.declareaxes.note -text {Declare what the numbers mean. This does not convert, scale or calibrate them. Known Dataset units cannot be relabelled here; use compatible display conversion or explicit Dataset normalization. Existing constraints and dependent geometry keep their original meaning.} -wraplength 580
    pack $w.declareaxes.note -fill x -padx 10 -pady 8
}
proc ::GX::CurveWorkbench::_coordinateDeclareApply {w token ids create values} {
    variable st;_coordinateDeclarationSession $w
    if {$token ne $st($w,token)||$st($w,coordinateDeclarationDraft) ne [_snapshotIds $w $ids]} {error {Coordinate owners changed; reopen the declaration}}
    set units [list [dict get $values x] [dict get $values y]]
    if {$create} {set result [createCoordinateCurve $w [dict get $values name] [dict get $values points] $units [dict get $values rationale]]} else {set result [declareCoordinates $w $ids $units [dict get $values rationale]]}
    set st($w,coordinateDeclarationDraft) [_snapshotIds $w $ids]
    return $result
}
