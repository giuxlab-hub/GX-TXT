# Scientific declarations reuse the CORE Script Registry and supervised Jobs.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_registeredDefinition {definition} {
    set fields {format parameter_ids parameter_units initial lower_bounds upper_bounds predictor_unit response_unit predictor_shape response_shape parameter_shape predictor_domain description}
    # Keep historical declarations byte-identical: an absent optional mask is
    # not materialized into their signed/hashed canonical representation.
    if {[dict exists $definition fixed_mask]} {lappend fields fixed_mask}
    foreach key [dict keys $definition] {if {$key ni $fields} {error "Unknown registered fit-model declaration field: $key"}}
    set definition [dict merge [dict create format gxtxt.fit_model.v1 lower_bounds {} upper_bounds {} predictor_shape {N 1} response_shape {N 1} parameter_shape {P 1} predictor_domain finite_real description {}] $definition]
    foreach key {parameter_ids parameter_units initial predictor_unit response_unit} {if {![dict exists $definition $key]} {error "Registered fit model requires $key"}}
    if {[dict get $definition format] ne "gxtxt.fit_model.v1"||[dict get $definition predictor_shape] ne {N 1}||[dict get $definition response_shape] ne {N 1}||[dict get $definition parameter_shape] ne {P 1}} {error {Registered functional models declare predictors N-by-1, response N-by-1 and parameters P-by-1}}
    if {[dict get $definition predictor_domain] ni {finite_real positive_real}} {error {Choose finite_real or positive_real predictor domain}}
    set ids [dict get $definition parameter_ids];set count [llength $ids]
    if {$count<1||$count>128||[llength [lsort -unique $ids]]!=$count} {error {A registered model requires one to 128 distinct parameter identities}}
    foreach id $ids {if {![regexp {^[A-Za-z][A-Za-z0-9_]{0,63}$} $id]} {error {Parameter identities must be public single identifiers}}}
    if {[llength [dict get $definition parameter_units]]!=$count||[llength [dict get $definition initial]]!=$count} {error {Initial estimates and declared units must match canonical parameter order}}
    foreach value [dict get $definition initial] {_finite $value {Declared initial parameter}}
    foreach unit [concat [dict get $definition parameter_units] [list [dict get $definition predictor_unit] [dict get $definition response_unit]]] {
        if {[string trim $unit] eq {}||[string length $unit]>256||[regexp {[\r\n\x00]} $unit]} {error {Declare each physical unit explicitly; use 1 for dimensionless values}}
    }
    if {[string length [dict get $definition description]]>2048||[regexp {[\r\n\x00]} [dict get $definition description]]} {error {Model description must be a bounded single line}}
    foreach key {lower_bounds upper_bounds} default {-Inf Inf} {
        set values [dict get $definition $key]
        if {$values eq {}} {set values [lrepeat $count $default]}
        if {[llength $values]!=$count} {error {Model parameter bounds must match canonical parameter order}}
        foreach value $values {if {$value ne $default} {_finite $value {Declared parameter bound}}}
        dict set definition $key $values
    }
    foreach lo [dict get $definition lower_bounds] hi [dict get $definition upper_bounds] initial [dict get $definition initial] {
        if {$lo > $hi||$initial<$lo||$initial>$hi} {error {Registered callback bounds must be ordered and contain their initial estimates; equal bounds fix that parameter}}
    }
    if {[dict exists $definition fixed_mask]} {
        set mask [dict get $definition fixed_mask]
        if {[llength $mask]!=$count} {error {Fixed mask must match canonical parameter order}}
        set normalized {}
        foreach value $mask {
            set value [_finite $value {Declared fixed mask}]
            if {$value!=0&&$value!=1} {error {Fixed mask values must be 0 or 1}}
            lappend normalized [expr {int($value)}]
        }
        dict set definition fixed_mask $normalized
    }
    # Deterministic field order makes declaration hashes independent of GUI
    # form insertion order. Parameter order remains the scientist's order.
    set result {};foreach key $fields {dict set result $key [dict get $definition $key]}
    return $result
}
proc ::GX::DatasetCurveFit::registeredModelDeclare {reference callableId entrypoint definition} {
    set definition [_registeredDefinition $definition]
    set m [::GX::scriptRegistryDescribe $reference]
    set declaration [dict create entrypoint $entrypoint contract gxtxt.fit_model.v1 declaration [::GX::scientificRecipeEncode $definition]]
    set callables [dict get $m callables];dict set callables $callableId $declaration
    ::GX::scriptRegistryCallablesValidate $callables
    set channel [::open [dict get $m source_path] rb]
    try {set bytes [read $channel]} finally {::close $channel}
    set code [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $code] ne $bytes} {error {Script source is not exact UTF-8; preserve it and repair its encoding explicitly before declaring a model}}
    ::GX::scriptRegistryUpdate [dict get $m scope] [dict get $m id] [dict get $m sha256] [dict create callables $callables] $code
    return [registeredModelDescribe $reference $callableId]
}
proc ::GX::DatasetCurveFit::registeredModelDescribe {reference callableId} {
    set registered [::GX::scriptRegistryCallableDescribe $reference $callableId]
    if {[dict get $registered contract] ne "gxtxt.fit_model.v1"} {error {Registered callable has another scientific contract}}
    set definition [_registeredDefinition [::GX::scientificRecipeDataDecode [dict get $registered declaration] gxtxt.fit_model.v1]]
    return [dict merge $registered [dict create definition $definition]]
}
proc ::GX::DatasetCurveFit::registeredModels {} {
    set result {}
    foreach registered [::GX::scriptRegistryCallableList] {
        if {[dict get $registered contract] ne "gxtxt.fit_model.v1"} continue
        # Keep a scientifically invalid declaration visible with its reason.
        # Source integrity failures are reported by the CORE Script Library.
        if {[catch {set descriptor [registeredModelDescribe [dict get $registered reference] [dict get $registered callable_id]]} reason]} {
            dict set registered status invalid;dict set registered reason $reason;lappend result $registered
        } else {lappend result [dict merge $registered $descriptor [dict create status available]]}
    }
    return $result
}
proc ::GX::DatasetCurveFit::_registeredModelValidate {captured} {
    set actual [registeredModelDescribe [dict get $captured reference] [dict get $captured callable_id]]
    foreach key {source_sha256 declaration_sha256 revision language version entrypoint contract declaration} {
        if {![dict exists $captured $key]||[dict get $captured $key] ne [dict get $actual $key]} {error "Registered model $key changed. Review and select its current declaration before fitting."}
    }
    return $actual
}
proc ::GX::DatasetCurveFit::_registeredFitValidate {source fit} {
    set options [dict get $fit options]
    _influenceOption registered $options
    _bootstrapOptions registered $options
    set registered [_registeredModelValidate [dict get $options registered_model]]
    set definition [dict get $registered definition]
    set orientation [_fitOrientation registered $options]
    if {$orientation ni {y_of_x x_of_y}} {error {Registered functional models currently require Y(X) or X(Y) orientation}}
    set axes [dict get $source source_axes];set order {x y}
    if {$orientation eq "x_of_y"} {set order {y x}}
    foreach axis $order role {predictor response} {
        set unit [dict get $axes $axis unit];if {$unit eq {}} {set unit 1}
        if {$unit ne [dict get $definition ${role}_unit]} {error "Registered model $role unit differs from the source. Apply an explicit Unit Registry conversion or select a matching declaration."}
    }
    if {[dict get [_measurementOptions $options] kind] eq "sigma_xy"} {error {Registered callbacks do not yet supply an orthogonal XY fitting contract}}
    _registeredSolverOptions $definition $options
    set initial [dict get $fit initial]
    if {[llength $initial]!=[llength [dict get $definition parameter_ids]]} {error {Initial parameters differ from the registered canonical order}}
    foreach value $initial lo [dict get $definition lower_bounds] hi [dict get $definition upper_bounds] {
        _finite $value {Registered initial parameter}
        if {$value<$lo||$value>$hi} {error {Initial parameters lie outside their declared bounds}}
    }
    return $registered
}
proc ::GX::DatasetCurveFit::registeredRecipe {key reference callableId scope domain {options {}}} {
    variable state
    _assertLoaded $key
    set registered [registeredModelDescribe $reference $callableId]
    set source [_sourceProvenance $key]
    set options [dict merge {orientation y_of_x noise_model unspecified confidence .95 prediction_band none translation_u {mode off delta 0} translation_v {mode off delta 0}} $options]
    dict set options registered_model $registered
    set fit [dict create model registered scope $scope domain $domain degree 1 initial [dict get $registered definition initial] options $options selection_descriptor [_selectionDescriptor $key]]
    set recipe [dict create format gxtxt.fit_recipe.v1 owner viewer.dataset_curve_fit producers [_recipeProducers] source $source fit $fit model_cards {} captured_fit_id {}]
    set encoded [::GX::scientificRecipeEncode $recipe]
    recipeValidate $encoded
    return $encoded
}
proc ::GX::DatasetCurveFit::registeredSubmit {encoded {name {Registered model preview}}} {
    recipeValidate $encoded;set recipe [_recipeDecode $encoded]
    if {[dict get $recipe fit model] ne "registered"} {error {A registered Job requires a registered-model recipe}}
    set name [string trim $name]
    if {$name eq {}||[string length $name]>160||[regexp {[\r\n\x00]} $name]} {error {Preview Workspace name must be a nonempty single line of at most 160 characters}}
    set registered [dict get $recipe fit options registered_model]
    set payload [::GX::scientificRecipeEncode [dict create format gxtxt.registered_fit_job.v1 recipe $encoded name $name]]
    # The inert envelope is canonical base64, which needs no JSON escaping.
    set invocation [dict create callable_id [dict get $registered callable_id] source_sha256 [dict get $registered source_sha256] revision [dict get $registered revision] declaration_sha256 [dict get $registered declaration_sha256] consumer_api DATASET_CURVE_FIT_API_v1 consumer_operation registered_run payload_json \"$payload\"]
    return [::GX::scriptJobSubmit [dict get $registered reference] {} [dict create callable_invocation $invocation]]
}
proc ::GX::DatasetCurveFit::_registeredPrepare {encoded identity} {
    variable state
    set payload [::GX::scientificRecipeDataDecode $encoded gxtxt.registered_fit_job.v1]
    set recipe [_recipeDecode [dict get $payload recipe]]
    if {[dict get $identity consumer_api] ne "DATASET_CURVE_FIT_API_v1"||[dict get $identity consumer_operation] ne "registered_run"} {error {This Job was not submitted to the Fitter consumer}}
    set registered [_registeredFitValidate [dict get $recipe source] [dict get $recipe fit]]
    foreach field {reference callable_id source_sha256 declaration_sha256 revision entrypoint language} {
        if {[dict get $registered $field] ne [dict get $identity $field]} {error "Supervised model identity differs from the fit recipe: $field"}
    }
    set key [new]
    try {
        recipeLoadSettings $key [dict get $payload recipe] 1
        if {$state($key,sourceToken) eq {}} {error {Registered model Jobs require an exact Dataset source}}
        # Every invocation retains an independent Workspace, including repeated
        # and concurrent runs of the same model. Names are display metadata;
        # scientific identity remains the pinned source/declaration and Job ID.
        set suffix " · [dict get $identity run_id]"
        set state($key,workspaceName) "[string range [dict get $payload name] 0 [expr {159-[string length $suffix]}]]$suffix"
        _saveState $key
        set state($key,registeredRecipe) $recipe
        set execution {}
        foreach field {run_id reference callable_id source_sha256 declaration_sha256 revision language entrypoint consumer_api consumer_operation} {dict set execution $field [dict get $identity $field]}
        set state($key,registeredExecution) $execution
        set record [::GX::scriptRegistryDescribe [dict get $registered reference]]
        set channel [::open [dict get $record source_path] rb];set writer {}
        try {
            set writer [::GX::interactiveDocumentResourceOpenWriter $state($key,documentId) [dict create format gxtxt.registered_model_source_utf8_v1 language [dict get $registered language] source_sha256 [dict get $registered source_sha256]]]
            while {![eof $channel]} {::GX::interactiveDocumentResourceAppend $writer [read $channel 1048576]}
            set resource [::GX::interactiveDocumentResourceFinalize $writer];set writer {}
        } finally {::close $channel;if {$writer ne {}} {::GX::interactiveDocumentResourceAbort $writer}}
        if {[dict get $resource sha256] ne [dict get $registered source_sha256]} {error {Registered executable changed during retained-source capture}}
        set state($key,registeredSourceResource) $resource
        return [dict create key $key document_id $state($key,documentId) fit [dict get $recipe fit] registered $registered]
    } on error {message options} {close $key;return -options $options $message}
}
proc ::GX::DatasetCurveFit::_registeredWithInput {key consumer} {
    variable state
    set fit [dict get $state($key,registeredRecipe) fit];set options [dict get $fit options]
    set companions [_measurementCompanions $key registered $options]
    set mask [expr {[dict get $fit scope] eq "selected"?[_selectionDescriptor $key]:{}}]
    return [::GX::curveSourceWithNumericInput $state($key,sourceToken) [list ::GX::DatasetCurveFit::_registeredInput $key $consumer] $mask {} {} $companions]
}
proc ::GX::DatasetCurveFit::_registeredInput {key consumer input} {
    variable state
    set fit [dict get $state($key,registeredRecipe) fit]
    set training [expr {[dict get $fit scope] eq "selected"?[dict get $input training]:$input}]
    set binding [_measurementBinding $key registered [dict get $fit options] $training]
    return [{*}$consumer $input $binding]
}
proc ::GX::DatasetCurveFit::_registeredInterpret {key report} {
    variable state
    set fit [dict get $state($key,registeredRecipe) fit]
    set report [dict merge $report $fit]
    dict set report orientation [_fitOrientation registered [dict get $fit options]]
    dict set report translation [_translationMetadata $key $report]
    dict set report source_id $state($key,source)
    dict set report selected_indices [selectedIndices $key]
    dict set report registered_source_resource $state($key,registeredSourceResource)
    dict set report registered_execution $state($key,registeredExecution)
    dict set report registered_model_state_sha256 [_numericStateDigest [dict get $report registered_model_state]]
    dict set report recipe_producers [_recipeProducers]
    set report [_interpretStatistics $key $report]
    dict set report physical_formula [string map [list \n {; }] [formula $report]]
    return $report
}
proc ::GX::DatasetCurveFit::_registeredFinish {key report} {
    variable state
    _validateStatisticsMetadata $report
    set scene $state($key,scene)
    foreach field {fitted_native residual_native} resource {preview_geometry_resource preview_residual_plot_resource} {
        set native [::GX::interactiveDocumentNative2DRestore [dict get $report $resource] $scene]
        dict set report $field $native
        ::GX::Native2D::core object_style $scene $native {visible 0 selectable 0}
        set sampled [::GX::Native2D::core object_sample $scene $native 4096]
        if {$field eq "fitted_native"} {dict set report fitted [dict get $sampled points];dict set report fitted_indices [dict get $sampled point_indices];dict set report fitted_breaks [dict get $sampled breaks]} else {dict set report residual_display [dict get $sampled points]}
    }
    set report [dict merge $report [_predictionRestore $scene $report {0.09 0.64 0.29} 0]]
    set page [_numericResidualPage $report 0 200]
    dict set report residual [dict get $page rows];dict set report residual_rows [dict get $page source_rows]
    set state($key,preview) $report;set state($key,previewAccepted) 0;set state($key,previewFitId) {}
    _saveState $key
    ::GX::sessionWorkspaceRename $state($key,documentId) $state($key,workspaceName)
    return [registeredPreviewReference $state($key,documentId) $state($key,activeSource)]
}
proc ::GX::DatasetCurveFit::registeredPreviewReference {documentId sourceId} {
    set doc [::GX::interactiveDocumentRead $documentId]
    if {[dict get $doc module_id] ne "viewer.dataset_curve_fit"} {error {Preview document belongs to another module}}
    foreach entry [dict get $doc payload workspace_sources] {
        if {[dict get $entry id] ne $sourceId} continue
        set saved [dict get $entry state];set result [dict get $saved preview_receipt]
        if {[dict get $result model] ne "registered"} {error {This source has no registered-model preview}}
        _validateStatisticsMetadata $result
        return [dict create schema gxtxt.fit_preview_ref.v1 document_id $documentId generation [dict get $doc generation] source_curve_id $sourceId source_sha256 [dict get $result registered_model_state source_sha256] preview_sha256 [_numericStateDigest $result] accepted [dict get $saved previewAccepted]]
    }
    error {Registered preview source is unavailable}
}
proc ::GX::DatasetCurveFit::registeredPreviewInfo {reference} {
    if {[dict get $reference schema] ne "gxtxt.fit_preview_ref.v1"} {error {Unsupported registered preview reference}}
    set doc [::GX::interactiveDocumentRead [dict get $reference document_id]]
    if {[dict get $doc generation] ne [dict get $reference generation]||[dict get $doc module_id] ne "viewer.dataset_curve_fit"} {error {Registered preview owner changed}}
    foreach entry [dict get $doc payload workspace_sources] {
        if {[dict get $entry id] ne [dict get $reference source_curve_id]} continue
        set saved [dict get $entry state];set result [dict get $saved preview_receipt]
        if {[_numericStateDigest $result] ne [dict get $reference preview_sha256]||[dict get $result registered_model_state source_sha256] ne [dict get $reference source_sha256]} {error {Registered preview content changed}}
        _validateStatisticsMetadata $result
        return [dict create reference $reference accepted [dict get $saved previewAccepted] preview $result]
    }
    error {Retained registered preview is unavailable}
}
proc ::GX::DatasetCurveFit::registeredAccept {reference {name {}}} {
    variable state
    set info [registeredPreviewInfo $reference]
    if {[dict get $info accepted]} {error {Registered preview was already accepted}}
    set doc [::GX::interactiveDocumentRead [dict get $reference document_id]]
    set key [new]
    try {
        set state($key,documentId) [dict get $doc id]
        _applyPayload $key [dict get $doc payload]
        activateSource $key [dict get $reference source_curve_id]
        set state($key,recipePointMask) [dict get $info preview selection_descriptor]
        accept $key $name;_saveState $key
        set record [lindex $state($key,records) end]
        return [resultReference [dict get $doc id] [dict get $record fit_curve_id]]
    } finally {close $key}
}
proc ::GX::DatasetCurveFit::_validateRegisteredModelState {result} {
    if {[dict get $result model] ne "registered"} return
    set model [dict get $result registered_model_state]
    if {[dict exists $model callback]||[dict get $model kind] ne "registered_callback"||[_numericStateDigest $model] ne [dict get $result registered_model_state_sha256]} {error {Retained registered model state changed}}
    set registered [dict get $result options registered_model]
    if {[dict exists $result registered_execution]} {
        foreach field {reference callable_id source_sha256 declaration_sha256 revision language entrypoint} {
            if {[dict get $result registered_execution $field] ne [dict get $registered $field]} {error "Retained registered invocation changed $field"}
        }
    }
    if {[dict get $model source_sha256] ne [dict get $registered source_sha256]||[dict get $model binding_sha256] ne [dict get $registered declaration_sha256]} {error {Registered executable or declaration identity changed}}
    set resource [::GX::interactiveDocumentResourceInfo [dict get $result registered_source_resource]]
    if {[dict get $resource sha256] ne [dict get $model source_sha256]||[dict get $resource metadata format] ne "gxtxt.registered_model_source_utf8_v1"} {error {Retained registered executable bytes changed}}
    set definition [_registeredDefinition [dict get $registered definition]]
    set parameters [dict get $result statistical_results training parameters]
    if {[dict exists $result statistical_results training solver diagnostics]} {
        set receipt [dict get $result statistical_results training solver diagnostics]
        if {[dict get $receipt schema] ne "gxtxt.callback_solver_receipt.v1"} {error {Registered model requires its callback solver receipt}}
        set expectedSolver [expr {[dict get $receipt method] eq "least_squares"?"scipy.optimize.least_squares":"fixed_evaluation"}]
        if {[dict get $model solver] ne $expectedSolver||[dict get $model converged]!=[dict get $receipt converged]||[dict get $model iterations]!=[dict get $receipt iterations]||[dict get $model function_evaluations]!=[dict get $receipt function_evaluations]} {error {Registered retained solver state differs from the CORE receipt}}
        foreach field {initial_parameters lower_bounds upper_bounds fixed_mask} {
            if {[llength [dict get $model $field]]!=[llength $parameters]} {error {Registered retained solver parameter length changed}}
            foreach actual [dict get $model $field] expected [dict get $receipt $field] {if {$actual!=$expected} {error "Registered retained $field differs from its CORE receipt"}}
        }
        set policy [_registeredSolverOptions $definition [dict get $result options]]
        foreach {field target} {solver requested_solver method strategy max_function_evaluations max_function_evaluations function_tolerance function_tolerance gradient_tolerance gradient_tolerance parameter_tolerance parameter_tolerance} {
            set actual [dict get $policy $field];set expected [dict get $receipt $target]
            if {$field in {solver method}} {if {$actual ne $expected} {error "Registered requested $field differs from its CORE receipt"}} elseif {$actual!=$expected} {error "Registered requested $field differs from its CORE receipt"}
        }
        set scales [dict get $policy parameter_scales];if {$scales eq {}} {set scales [lrepeat [llength $parameters] 1]}
        foreach actual $scales expected [dict get $receipt parameter_scales] {if {$actual!=$expected} {error {Registered physical parameter scales differ from their CORE receipt}}}
    }
    if {[llength $parameters]!=[llength [dict get $definition parameter_ids]]} {error {Registered parameter count changed}}
    set count [llength $parameters]
    set declaredMask [::GX::datasetPublicationV2DictDefault $definition fixed_mask [lrepeat $count 0]]
    set retainedMask [::GX::datasetPublicationV2DictDefault $model fixed_mask [lrepeat $count 0]]
    if {[llength $retainedMask]!=$count} {error {Retained fixed mask differs from canonical parameter order}}
    foreach declared $declaredMask retained $retainedMask lo [dict get $definition lower_bounds] hi [dict get $definition upper_bounds] parameter $parameters initial [dict get $model initial_parameters] {
        set expected [expr {$declared||$lo==$hi}]
        if {$retained ni {0 1 0.0 1.0}||$retained!=$expected||([dict get $parameter role] eq "fixed")!=$expected} {error {Retained parameter fixed role differs from its registered declaration}}
        if {$expected&&[dict get $parameter value]!=$initial} {error {Retained fixed parameter differs from its selected initial value}}
    }
    foreach parameter $parameters id [dict get $definition parameter_ids] unit [dict get $definition parameter_units] value [dict get $model parameters] {
        if {[dict get $parameter id] ne $id||[dict get $parameter unit] ne $unit||[dict get $parameter value]!=$value} {error {Registered canonical parameter order, unit or value changed}}
    }
}
