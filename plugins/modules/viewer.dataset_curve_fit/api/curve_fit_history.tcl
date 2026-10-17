# SPDX-License-Identifier: GPL-3.0-or-later
# Host projections only. CORE Recipe owns History and Document owns persistence.
proc ::GX::DatasetCurveFit::_historyValidate {record} {
    workspaceValidate [dict get $record base]
    return 1
}
proc ::GX::DatasetCurveFit::_historyCapture {w} {return [_payload $w]}
proc ::GX::DatasetCurveFit::_historyReplay {record} {return [::GX::scientificHistoryState $record]}
::GX::scientificRecipeHostRegister viewer.dataset_curve_fit [dict create capture ::GX::DatasetCurveFit::_historyCapture validate ::GX::DatasetCurveFit::_historyValidate replay ::GX::DatasetCurveFit::_historyReplay]
proc ::GX::DatasetCurveFit::_historyGuard {w} {
    variable state
    return [expr {(![info exists state($w,loading)] || !$state($w,loading)) && ![info exists state($w,press)] && ![info exists state($w,pan)]}]
}
proc ::GX::DatasetCurveFit::_historyEditable {w} {
    return [expr {[_historyGuard $w] && [::GX::scientificHistoryViewerEditable $w]}]
}
proc ::GX::DatasetCurveFit::_historyCommit {w record} {
    set payload [::GX::scientificHistoryState $record]
    dict set payload scientific_history $record
    _writePayload $w $payload
}
proc ::GX::DatasetCurveFit::_historyRestore {w payload} {
    variable state
    set state($w,restoringWorkspace) 1
    try {
        _workspaceCapture $w
        unset -nocomplain state($w,templateBinding) state($w,recipePointMask) state($w,influenceLinkedPoint)
        foreach entry [dict values $state($w,sources)] {
            set source [dict get $entry state]
            if {[dict get $source sourceToken] ne {}} {::GX::curveSourceClose [dict get $source sourceToken]}
            if {[dict get $source selectionScene] ne $state($w,selectionScene)} {::GX::Native2D::core destroy [dict get $source selectionScene]}
        }
        ::GX::Native2D::core destroy $state($w,scene)
        ::GX::Native2D::core destroy $state($w,selectionScene)
        if {[info exists state($w,residualViewScene)]} {::GX::Native2D::core destroy $state($w,residualViewScene);unset state($w,residualViewScene)}
        set state($w,scene) [::GX::Native2D::core scene];set state($w,selectionScene) [::GX::Native2D::core scene]
        foreach field {source selectionObject accepted previewFitId sourceToken activeSource} {set state($w,$field) {}}
        foreach field {sources records preview rows filters loadedBinding rects sourceDescriptor} {set state($w,$field) {}}
        set state($w,previewAccepted) 0
        _applyPayload $w $payload
        if {$state($w,preview) ne {}} {
            _resultPresentation $w
            _residualColumns $w $state($w,preview);_residualPageUi $w 0
        } else {set state($w,report) {}; $w.right.residuals.table delete [$w.right.residuals.table children {}]}
        _uiModelFields $w;_uiDomainFields $w
        $w.actions.accept configure -state [expr {$state($w,preview) ne {} && !$state($w,previewAccepted) ? "normal" : "disabled"}]
        $w.actions.publish configure -state [expr {$state($w,preview) ne {} ? "normal" : "disabled"}]
        $w.actions.export configure -state [expr {$state($w,records) ne {} ? "normal" : "disabled"}]
        redraw $w
    } finally {unset -nocomplain state($w,restoringWorkspace)}
}
proc ::GX::DatasetCurveFit::_historyAttach {w} {
    variable state
    if {$state($w,sessionToken) eq {}} return
    set record {}
    if {$state($w,documentId) ne {}} {set record [::GX::datasetPublicationV2DictDefault [dict get [::GX::interactiveDocumentRead $state($w,documentId)] payload] scientific_history {}]}
    ::GX::scientificHistoryViewerAttach $w viewer.dataset_curve_fit [dict create capture [list ::GX::DatasetCurveFit::_historyCapture $w] restore [list ::GX::DatasetCurveFit::_historyRestore $w] commit [list ::GX::DatasetCurveFit::_historyCommit $w] guard [list ::GX::DatasetCurveFit::_historyGuard $w]] $record
    ::GX::scientificHistoryViewerStrip $w $w.footer $w.footer.status modules.dataset_curve_fit.history_strip [list -fill x -before $w.footer.coordinateReadout]
    ::GX::viewerCommandMenusRefresh $w
}
proc ::GX::DatasetCurveFit::_commandEnabled {w id} {
    variable state
    if {$id in {model_card surface_workflow}} {return 1}
    if {$id eq "filter_cancel"} {return [expr {![ _historyGuard $w]}]}
    if {![_historyGuard $w]} {return 0}
    if {$id eq "profile_details"} {return [expr {[dict exists $state($w,preview) statistical_results profile]||[llength [$w.left.viewport.content.accepted.list curselection]]==1}]}
    if {$id eq "bootstrap_details"} {return [expr {[dict exists $state($w,preview) statistical_results bootstrap]||[llength [$w.left.viewport.content.accepted.list curselection]]==1}]}
    if {$id eq "residual_sequence"} {return [expr {[llength [$w.left.viewport.content.accepted.list curselection]]==1}]}
    if {$id eq "influence_details"} {return [expr {[dict exists $state($w,preview) statistical_results influence]||[llength [$w.left.viewport.content.accepted.list curselection]]==1}]}
    if {$id eq "parameter_dataset"} {return [expr {[llength $state($w,records)]>0}]}
    if {$id eq "covariance_details"} {return [dict exists $state($w,preview) covariance_binding]}
    if {$id eq "model_suggestions"} {return [expr {$state($w,source) ne {}&&$state($w,orientation) in {y_of_x x_of_y}}]}
    if {$id eq "model_comparison"} {return [expr {[llength $state($w,records)]>=2}]}
    if {$id in {recipe_python recipe_octave model_export model_workbench derived_properties physical_plausibility retained_query}} {return [expr {[llength [$w.left.viewport.content.accepted.list curselection]]==1}]}
    if {$id eq "template_apply"} {return [expr {[llength [::GX::interactiveDocumentList viewer.dataset_curve_fit dataset_curve_fit_recipe]]>0}]}
    if {$id in {parameter_correlation solver_details}} {return [expr {$state($w,preview) ne {}&&[dict exists $state($w,preview) statistical_results training]}]}
    if {$id eq "smoothing_details"} {return [dict exists $state($w,preview) statistical_results training provenance smoothing]}
    if {$id eq "log_details"} {return [dict exists $state($w,preview) statistical_results training context response_transform]}
    if {$id eq "prediction_details"} {return [expr {$state($w,preview) ne {}&&[dict exists $state($w,preview) prediction_plan]}]}
    if {$id eq "scientific_report"} {return [expr {$state($w,preview) ne {}}]}
    if {$id eq "measurement_details"} {return [expr {$state($w,preview) ne {}&&[dict exists $state($w,preview) measurement_binding]}]}
    if {$id in {undo redo previous next latest branch}} {
        if {![dict exists $::GX::ScientificHistory::viewers $w]} {return 0}
        set adapter [dict get $::GX::ScientificHistory::viewers $w];set record [dict get $adapter record]
        set count [llength [dict get $record steps]];set cursor [dict get $record cursor]
        switch $id {
            undo {return [expr {![dict get $adapter browsing] && $cursor>0}]}
            redo {return [expr {![dict get $adapter browsing] && $cursor<$count}]}
            branch {return [expr {[dict get $adapter browse_cursor]<$count}]}
            default {return [expr {$count>0}]}
        }
    }
    if {$id in {timeline strip history_details workspace_close workspace_open workspace_manager}} {return 1}
    if {![_historyEditable $w]} {return 0}
    if {$id in {template_save log_publish}} {return [expr {[llength [$w.left.viewport.content.accepted.list curselection]]==1}]}
    if {$id eq "knot_settings"} {return [expr {$state($w,activeSource) ne {}&&$state($w,model) in {akima bspline}&&$state($w,orientation) in {y_of_x x_of_y}}]}
    if {$id eq "smoothing_settings"} {return [expr {$state($w,model) eq "smoothing_spline"}]}
    if {$id eq "solver_settings"} {return [expr {$state($w,model) in {exponential power_law gaussian components regions formula rational implicit complex_response registered}||($state($w,model) in {linear polynomial}&&$state($w,measurementKind) eq "sigma_xy")}]}
    if {$id eq "parameter_settings"} {return [expr {$state($w,activeSource) ne {}&&(($state($w,model) in {linear polynomial exponential power_law gaussian components regions formula rational registered fourier}&&$state($w,orientation) in {y_of_x x_of_y})||($state($w,model) in {circular_arc quadratic_bezier cubic_bezier parametric_polynomial}&&$state($w,orientation) eq "parametric")||($state($w,model) in {linear polynomial exponential power_law gaussian}&&$state($w,orientation) eq "r_of_theta"))}]}
    if {$id eq "registered_cancel"} {return [expr {[info exists state($w,registeredJob)]&&$state($w,registeredJob) ne {}}]}
    if {$id in {component_settings region_settings formula_settings rational_settings implicit_settings complex_settings registered_settings registered_declare}} {return [expr {$state($w,activeSource) ne {}&&$state($w,orientation) in {y_of_x x_of_y}}]}
    if {$id eq "covariance_settings"} {return [expr {$state($w,activeSource) ne {}&&$state($w,sourceKind) eq "dataset"&&$state($w,model) in {linear polynomial}&&$state($w,orientation) in {y_of_x x_of_y}}]}
    if {$id in {baseline_settings log_settings smooth_source}} {return [expr {$state($w,activeSource) ne {}&&$state($w,sourceKind) eq "dataset"&&$state($w,sourceTransformManifest) eq {}}]}
    if {$id in {preview accept}} {return [expr {[$w.actions.$id cget -state] ne "disabled"}]}
    if {$id eq "workspace_clear_history"} {
        set record [::GX::scientificHistoryViewerRecord $w]
        return [expr {$state($w,documentId) ne {} && [dict get $record steps] ne {} && [dict get $record cursor]==[llength [dict get $record steps]]}]
    }
    if {$id in {workspace_duplicate workspace_rename workspace_delete workspace_clear_history}} {return [expr {$state($w,documentId) ne {}}]}
    dict for {name label} [_commandWidgets] {
        if {[string map {. _} $name] ne $id} continue
        set parts [split $name .];set widget [_widget $w [lindex $parts 0]].[join [lrange $parts 1 end] .]
        if {[$widget cget -state] eq "disabled"} {return 0}
        if {[string match workspace.actions.* $name] && $name ni {workspace.actions.reload workspace.actions.reverse workspace.actions.span}} {return [expr {[$w.left.viewport.content.sources.body.sources selection] ne {}}]}
        if {[string match accepted.* $name]} {return [expr {[$w.left.viewport.content.accepted.list curselection] ne {}}]}
        if {$name eq "filter.remove"} {return [expr {[$w.left.viewport.content.filters.list curselection] ne {}}]}
        if {[string match residualPager.* $name]} {return [expr {$state($w,preview) ne {}}]}
    }
    return 1
}
proc ::GX::DatasetCurveFit::_commandInvoke {w id} {
    if {$id in {undo redo previous next latest branch}} {return [::GX::scientificHistoryViewerNavigate $w $id]}
    if {$id eq "save"} {return [_saveState $w]}
    variable state
    if {$id eq "workspace_clear_history"} {return [::GX::scientificHistoryViewerClear $w $state($w,documentId)]}
    if {$id in {workspace_new workspace_open workspace_duplicate workspace_rename workspace_manager workspace_close workspace_delete}} {
        set callbacks [dict create current [list ::GX::DatasetCurveFit::_currentWorkspace $w] save [list ::GX::DatasetCurveFit::_saveState $w] close [list ::GX::DatasetCurveFit::_closeWindow $w] open ::GX::DatasetCurveFit::open]
        return [::GX::sessionWorkspaceViewerAction dataset_curve_fit $callbacks $w [string range $id 10 end]]
    }
    switch $id {
        configuration {return [::GX::configurationModuleDialog viewer.dataset_curve_fit $w]}
        panels_reset {return [_panelsReset $w]}
        translation {return [_uiSafe $w [list ::GX::DatasetCurveFit::_translationSettings $w]]}
        statistics_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_statisticalSettings $w]]}
        smoothing_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_smoothingSettings $w]]}
        smoothing_details {return [_smoothingDetails $w]}
        solver_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_solverSettings $w]]}
        registered_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_registeredSettings $w]]}
        registered_declare {return [_uiSafe $w [list ::GX::DatasetCurveFit::_registeredDeclareDialog $w]]}
        registered_cancel {return [_uiSafe $w [list ::GX::DatasetCurveFit::_registeredCancel $w]]}
        component_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_componentSettings $w]]}
        knot_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_knotSettings $w]]}
        rational_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_rationalSettings $w]]}
        implicit_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_implicitSettings $w]]}
        complex_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_complexSettings $w]]}
        surface_workflow {return [_uiSafe $w [list ::GX::DatasetCurveFit::openSurface]]}
        formula_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_formulaSettings $w]]}
        parameter_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_parameterSettings $w]]}
        region_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_regionSettings $w]]}
        log_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_logSettings $w]]}
        log_publish {return [_uiSafe $w [list ::GX::DatasetCurveFit::_logPublishDialog $w]]}
        log_details {return [_logDetails $w]}
        smooth_source {return [_uiSafe $w [list ::GX::DatasetCurveFit::_smoothSettings $w]]}
        baseline_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_baselineSettings $w]]}
        residual_source {return [_uiSafe $w [list ::GX::DatasetCurveFit::_residualAxis $w source]]}
        residual_predicted {return [_uiSafe $w [list ::GX::DatasetCurveFit::_residualAxis $w predicted]]}
        parameter_correlation {return [_correlationWindow $w]}
        solver_details {return [_solverDetails $w]}
        residual_sequence {return [_sequenceDetails $w]}
        influence_details {return [_influenceDetails $w]}
        bootstrap_details {return [_bootstrapDetails $w]}
        profile_details {return [_profileDetails $w]}
        profile_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_profileSettings $w]]}
        bootstrap_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_bootstrapSettings $w]]}
        prediction_details {return [_predictionDetails $w]}
        scientific_report {return [_scientificReportDetails $w]}
        model_card {return [_modelCardDetails $w]}
        covariance_settings {return [_uiSafe $w [list ::GX::DatasetCurveFit::_covarianceSettings $w]]}
        covariance_details {return [_uiSafe $w [list ::GX::DatasetCurveFit::_covarianceDetails $w]]}
        measurement_details {return [_measurementDetails $w]}
        parameter_dataset {return [_uiSafe $w [list ::GX::DatasetCurveFit::_parameterDatasetDialog $w]]}
        family_sources {return [_uiSafe $w [list ::GX::DatasetCurveFit::_familyDialog $w]]}
        global_family {return [_uiSafe $w [list ::GX::DatasetCurveFit::_globalFamilyDialog $w]]}
        global_family_results {return [_globalResults $w]}
        model_comparison {return [_comparisonWindow $w]}
        retained_query {return [_uiSafe $w [list ::GX::DatasetCurveFit::_queryOpen $w]]}
        model_suggestions {return [_uiSafe $w [list ::GX::DatasetCurveFit::_suggestionOpen $w]]}
        physical_plausibility {return [_uiSafe $w [list ::GX::DatasetCurveFit::_plausibilityOpen $w]]}
        derived_properties {return [_uiSafe $w [list ::GX::DatasetCurveFit::_derivedOpen $w]]}
        model_workbench {return [_uiSafe $w [list ::GX::DatasetCurveFit::_workbenchTransfer $w]]}
        model_export {return [_uiSafe $w [list ::GX::DatasetCurveFit::_modelExport $w]]}
        recipe_python {return [_uiSafe $w [list ::GX::DatasetCurveFit::_recipeExport $w Python]]}
        recipe_octave {return [_uiSafe $w [list ::GX::DatasetCurveFit::_recipeExport $w Octave]]}
        template_save {return [_uiSafe $w [list ::GX::DatasetCurveFit::_templateSaveDialog $w]]}
        template_apply {return [_uiSafe $w [list ::GX::DatasetCurveFit::_templateDialog $w]]}
        timeline {return [::GX::scientificHistoryViewerStripSet $w {mode History visible 1}]}
        strip {return [::GX::scientificHistoryViewerStripToggle $w]}
        history_details {return [::GX::scientificHistoryViewerDetails $w]}
        source_activate {return [_uiSafe $w [list ::GX::DatasetCurveFit::_workspaceSelect $w]]}
    }
    if {[string match selection_* $id] && $id in {selection_replace selection_add selection_subtract}} {set state($w,rectMode) [string totitle [string range $id 10 end]];return}
    if {$id in {preview accept}} {return [$w.actions.$id invoke]}
    dict for {name label} [_commandWidgets] {
        if {[string map {. _} $name] ne $id} continue
        set parts [split $name .];set widget [_widget $w [lindex $parts 0]].[join [lrange $parts 1 end] .]
        return [$widget invoke]
    }
}
proc ::GX::DatasetCurveFit::_commandsAttach {w} {
    set handlers {}
    dict for {id entry} [::GX::viewerCommandCatalog viewer.dataset_curve_fit] {
        dict set handlers $id [dict create command [list ::GX::DatasetCurveFit::_commandInvoke $w $id] enabled [list ::GX::DatasetCurveFit::_commandEnabled $w $id]]
    }
    ::GX::viewerCommandsAttach $w viewer.dataset_curve_fit $handlers
}
