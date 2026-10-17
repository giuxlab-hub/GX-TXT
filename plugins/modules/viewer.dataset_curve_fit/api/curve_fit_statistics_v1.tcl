# SPDX-License-Identifier: GPL-3.0-or-later
# Fitter transports Numeric facts; the public CORE API owns their meaning.
proc ::GX::DatasetCurveFit::_interpretStatistics {key result} {
    dict set result producer_framework_version $::GX::version
    set source [_sourceProvenance $key]
    set axes [dict get $source source_axes]
    set context [dict create orientation [dict get $result orientation] \
        x_unit [dict get $axes x unit] y_unit [dict get $axes y unit] \
        x_variable_id [dict get $axes x variable_id] y_variable_id [dict get $axes y variable_id] \
        radial_unit [::GX::datasetPublicationV2DictDefault $result metric_unit {}] \
        constraints none coefficient_space translated_fit translation [dict get $result translation] \
        zero_normal_sign_policy [::GX::datasetPublicationV2DictDefault $result zero_normal_sign_policy unspecified]]
    if {[dict get $result model] in {rational akima bspline}} {dict set context coefficient_space original_physical}
    if {[dict get $result model] eq "implicit"} {dict set context orientation implicit_residual}
    set facts [dict get $result numeric_statistics]
    if {[dict get $result model] eq "complex_response"} {
        dict set context orientation joint_responses;dict set context y_unit 1;dict set context coefficient_space original_physical
        dict set result complex_model_state [dict get $facts complex_model_state]
        dict set result complex_model_state_sha256 [_numericStateDigest [dict get $facts complex_model_state]]
    }
    if {[dict exists $facts numeric_model_state]} {
        dict set result numeric_model_state [dict get $facts numeric_model_state]
        dict set result numeric_model_state_sha256 [_numericStateDigest [dict get $facts numeric_model_state]]
    }
    set raw [dict get $facts fit]
    if {[dict exists $facts numeric_model_state]} {dict set raw model [dict get $facts numeric_model_state]}
    if {[dict exists $result registered_model_state]} {dict set raw model [dict get $result registered_model_state]}
    if {[dict get $result model] eq "smoothing_spline"} {dict set context smoother_predictor_unit [dict get $result translation u unit]}
    set options [dict get $result options]
    dict set context noise_model [::GX::datasetPublicationV2DictDefault $options noise_model unspecified]
    if {[dict exists $result covariance_binding]} {dict set context covariance_unit [dict get $result covariance_binding covariance_unit]}
    set smoothing [_smoothContext $source]
    if {$smoothing ne {}} {dict set context smoothing $smoothing}
    set baseline [_baselineContext $source]
    if {$baseline ne {}} {dict set context baseline_correction $baseline}
    set logarithm [_logContext $source [dict get $result orientation]]
    if {$logarithm ne {}} {dict set context response_transform $logarithm}
    if {[dict exists $result preprocessing]} {
        dict set result preprocessing coordinate_transform [dict create orientation [dict get $result orientation] source_axes $axes translation [dict get $result translation] smoothing $smoothing baseline_correction $baseline response_transform $logarithm]
    }
    set confidence [::GX::datasetPublicationV2DictDefault $options confidence 0.95]
    set modelId math.numeric.[dict get $result model]
    if {[dict get $result model] in {components regions formula registered}} {set modelId math.numeric.nonlinear}
    foreach {role field} {training training evaluation evaluation} {
        dict set context sample_role $role
        set roleRaw $raw;set provenance [dict create producer viewer.dataset_curve_fit source_identity $source]
        if {[dict get $result model] in {akima bspline}&&$role eq "evaluation"} {
            set roleRaw [dict get $facts knot_evaluation]
            set context [dict get $result statistical_results training context]
            dict set context sample_role evaluation
        }
        if {[dict get $result model] eq "rational"&&$role eq "evaluation"} {set roleRaw [dict get $facts rational_evaluation];dict set roleRaw model [dict get $facts numeric_model_state]}
        if {[dict get $result model] eq "complex_response"} {
            dict set provenance complex_binding [dict get $result complex_binding]
            if {$role eq "evaluation"} {set roleRaw [dict get $facts complex_evaluation];dict set roleRaw model [dict get $facts numeric_model_state]}
        }
        if {$role eq "training"&&[dict exists $facts physical_observation_signature]} {dict set provenance physical_observation_signature [dict get $facts physical_observation_signature]}
        if {[dict exists $result covariance_binding]} {dict set provenance covariance_binding [dict get $result covariance_binding]}
        if {[dict exists $result measurement_binding]} {
            dict set provenance measurement_binding [dict get $result measurement_binding]
            dict set provenance measurement_selection [dict get $result measurement_selection]
            if {$role eq "evaluation"} {dict set roleRaw weight_semantics unweighted}
        }
        if {$role eq "evaluation"&&[::GX::datasetPublicationV2DictDefault $roleRaw fit_geometry vertical_response] eq "orthogonal_xy"} {
            # Evaluation is the existing functional response deviation at the
            # original source coordinates. It does not refit latent positions.
            dict set roleRaw fit_geometry vertical_response
            dict unset roleRaw solver_receipt
            dict set provenance training_fit_geometry orthogonal_xy
        }
        dict set result statistical_results $role [::GX::StatisticsV1::fromNumeric $modelId \
            [dict get $roleRaw operation] $roleRaw $context [dict get $facts $field] $provenance]
    }
    set training [dict get $result statistical_results training]
    set plan [::GX::StatisticsV1::parameterInferencePlan $training $confidence]
    set numeric {}
    if {[dict exists $facts parameter_uncertainty]} {
        set numeric [dict get $facts parameter_uncertainty]
    } elseif {[dict get $plan status] eq "value"} {set numeric [::GX::NumericAPIv1::parameterUncertainty $plan]}
    dict set result statistical_results training [::GX::StatisticsV1::withParameterUncertainty $training $confidence $numeric]
    if {[dict exists $result comparison_input]} {
        set sourceId [::GX::datasetPublicationV2DictDefault $source source_dataset_id [::GX::datasetPublicationV2DictDefault $source source_sample_id {}]]
        set binding [dict merge [dict create schema gxtxt.observation_binding.v1 source_id "[dict get $source source_kind]:$sourceId"] [dict get $result comparison_input]]
        dict unset result comparison_input
        dict set result observation_binding $binding
        set selectionPlan [::GX::StatisticsV1::modelSelectionPlan [dict get $result statistical_results training] $binding]
        dict set result model_selection plan $selectionPlan
        if {[dict get $selectionPlan status] eq "value"} {dict set result model_selection numeric [::GX::NumericAPIv1::fitInformationCriteria $selectionPlan]}
    }
    if {[dict exists $facts prediction_plan]} {
        dict set result prediction_plan [::GX::StatisticsV1::predictionInferencePlan [dict get $result statistical_results training] [dict get $facts prediction_plan kind] $confidence]
    }
    if {[dict exists $facts prediction_receipt]} {
        dict set result statistical_results prediction [::GX::StatisticsV1::predictionInterpretation [dict get $result statistical_results training] [dict get $facts prediction_receipt]]
        dict set result prediction_display_note [dict get $facts prediction_display_note]
    }
    if {[dict exists $facts influence]} {dict set result statistical_results influence [::GX::StatisticsV1::influenceInterpretation [dict get $result statistical_results training] [dict get $facts influence]]}
    if {[dict exists $facts profile]} {dict set result statistical_results profile [::GX::StatisticsV1::profileInterpretation [dict get $result statistical_results training] [dict get $facts profile]]}
    if {[dict exists $facts bootstrap]} {dict set result statistical_results bootstrap [::GX::StatisticsV1::bootstrapInterpretation [dict get $result statistical_results training] [dict get $facts bootstrap]]}
    if {[dict get $result model] eq "rational"} {dict set result rational_state_sha256 [_numericStateDigest [_rationalState $result]]}
    if {[dict get $result model] in {akima bspline}} {dict set result knot_binding_sha256 [_knotResultIdentity $result]}
    dict unset result numeric_statistics
    return [_applyStatisticsAliases $result]
}
proc ::GX::DatasetCurveFit::_statisticsAliasRows {result} {
    set aliases {}
    foreach {role prefix} {training train evaluation source} {
        set mapping [dict create ${prefix}_rmse rmse ${prefix}_r2 r_squared]
        # train_n is the physical source-row count. Joint complex n counts
        # Cartesian residual components and must not overwrite that identity.
        if {$role eq "training"&&[dict get $result model] ne "complex_response"} {dict set mapping train_n n}
        if {[::GX::datasetPublicationV2DictDefault $result parametric 0]} {
            # Historical geometric r2 is an XY dispersion score. Preserve that
            # identity explicitly; it has never been centered response R squared.
            dict set mapping ${prefix}_r2 geometric_dispersion_score
            dict set mapping ${prefix}_geometric_dispersion_score geometric_dispersion_score
            dict set mapping ${prefix}_geometric_rmse rmse
            dict set mapping ${prefix}_max_geometric_distance max_abs_error
        }
        foreach row [::GX::StatisticsV1::scalarRows [dict get $result statistical_results $role] $mapping] {
            dict set row sample_role $role
            dict set aliases [dict get $row id] $row
        }
    }
    return $aliases
}
proc ::GX::DatasetCurveFit::_applyStatisticsAliases {result} {
    set aliases [_statisticsAliasRows $result]
    dict for {id row} $aliases {dict set result $id [dict get $row value]}
    dict set result statistical_aliases $aliases
    return $result
}
proc ::GX::DatasetCurveFit::_validateStatisticsMetadata {result} {
    # Historical accepted Sessions lack this additive field. Preserve the raw
    # historical payload; never certify it as a newly interpreted result.
    if {![dict exists $result statistical_results]} {return legacy_unvalidated}
    set expected [_statisticsAliasRows $result]
    if {![dict exists $result statistical_aliases]||[dict size [dict get $result statistical_aliases]]!=[dict size $expected]} {error {Statistical compatibility aliases are missing or incomplete}}
    dict for {id row} $expected {
        if {![dict exists $result statistical_aliases $id]||![dict exists $result $id]} {error "Missing statistical compatibility alias $id"}
        set saved [dict get $result statistical_aliases $id]
        if {[dict size $saved]!=[dict size $row]} {error "Modified statistical compatibility alias $id"}
        dict for {field value} $row {
            if {![dict exists $saved $field]||[dict get $saved $field] ne $value} {error "Modified statistical compatibility alias $id/$field"}
        }
        if {[dict get $result $id] ne [dict get $row value]} {error "Modified statistical compatibility value $id"}
    }
    _smoothStatisticsValidate $result
    _validateNumericModelState $result
    _validateRationalMetadata $result
    _validateKnotMetadata $result
    _validateImplicitMetadata $result
    _validateComplexMetadata $result
    _validateRegisteredModelState $result
    _validateMeasurementMetadata $result
    _validateCovarianceMetadata $result
    _validateInfluenceMetadata $result
    _validateBootstrapMetadata $result
    _validateProfileMetadata $result
    _validatePredictionMetadata $result
    _validateModelSelection $result
    _validateRegionalMetadata $result
    return validated
}
proc ::GX::DatasetCurveFit::_validatePredictionMetadata {result} {
    if {![dict exists $result statistical_results prediction]} {
        if {[dict exists $result prediction_resource]} {error {Prediction columns lack their captured CORE interpretation}}
        return
    }
    set meaning [dict get $result statistical_results prediction]
    ::GX::StatisticsV1::validate $meaning
    set raw [dict create numeric_api NUMERIC_API_v1 operation prediction_uncertainty plan [dict get $meaning provenance prediction_plan]]
    foreach field {model_source_sha256 model_binding_sha256} {dict set raw $field [dict get $meaning provenance $field]}
    if {[dict exists $meaning provenance model_evaluation_kind]} {dict set raw model_evaluation_kind [dict get $meaning provenance model_evaluation_kind]}
    dict for {field quantity} [::GX::StatisticsV1::numericFieldMap prediction_uncertainty] {dict set raw $field [dict get $meaning quantities $quantity value]}
    set expected [::GX::StatisticsV1::predictionInterpretation [dict get $result statistical_results training] $raw]
    if {[dict get $expected request] ne [dict get $meaning request]} {error {Prediction interpretation differs from the accepted fitted source}}
    if {![dict exists $result prediction_resource]} {error {Prediction result is missing its original owned columns}}
    set resource [::GX::interactiveDocumentResourceInfo [dict get $result prediction_resource]]
    set metadata [dict get $resource metadata];set n [dict get $result output_n]
    if {[dict get $resource size_bytes]!=64*$n||[dict get $metadata format] ne "float64_interleaved_le"||[dict get $metadata row_count]!=$n||[dict get $meaning quantities prediction_query_count value]!=$n||[dict get $metadata columns] ne {prediction_query prediction_mean prediction_lower prediction_upper prediction_mean_se prediction_se prediction_noise_sd prediction_available}} {error {Prediction resource shape or canonical column identities changed}}
    if {[dict exists $result prediction_gap_resource]} {
        set gap [::GX::interactiveDocumentResourceInfo [dict get $result prediction_gap_resource]]
        if {[dict get $gap metadata format] ne "native2d.uint8_break_before_v1"} {error {Prediction boundary gap format changed}}
    }
    foreach boundary {lower upper} {
        if {![dict exists $result prediction_${boundary}_resource]} continue
        set geometry [::GX::interactiveDocumentResourceInfo [dict get $result prediction_${boundary}_resource]]
        set count [dict get $geometry metadata point_count]
        if {![info exists gap]||![string is entier -strict $count]||$count<1||[dict get $geometry metadata format] ne "native2d.float64_xy_le_v1"||[dict get $geometry size_bytes]!=16*$count||[dict get $gap size_bytes]!=$count} {error {Prediction boundary and original gap identity differ}}
    }
}
proc ::GX::DatasetCurveFit::_predictionRestore {scene provenance color visible} {
    set restored {}
    try {
        foreach boundary {lower upper} {
            if {![dict exists $provenance prediction_${boundary}_resource]} continue
            set resource [dict get $provenance prediction_${boundary}_resource]
            if {[dict get $resource metadata point_count]>1} {
                if {![dict exists $provenance prediction_gap_resource]} {error {Prediction boundary is missing its original gap identity}}
                set native [::GX::interactiveDocumentNative2DRestoreWithGaps $resource [dict get $provenance prediction_gap_resource] $scene]
            } else {set native [::GX::interactiveDocumentNative2DRestore $resource $scene]}
            dict set restored prediction_${boundary}_native $native
            ::GX::Native2D::core style $scene $native $color 1.25
            ::GX::Native2D::core object_style $scene $native [dict create visible $visible locked 1 selectable 0 line_style 1 marker 0]
            ::GX::Native2D::core direction_marker $scene $native {present 0}
        }
        return $restored
    } on error {message options} {
        dict for {field native} $restored {::GX::Native2D::core delete $scene $native}
        return -options $options $message
    }
}
proc ::GX::DatasetCurveFit::_predictionLoadBoundary {scene path gaps} {
    if {[file size $path]==16} {
        set channel [::open $path rb];try {set native [::GX::Native2D::core append_binary_point $scene 0 [read $channel]]} finally {::close $channel}
    } else {set native [::GX::native2DLoadNumericRowsWithGaps $scene $path $gaps]}
    try {
        ::GX::Native2D::core object_style $scene $native {marker 0}
        ::GX::Native2D::core direction_marker $scene $native {present 0}
        return $native
    } on error {message options} {::GX::Native2D::core delete $scene $native;return -options $options $message}
}
proc ::GX::DatasetCurveFit::_predictionDraw {scene canvas result background tags} {
    foreach boundary {lower upper} {
        set field prediction_${boundary}_native
        if {![dict exists $result $field]} continue
        set native [dict get $result $field];set visible [dict get [::GX::Native2D::core object_style $scene $native] visible]
        try {
            ::GX::Native2D::core visible $scene $native 1
            ::GX::native2DCanvasDrawObject $canvas [::GX::native2DPresentationObjectSnapshot $scene $native 4096] $background [concat $tags prediction_$boundary]
        } finally {::GX::Native2D::core visible $scene $native $visible}
    }
}
proc ::GX::DatasetCurveFit::_predictionPublicationPage {reader count} {
    set page [::GX::interactiveDocumentResourceNext $reader [expr {64*$count}]]
    if {[dict get $page count]!=64*$count} {error {Prediction columns ended before the exact fitted geometry}}
    binary scan [dict get $page bytes] q* values
    set ids {prediction_query prediction_mean prediction_lower prediction_upper prediction_mean_se prediction_se prediction_noise_sd prediction_available}
    set columns {};foreach id $ids {dict set columns $id {}}
    foreach {query mean lower upper meanSe se noise available} $values {
        foreach id $ids value [list $query $mean $lower $upper $meanSe $se $noise $available] {dict lappend columns $id $value}
    }
    return $columns
}
proc ::GX::DatasetCurveFit::_numericStateDigest {value} {
    # The shared typed result transport has already preserved binary64 values
    # as roundtrippable decimals, including infinite bounds. Hash its captured
    # Tcl value; do not pass it through Octave JSON.
    set channel [file tempfile path]
    try {
        fconfigure $channel -encoding utf-8 -translation lf
        puts -nonewline $channel $value
        ::close $channel;set channel {}
        return [::GX::sha256File $path]
    } finally {if {$channel ne {}} {::close $channel};file delete -force -- $path}
}
proc ::GX::DatasetCurveFit::_validateNumericModelState {result} {
    if {![dict exists $result numeric_model_state]} {
        if {[dict exists $result statistical_results training solver diagnostics]} {
            set schema [dict get $result statistical_results training solver diagnostics schema]
            if {$schema eq "gxtxt.callback_solver_receipt.v1"} {
                if {[dict get $result model] ne "registered"||![dict exists $result registered_model_state]} {error {Callback fit is missing its exact registered model state}}
                return
            }
            error {Native fit is missing its exact Numeric model state}
        }
        return
    }
    set model [dict get $result numeric_model_state]
    if {![dict exists $result numeric_model_state_sha256]||[_numericStateDigest $model] ne [dict get $result numeric_model_state_sha256]} {error {Numeric model state integrity check failed}}
    set statistics [dict get $result statistical_results training]
    ::GX::StatisticsV1::validate $statistics
    set receipt [dict get $statistics solver diagnostics]
    if {[dict get $receipt schema] ne "gxtxt.numeric_solver_receipt.v1"} {error {Native model state requires its native solver receipt}}
    set expectedKind [dict get $result model]
    if {$expectedKind eq "polynomial"} {set expectedKind polynomial_fit}
    if {$expectedKind eq "components"} {set expectedKind expression;if {![dict exists $model composition]} {error {Component fit lost its frozen declarations}}}
    if {$expectedKind eq "regions"} {set expectedKind expression;if {![dict exists $model regional_composition]} {error {Regional fit lost its frozen declarations}}}
    if {$expectedKind eq "complex_response"} {set expectedKind expression}
    if {$expectedKind in {formula rational implicit}} {set expectedKind expression;if {![dict exists $model formula_declaration]} {error {Formula fit lost its frozen declaration}}}
    if {[dict get $model kind] ne $expectedKind||[dict get $model schema_version]!=1} {error {Numeric model identity changed}}
    set parameters [dict get $statistics parameters]
    if {[llength [dict get $model parameters]]!=[llength $parameters]||[llength [dict get $model parameter_ids]]!=[llength $parameters]} {error {Numeric model parameter identity count changed}}
    foreach value [dict get $model parameters] id [dict get $model parameter_ids] parameter $parameters {
        if {$id ne [dict get $parameter id]||$value!=[dict get $parameter value]} {error {Numeric model parameter identities or values changed}}
    }
    foreach key {initial_parameters} {if {[dict get $model $key] ne [dict get $receipt $key]} {error {Numeric model initial state differs from its solver receipt}}}
    foreach key {lower_bounds upper_bounds fixed_mask parameter_scales function_tolerance gradient_tolerance parameter_tolerance max_iterations max_seconds strategy loss loss_scale} {
        if {[dict get $model solver_options $key] ne [dict get $receipt $key]} {error "Numeric model solver setting changed: $key"}
    }
    if {[::GX::datasetPublicationV2DictDefault [dict get $statistics context] fit_geometry vertical_response] eq "orthogonal_xy"&&([dict get $model solver_options fit_geometry] ne "orthogonal_xy"||[dict get $model solver_options required_measurement_input] ne "sigma_xy")} {error {Numeric model lost its required XY uncertainty contract}}
}
proc ::GX::DatasetCurveFit::_requireConvergedNativeFit {result} {
    if {[dict exists $result registered_model_state]&&![dict get $result registered_model_state converged]} {
        error {The registered callback solver did not converge. Inspect its retained solver message and run a new preview before accepting.}
    }
    if {[dict exists $result statistical_results training solver diagnostics]&&![dict get $result statistical_results training solver converged]} {
        error {The native solver did not converge. Inspect the solver report and preview again before accepting or publishing this fit.}
    }
}
proc ::GX::DatasetCurveFit::_validateAcceptedStatistics {record} {
    if {![dict exists $record provenance]} {return legacy_unvalidated}
    set metadata [dict get $record provenance]
    if {[dict exists $metadata accepted_name]&&([_acceptedName [dict get $metadata accepted_name]] ne [dict get $metadata accepted_name]||[dict get $record label] ne [dict get $metadata accepted_name])} {error {Accepted curve name differs from its retained provenance}}
    set status [_validateStatisticsMetadata $metadata]
    _preprocessingInfo $metadata
    if {$status eq "validated"} {
        foreach {field alias} {rmse train_rmse r2 train_r2} {
            if {![dict exists $record $field]||[dict get $record $field] ne [dict get $metadata $alias]} {error "Modified accepted statistical value $field"}
        }
    }
    return $status
}
proc ::GX::DatasetCurveFit::_predictionLabels {} {
    return {none {No response interval} mean_confidence {Pointwise mean confidence interval} new_observation {Pointwise future-observation prediction interval}}
}
proc ::GX::DatasetCurveFit::_statisticalSettings {w} {
    variable state
    set labels {unspecified {Unspecified — no confidence claim} independent_gaussian_estimated_variance {Independent Gaussian errors; variance estimated from residuals} independent_gaussian_known_sigma {Independent Gaussian errors; known absolute measurement sigma} correlated_gaussian_known_covariance {Correlated Gaussian errors; known full covariance} correlated_gaussian_estimated_scale {Correlated Gaussian errors; full covariance with estimated scale}}
    set fields [dict create noise [dict create type choice label {Measurement error assumption} values [dict values $labels]] confidence [dict create type number label {Confidence level (between 0 and 1)} required 1]]
    dict set fields measurementKind [dict create type choice label {Training measurement role} values [dict values [_measurementLabels]]]
    dict set fields measurementVariable [dict create type choice label {Training measurement column} values [dict keys [_measurementChoices $w]]]
    dict set fields measurementIndependentVariable [dict create type choice label {Independent-axis sigma column (both-axis ODR only)} values [dict keys [_measurementChoices $w]]]
    dict set fields measurementMissing [dict create type choice label {Missing training measurements} values {{Report an error} {Omit explicitly and record rows}}]
    dict set fields influence [dict create type boolean label {Exact linear influence diagnostics (linear/polynomial response fits)}]
    dict set fields band [dict create type choice label {Response interval} values [dict values [_predictionLabels]]]
    dict set fields sigma [dict create type string label {Future absolute sigma in response units (known-noise prediction only)}]
    dict set fields weights [dict create type string label {Future relative precision (relative-weight prediction only)}]
    set measurementLabel {No measurement column};dict for {label id} [_measurementChoices $w] {if {$id eq $state($w,measurementVariable)} {set measurementLabel $label;break}}
    set independentLabel {No measurement column};dict for {label id} [_measurementChoices $w] {if {$id eq $state($w,measurementIndependentVariable)} {set independentLabel $label;break}}
    ::GX::uiFieldFormCreate $w.statistics {Statistical assumptions and intervals} $fields \
        [dict create influence $state($w,influenceDiagnostics) noise [dict get $labels $state($w,noiseModel)] confidence $state($w,confidence) band [dict get [_predictionLabels] $state($w,predictionBand)] sigma $state($w,predictionSigma) weights $state($w,predictionWeights) measurementKind [dict get [_measurementLabels] $state($w,measurementKind)] measurementVariable $measurementLabel measurementIndependentVariable $independentLabel measurementMissing [dict get {error {Report an error} omit {Omit explicitly and record rows}} $state($w,measurementMissing)]] \
        [list ::GX::DatasetCurveFit::_statisticalApply $w $state($w,activeSource) $labels] $w
    ttk::label $w.statistics.note -text {Intervals are pointwise marginal intervals. Nonlinear intervals use a local approximation. Known-sigma intervals require absolute measurement weights; choosing an assumption does not supply those measurements.} -wraplength 540
    pack $w.statistics.note -fill x -padx 8 -pady 8
}
proc ::GX::DatasetCurveFit::_statisticalApply {w owner labels values} {
    variable state
    if {$owner ne $state($w,activeSource)} {error {Active source changed; reopen statistical settings}}
    set confidence [_finite [dict get $values confidence] {Confidence level}]
    if {$confidence<=0||$confidence>=1} {error {Confidence must be strictly between zero and one}}
    set chosen {};dict for {id label} $labels {if {$label eq [dict get $values noise]} {set chosen $id}}
    if {$chosen eq {}} {error {Choose a declared measurement error assumption}}
    dict for {id label} [_predictionLabels] {if {[dict get $values band] eq $label} {dict set values band $id;break}}
    if {[dict get $values band] ni {none mean_confidence new_observation}} {error {Choose a registered response interval}}
    foreach field {sigma weights} {
        set value [string trim [dict get $values $field]]
        if {$value ne {}&&[_finite $value {Future measurement scale or precision}]<=0} {error {Future measurement scale and precision must be positive}}
        if {$value ne {}&&[dict get $values band] ne "new_observation"} {error {Future measurement noise applies only to a prediction interval}}
        dict set values $field $value
    }
    if {[dict get $values sigma] ne {}&&[dict get $values weights] ne {}} {error {Choose absolute sigma or relative precision, according to the fitted noise model}}
    set measurement [dict create kind $state($w,measurementKind) variable_id $state($w,measurementVariable) independent_variable_id $state($w,measurementIndependentVariable) nonfinite $state($w,measurementMissing)]
    if {[dict exists $values measurementKind]} {
        set mode [dict get $values measurementKind]
        dict for {id label} [_measurementLabels] {if {$mode eq $label} {set mode $id;break}}
        set variable [dict get $values measurementVariable]
        if {[dict exists [_measurementChoices $w] $variable]} {set variable [dict get [_measurementChoices $w] $variable]}
        set missing [dict get $values measurementMissing]
        if {$missing eq "Report an error"} {set missing error};if {$missing eq "Omit explicitly and record rows"} {set missing omit}
        if {$mode eq "none"} {set variable {}}
        set measurement [dict create kind $mode variable_id $variable nonfinite $missing]
        set independent [::GX::datasetPublicationV2DictDefault $values measurementIndependentVariable {}]
        if {[dict exists [_measurementChoices $w] $independent]} {set independent [dict get [_measurementChoices $w] $independent]}
        if {$mode ne "sigma_xy"} {set independent {}}
        dict set measurement independent_variable_id $independent
    }
    _measurementCompanions $w $state($w,model) [dict create measurement $measurement orientation $state($w,orientation)]
    if {$state($w,covarianceSettings) ne {}&&[dict get $measurement kind] ne "none"} {error {Disable full covariance before selecting independent measurement weights}}
    if {[dict get $measurement kind] eq "sigma_xy"&&$chosen eq "independent_gaussian_estimated_variance"} {error {Both-axis sigma inference uses supplied absolute uncertainties; choose known Gaussian sigma or leave the noise distribution unspecified}}
    set influence [::GX::datasetPublicationV2DictDefault $values influence $state($w,influenceDiagnostics)]
    _influenceOption $state($w,model) [dict create influence_diagnostics $influence orientation $state($w,orientation) measurement $measurement]
    if {![::GX::scientificHistoryViewerPrepareEdit $w]} return
    set state($w,influenceDiagnostics) $influence
    set state($w,noiseModel) $chosen;set state($w,confidence) $confidence
    set state($w,predictionBand) [dict get $values band];set state($w,predictionSigma) [dict get $values sigma];set state($w,predictionWeights) [dict get $values weights]
    set state($w,measurementKind) [dict get $measurement kind];set state($w,measurementVariable) [dict get $measurement variable_id];set state($w,measurementMissing) [dict get $measurement nonfinite]
    set state($w,measurementIndependentVariable) [dict get $measurement independent_variable_id]
    if {[winfo exists $w.left.viewport.content.settings.parameters.initial]} {_uiModelFields $w}
    _invalidateSettings $w;_workspaceCapture $w;_saveState $w
    set state($w,status) {Statistical assumptions saved. Preview again to calculate eligible intervals.}
}
proc ::GX::DatasetCurveFit::_resultPresentation {w} {
    variable state
    if {![llength [info commands winfo]]||![winfo exists $w.right.report.parameters]} return
    set result $state($w,preview)
    set state($w,qualityReport) {}
    if {$result eq {}} {set state($w,report) {};_technicalDetailsRender $w;return}
    if {[dict exists $result statistical_results training]} {
        set state($w,report) [formula $result]
        set state($w,qualityReport) [::GX::StatisticsV1::report [dict get $result statistical_results training] {n rmse r_squared dof}]
        if {[dict exists $result statistical_results training provenance smoothing]} {
            set summary [::GX::StatisticsV1::report [dict get $result statistical_results training] {n edf smoothing_lambda smoothing_gcv_score}]
            set state($w,qualityReport) "[join [lrange [split $summary \n] 0 3] \n]\nInterpretation and search: Results → Smoothing diagnostics."
        }
        if {[dict exists $result statistical_results training context response_transform]} {
            set plan [::GX::StatisticsV1::logResponsePlan [dict get $result statistical_results training]]
            set state($w,qualityReport) "[join [lrange [split $state($w,qualityReport) \n] 0 3] \n]\n[lindex [dict get $plan assumptions] 0]\nAssumptions: Results → Log-response interpretation."
            if {[dict exists $result statistical_results training provenance smoothing]} {append state($w,qualityReport) "\nInterpretation and search: Results → Smoothing diagnostics."}
        }
        if {[dict exists $result statistical_results profile]} {append state($w,qualityReport) "\nProfile likelihood: [dict get $result statistical_results profile status]. Results → Profile likelihood shows the actual threshold, search endpoints and constrained trials."}
        if {[dict exists $result statistical_results bootstrap]} {append state($w,qualityReport) "\nParameter bootstrap: [dict get $result statistical_results bootstrap status]. Results → Parameter bootstrap contains the recorded refits and qualifications."}
        if {[dict exists $result statistical_results influence]} {append state($w,qualityReport) "\nInfluence and exact training-row diagnostics: Results → Linear influence."}
        append state($w,qualityReport) "\n[::GX::StatisticsV1::solverReport [dict get $result statistical_results training]]"
        if {[dict exists $result prediction_plan]} {
            set plan [dict get $result prediction_plan]
            if {[dict exists $result statistical_results prediction]} {
                set meaning [dict get $result statistical_results prediction]
                append state($w,qualityReport) "\n[dict get [_predictionLabels] [dict get $plan kind]] (confidence [dict get $plan parameter_plan confidence]).\nAvailable rows: [dict get $meaning quantities prediction_available_count value] of [dict get $meaning quantities prediction_query_count value]. Assumptions: Results → Response interval details."
            } else {append state($w,qualityReport) "\nResponse interval: [dict get $plan status] — [dict get $plan reason]"}
        }
    } else {set state($w,report) "[formula $result]\nHistorical fit: statistical interpretation was not recorded."}
    set outputDomain [_outputDomainInfo $result]
    if {$outputDomain ne {}} {
        append state($w,qualityReport) "\nOutput extrapolation: [dict get $outputDomain outside_count] of [dict get $outputDomain row_count] points outside [dict get $outputDomain reference_domain] ([dict get $outputDomain reference_basis]). Orange dashed segments touch extrapolated points. This envelope does not identify excluded interior observations."
    } else {append state($w,qualityReport) "\nOutput extrapolation classification was not recorded for this historical fit."}
    set preprocessing [_preprocessingInfo $result]
    if {[dict get $preprocessing status] eq "value"} {
        append state($w,qualityReport) "\nInput rows: original [dict get $preprocessing original_count] ([dict get $preprocessing original_count_status]), filtered [dict get $preprocessing filtered_count], finite [dict get $preprocessing finite_count], selected [dict get $preprocessing selected_count], fitted [dict get $preprocessing fit_count]. Results → Scientific report includes exact row-stage and exclusion receipts."
    }
    _technicalDetailsRender $w
}
proc ::GX::DatasetCurveFit::_predictionDetails {w} {
    variable state
    if {$state($w,preview) eq {}||![dict exists $state($w,preview) prediction_plan]} {error {Preview a requested response interval first}}
    set result $state($w,preview);set plan [dict get $result prediction_plan]
    if {[dict exists $result statistical_results prediction]} {
        set content "[::GX::StatisticsV1::report [dict get $result statistical_results prediction] {prediction_query_count prediction_available_count prediction_unavailable_count prediction_critical_value prediction_critical_reused prediction_covariance_roundoff_count}]\n\n[dict get $result prediction_display_note]"
    } else {set content "[dict get [_predictionLabels] [dict get $plan kind]]\n[dict get $plan status] — [dict get $plan reason]"}
    set dialog $w.predictionDetails
    if {[winfo exists $dialog]} {destroy $dialog}
    toplevel $dialog;wm title $dialog {Response interval details};wm transient $dialog $w
    text $dialog.text -wrap word -width 86 -height 24 -yscrollcommand [list $dialog.scroll set]
    ttk::scrollbar $dialog.scroll -command [list $dialog.text yview]
    grid $dialog.text -row 0 -column 0 -sticky nsew;grid $dialog.scroll -row 0 -column 1 -sticky ns
    grid rowconfigure $dialog 0 -weight 1;grid columnconfigure $dialog 0 -weight 1
    $dialog.text insert end $content;$dialog.text configure -state disabled
    bind $dialog <Escape> [list destroy $dialog];focus $dialog.text
}
proc ::GX::DatasetCurveFit::_reportWidth {w width} {
    set width [expr {max(80,$width-[winfo reqwidth $w.right.report.scroll]-16)}]
    $w.right.report.result configure -wraplength $width
    $w.right.report.parameterDetail configure -wraplength $width
    $w.right.report.quality configure -wraplength $width
    _reportViewportFit $w [winfo height $w.right]
}
proc ::GX::DatasetCurveFit::_parameterTableChanged {w args} {
    variable state
    if {![winfo exists $w.right.report.parameters]} return
    set tree $w.right.report.parameters
    $tree delete [$tree children {}];set state($w,parameterDetail) {}
    if {$state($w,report) eq {}||$state($w,preview) eq {}||![dict exists $state($w,preview) statistical_results training]} {set state($w,qualityReport) {};_technicalDetailsRender $w;return}
    set rows [::GX::StatisticsV1::parameterRows [dict get $state($w,preview) statistical_results training]]
    set state($w,parameterRows) $rows;set i 0
    foreach row $rows {
        set value [dict get $row value_status];if {[dict exists $row value]} {set value [format %.9g [dict get $row value]]}
        set se [dict get $row se_status];if {[dict exists $row standard_error]} {set se [format %.9g [dict get $row standard_error]]}
        set interval [dict get $row ci_status]
        if {[dict exists $row lower]} {set interval "[format %.9g [dict get $row lower]] … [format %.9g [dict get $row upper]]"}
        $tree insert {} end -id p[incr i] -values [list [dict get $row id] $value [dict get $row unit] $se $interval [dict get $row role]]
    }
    if {$i} {$tree selection set p1;_parameterDetail $w}
}
proc ::GX::DatasetCurveFit::_parameterDetail {w} {
    variable state
    set selected [$w.right.report.parameters selection]
    if {$selected eq {}} return
    set row [lindex $state($w,parameterRows) [expr {[string range [lindex $selected 0] 1 end]-1}]]
    set state($w,parameterDetail) "[dict get $row id] — SE: [dict get $row se_status] [dict get $row se_reason]; CI: [dict get $row ci_status] [dict get $row ci_reason]"
    if {[dict exists $row confidence]} {append state($w,parameterDetail) " (confidence [dict get $row confidence])"}
}
proc ::GX::DatasetCurveFit::_correlationWindow {w} {
    variable state
    if {$state($w,preview) eq {}||![dict exists $state($w,preview) statistical_results training]} {error {Preview a current fit first}}
    set text [::GX::StatisticsV1::parameterCorrelationReport [dict get $state($w,preview) statistical_results training]]
    set dialog $w.parameterCorrelation
    if {[winfo exists $dialog]} {destroy $dialog}
    toplevel $dialog;wm title $dialog {Parameter correlation};wm transient $dialog $w
    text $dialog.text -wrap none -width 84 -height 15 -yscrollcommand [list $dialog.y set] -xscrollcommand [list $dialog.x set]
    ttk::scrollbar $dialog.y -command [list $dialog.text yview]
    ttk::scrollbar $dialog.x -orient horizontal -command [list $dialog.text xview]
    grid $dialog.text -row 0 -column 0 -sticky nsew;grid $dialog.y -row 0 -column 1 -sticky ns;grid $dialog.x -row 1 -column 0 -sticky ew
    grid rowconfigure $dialog 0 -weight 1;grid columnconfigure $dialog 0 -weight 1
    $dialog.text insert end $text;$dialog.text configure -state disabled
    bind $dialog <Escape> [list destroy $dialog];focus $dialog.text
}
proc ::GX::DatasetCurveFit::_solverDetails {w} {
    variable state
    if {$state($w,preview) eq {}||![dict exists $state($w,preview) statistical_results training]} {error {Preview a current fit first}}
    set content [_technicalResultText $state($w,preview)]
    set dialog $w.solverDetails
    if {[winfo exists $dialog]} {destroy $dialog}
    toplevel $dialog;wm title $dialog {Solver diagnostics};wm transient $dialog $w
    text $dialog.text -wrap word -width 90 -height 24 -yscrollcommand [list $dialog.scroll set]
    ttk::scrollbar $dialog.scroll -command [list $dialog.text yview]
    grid $dialog.text -row 0 -column 0 -sticky nsew;grid $dialog.scroll -row 0 -column 1 -sticky ns
    grid rowconfigure $dialog 0 -weight 1;grid columnconfigure $dialog 0 -weight 1
    $dialog.text insert end $content;$dialog.text configure -state disabled
    bind $dialog <Escape> [list destroy $dialog];focus $dialog.text
}
