# SPDX-License-Identifier: GPL-3.0-or-later
# UI orchestration of CORE canonical geometry, file publication and PDF services.
proc ::GX::CurveWorkbench::_installDatasetCommands {w} {
    _commandRegister $w object.spline_line {Convert Selected Spline Segment to Line} {} selection [list ::GX::CurveWorkbench::_splineLine $w]
    set menu $w.toolbar.workspace.menu
    $menu add separator
    foreach {label handler} {{Publish / Export as Sketch Dataset…} sketch {Commit changes to opened Sketch Dataset} commit {Export Current View as PDF…} current {Export Entire Workspace as PDF…} fit} {
        $menu add command -label $label -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_datasetExportOpen $w $handler] 1]
    }
}
proc ::GX::CurveWorkbench::_splineLine {w} {
    variable st
    _semanticSync $w
    set refs $st($w,sketchSelection)
    if {[llength $refs]!=1||[dict get [lindex $refs 0] entity] ne "segment"} {error {Select exactly one local Spline span.}}
    set ref [lindex $refs 0];set id [dict get $ref logical];set record [_record $w $id]
    # Named fragment ranges cannot be reinterpreted after changing the primitive
    # layout. Refuse instead of silently moving their geometric meaning.
    dict for {fragment entry} $st($w,sketchFragments) {
        if {[dict get $entry definition parent] eq $id} {error "Fragment $fragment depends on this Path's parameter intervals. Remove that fragment before changing Spline topology."}
    }
    set before [_snapshotIds $w [list $id]];set undo $st($w,undo);set redo $st($w,redo)
    try {
        if {[catch {set definition [::GX::Native2D::core spline_span_to_line $st($w,scene) [dict get $record native] [dict get $ref index]]} cause]} {error "Cannot convert this span without violating its geometry or constraints: $cause. No geometry changed."}
        dict set record sketch_definition $definition
        dict set record samples [_sketchSamples $w [dict get $record native]]
        dict set record sketch_samples [::GX::Native2D::core count $st($w,scene) [dict get $record native]]
        dict set record breaks [::GX::Native2D::core breaks $st($w,scene) [dict get $record native]]
        dict lappend record operations [dict create operation spline_span_to_line reference [dict get $ref index]]
        dict set st($w,curves) $id $record
        _constraintCapture $w
        _semanticApply $w {};_selectionScene $w
        _history $w $before [list $id]
    } on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $undo;set st($w,redo) $redo;return -options $options $message}
    set st($w,status) {Selected span converted to retained Line; adjacent exact curves and shared nodes preserved.}
}
proc ::GX::CurveWorkbench::_sketchContent {w {all 0}} {
    variable st
    _semanticSync $w
    set members [_semanticMembers $w]
    if {$all||![llength $members]} {
        set members {};dict for {id record} $st($w,curves) {lappend members [dict create kind object id [dict get $record native] index 0 valid 1]}
    }
    set reverse [_logicalNativeMap $w];set objects {};set full {};set partial {};set conversions {};set included {};set extracted {};set sources {};set selectionScope [expr {$all||![llength [_semanticMembers $w]]?"whole Workspace":"explicit selection"}]
    foreach member $members {
        set native [dict get $member id];set kind [dict get $member kind];set index [dict get $member index]
        if {![dict exists $reverse $native]} {error {Selection includes a non-geometric helper or fragment. Select its explicit geometry before export.}}
        set id [dict get $reverse $native];set record [_record $w $id];set defs {}
        foreach source [_sketchSourceLineage $record] {if {$source ni $sources} {lappend sources $source}}
        if {[dict get $record source] ne {}&&[dict get $record source] ni $sources} {lappend sources [dict get $record source]}
        if {[dict exists $record sketch_definition]} {
            set reference [expr {$kind eq "object"?3000000000:$index}]
            set defs [list [::GX::Native2D::core selection_definition $st($w,scene) $native $reference]]
        } else {
            if {[dict get $record source] ne {}} {_sourceSnapshotRequire $w $record}
            set defs [::GX::sketchDatasetPointGeometry $st($w,scene) $native $kind $index]
            lappend conversions "$id: exact XY vertices and gaps → [llength $defs] retained point/Polyline objects; source [dict get $record source]"
        }
        set part 0
        foreach definition $defs {
            set key [expr {$kind eq "object"&&[llength $defs]==1?$id:"${id}_${kind}_${index}_[incr part]"}]
            dict set objects $key [dict create name [dict get $record name] definition $definition units [_coordinateUnits $record] provenance [dict create source_dataset [dict get $record source] source_object $id selection $member operations [dict get $record operations]]]
            dict set objects $key metadata [dict merge [::GX::datasetPublicationV2DictDefault $record sketch_metadata {}] [::GX::datasetPublicationV2DictDefault $record sketch_attributes {}]]
            if {[dict exists $record sketch_provenance]} {dict set objects $key provenance origin [dict get $record sketch_provenance]}
            lappend included $key
            if {[dict exists $record sketch_definition]} {lappend extracted [dict create source $id native $native kind $kind index $index key $key]}
        }
        if {$kind eq "object"} {lappend full $id} else {lappend partial $id}
    }
    set parameters [::GX::sketchDatasetParameters [_parameterBind $w]];set warnings {}
    foreach objectId [dict keys $st($w,curves)] {if {$objectId ni $full&&$objectId ni $partial} {lappend warnings "Object $objectId is outside the explicit selection."}}
    if {$partial ne {}} {lappend warnings "Only selected local entities from [join $partial {, }] are exported; unselected constituents remain in the Workspace."}
    set constraints [::GX::sketchDatasetSubsetRelations $st($w,scene) $extracted [_constraintCapture $w]]
    dict for {constraintId constraint} $st($w,constraints) {if {![dict exists $constraints $constraintId]} {lappend warnings "Constraint $constraintId is outside the exported geometry or is represented by shared topology."}}
    dict for {id record} $constraints {
        if {[dict exists $record expression]} {dict set constraints $id expression [::GX::sketchDatasetParameterExpression [dict get $record expression] [dict get $parameters substitutions]]}
    }
    set sketch [dict create schema gxtxt.geometry.sketch version 1.0 objects $objects constraints $constraints parameters [dict get $parameters definitions] provenance [dict create producer viewer.curve_workbench workspace $st($w,document) conversions $conversions]]
    ::GX::sketchDatasetValidate $sketch
    return [dict create sketch $sketch included $included conversions $conversions warnings $warnings source_dataset_ids $sources scope $selectionScope]
}
proc ::GX::CurveWorkbench::_datasetExportOpen {w mode} {
    variable st
    if {$mode eq "commit"} {return [_datasetCommit $w]}
    ::GX::uiFieldFormCreate $w.datasetExport [expr {$mode eq "sketch"?"Publish canonical Sketch Dataset":"Publish PDF Dataset — $mode"}] {dataset_id {type string required 1 label {New Dataset ID}}} [dict create dataset_id "[expr {$mode eq "sketch"?"sketch":"pdf"}]_[clock seconds]"] [list ::GX::CurveWorkbench::_datasetExportApply $w $mode] $w
}
proc ::GX::CurveWorkbench::_datasetExportApply {w mode values} {
    variable st
    set id [dict get $values dataset_id]
    if {$mode eq "sketch"} {
        set report [_sketchContent $w]
        set result [::GX::sketchDatasetPublish [_session] viewer.curve_workbench $id [dict get $report sketch] [dict create source_dataset_ids [dict get $report source_dataset_ids]]]
        _datasetReport $w $id $report
        set st($w,status) "Published Sketch $id: [join [dict get $report included] {, }]. [join [dict get $report conversions] {; }]"
    } else {
        set channel [file tempfile path];close $channel
        try {
            ::GX::native2DCanvasPreview $st($w,scene) $st($w,document) $mode [dict create output_format pdf output_file $path width 1400 annotations 1 dimensions $st($w,showDimensions) constraints $st($w,showConstraints) point_budget 65536]
            set result [::GX::datasetFilePublicationPublish [_session] viewer.curve_workbench [dict create dataset_id $id contract document.pdf format pdf storage_kind binary media_type application/pdf source_file $path provenance "Curve Workbench $mode graphical export; Workspace $st($w,document)"]]
        } finally {file delete -force $path}
        set st($w,status) "Published PDF Dataset $id ($mode). Open Dataset in the Dataset browser to read it."
    }
    catch {::GX::refreshDatasetChoices}
    return $result
}
proc ::GX::CurveWorkbench::_datasetCommit {w} {
    variable st
    if {![info exists st($w,sketchDataset)]} {error {Open a published Sketch Dataset before committing changes. Workspace Save remains independent.}}
    set binding $st($w,sketchDataset);set id [dict get $binding id]
    set report [_sketchContent $w 1]
    _save $w
    set receipt [::GX::sketchDatasetPublish [_session] viewer.curve_workbench $id [dict get $report sketch] [dict create replace_owned 1 expected_sha256 [dict get $binding sha256] source_dataset_ids [dict get $report source_dataset_ids]]]
    dict set st($w,sketchDataset) sha256 [dict get $receipt sha256]
    if {[catch {_save $w} reason]} {
        set st($w,status) "Canonical Sketch $id committed, but draft save failed: $reason. Retry Workspace Save or reopen the canonical Dataset."
        dict set receipt draft_saved 0
        dict set receipt recovery {Canonical revision is retained. Retry Workspace Save, or reopen Dataset into a new draft.}
        _datasetReport $w $id [dict merge $report [dict create warnings [list $st($w,status)]]]
        return $receipt
    }
    dict set receipt draft_saved 1
    set st($w,status) "Committed Sketch Dataset $id."
    return $receipt
}
proc ::GX::CurveWorkbench::_datasetImportApply {w id} {
    variable st
    set sketch [::GX::sketchDatasetRead [_session] $id]
    if {[dict size $st($w,curves)]} {error {Sketch import requires a new Workspace}}
    set mapping {}
    foreach key [dict keys [dict get $sketch objects]] {
        if {[regexp {^curve([0-9]+)$} $key -> ordinal] && $ordinal>$st($w,next)} {set st($w,next) $ordinal}
    }
    dict for {key object} [dict get $sketch objects] {
        set native [::GX::Native2D::core sketch_create $st($w,scene) [dict get $object definition] 257]
        set record [_newRecord $w [dict get $object name] [_sketchSamples $w $native] {} x y {} {} {} {} {} [list [dict create operation import_sketch dataset $id object $key]]]
        dict set record id $key
        dict set record sketch_metadata [::GX::datasetPublicationV2DictDefault $object metadata {}]
        dict set record sketch_provenance [::GX::datasetPublicationV2DictDefault $object provenance {}]
        dict set record sketch_provenance source_dataset_ids [::GX::datasetFilePublicationSourceIds [::GX::datasetField $id source_dataset_ids {}]]
        dict set record sketch_units [dict get $object units]
        if {[llength [lsort -unique [dict get $object units]]]==1&&[lindex [dict get $object units] 0] ne {}} {dict set record working_unit [lindex [dict get $object units] 0]}
        set logical [dict get $record id];dict set mapping $key $logical
        _addRecord $w $record $native
    }
    set st($w,active) [lindex [dict values $mapping] 0]
    dict for {key record} [dict get $sketch constraints] {
        set spec [dict get $record definition]
        foreach field {a b axis} {if {[dict exists $spec $field]} {dict set spec $field [dict get $mapping [dict get $spec $field]]}}
        dict set record definition $spec
        set receipt [::GX::Native2D::core constraint_create $st($w,scene) [_constraintNativeSpec $w $spec]]
        dict set record native [dict get $receipt id]
        dict set st($w,constraints) $key $record
        if {[regexp {^constraint([0-9]+)$} $key -> ordinal] && $ordinal>$st($w,nextConstraint)} {set st($w,nextConstraint) $ordinal}
    }
    set st($w,sketchDataset) [dict create id $id sha256 [::GX::datasetField $id sha256 [::GX::datasetField $id canonical_sha256 {}]]]
    _selectionScene $w;_fit $w
    # Publish the complete reconstructed geometry once, then restore parameters
    # through CORE while autosaving is suspended. The outer transaction rolls
    # back the newly created document if any late operation fails.
    _writeWorkspace $w
    ::GX::_parameterWrite [_parameterBind $w] [dict get $sketch parameters]

    set st($w,status) "Opened Sketch Dataset $id as an editable draft. Use Commit changes to update the Dataset; Workspace Save saves the draft."
}

proc ::GX::CurveWorkbench::_datasetImport {w id} {
    variable st
    if {[dict size $st($w,curves)]} {error {Sketch import requires a new empty Workspace.}}
    ::GX::sketchDatasetRead [_session] $id
    set before [_recipeState $w];set prior $st($w,document);set original {}
    if {$prior ne {}} {set original [dict get [::GX::interactiveDocumentRead $prior] payload]}
    set st($w,importTransaction) 1
    try {
        _datasetImportApply $w $id
        unset st($w,importTransaction)
        _save $w
    } on error {message options} {
        set st($w,importTransaction) 1
        if {[info exists st($w,parameterContext)]} {catch {::GX::parameterUnsubscribe $st($w,parameterContext)};unset st($w,parameterContext)}
        if {$st($w,document) ne {}&&$st($w,document) ne $prior} {
            set created $st($w,document);set st($w,document) {}
            if {[info exists st($w,lifecycleSubscription)]} {::GX::interactiveDocumentLifecycleUnsubscribe $st($w,lifecycleSubscription);unset st($w,lifecycleSubscription)}
            ::GX::interactiveDocumentDelete $created
        } elseif {$prior ne {}} {::GX::interactiveDocumentUpdate $prior $original}
        foreach key [dict keys $st($w,curves)] {dict set before $key {}}
        _restoreSnapshot $w $before
        set st($w,document) $prior
        unset -nocomplain st($w,ownerGeneration) st($w,sketchDataset) st($w,importTransaction)
        return -options $options "Sketch import rolled back: $message"
    } finally {unset -nocomplain st($w,importTransaction)}
}
proc ::GX::CurveWorkbench::_datasetReport {w id report} {
    set d $w.exportReport;catch {destroy $d};toplevel $d;wm title $d "Sketch publication report — $id"
    wm geometry $d 760x440
    text $d.text -wrap word;ttk::scrollbar $d.scroll -command [list $d.text yview]
    $d.text configure -yscrollcommand [list $d.scroll set]
    ttk::button $d.close -text Close -command [list destroy $d];pack $d.close -side bottom -pady 6
    pack $d.scroll -side right -fill y;pack $d.text -fill both -expand 1
    $d.text insert end "Destination Dataset: $id\nScope: [dict get $report scope]\n\n"
    foreach {key title} {included {Objects / local entities} conversions {Scientific-to-geometric conversions} source_dataset_ids {Source Dataset identities} warnings {Warnings / omissions / dependencies}} {
        $d.text insert end "$title\n[join [dict get $report $key] \n]\n\n"
    }
    $d.text configure -state disabled
}

proc ::GX::CurveWorkbench::_sketchSourceLineage {record {depth 0}} {
    if {$depth>16||[catch {dict size $record}]} {return {}}
    set result {}
    dict for {key value} $record {
        if {$key in {source source_dataset source_dataset_id source_dataset_ids}&&$value ne {}} {
            foreach id [::GX::datasetFilePublicationSourceIds $value] {if {![catch {::GX::datasetPublicationV2ValidateId dataset $id}]&&$id ni $result} {lappend result $id}}
        } elseif {$key in {provenance sketch_provenance origin source_descriptor}} {
            foreach id [_sketchSourceLineage $value [expr {$depth+1}]] {if {$id ni $result} {lappend result $id}}
        } elseif {$key eq "source_identities"} {
            foreach identity $value {if {[dict exists $identity dataset_id]} {set id [dict get $identity dataset_id];if {$id ni $result} {lappend result $id}}}
        }
    }
    return $result
}
