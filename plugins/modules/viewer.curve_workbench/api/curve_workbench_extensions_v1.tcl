# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::CurveWorkbench {variable extensionTransactions {};variable extensionSerial 0}
proc ::GX::CurveWorkbench::_extensionContext {w} {
    variable st
    _cancelGesture $w;_pointSyncApply $w
    if {$st($w,document) eq {}} {_save $w}
    set owner [::GX::interactiveDocumentRead $st($w,document)];set units {};set active $st($w,active)
    if {$active ne {}} {dict set units x [lindex [_coordinateUnits [_record $w $active]] 0];dict set units y [lindex [_coordinateUnits [_record $w $active]] 1]}
    return [dict create workbench_id viewer.curve_workbench workbench_version $::GX::CurveWorkbench::version document_id $st($w,document) revision [dict get $owner revision] selection [dict create kind curve ids [_cadSelected $w] point_indices [_selected $w]] active_object $active active_group $st($w,cadGroup) working_plane {} units $units parameters {}]
}
proc ::GX::CurveWorkbench::_extensionBegin {context} {
    variable st;variable extensionTransactions;variable extensionSerial
    set w {}
    foreach key [array names st *,document] {if {$st($key) eq [dict get $context document_id]} {set w [string range $key 0 end-9];break}}
    if {$w eq {}||![winfo exists $w]||$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error "Workbench document owner is no longer available"}
    if {$st($w,publishBusy)||[info exists st($w,extensionBusy)]&&$st($w,extensionBusy)} {error "Finish the current Workbench operation first"}
    _cancelGesture $w;_pointSyncApply $w
    set id "extension-[pid]-[incr extensionSerial]-[clock clicks]"
    dict set extensionTransactions $id [dict create window $w context $context before [_snapshotIds $w [dict keys $st($w,curves)]] undo $st($w,undo) redo $st($w,redo) created {} modified {} deleted {}]
    set st($w,extensionBusy) 1
    return $id
}
proc ::GX::CurveWorkbench::_extensionRequire {transaction} {
    variable st;variable extensionTransactions
    if {![dict exists $extensionTransactions $transaction]} {error "Unknown or closed Workbench extension transaction"}
    set receipt [dict get $extensionTransactions $transaction];set w [dict get $receipt window];set context [dict get $receipt context]
    if {![winfo exists $w]||$st($w,token) ne [::GX::interactiveDocumentSessionToken]} {error "Workbench Session lifetime changed during extension execution"}
    set owner [::GX::interactiveDocumentRead [dict get $context document_id]]
    if {[dict get $owner revision]!=[dict get $context revision]||[dict get $owner generation] ne $st($w,ownerGeneration)} {error "Workbench document changed during extension execution"}
    return $receipt
}
proc ::GX::CurveWorkbench::_extensionTrack {transaction kind id} {variable extensionTransactions;set receipt [dict get $extensionTransactions $transaction];dict lappend receipt $kind $id;dict set extensionTransactions $transaction $receipt}
proc ::GX::CurveWorkbench::_extensionApply {transaction result} {
    variable st;variable extensionTransactions
    set receipt [_extensionRequire $transaction];set w [dict get $receipt window]
    if {![dict exists $result operations]} {error "Mutating extension must return structured operations"}
    dict set extensionTransactions $transaction provenance [::GX::datasetPublicationV2DictDefault $result provenance {}]
    set operations [dict get $result operations]
    if {[llength $operations]>256} {error "Extension transaction limit is 256 semantic operations"}
    foreach operation $operations {
        set action [dict get $operation operation]
        if {$action ni {affine create_sketch create_points replace_points delete identity replay_recipe}} {error "Unsupported extension geometry operation: $action"}
        set allowed [dict get {affine {operation target_ids matrix} create_sketch {operation name definition display_samples working_unit} create_points {operation name points working_unit} replace_points {operation target_ids points} delete {operation target_ids} identity {operation target_ids name attributes} replay_recipe {operation encoded}} $action]
        foreach key [dict keys $operation] {if {$key ni $allowed} {error "Unknown $action extension field: $key"}}
        set targets [::GX::datasetPublicationV2DictDefault $operation target_ids {}];set native {}
        foreach target $targets {
            set record [_record $w $target]
            if {[_bulkRecord $record]||[dict get $record locked]} {error "Extension target $target is read-only; use explicit Convert to Native where appropriate"}
            lappend native [dict get $record native]
        }
        switch -- $action {
            replay_recipe {
                set encoded [dict get $operation encoded];::GX::scientificRecipeValidate $encoded
                set recipe [::GX::scientificRecipeDecode $encoded]
                if {[dict get $recipe workbench_id] ne "viewer.curve_workbench"} {error "Recipe belongs to a different Workbench"}
                set old [dict keys $st($w,curves)];set new [_recipeApplyState $w $recipe]
                foreach id $new {_extensionTrack $transaction [expr {$id in $old ? "modified" : "created"}] $id}
                foreach id $old {if {$id ni $new} {_extensionTrack $transaction deleted $id}}
            }
            affine {
                if {$native eq {}} {error "Affine operation requires logical targets"}
                _cadUnits $w $targets
                ::GX::Native2D::core affine $st($w,scene) $native [dict get $operation matrix] 0
                foreach target $targets {_syncSamples $w $target;_extensionTrack $transaction modified $target}
            }
            replace_points {
                if {[llength $targets]!=1||[llength [dict get $operation points]]>65536} {error "Replace points requires one target and at most 65536 exact points"}
                set target [lindex $targets 0];::GX::Native2D::core replace $st($w,scene) [lindex $native 0] [dict get $operation points]
                _syncSamples $w $target;_extensionTrack $transaction modified $target
            }
            create_sketch - create_points {
                set name [string trim [dict get $operation name]];if {$name eq {}} {error "Extension geometry requires a name"}
                set unit [::GX::datasetPublicationV2DictDefault $operation working_unit {}];if {$unit ne {}} {::GX::unitRegistryConversionPlan $unit $unit}
                if {$action eq "create_sketch"} {set object [::GX::Native2D::core sketch_create $st($w,scene) [dict get $operation definition] [::GX::datasetPublicationV2DictDefault $operation display_samples 257]]} else {
                    if {[llength [dict get $operation points]]>65536} {error "Extension point input limit is 65536"}
                    set object [::GX::Native2D::core add $st($w,scene) [dict get $operation points]]
                }
                try {set record [_newRecord $w $name [_sketchSamples $w $object] {} x y {} {} {} {} {} [list [dict create operation extension_create geometry_operation $action]]];dict set record working_unit $unit;set id [dict get $record id];_addRecord $w $record $object} on error {message options} {::GX::Native2D::core delete $st($w,scene) $object;return -options $options $message}
                _extensionTrack $transaction created $id
            }
            delete {foreach target $targets {_removeRecord $w $target;_extensionTrack $transaction deleted $target}}
            identity {
                foreach target $targets {
                    set record [_record $w $target];set owner [dict get $record native]
                    if {[dict exists $operation name]} {::GX::Native2D::core identity_name $st($w,scene) $owner [dict get $operation name];dict set record name [dict get $operation name]}
                    if {[dict exists $operation attributes]} {dict for {key value} [dict get $operation attributes] {::GX::Native2D::core identity_attribute $st($w,scene) $owner $key $value;dict set record sketch_attributes $key $value}}
                    dict set st($w,curves) $target $record;_extensionTrack $transaction modified $target
                }
            }
        }
    }
    set receipt [dict get $extensionTransactions $transaction]
    return [dict create created_ids [lsort -unique [dict get $receipt created]] modified_ids [lsort -unique [dict get $receipt modified]] deleted_ids [lsort -unique [dict get $receipt deleted]] operations $operations]
}
proc ::GX::CurveWorkbench::_extensionCommit {transaction applied} {
    variable st;variable extensionTransactions
    set receipt [_extensionRequire $transaction];set w [dict get $receipt window];set before [dict get $receipt before]
    foreach id [dict get $applied created_ids] {dict set before $id {}}
    set ids [lsort -unique [concat [dict keys [dict remove $before @cad]] [dict get $applied created_ids]]]
    if {[dict get $applied created_ids] ne {}} {set st($w,active) [lindex [dict get $applied created_ids] 0]}
    foreach id [concat [dict get $applied created_ids] [dict get $applied modified_ids]] {
        if {[dict exists $st($w,curves) $id]} {set record [_record $w $id];dict lappend record operations [dict create operation extension_transaction parameters [dict get $applied operations] provenance [::GX::datasetPublicationV2DictDefault $receipt provenance {}]];dict set st($w,curves) $id $record}
    }
    set warnings {}
    if {[catch {_selectionScene $w;_history $w $before $ids} message options]} {
        set owner [::GX::interactiveDocumentRead $st($w,document)]
        if {[dict get $owner revision]==[dict get $receipt context revision]} {return -options $options $message}
        lappend warnings "Extension committed; subsequent presentation/recovery step failed: $message"
    }
    set revision [dict get [::GX::interactiveDocumentRead $st($w,document)] revision]
    set st($w,extensionBusy) 0;dict unset extensionTransactions $transaction
    set st($w,status) "Extension committed as one Undo action[expr {$warnings eq {} ? {.} : ": [join $warnings {; }]"}]"
    return [dict create revision $revision warnings $warnings]
}
proc ::GX::CurveWorkbench::_extensionRollback {transaction} {
    variable st;variable extensionTransactions
    if {![dict exists $extensionTransactions $transaction]} return
    set receipt [dict get $extensionTransactions $transaction];set w [dict get $receipt window]
    try {
        if {[winfo exists $w]&&$st($w,token) eq [::GX::interactiveDocumentSessionToken]} {
            set before [dict get $receipt before];foreach id [dict get $receipt created] {dict set before $id {}}
            _restoreSnapshot $w $before;set st($w,undo) [dict get $receipt undo];set st($w,redo) [dict get $receipt redo];_curveList $w;_pointList $w;_draw $w
        }
    } finally {if {[info exists st($w,extensionBusy)]} {set st($w,extensionBusy) 0};dict unset extensionTransactions $transaction}
}
proc ::GX::CurveWorkbench::_buildExtensions {w} {
    variable st
    ::GX::workbenchExtensionHostRegister viewer.curve_workbench [dict create begin ::GX::CurveWorkbench::_extensionBegin apply ::GX::CurveWorkbench::_extensionApply commit ::GX::CurveWorkbench::_extensionCommit rollback ::GX::CurveWorkbench::_extensionRollback]
    ttk::button $w.cad.extensions -text "Extensions…" -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::workbenchExtensionActionDialog $w.extensions [list ::GX::CurveWorkbench::_extensionContext $w] $w]]
    pack $w.cad.extensions -side left -padx 3
}
