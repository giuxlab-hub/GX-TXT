# SPDX-License-Identifier: GPL-3.0-or-later
# Curve supplies scientific hooks. CORE owns History state, workers and controls.
proc ::GX::CurveWorkbench::_historyBrowsing {w} {
    variable st
    return [expr {[info exists st($w,historyReady)] && $st($w,historyReady) && [dict get [::GX::scientificHistoryViewerRestoreContext $w] browsing]}]
}
proc ::GX::CurveWorkbench::_historyGuard {w} {
    variable st
    if {![info exists st($w,token)] || $st($w,token) ne [::GX::interactiveDocumentSessionToken] || $st($w,publishBusy) && ![info exists st($w,historySubmitting)]} {return 0}
    foreach key {drag pointDrag directionDrag annotationDrag handleDrag tangentDrag cadDrag} {
        if {[info exists st($w,$key)] && $st($w,$key) ne {}} {return 0}
    }
    return 1
}
proc ::GX::CurveWorkbench::_historyCad {w} {return [dict get [_snapshotIds $w {}] @cad]}
proc ::GX::CurveWorkbench::_historyAuxCapture {w} {
    variable st
    set auxiliary [dict create format gxtxt.curve_presentation.v1 fields {} native {} selection {}]
    foreach key {next nextGroup nextConstraint nextMeasurement nextFragment nextSelectionSet nextLayer nextSavedView nextSeries nextImage active reference target externalFeedback bridgeKind bridgeSubdivisions bridgeTolerance fragments composeName resultId cadGroup cadTarget cadTool cadObjectSnap coordinatePresentation coordinateView coordinateFrameViews metric directionShown gridShown gridSnap leftVisible listVisible pointsVisible composeVisible compareVisible comparisonEnabled comparisonConfig comparisonRecord lastGeometricComparison publicationArrangement publicationRepresentation showConstraints showDimensions} {
        if {[info exists st($w,$key)]} {dict set auxiliary fields $key $st($w,$key)}
    }
    foreach key {view_requested aspect background grid presentation gizmo} {dict set auxiliary native $key [::GX::Native2D::core $key $st($w,scene)]}
    if {![catch {set pivot [::GX::Native2D::core pivot $st($w,scene)]}]} {dict set auxiliary native pivot $pivot}
    set reverse [_logicalNativeMap $w]
    foreach member [_semanticMembers $w] {
        if {![dict get $member valid]} continue
        set native [dict get $member id];set kind [dict get $member kind]
        if {$kind eq {fragment}} {
            dict for {logical record} $st($w,sketchFragments) {if {[dict exists $record native] && [dict get $record native]==$native} {dict lappend auxiliary selection [dict create logical $logical kind fragment index 0];break}}
        } elseif {[dict exists $reverse $native]} {dict lappend auxiliary selection [dict create logical [dict get $reverse $native] kind $kind index [dict get $member index]]}
    }
    if {$st($w,active) ne {} && $st($w,selectionObject) ne {}} {dict set auxiliary point_selection [_pointSelectionDescriptor $w]}
    return $auxiliary
}
proc ::GX::CurveWorkbench::_historyAuxRestore {w auxiliary} {
    variable st
    if {$auxiliary eq {}} return
    if {![dict exists $auxiliary format] || [dict get $auxiliary format] ne {gxtxt.curve_presentation.v1}} {error {Unsupported Curve History presentation state}}
    set st($w,historyRestoring) 1
    try {
        dict for {key value} [dict get $auxiliary fields] {
            if {$key ni {next nextGroup nextConstraint nextMeasurement nextFragment nextSelectionSet nextLayer nextSavedView nextSeries nextImage active reference target externalFeedback bridgeKind bridgeSubdivisions bridgeTolerance fragments composeName resultId cadGroup cadTarget cadTool cadObjectSnap coordinatePresentation coordinateView coordinateFrameViews metric directionShown gridShown gridSnap leftVisible listVisible pointsVisible composeVisible compareVisible comparisonEnabled comparisonConfig comparisonRecord lastGeometricComparison publicationArrangement publicationRepresentation showConstraints showDimensions}} {error {Unknown Curve presentation field}}
            if {$key in {next nextGroup nextConstraint nextMeasurement nextFragment nextSelectionSet nextLayer nextSavedView nextSeries nextImage}} {
                if {![string is entier -strict $value] || $value<0} {error {Invalid recovered Curve allocation counter}}
                set value [expr {max($st($w,$key),$value)}]
            }
            set st($w,$key) $value
        }
        if {![dict exists $st($w,curves) $st($w,active)]} {set st($w,active) [lindex [dict keys $st($w,curves)] 0]}
        set members {}
        foreach member [dict get $auxiliary selection] {
            set logical [dict get $member logical]
            if {[dict get $member kind] eq {fragment}} {
                if {[dict exists $st($w,sketchFragments) $logical native]} {lappend members [dict create kind fragment id [dict get $st($w,sketchFragments) $logical native] index 0]}
            } elseif {[dict exists $st($w,curves) $logical]} {lappend members [dict create kind [dict get $member kind] id [dict get $st($w,curves) $logical native] index [dict get $member index]]}
        }
        _semanticApply $w $members
        _selectionScene $w
        if {[dict exists $auxiliary point_selection] && $st($w,selectionObject) ne {}} {_restorePointSelectionDescriptor $w [dict get $auxiliary point_selection]}
        set native [dict get $auxiliary native]
        foreach key {aspect background grid presentation gizmo} {if {[dict exists $native $key]} {::GX::Native2D::core $key $st($w,scene) [dict get $native $key]}}
        if {[dict exists $native pivot]} {set pivot [dict get $native pivot];if {[dict get $pivot mode] eq {custom}} {::GX::Native2D::core pivot $st($w,scene) custom [dict get $pivot point]} elseif {$members ne {}} {::GX::Native2D::core pivot $st($w,scene) [dict get $pivot mode]}}
        if {[dict exists $native view_requested]} {::GX::Native2D::core view $st($w,scene) [dict get $native view_requested]}
        _restoreViewportPreferences $w
        _curveList $w;_pointList $w;_draw $w
    } finally {unset -nocomplain st($w,historyRestoring)}
}
proc ::GX::CurveWorkbench::_historyUndoAux {w before} {
    set auxiliary [_historyAuxCapture $w]
    if {![dict exists $before @cad]} {return $auxiliary}
    set cad [dict get $before @cad]
    foreach {field key} {active active cadGroup target_group cadTarget target_scope cadTool tool cadObjectSnap object_snap coordinatePresentation coordinate_presentation coordinateView coordinate_view coordinateFrameViews coordinate_frame_views metric coordinate_metric bridgeTolerance bridge_tolerance lastGeometricComparison geometric_comparison} {
        if {[dict exists $cad $key]} {dict set auxiliary fields $field [dict get $cad $key]}
    }
    foreach key {grid presentation view_requested pivot gizmo} {if {[dict exists $cad $key]} {dict set auxiliary native $key [dict get $cad $key]}}
    if {[dict exists $cad semantic_selection]} {dict set auxiliary selection [dict get $cad semantic_selection]}
    if {[dict exists $cad point_selection]} {dict set auxiliary point_selection [dict get $cad point_selection]} else {dict unset auxiliary point_selection}
    if {[dict exists $cad viewport_preferences]} {dict for {key value} [dict get $cad viewport_preferences] {dict set auxiliary fields $key $value}}
    foreach {key field} {enabled comparisonEnabled config comparisonConfig record comparisonRecord} {if {[dict exists $cad explicit_comparison $key]} {dict set auxiliary fields $field [dict get $cad explicit_comparison $key]}}
    return $auxiliary
}
proc ::GX::CurveWorkbench::_historyCapture {w} {
    set snapshot [_recipeState $w]
    dict set snapshot @cad [_historyCad $w]
    return $snapshot
}
proc ::GX::CurveWorkbench::_historyDescribe {w row} {
    variable st
    set importedKind {}
    if {[info exists st($w,descriptionProjection)] && [dict exists $row patch]} {
        # A temporary UI projection during CORE's ordered import callback.
        # Fold only metadata/identity membership; never replay scientific states.
        set before $st($w,descriptionProjection);set next $before
        if {[dict exists $row patch @cad]} {
            set cad [dict get $row patch @cad]
            dict set next constraints [::GX::datasetPublicationV2DictDefault $cad constraints {}]
            dict set next parameters [::GX::datasetPublicationV2DictDefault $cad parameter_definitions {}]
        }
        dict for {id value} [dict remove [dict get $row patch] @cad] {
            if {$value in {{} @gxtxt.recipe.delete}} {dict unset next ids $id} else {dict set next ids $id 1}
        }
        if {[dict get $before constraints] ne [dict get $next constraints]} {set importedKind [expr {[dict size [dict get $next constraints]]>[dict size [dict get $before constraints]] ? {constraint_add} : {constraint_edit}}]} elseif {[dict get $before parameters] ne [dict get $next parameters]} {set importedKind parameter} elseif {[dict size [dict get $next ids]]>[dict size [dict get $before ids]]} {set importedKind create} elseif {[dict size [dict get $next ids]]<[dict size [dict get $before ids]]} {set importedKind delete}
        set st($w,descriptionProjection) $next
    }
    set names {}
    if {[dict exists $row parameters]} {
        dict for {id operations} [dict get $row parameters] {
            if {![llength $operations]} continue
            set last [lindex $operations end]
            if {[catch {dict size $last}]} {lappend names [lindex $last 0]} else {lappend names [::GX::datasetPublicationV2DictDefault $last operation edit]}
        }
    }
    set kind [::GX::datasetPublicationV2DictDefault $row kind {}]
    if {$kind eq {}} {set kind $importedKind}
    if {$kind eq {}} {set kind [expr {[llength [lsort -unique $names]]==1 ? [lindex $names 0] : {edit}}]}
    set description [::GX::datasetPublicationV2DictDefault $row description {}]
    if {$description eq {} || $description in {geometry_state update_logical_geometry}} {set description [string totitle [string map {_ { }} $kind]]}
    set result [dict create description $description kind $kind]
    if {$kind in {create create_primitive constraint_add translate rotate scale}} {dict set result group $kind;dict set result group_label $description}
    return $result
}
proc ::GX::CurveWorkbench::_historyError {w receipt} {
    variable st
    if {[info exists st($w,recoveryNotice)]} {set st($w,recoveryNotice) "History warning: [dict get $receipt error]. Accepted RAM state remains available; retry Save or export before closing."}
}
proc ::GX::CurveWorkbench::_historyAccepted {w receipt} {
    variable st
    set st($w,historyDirty) 1
}
proc ::GX::CurveWorkbench::_historyAttach {w} {
    variable st
    set seed $st($w,historySeed)
    if {$seed ne {} && (![dict exists $seed format] || ![dict exists $seed cursor] || ![dict exists $seed workbench_id])} {
        set header [::GX::scientificHistoryCreate viewer.curve_workbench [dict get $seed base]]
        set seed [dict merge $header $seed [dict create workbench_id viewer.curve_workbench retention complete legacy_import 1]]
        if {![dict exists $st($w,historySeed) cursor]} {dict set seed cursor [llength [dict get $seed steps]]}
    }
    set callbacks [dict create document_id $st($w,document) capture [list ::GX::CurveWorkbench::_historyCapture $w] restore [list ::GX::CurveWorkbench::_historyRestore $w] commit [list ::GX::CurveWorkbench::_historyProject $w] guard [list ::GX::CurveWorkbench::_historyGuard $w] accepted [list ::GX::CurveWorkbench::_historyAccepted $w] error [list ::GX::CurveWorkbench::_historyError $w] describe [list ::GX::CurveWorkbench::_historyDescribe $w] context [list ::GX::CurveWorkbench::_historyContext $w] context_action [list ::GX::CurveWorkbench::_historyContextAction $w]]
    dict set callbacks capture_aux [list ::GX::CurveWorkbench::_historyAuxCapture $w]
    dict set callbacks restore_aux [list ::GX::CurveWorkbench::_historyAuxRestore $w]
    if {$st($w,historyAuxSeed) ne {}} {dict set callbacks auxiliary $st($w,historyAuxSeed)}
    if {$st($w,historyRecoveryChoice) ne {}} {dict set callbacks recovery_choice $st($w,historyRecoveryChoice)}
    set base [expr {$seed eq {} ? [dict create @cad [_historyCad $w]] : [dict get $seed base]}]
    set ids {};foreach id [expr {$seed eq {} ? [dict keys $st($w,curves)] : [dict keys [dict remove $base @cad]]}] {dict set ids $id 1}
    set cad [::GX::datasetPublicationV2DictDefault $base @cad {}]
    set st($w,descriptionProjection) [dict create constraints [::GX::datasetPublicationV2DictDefault $cad constraints {}] parameters [::GX::datasetPublicationV2DictDefault $cad parameter_definitions {}] ids $ids]
    try {set attached [::GX::scientificHistoryViewerAttach $w viewer.curve_workbench $callbacks $seed]} finally {unset st($w,descriptionProjection)}
    set st($w,historyReady) 1;set st($w,historyDirty) [expr {$seed eq {} ? [dict get [::GX::scientificHistoryViewerStatus $w] count]>0 : ($attached ne $seed || ($st($w,historyAuxSeed) ne {} && [::GX::scientificHistoryViewerAuxiliary $w] ne $st($w,historyAuxSeed)))}];set st($w,historyDocument) $st($w,document)
    unset st($w,historySeed) st($w,historyAuxSeed)
    ::GX::scientificHistoryViewerStrip $w $w $w.status {} [list -side bottom -fill x -before $w.main]
}
proc ::GX::CurveWorkbench::_historyScientificCad {cad} {
    return [dict remove $cad active selection target_group target_scope tool object_snap pivot gizmo grid presentation view_requested coordinate_presentation coordinate_view coordinate_frame_views coordinate_metric point_selection viewport_preferences semantic_selection explicit_comparison geometric_comparison comparison_method bridge_tolerance publication_arrangement publication_representation show_constraints show_dimensions]
}
proc ::GX::CurveWorkbench::_historySubmit {w before ids} {
    variable st
    if {![info exists st($w,historyReady)] || !$st($w,historyReady)} {return}
    set st($w,historySubmitting) 1;set accepted 0
    try {
        if {[_historyBrowsing $w]} {error {History is read-only. Return to Latest or explicitly restart here.}}
        if {![::GX::scientificHistoryViewerPrepareEdit $w]} {_restoreSnapshot $w $before;_draw $w;return [dict create accepted 0 status cancelled]}
        foreach id [_sketchAffected $w [dict keys [dict remove $before @cad]]] {
            if {[dict exists $st($w,curves) $id] && [dict exists [_record $w $id] sketch_definition]} {_syncSamples $w $id}
            if {$id ni $ids} {lappend ids $id}
        }
        set st($w,historyRecording) 1
        try {_changed $w} finally {unset st($w,historyRecording)}
        set after [_snapshotIds $w $ids];dict set after @cad [_historyCad $w]
        if {[dict exists $before @cad] && [dict remove $before @cad] eq [dict remove $after @cad] && [_historyScientificCad [dict get $before @cad]] eq [_historyScientificCad [dict get $after @cad]]} {
            return [_save $w]
        }
        set patch {};set operations {};set created 0;set deleted 0
        dict for {id value} $after {
            if {$id ne {@cad} && $value eq {}} {dict set patch $id @gxtxt.recipe.delete;incr deleted} else {dict set patch $id $value}
            if {$id ne {@cad} && $value ne {}} {
                if {[dict exists $value operations]} {dict set operations $id [dict get $value operations]}
                if {[dict exists $before $id] && [dict get $before $id] eq {}} {incr created}
            }
        }
        set kind edit
        if {$created} {set kind create} elseif {$deleted} {set kind delete} elseif {[dict exists $before @cad]} {
            set old [dict get $before @cad];set new [dict get $after @cad]
            if {[::GX::datasetPublicationV2DictDefault $old constraints {}] ne [::GX::datasetPublicationV2DictDefault $new constraints {}]} {set kind [expr {[dict size [dict get $new constraints]]>[dict size [::GX::datasetPublicationV2DictDefault $old constraints {}]] ? {constraint_add} : {constraint_edit}}]} elseif {[::GX::datasetPublicationV2DictDefault $old parameter_definitions {}] ne [::GX::datasetPublicationV2DictDefault $new parameter_definitions {}]} {set kind parameter}
        }
        set semantic [dict create api_id SCIENTIFIC_RECIPE_API_v1 geometry_api_id NATIVE_2D_GEOMETRY_API_v1 api_version 1 operation geometry_state semantic_operation update_logical_geometry parameters $operations targets $ids result_ids [dict keys $st($w,curves)] working_unit [_recipeUnit $after]]
        dict set semantic undo_auxiliary [_historyUndoAux $w $before]
        if {$kind ne {edit}} {dict set semantic kind $kind}
        set presentation [_historyDescribe $w $semantic]
        dict set semantic kind [dict get $presentation kind]
        set receipt [::GX::scientificHistoryViewerSubmitPatch $w $patch [dict get $presentation description] $semantic]
        set accepted 1
        return $receipt
    } on error {message options} {
        if {!$accepted} {catch {_restoreSnapshot $w $before};catch {_draw $w}}
        return -options $options $message
    } finally {unset -nocomplain st($w,historySubmitting)}
}
proc ::GX::CurveWorkbench::_historyRestore {w desired} {
    variable st
    set context [::GX::scientificHistoryViewerRestoreContext $w];set mode [dict get $context mode]
    set token [_parameterBind $w]
    set st($w,historyRestoring) 1;set st($w,importTransaction) 1
    try {
        if {$token ne {}} {
            set cad [dict get $desired @cad]
            set definitions [::GX::datasetPublicationV2DictDefault $cad parameter_definitions {}]
            set shared [::GX::datasetPublicationV2DictDefault $cad session_parameters [::GX::parameterSessionDefinitions]]
            if {$mode eq {browse} || ($mode eq {rollback} && [dict get $context browsing])} {
                ::GX::parameterReadView $token $definitions $shared
            } else {
                if {$mode eq {branch} && $shared ne [::GX::parameterSessionDefinitions]} {error {Historical Session parameters differ from the live shared scope. Reconcile them explicitly before restarting.}}
                ::GX::parameterReadViewClose $token
                if {$mode in {undo redo branch seek rollback} && [::GX::parameterDefinitions $token] ne $definitions} {::GX::_parameterWrite $token $definitions}
            }
        }
        _recipeApplyState $w [dict create base $desired steps {}]
        if {[dict exists $desired @cad history_presentation]} {
            set display [dict get $desired @cad history_presentation]
            dict for {key value} [dict remove $display native] {if {$key eq {next}} {set value [expr {max($st($w,next),$value)}]};set st($w,$key) $value}
            if {[dict exists $display native]} {dict for {key value} [dict get $display native] {::GX::Native2D::core $key $st($w,scene) $value}}
        }
        if {$mode eq {undo} && [dict get $context cursor]>0} {
            set operation [::GX::scientificHistoryViewerOperation $w [dict get $context cursor]]
            if {[dict exists $operation undo_auxiliary]} {_historyAuxRestore $w [dict get $operation undo_auxiliary]}
        }
        _curveList $w;_pointList $w;_draw $w
    } finally {unset -nocomplain st($w,historyRestoring) st($w,importTransaction)}
}
proc ::GX::CurveWorkbench::_timelineState {w index} {return [::GX::scientificHistoryViewerStateAt $w $index]}
proc ::GX::CurveWorkbench::_timelineBuild {w} {
    variable st
    set st($w,stripVisible) 1;set st($w,stripView) Description
    $w.toolbar.workspace.menu add command -label {Clear History…} -command [list ::GX::CurveWorkbench::_safe $w [list ::GX::CurveWorkbench::_clearHistory $w]]
    $w.toolbar.settings.menu add checkbutton -label {Show Description / History strip} -variable ::GX::CurveWorkbench::st($w,stripVisible) -command [list ::GX::CurveWorkbench::_timelineShow $w]
    set previous [$w.toolbar.settings.menu cget -postcommand]
    $w.toolbar.settings.menu configure -postcommand [list ::GX::CurveWorkbench::_timelineSettingsPost $w $previous]
}
proc ::GX::CurveWorkbench::_timelineSettingsPost {w previous} {
    variable st
    if {$previous ne {}} {uplevel #0 $previous}
    if {[info exists st($w,historyReady)] && $st($w,historyReady)} {set st($w,stripVisible) [dict get [::GX::scientificHistoryViewerStripGet $w] visible]}
}
proc ::GX::CurveWorkbench::_timelineShow {w} {variable st;::GX::scientificHistoryViewerStripSet $w [dict create visible $st($w,stripVisible)]}
proc ::GX::CurveWorkbench::_timelineSwitch {w} {variable st;::GX::scientificHistoryViewerStripSet $w [dict create mode $st($w,stripView)]}
proc ::GX::CurveWorkbench::_timelineRender {w} {return}
proc ::GX::CurveWorkbench::_timelineBrowse {w index {mode legacy}} {_cancelGesture $w;return [::GX::scientificHistoryViewerBrowse $w $index $mode]}
proc ::GX::CurveWorkbench::_timelineRestart {w index} {_timelineBrowse $w $index index;return [::GX::scientificHistoryViewerNavigate $w branch]}
proc ::GX::CurveWorkbench::_timelineExpand {w first} {::GX::scientificHistoryViewerGroupExpand $w $first}
proc ::GX::CurveWorkbench::_clearHistory {w} {variable st;return [::GX::scientificHistoryViewerClear $w $st($w,document)]}
proc ::GX::CurveWorkbench::_historyContext {w menu index} {
    foreach id [_timelineConstraints $w $index] {
        foreach {action title} {inspect {Select / inspect} edit {Restart here, then edit} remove {Restart here, then remove}} {
            $menu add command -label "$title constraint $id (step $index)…" -command [list ::GX::scientificHistoryViewerContextAction $w constraint [list $index $id $action]]
        }
    }
    $menu add command -label {Inspect constraints / dimensions…} -command [list ::GX::scientificHistoryViewerContextAction $w dimensions]
}
proc ::GX::CurveWorkbench::_historyContextAction {w action payload} {
    switch $action {
        constraint {_timelineConstraint $w {*}$payload}
        dimensions {_constraintOpen $w}
        default {error {Unknown Curve History domain action}}
    }
}
proc ::GX::CurveWorkbench::_replaceDecision {w} {
    variable st
    if {[_historyBrowsing $w]} {::GX::scientificHistoryViewerNavigate $w latest}
    if {![info exists st($w,historyDirty)] || !$st($w,historyDirty)} {return 1}
    set answer [tk_messageBox -parent $w -type yesnocancel -default cancel -title {Save current Workspace?} -message {Yes: Save, then continue. No: discard unsaved changes. Cancel: keep editing.}]
    if {$answer eq {cancel}} {return 0}
    if {$answer eq {yes}} {_saveExplicit $w;return 1}
    if {[tk_messageBox -parent $w -type okcancel -default cancel -icon warning -message {Discard the unsaved changes in this Workspace?}] ne {ok}} {return 0}
    ::GX::scientificHistoryViewerDiscard $w
    if {$st($w,document) ne {}} {::GX::workbenchRecoveryResolve $st($w,document) saved}
    set st($w,historyDiscard) 1
    return 1
}
proc ::GX::CurveWorkbench::_timelineEditable {w} {
    variable st
    if {![info exists st($w,historyReady)] || !$st($w,historyReady) || [info exists st($w,historyRestoring)]} {return 1}
    if {[_historyBrowsing $w]} {_notice $w {History is read-only. Return to Latest, or explicitly restart here.};return 0}
    return [::GX::scientificHistoryViewerPrepareEdit $w]
}
foreach command {_sketchTool _sketchModifyTool _dimensionTool _dimensionEdit _transformStart _duplicate _operation _constraintAction _datasetCommit _datasetImport _parameterRecalculate} {
    if {[info commands ::GX::CurveWorkbench::$command] eq {}} continue
    rename ::GX::CurveWorkbench::$command ::GX::CurveWorkbench::${command}_history_guard_base
    proc ::GX::CurveWorkbench::$command {w args} [format {
        if {![_timelineEditable $w]} return
        tailcall %s_history_guard_base $w {*}$args
    } $command]
}

# Direct identities are obtained from the immutable recipe patch, never guessed
# from displayed labels. Browsing is read-only; editing requires explicit restart.
proc ::GX::CurveWorkbench::_timelineConstraints {w index} {
    set after [::GX::datasetPublicationV2DictDefault [dict get [_timelineState $w $index] @cad] constraints {}]
    if {$index==0} {return [dict keys $after]}
    set before [::GX::datasetPublicationV2DictDefault [dict get [_timelineState $w [expr {$index-1}]] @cad] constraints {}]
    set changed {}
    dict for {id value} $after {if {![dict exists $before $id] || [dict get $before $id] ne $value} {lappend changed $id}}
    return $changed
}
proc ::GX::CurveWorkbench::_timelineConstraint {w index id action} {
    variable st
    if {$action eq "inspect"} {
        _timelineBrowse $w $index index
    } else {
        set current [::GX::scientificHistoryViewerStatus $w]
        if {$index!=[dict get $current cursor] || $index<[dict get $current count] || [_historyBrowsing $w]} {
            _timelineRestart $w $index
            if {[_historyBrowsing $w] || [dict get [::GX::scientificHistoryViewerStatus $w] cursor]!=$index} return
        }
        if {![_timelineEditable $w]} return
    }
    if {![dict exists $st($w,constraints) $id]} {error "Constraint $id is unavailable in this state."}
    _constraintOpen $w
    set tree [::GX::CurveWorkbench::_constraintPanel $w].tree
    $tree selection set $id;$tree see $id
    _constraintMarkerSelect $w $id
    switch $action {
        inspect {set st($w,status) "History step $index; $id: [_constraintDescription $w [dict get $st($w,constraints) $id]]. Read-only; use Restart to edit."}
        edit {_dimensionEdit $w}
        remove {_constraintAction $w remove}
    }
    if {$action ne "inspect" && ![winfo exists $w.inline]} {focus $w.right.viewport.canvas}
}
