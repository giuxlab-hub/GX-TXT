# SPDX-License-Identifier: GPL-3.0-or-later
proc ::P017Manual::run {} {
    set original [publish]
    ::GX::modulePublicApiActivate viewer.dataset_curve_fit DATASET_CURVE_FIT_API_v1
    set ::w [::GX::DatasetCurveFit::open {workspace_id new workspace_name {P017 fitter History API reuse} dataset_id qa_history_source}];set w $::w;pause 150
    check {[winfo ismapped $w]} {Manual Dataset Curve Fit is mapped for its distinct native-scene restoration path}
    ::GX::DatasetCurveFit::loadSource $w qa_history_source source_x source_y {}
    check {$::GX::DatasetCurveFit::state($w,sourcePointCount)==8 && $::GX::DatasetCurveFit::state($w,sourceKind) eq {dataset}} {Fitter public source API loads all eight canonical scientific rows}
    ::GX::DatasetCurveFit::_commandInvoke $w save
    set document $::GX::DatasetCurveFit::state($w,documentId)
    check {$document ne {}} {Fitter explicit Save binds its normal Workspace Document}
    durable $w
    set count [dict get [::GX::scientificHistoryViewerStatus $w] count]
    set revision [dict get [::GX::interactiveDocumentMetadata $document] revision]
    set initial $::GX::DatasetCurveFit::state($w,model)
    auditStart
    ::GX::DatasetCurveFit::_uiApplySetting $w model polynomial
    check {$::GX::DatasetCurveFit::state($w,model) eq {polynomial} && [dict get [::GX::scientificHistoryViewerStatus $w] count]==$count+1} {Existing fitter setting command records one immediate native History operation}
    ::GX::scientificHistoryViewerNavigate $w undo
    check {$::GX::DatasetCurveFit::state($w,model) eq $initial && $::GX::DatasetCurveFit::state($w,sourcePointCount)==8} {Fitter Undo reconstructs scientific source scenes and prior model setting}
    ::GX::scientificHistoryViewerNavigate $w redo
    check {$::GX::DatasetCurveFit::state($w,model) eq {polynomial} && $::GX::DatasetCurveFit::state($w,sourcePointCount)==8} {Fitter Redo restores the accepted model context and source extent}
    check {[dict get [::GX::interactiveDocumentMetadata $document] revision]==$revision} {Fitter setting/navigation leaves stored Document revision unchanged}
    auditEnd fit
    ::GX::DatasetCurveFit::_commandInvoke $w save;durable $w
    shot fit_api_reuse $w
    ::GX::DatasetCurveFit::_closeWindow $w 1
    check {![winfo exists $w]} {Fitter Close flushes before native-scene disposal}
    set ::w [::GX::DatasetCurveFit::open [dict create workspace_id $document]];set w $::w;pause 150
    check {$::GX::DatasetCurveFit::state($w,model) eq {polynomial} && $::GX::DatasetCurveFit::state($w,sourcePointCount)==8} {Fitter real reopen restores saved context and canonical source}
    check {[dict get [::GX::sessionInspectionDatasetPayload qa_history_source] sha256] eq $original} {Fitter History smoke preserves canonical Dataset bytes}
    emit final [dict create workspace_id $document history [::GX::scientificHistoryViewerStatus $w] source_sha256 $original no_numeric_fit 1]
    ::GX::DatasetCurveFit::_closeWindow $w 1
}
