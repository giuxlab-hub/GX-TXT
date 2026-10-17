# Registered declarations and asynchronous previews use existing CORE owners.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_registeredSettings {w} {
    variable state
    _assertLoaded $w
    set choices {}
    foreach model [registeredModels] {
        if {[dict get $model status] ne "available"} continue
        set label "[dict get $model reference]/[dict get $model callable_id] · [dict get $model language] · revision [dict get $model revision]"
        dict set choices $label $model
    }
    if {![dict size $choices]} {return [_registeredDeclareDialog $w]}
    set selected [lindex [dict keys $choices] 0]
    if {[info exists state($w,registeredModel)]&&$state($w,registeredModel) ne {}} {
        dict for {label model} $choices {
            if {[dict get $model reference] eq [dict get $state($w,registeredModel) reference]&&[dict get $model callable_id] eq [dict get $state($w,registeredModel) callable_id]} {set selected $label}
        }
    }
    ::GX::uiFieldFormCreate $w.registeredModel {Choose registered fit model} [dict create model [dict create type choice label Model values [dict keys $choices]]] [dict create model $selected] [list ::GX::DatasetCurveFit::_registeredApply $w $state($w,activeSource) $choices] $w
    ttk::button $w.registeredModel.declare -text {Declare a Script Library model…} -command [list ::GX::DatasetCurveFit::_registeredDeclareDialog $w]
    pack $w.registeredModel.declare -fill x -padx 8 -pady 8
}
proc ::GX::DatasetCurveFit::_registeredApply {w owner choices values} {
    variable state
    if {$state($w,activeSource) ne $owner} {error {Active source changed; reopen model selection}}
    set registered [_registeredModelValidate [dict get $choices [dict get $values model]]]
    set fit [dict create initial [dict get $registered definition initial] options [dict create orientation $state($w,orientation) registered_model $registered]]
    _registeredFitValidate [_sourceProvenance $w] $fit
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    # Parameter scales belong to one declared parameter identity/order. A newly
    # selected declaration must not inherit another model's unreviewed scales.
    set old {};if {[info exists state($w,registeredModel)]} {set old $state($w,registeredModel)}
    if {$old eq {}||[dict get $old declaration_sha256] ne [dict get $registered declaration_sha256]||[dict get $old source_sha256] ne [dict get $registered source_sha256]} {
        if {[dict exists $state($w,solverSettings) registered]} {dict unset state($w,solverSettings) registered}
    }
    set state($w,registeredModel) $registered;set state($w,model) registered
    set state($w,initial) [join [dict get $registered definition initial] ,];set state($w,degree) 1
    _invalidateSettings $w;_workspaceCapture $w;_saveState $w;_uiModelFields $w
    set state($w,status) "Registered model [dict get $registered reference]/[dict get $registered callable_id] selected. Preview submits a supervised Job; acceptance remains explicit."
}
proc ::GX::DatasetCurveFit::_registeredDeclareDialog {w} {
    variable state
    _assertLoaded $w
    set references {}
    foreach script [::GX::scriptRegistryList all] {lappend references [dict get $script scope]:[dict get $script id]}
    if {$references eq {}} {error {Save the model function in the Python or Octave Script Library first, then declare its scientific parameters here}}
    set axes [dict get [_sourceProvenance $w] source_axes];set order {x y}
    if {$state($w,orientation) eq "x_of_y"} {set order {y x}}
    lassign $order independent response
    set fields [dict create reference [dict create type choice label {Script Library reference} values $references]]
    foreach {id label} {callable_id {Stable model ID} entrypoint {Function name (parameters, predictors)} parameter_ids {Parameter IDs, comma-separated} parameter_units {Parameter units, comma-separated (1 = dimensionless)} initial {Initial values, comma-separated} lower_bounds {Lower bounds, comma-separated (blank = unbounded)} upper_bounds {Upper bounds, comma-separated (equal bounds fix a parameter)} fixed_mask {Fixed parameters, comma-separated 0/1 (blank uses equal bounds only)} predictor_unit {Predictor unit} response_unit {Response unit} description Description} {dict set fields $id [dict create type string label $label]}
    dict set fields predictor_domain [dict create type choice label {Predictor domain} values {finite_real positive_real}]
    set values [dict create reference [lindex $references 0] callable_id model entrypoint model parameter_ids {} parameter_units {} initial {} lower_bounds {} upper_bounds {} fixed_mask {} predictor_unit [dict get $axes $independent unit] response_unit [dict get $axes $response unit] description {} predictor_domain finite_real]
    ::GX::uiFieldFormCreate $w.declareModel {Declare registered model} $fields $values [list ::GX::DatasetCurveFit::_registeredDeclareApply $w $state($w,activeSource)] $w
}
proc ::GX::DatasetCurveFit::_registeredDeclareApply {w owner values} {
    variable state
    if {$state($w,activeSource) ne $owner} {error {Active source changed; reopen model declaration}}
    set definition {}
    foreach field {parameter_ids parameter_units initial lower_bounds upper_bounds fixed_mask} {
        set text [string trim [::GX::datasetPublicationV2DictDefault $values $field {}]];set parsed {}
        if {$field eq "fixed_mask"&&$text eq {}} continue
        if {$text ne {}} {foreach value [split $text ,] {lappend parsed [string trim $value]}}
        dict set definition $field $parsed
    }
    foreach field {predictor_unit response_unit description predictor_domain} {dict set definition $field [string trim [dict get $values $field]]}
    set registered [registeredModelDeclare [dict get $values reference] [string trim [dict get $values callable_id]] [string trim [dict get $values entrypoint]] $definition]
    _registeredApply $w $owner [dict create declared $registered] {model declared}
}
proc ::GX::DatasetCurveFit::_registeredUiRecipe {w domain initial options} {
    variable state
    if {![info exists state($w,registeredModel)]||$state($w,registeredModel) eq {}} {error {Choose or declare a registered model first}}
    set model [_registeredModelValidate $state($w,registeredModel)]
    set encoded [registeredRecipe $w [dict get $model reference] [dict get $model callable_id] $state($w,scope) $domain $options]
    set recipe [::GX::scientificRecipeDataDecode $encoded gxtxt.fit_recipe.v1]
    # Keep the exact GUI field dictionary, including its frozen declaration.
    dict set recipe fit options $options;dict set recipe fit initial $initial;dict set recipe fit degree $state($w,degree)
    set encoded [::GX::scientificRecipeEncode $recipe];recipeValidate $encoded
    return $encoded
}
proc ::GX::DatasetCurveFit::_registeredUiPreview {w domain initial options} {
    variable state
    if {[info exists state($w,registeredJob)]&&$state($w,registeredJob) ne {}} {error {A registered model Job is already active for this viewer}}
    set encoded [_registeredUiRecipe $w $domain $initial $options]
    set job [registeredSubmit $encoded "Registered preview [dict get $state($w,registeredModel) callable_id]"]
    set state($w,registeredJob) [dict get $job id]
    set state($w,registeredJobRecipe) $encoded
    set state($w,registeredJobSource) $state($w,activeSource)
    set state($w,status) "Registered model Job [dict get $job id] submitted. You may close this viewer; its retained preview will remain in Session Workspaces."
    $w.actions.accept configure -state disabled
    after 250 [list ::GX::DatasetCurveFit::_registeredPoll $w $state($w,sessionToken) [dict get $job id]]
    return $job
}
proc ::GX::DatasetCurveFit::_registeredPoll {w token job} {
    variable state
    if {![winfo exists $w]||![info exists state($w,registeredJob)]||$state($w,registeredJob) ne $job||$state($w,sessionToken) ne $token} return
    if {[catch {set info [::GX::scriptJobDescribe $job]} reason]} {set state($w,status) "Registered Job status unavailable: $reason";set state($w,registeredJob) {};return}
    set status [dict get $info state]
    if {$status ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {after 500 [list ::GX::DatasetCurveFit::_registeredPoll $w $token $job];return}
    set state($w,registeredJob) {}
    if {$status ne "COMPLETED"} {set state($w,status) "Registered model Job $job: $status. Inspect its Script Job log; no preview was accepted.";return}
    if {[catch {
        set inspected [::GX::scriptJobInspect $job]
        if {[dict get $inspected callable_validation] ne "verified"} {error {Job result receipt is not verified}}
        set reference [dict get $inspected callable_result result]
        _registeredAdopt $w $reference $state($w,registeredJobRecipe) $state($w,registeredJobSource)
    } reason]} {set state($w,status) "Completed Job $job retained its Workspace preview. Import into this viewer stopped: $reason";return}
    set state($w,status) "Registered model preview ready from Job $job. Review parameters and residuals, then accept explicitly."
}
proc ::GX::DatasetCurveFit::_registeredAdopt {w reference encoded owner} {
    variable state
    _assertLoaded $w
    if {$state($w,activeSource) ne $owner} {error {The active source changed}}
    set recipe [_recipeDecode $encoded];set fit [dict get $recipe fit]
    set options [_uiFitOptions $w];set initial [lmap value [split $state($w,initial) ,] {string trim $value}]
    set domain source
    if {$state($w,domain) eq "range"} {set domain [list $state($w,min) $state($w,max) $state($w,samples)]}
    foreach {field value} [list model $state($w,model) scope $state($w,scope) domain $domain degree $state($w,degree) initial $initial options $options selection_descriptor [_selectionDescriptor $w]] {
        if {[dict get $fit $field] ne $value} {error "The submitted $field changed"}
    }
    recipeValidate $encoded
    set info [registeredPreviewInfo $reference]
    if {[dict get $info accepted]} {error {The Job preview was already accepted elsewhere}}
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    _saveState $w
    set report [dict get $info preview];set copied {}
    foreach field [dict keys $report *_resource] {
        set resource [dict get $report $field]
        if {![dict exists $copied $resource]} {dict set copied $resource [::GX::managedResourceCopy $state($w,documentId) $resource]}
        dict set report $field [dict get $copied $resource]
    }
    # The immutable scientific state and parameter order stay unchanged; only
    # public resource ownership is rebound to this independent Workspace.
    _validateStatisticsMetadata $report
    set loaded {}
    try {
        foreach field {fitted_native residual_native} resource {preview_geometry_resource preview_residual_plot_resource} {
            set native [::GX::interactiveDocumentNative2DRestore [dict get $report $resource] $state($w,scene)]
            lappend loaded $native;dict set report $field $native
            ::GX::Native2D::core object_style $state($w,scene) $native {visible 0 selectable 0}
        }
        set boundaries [_predictionRestore $state($w,scene) $report {0.09 0.64 0.29} 0]
        dict for {field native} $boundaries {lappend loaded $native;dict set report $field $native}
    } on error {message detail} {foreach native $loaded {::GX::Native2D::core delete $state($w,scene) $native};return -options $detail $message}
    dict set report source_id $state($w,source)
    _disposePreview $w
    set state($w,preview) $report;set state($w,previewAccepted) 0;set state($w,previewFitId) {}
    _resultPresentation $w;_residualColumns $w $report;set state($w,residualStart) 0;_residualPageUi $w 0
    $w.actions.accept configure -state normal;$w.actions.publish configure -state normal
    _workspaceCapture $w;_saveState $w;redraw $w
}
proc ::GX::DatasetCurveFit::_registeredCancel {w} {
    variable state
    if {![info exists state($w,registeredJob)]||$state($w,registeredJob) eq {}} {error {No registered model Job is active for this viewer}}
    ::GX::scriptJobCancel $state($w,registeredJob)
    set state($w,status) {Registered model cancellation requested. The original data and accepted fits remain retained.}
}
