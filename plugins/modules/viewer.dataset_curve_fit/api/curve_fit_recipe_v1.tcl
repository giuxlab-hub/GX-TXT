# Data-only fit replay through the same public Fitter/Numeric path as the GUI.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_recipeProducers {} {
    return [dict create viewer.dataset_curve_fit [::GX::moduleField viewer.dataset_curve_fit version {}] math.numeric [::GX::moduleField math.numeric version {}] semantics_api STATISTICAL_RESULT_SEMANTICS_API_v1 recipe_api gxtxt.fit_recipe.v1]
}
proc ::GX::DatasetCurveFit::_recipeCards {provenance} {
    set cards {}
    foreach kind {composition regional_composition} {
        if {[dict exists $provenance numeric_model_state $kind cards]} {
            foreach card [dict get $provenance numeric_model_state $kind cards] {
                dict set cards [dict get $card id] [dict create version [dict get $card version] descriptor_sha256 [dict get $card descriptor_sha256] definition_sha256 [dict get $card definition_sha256]]
            }
        }
    }
    return $cards
}
proc ::GX::DatasetCurveFit::_recipeFromRecord {record} {
    set p [dict get $record provenance]
    if {![dict exists $p recipe_producers]} {error {This retained fit predates replay provenance. Make an explicit new preview and accept it before capturing a rerun recipe.}}
    set source {}
    foreach field {source_kind source_dataset_id source_x_variable_id source_y_variable_id source_sha256 source_filters source_transform_manifest source_scientific_fingerprints source_sample_id source_sample_descriptor source_axes logarithm_lineage smoothing_lineage} {
        if {[dict exists $p $field]} {dict set source $field [dict get $p $field]}
    }
    if {[dict exists $p covariance_binding]} {dict set source covariance_binding [dict get $p covariance_binding]}
    if {[dict exists $p complex_binding]} {dict set source complex_binding [dict get $p complex_binding]}
    set fit {};foreach field {model scope domain degree initial options selection_descriptor} {dict set fit $field [dict get $p $field]}
    set recipe [dict create format gxtxt.fit_recipe.v1 owner viewer.dataset_curve_fit producers [dict get $p recipe_producers] source $source fit $fit model_cards [_recipeCards $p] captured_fit_id [dict get $record fit_curve_id]]
    if {[dict exists $p template_binding]} {dict set recipe template_binding [dict get $p template_binding]}
    return $recipe
}
proc ::GX::DatasetCurveFit::recipeCapture {documentId fitId} {
    set reference [resultReference $documentId $fitId]
    return [::GX::scientificRecipeEncode [_recipeFromRecord [_recipeResultRecord $reference]]]
}
proc ::GX::DatasetCurveFit::_recipeDecode {encoded} {
    set recipe [::GX::scientificRecipeDataDecode $encoded gxtxt.fit_recipe.v1]
    foreach field {owner producers source fit model_cards captured_fit_id} {if {![dict exists $recipe $field]} {error "Fit recipe requires $field"}}
    if {[dict get $recipe owner] ne "viewer.dataset_curve_fit"} {error {Fit recipe belongs to another scientific owner}}
    if {[dict get $recipe producers] ne [_recipeProducers]} {error {Fit recipe producer/API versions differ. Review and explicitly capture a new recipe.}}
    set fit [dict get $recipe fit]
    foreach field {model scope domain degree initial options selection_descriptor} {if {![dict exists $fit $field]} {error "Fit recipe needs $field"}}
    set model [dict get $fit model];set options [dict get $fit options]
    if {$model ni {linear polynomial exponential power_law gaussian components regions formula rational implicit complex_response circular_arc quadratic_bezier cubic_bezier pchip smoothing_spline akima bspline fourier parametric_polynomial parametric_spline registered}} {error {Unknown fit recipe model}}
    if {[dict get $fit scope] ni {all selected}} {error {Invalid fit recipe scope}}
    foreach key [dict keys $options] {
        if {$key ni {covariance bootstrap profile influence_diagnostics orientation noise_model confidence prediction_band prediction_sigma prediction_weights smoothing_lambda smoothing_options knot_options period component_recipe region_recipe formula_recipe rational_recipe rational_extrapolation implicit_recipe implicit_branch complex_recipe complex_data topology parameterization parameter_variable_id user_period closure_tolerance polar_frame translation_u translation_v measurement solver_options registered_model}} {error "Unknown fit recipe option: $key"}
    }
    _bootstrapOptions $model $options
    _profileOptions $model $options
    _influenceOption $model $options
    _fitOrientation $model $options
    _measurementOptions $options
    set covariance [_covarianceOptions $options]
    if {$covariance ne {}} {
        if {![dict exists $recipe source covariance_binding]} {error {Fit recipe requires its captured covariance Dataset identity}}
        dict for {key value} $covariance {if {$value ne [dict get $recipe source covariance_binding $key]} {error {Fit recipe covariance declaration differs from its captured binding}}}
    }
    foreach value [dict get $fit initial] {_finite $value {Recipe initial parameter}}
    if {$model eq "registered"} {_registeredFitValidate [dict get $recipe source] $fit} else {_solverOptionNodes $model [dict get $fit initial] $options}
    set degree [dict get $fit degree]
    if {![string is integer -strict $degree]||$degree<1||($model in {polynomial parametric_polynomial}&&$degree>12)} {error {Invalid fit recipe degree/order}}
    set domain [dict get $fit domain]
    if {$domain ne "source"} {
        if {[lindex $domain 0] eq "parameter"} {set domain [lrange $domain 1 end]}
        if {[llength $domain]!=3} {error {Fit recipe output domain needs min/max/count}}
        lassign $domain lo hi count;_finite $lo {Recipe output minimum};_finite $hi {Recipe output maximum}
        if {$hi<=$lo||![string is integer -strict $count]||$count<2||$count>10000} {error {Invalid fit recipe output domain}}
    }
    if {$model in {components regions}&&[dict size [dict get $recipe model_cards]]==0} {error {Fit recipe lacks frozen model card identities}}
    if {$model eq "complex_response"} {
        _complexData $options;set resolved [_resolveComplex [dict get $options complex_recipe]]
        if {[dict get $fit initial] ne [dict get $resolved parameters]} {error {Complex recipe initial parameters differ from their physical declaration}}
        if {[_fitOrientation $model $options] ne "y_of_x"||[dict get $options complex_recipe predictor_unit] ne [dict get $recipe source source_axes x unit]} {error {Complex recipe lost physical frequency coordinates}}
    }
    if {$model in {akima bspline}} {_knotSettingsValues $model [dict get $options knot_options]}
    if {$model eq "rational"} {
        _rationalCheckAxes [dict get $options rational_recipe] [dict get $recipe source source_axes] [_fitOrientation $model $options]
        set resolved [_resolveRational [dict get $options rational_recipe]]
        if {[dict get $fit initial] ne [dict get $resolved initial_parameters]} {error {Rational initial values differ from the physical declaration}}
        if {[::GX::datasetPublicationV2DictDefault $options rational_extrapolation error] ni {error allow}} {error {Rational extrapolation policy changed}}
    }
    if {$model eq "implicit"} {
        _implicitCheckAxes [dict get $options implicit_recipe] [dict get $recipe source source_axes]
        _implicitBranchNode [dict get $options implicit_branch] [_fitOrientation $model $options]
        _resolveImplicit [dict get $options implicit_recipe]
    }
    if {$model eq "formula"} {
        set formula [dict get $options formula_recipe]
        _formulaCheckAxes $formula [dict get $recipe source source_axes] [_fitOrientation $model $options]
        set resolved [_resolveFormula $formula]
        if {[dict get $fit initial] ne [dict get $resolved initial_parameters]} {error {Formula recipe initial values differ from its declaration}}
    }
    ::GX::curveSourcePointMaskValidate [dict get $fit selection_descriptor]
    return $recipe
}
proc ::GX::DatasetCurveFit::recipeValidate {encoded} {
    set recipe [_recipeDecode $encoded];set source [dict get $recipe source]
    switch [dict get $source source_kind] {
        dataset {
            set snapshot [dict create api_id CURVE_SOURCE_API_v1 api_version 1 source_identities [dict get $source source_scientific_fingerprints]]
            if {[llength [dict get $snapshot source_identities]]==0} {error {Fit recipe lacks source fingerprints}}
            set check [::GX::curveSourceValidateSnapshot $::GX::currentSession $snapshot]
            if {![dict get $check valid]} {error "Fit recipe source content/schema changed: $check"}
            if {[dict exists $source covariance_binding]} {
                set binding [dict get $source covariance_binding]
                if {[::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $binding dataset_id]] ne [dict get $binding covariance_dataset_identity]} {error {Fit recipe covariance Dataset content/schema changed; review and capture a new covariance declaration}}
            }
            if {[dict exists $source complex_binding]} {
                set binding [dict get $source complex_binding]
                if {[::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $source source_dataset_id]] ne [dict get $binding input_dataset_identity]} {error {Complex recipe observation Dataset content/schema changed}}
                if {[dict get $binding covariance layout] eq "per_observation"&&[::GX::curveSourceDatasetIdentity $::GX::currentSession [dict get $binding covariance dataset_id]] ne [dict get $binding covariance_dataset_identity]} {error {Complex recipe covariance Dataset content/schema changed}}
            }
            _logRecipeValidate $source
            _smoothRecipeValidate $source
        }
        builtin_sample {
            if {[sampleDescriptor [dict get $source source_sample_id]] ne [dict get $source source_sample_descriptor]} {error {Fit recipe built-in sample definition changed}}
        }
        default {error {Unsupported fit recipe source kind}}
    }
    if {[dict size [dict get $recipe model_cards]]} {
        set catalog [expr {[dict get $recipe fit model] eq "regions" ? [regionCatalog] : [componentCatalog]}]
        set current {};foreach card $catalog {dict set current [dict get $card id] $card}
        dict for {id expected} [dict get $recipe model_cards] {
            if {![dict exists $current $id]} {error "Fit recipe model card is unavailable: $id"}
            dict for {field value} $expected {if {[dict get $current $id $field] ne $value} {error "Fit recipe model card changed: $id / $field"}}
        }
    }
    return [dict create status validated format gxtxt.fit_recipe.v1 model [dict get $recipe fit model] scope [dict get $recipe fit scope] source_kind [dict get $source source_kind] captured_fit_id [dict get $recipe captured_fit_id]]
}
proc ::GX::DatasetCurveFit::recipeLoadSettings {key encoded {exact 0}} {
    variable state
    _assertSession $key
    recipeValidate $encoded;set recipe [_recipeDecode $encoded]
    set source [dict get $recipe source];set fit [dict get $recipe fit]
    if {[dict get $source source_kind] eq "dataset"} {
        loadSource $key [dict get $source source_dataset_id] [dict get $source source_x_variable_id] [dict get $source source_y_variable_id] [dict get $source source_filters] [::GX::datasetPublicationV2DictDefault $source source_transform_manifest {}] [dict get $source source_scientific_fingerprints]
    } else {
        loadSample $key [dict get $source source_sample_id]
        unset -nocomplain state($key,recipePointMask) state($key,templateBinding)
    }
    set mask [dict get $fit selection_descriptor]
    set manual {};dict for {row mode} [dict get $mask manual_rows] {
        set index [lsearch -exact $state($key,rows) $row]
        if {$index>=0} {lappend manual [list $index $mode]}
    }
    _restoreSelectionDescriptor $key [dict create base_selected [dict get $mask base_selected] regions [dict get $mask regions] manual $manual]
    if {$exact&&[dict get $source source_kind] eq "dataset"} {set state($key,recipePointMask) $mask}
    # These are ordinary Workspace controls. Scientific replay uses the
    # captured argument dictionary and exact row mask, never display points.
    foreach field {model scope degree} {set state($key,$field) [dict get $fit $field]}
    set state($key,initial) [join [dict get $fit initial] ,]
    set state($key,domain) source;set state($key,min) {};set state($key,max) {};set state($key,samples) 200
    if {[dict get $fit domain] ne "source"} {
        set domain [dict get $fit domain];set state($key,domain) range
        if {[lindex $domain 0] eq "parameter"} {set state($key,domain) parameter;set domain [lrange $domain 1 end]}
        lassign $domain state($key,min) state($key,max) state($key,samples)
    }
    foreach {field value} {covarianceSettings {} bootstrapSettings {} profileSettings {} influenceDiagnostics 0 orientation y_of_x noiseModel unspecified confidence .95 predictionBand none predictionSigma {} predictionWeights {} measurementKind none measurementVariable {} measurementIndependentVariable {} measurementMissing error solverSettings {} smoothingSettings {} knotSettings {} componentRecipe {} regionRecipe {} formulaRecipe {} rationalRecipe {} rationalExtrapolation error implicitRecipe {} implicitBranch {} complexRecipe {} complexData {} registeredModel {} period {} smoothing .01 topology auto parameterization row_order parameterVariable {} userPeriod {} closureTolerance {} translationUMode off translationUDelta 0 translationVMode off translationVDelta 0} {set state($key,$field) $value}
    set options [dict get $fit options]
    if {$state($key,model) in {akima bspline}} {dict set state($key,knotSettings) $state($key,model) [dict get $options knot_options]}
    foreach {option field} {covariance covarianceSettings bootstrap bootstrapSettings profile profileSettings influence_diagnostics influenceDiagnostics orientation orientation noise_model noiseModel confidence confidence prediction_band predictionBand prediction_sigma predictionSigma prediction_weights predictionWeights smoothing_lambda smoothing smoothing_options smoothingSettings period period component_recipe componentRecipe region_recipe regionRecipe formula_recipe formulaRecipe rational_recipe rationalRecipe rational_extrapolation rationalExtrapolation implicit_recipe implicitRecipe implicit_branch implicitBranch complex_recipe complexRecipe complex_data complexData registered_model registeredModel topology topology parameterization parameterization parameter_variable_id parameterVariable user_period userPeriod closure_tolerance closureTolerance polar_frame polarFrame} {
        if {[dict exists $options $option]} {set state($key,$field) [dict get $options $option]}
    }
    foreach axis {u v} upper {U V} {
        if {[dict exists $options translation_$axis]} {set state($key,translation${upper}Mode) [dict get $options translation_$axis mode];set state($key,translation${upper}Delta) [dict get $options translation_$axis delta]}
    }
    if {[dict exists $options measurement]} {foreach {option field} {kind measurementKind variable_id measurementVariable independent_variable_id measurementIndependentVariable nonfinite measurementMissing} {if {[dict exists $options measurement $option]} {set state($key,$field) [dict get $options measurement $option]}}}
    if {[dict exists $options solver_options]} {dict set state($key,solverSettings) [dict get $fit model] [dict get $options solver_options]}
    if {[dict exists $recipe template_binding]} {set state($key,templateBinding) [dict get $recipe template_binding]}
    return [dict create status settings_loaded model [dict get $fit model] scope [dict get $fit scope]]
}
proc ::GX::DatasetCurveFit::recipeRun {encoded {name {}} {acceptedName {}}} {
    variable state
    if {$acceptedName ne {}} {set acceptedName [_acceptedName $acceptedName]}
    recipeValidate $encoded;set recipe [_recipeDecode $encoded]
    if {[dict get $recipe fit model] eq "registered"} {error {Registered-model replay is asynchronous; use registered_submit and inspect its retained preview before accepting}}
    set name [string trim $name]
    if {$name eq {}} {set name "Rerun [dict get $recipe fit model]"}
    if {[string length $name]>160||[regexp {[\r\n\x00]} $name]} {error {Rerun Workspace name must be a single line of at most 160 characters}}
    set names [lmap item [::GX::sessionWorkspaceList] {dict get $item name}]
    set base $name;set suffix 1
    while {$name in $names} {set tail " ([incr suffix])";set name "[string range $base 0 [expr {159-[string length $tail]}]]$tail"}
    set key [new]
    try {
        recipeLoadSettings $key $encoded 1
        set fit [dict get $recipe fit]
        set state($key,workspaceName) $name
        preview $key [dict get $fit model] [dict get $fit scope] [dict get $fit domain] [dict get $fit degree] [dict get $fit initial] [dict get $fit options]
        accept $key $acceptedName
        # Exact mask belongs to the accepted provenance. A reopened viewer uses
        # its ordinary display selection; it never silently recomputes this fit.
        _saveState $key
        ::GX::sessionWorkspaceRename $state($key,documentId) $state($key,workspaceName)
        set record [lindex $state($key,records) end]
        return [resultReference $state($key,documentId) [dict get $record fit_curve_id]]
    } finally {close $key}
}
proc ::GX::DatasetCurveFit::resultReference {documentId fitId} {
    set doc [::GX::interactiveDocumentRead $documentId]
    if {[dict get $doc module_id] ne "viewer.dataset_curve_fit"} {error {Result document belongs to another module}}
    foreach record [dict get $doc payload records] {
        if {[dict get $record fit_curve_id] ne $fitId} continue
        _validateAcceptedStatistics $record
        return [dict create schema gxtxt.fit_result_ref.v1 document_id $documentId generation [dict get $doc generation] fit_curve_id $fitId provenance_sha256 [::GX::datasetStorageSha256Text $::GX::currentSession [dict get $record provenance]]]
    }
    error {Accepted fit ID does not exist in this Workspace}
}
proc ::GX::DatasetCurveFit::_recipeResultRecord {reference} {
    if {[dict get $reference schema] ne "gxtxt.fit_result_ref.v1"} {error {Unsupported retained fit reference}}
    set actual [resultReference [dict get $reference document_id] [dict get $reference fit_curve_id]]
    foreach key {generation provenance_sha256} {if {[dict get $actual $key] ne [dict get $reference $key]} {error {Retained fit reference changed or belongs to an expired owner generation}}}
    set doc [::GX::interactiveDocumentRead [dict get $reference document_id]]
    foreach record [dict get $doc payload records] {if {[dict get $record fit_curve_id] eq [dict get $reference fit_curve_id]} {return $record}}
}
proc ::GX::DatasetCurveFit::resultInfo {reference} {
    set record [_recipeResultRecord $reference];set p [dict get $record provenance]
    set resources {}
    foreach key [dict keys $p *_resource] {dict set resources $key [::GX::interactiveDocumentResourceInfo [dict get $p $key]]}
    if {[dict exists $record geometry_resource]} {dict set resources geometry_resource [::GX::interactiveDocumentResourceInfo [dict get $record geometry_resource]]}
    set outputDomain [_outputDomainInfo $p]
    if {$outputDomain eq {}} {set outputDomain {schema gxtxt.fit_output_domain.v1 status unavailable reason historical_receipt_not_recorded}}
    return [dict create reference $reference accepted_name [dict get $record label] model [dict get $record model] parameters [dict get $record parameters] formula [dict get $p physical_formula] statistical_results [dict get $p statistical_results] output_domain $outputDomain preprocessing [_preprocessingInfo $p] resources $resources template_binding [::GX::datasetPublicationV2DictDefault $p template_binding {}] recipe [::GX::scientificRecipeEncode [_recipeFromRecord $record]]]
}
proc ::GX::DatasetCurveFit::resultPublish {reference datasetId} {
    variable state
    set record [_recipeResultRecord $reference];set key [new]
    try {
        set state($key,documentId) [dict get $reference document_id]
        if {[dict exists $record geometry_resource]} {set id [::GX::interactiveDocumentNative2DRestore [dict get $record geometry_resource] $state($key,scene)]} else {set id [::GX::Native2D::core add $state($key,scene) [dict get $record points]]}
        dict set record id $id;set state($key,records) [list $record]
        return [publishFitDataset $key $datasetId $id]
    } finally {close $key}
}
proc ::GX::DatasetCurveFit::recipeScript {encoded language} {
    recipeValidate $encoded
    switch $language {
        Python {return "# GX-TXT explicit scientific rerun; creates a new retained Workspace.\nfrom gxtxt import gxtxt_api_call\nrecipe = '$encoded'\nresult = gxtxt_api_call('DATASET_CURVE_FIT_API_v1', 'recipe_run', \[recipe, 'Recipe rerun'\])\ninfo = gxtxt_api_call('DATASET_CURVE_FIT_API_v1', 'result_info', \[result\])\nprint(info\['formula'\])\nprint(result)\n"}
        Octave {return "% GX-TXT explicit scientific rerun; creates a new retained Workspace.\nrecipe = '$encoded';\nresult = gxtxt_api_call('DATASET_CURVE_FIT_API_v1', 'recipe_run', {recipe, 'Recipe rerun'});\ninfo = gxtxt_api_call('DATASET_CURVE_FIT_API_v1', 'result_info', {result});\ndisp(info.formula);\ndisp(result);\n"}
        default {error {Recipe script language must be Python or Octave}}
    }
}
proc ::GX::DatasetCurveFit::_recipeExport {w language} {
    variable state
    set selected [$w.left.viewport.content.accepted.list curselection]
    if {[llength $selected]!=1} {error {Select one accepted fit to export its rerun recipe}}
    set record [lindex $state($w,records) [lindex $selected 0]]
    set encoded [::GX::scientificRecipeEncode [_recipeFromRecord $record]]
    set text [recipeScript $encoded $language]
    set suffix [expr {$language eq "Python" ? ".py" : ".m"}]
    set destination [tk_getSaveFile -parent $w -title "Export $language fit rerun" -defaultextension $suffix -initialfile "fit_rerun$suffix"]
    if {$destination eq {}} return
    return [::GX::filePublicationPublishBundle [list [dict create id fit_recipe destination $destination writer [list ::GX::DatasetCurveFit::_recipeWrite $text]]]]
}
proc ::GX::DatasetCurveFit::_recipeWrite {text channel context} {puts -nonewline $channel $text}
