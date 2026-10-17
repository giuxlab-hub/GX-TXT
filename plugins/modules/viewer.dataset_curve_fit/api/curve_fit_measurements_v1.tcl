# Dataset measurement adaptation; CORE owns units/rows and Numeric owns fitting.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_digitizationMeasurement {key model options} {
    variable state
    set metadata [::GX::datasetMetadataRead $::GX::currentSession $state($key,dataset)]
    if {![dict exists $metadata curve_digitizer.uncertainty_binding]} {return {}}
    set spec [_measurementOptions $options]
    set published [dict get $metadata curve_digitizer.uncertainty_binding]
    set owned [list [dict get $published sigma_x_variable_id] [dict get $published sigma_y_variable_id]]
    if {[dict get $spec variable_id] ni $owned&&[dict get $spec independent_variable_id] ni $owned} {return {}}
    ::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_COMPANION_API_v1
    set capture [::GX::CurveDigitizerCompanion::publicationUncertainty $state($key,dataset)]
    if {[dict get $spec kind] ni {sigma sigma_xy}} {error {Digitizer standard uncertainties cannot be relabelled as relative precision}}
    set orientation [_fitOrientation $model $options]
    set plan [::GX::StatisticsV1::digitizationFitPlan [dict get $capture meaning] [dict get $spec kind] $orientation]
    if {[dict get $plan status] ne "value"} {error [dict get $plan reason]}
    foreach axis {x y} {if {$state($key,$axis) ne [dict get $published ${axis}_variable_id]} {error {Digitization uncertainty belongs to the original physical X/Y Variables}}}
    set response [dict get $plan response_axis];set predictor [dict get $plan predictor_axis]
    if {[dict get $spec variable_id] ne [dict get $published sigma_${response}_variable_id]||([dict get $spec kind] eq "sigma_xy"&&[dict get $spec independent_variable_id] ne [dict get $published sigma_${predictor}_variable_id])} {error {Bind each digitizer sigma to its declared physical coordinate axis}}
    if {$state($key,sourceTransformManifest) ne {}&&[dict get $state($key,sourceTransformManifest) operation] ne "reverse_sequence"} {error {Transform the uncertainty model explicitly before using it with transformed coordinates}}
    dict set capture fit_plan $plan
    return $capture
}
proc ::GX::DatasetCurveFit::_measurementOptions {options} {
    set spec [::GX::datasetPublicationV2DictDefault $options measurement {}]
    foreach key [dict keys $spec] {if {$key ni {kind variable_id independent_variable_id nonfinite}} {error "Unknown measurement binding field '$key'"}}
    set spec [dict merge {kind none variable_id {} independent_variable_id {} nonfinite error} $spec]
    if {[dict get $spec kind] ni {none sigma sigma_xy relative_precision}||[dict get $spec nonfinite] ni {error omit}} {error {Choose no weighting, response sigma, both-axis sigma or relative precision, with explicit error/omit missing-value policy}}
    if {[dict get $spec kind] ne "none"&&[dict get $spec variable_id] eq {}} {error {Choose a Dataset measurement column}}
    if {[dict get $spec kind] eq "none"&&[dict get $spec variable_id] ne {}} {error {A measurement column requires an explicit scientific role}}
    if {([dict get $spec kind] eq "sigma_xy")!=([dict get $spec independent_variable_id] ne {})} {error {Both-axis uncertainty requires a separate independent-axis sigma column; other modes must leave it unbound}}
    return $spec
}
proc ::GX::DatasetCurveFit::_measurementCompanions {key model options} {
    variable state
    set spec [_measurementOptions $options]
    if {[dict get $spec kind] eq "none"} {return {}}
    if {$state($key,sourceKind) ne "dataset"||$state($key,sourceToken) eq {}} {error {Measurement bindings require a real Dataset source}}
    _digitizationMeasurement $key $model $options
    if {$model ni {linear polynomial exponential power_law gaussian components regions formula rational registered}} {error {This model does not expose a response-weighted fitting contract}}
    if {[dict get $spec variable_id] ni [dict get [variables $state($key,dataset)] numeric]} {error {Choose an enabled numeric measurement column}}
    set companions [dict create measurement [dict get $spec variable_id]]
    if {[dict get $spec kind] eq "sigma_xy"} {
        if {[_fitOrientation $model $options] ni {y_of_x x_of_y}} {error {Both-axis uncertainty fitting requires Y(X) or X(Y) coordinates}}
        if {[dict get $spec independent_variable_id] ni [dict get [variables $state($key,dataset)] numeric]} {error {Choose an enabled numeric independent-axis sigma column}}
        dict set companions independent_measurement [dict get $spec independent_variable_id]
    }
    return $companions
}
proc ::GX::DatasetCurveFit::_measurementBinding {key model options input} {
    variable state
    set spec [_measurementOptions $options]
    if {[dict get $spec kind] eq "none"} {return {}}
    if {![dict exists $input companion_columns measurement]} {error {Exact measurement rows are missing from the source transport}}
    set column [dict get $input companion_columns measurement]
    if {[dict get $column variable_id] ne [dict get $spec variable_id]} {error {Measurement identity changed during source capture}}
    set orientation [_fitOrientation $model $options]
    set axes [dict get [_sourceProvenance $key] source_axes]
    set axis [expr {$orientation eq "x_of_y"?"x":"y"}]
    set responseUnit [dict get $axes $axis unit]
    if {$orientation eq "r_of_theta"} {set responseUnit [_geometricMetricUnit $key]}
    set unit [dict get $column variable_descriptor unit]
    if {$unit eq {}} {error {Declare the measurement column unit before using it for weighting}}
    set target [expr {[dict get $spec kind] in {sigma sigma_xy}?$responseUnit:"1"}]
    if {$target eq {}} {error {Declare the fitted response unit before binding its standard uncertainty}}
    set plan [::GX::unitRegistryAffinePlan $unit $target]
    if {![dict get $plan affine]} {error {Measurement scales require a compatible affine unit conversion}}
    set factor [expr {abs([dict get $plan scale])}]
    if {$factor<=0} {error {Measurement conversion must have a nonzero scale}}
    if {[dict get $spec kind] eq "relative_precision"&&[dict get $plan offset]!=0} {error {Relative precision units cannot have an additive offset}}
    set binding [dict merge $spec [dict create schema gxtxt.fit_measurement_binding.v1 source_dataset_id $state($key,dataset) source_identities $state($key,sourceIdentities) variable_descriptor [dict get $column variable_descriptor] input_unit $unit value_unit $target response_unit $responseUnit orientation $orientation conversion_plan $plan scale_factor $factor offset_applied 0]]
    set digitization [_digitizationMeasurement $key $model $options]
    if {$digitization ne {}} {dict set binding digitization $digitization}
    if {[dict get $spec kind] eq "sigma_xy"} {
        if {$orientation ni {y_of_x x_of_y}} {error {Both-axis uncertainties require Y(X) or X(Y)}}
        set column [dict get $input companion_columns independent_measurement]
        set target [dict get $axes [expr {$axis eq "x"?"y":"x"}] unit]
        set unit [dict get $column variable_descriptor unit]
        if {$unit eq {}||$target eq {}||[dict get $column variable_id] ne [dict get $spec independent_variable_id]} {error {Independent-axis sigma needs an exact column identity and declared physical units}}
        set plan [::GX::unitRegistryAffinePlan $unit $target]
        if {![dict get $plan affine]||[dict get $plan scale]==0} {error {Independent-axis sigma requires a compatible nonzero affine unit scale}}
        dict set binding independent_measurement [dict create variable_id [dict get $spec independent_variable_id] variable_descriptor [dict get $column variable_descriptor] input_unit $unit value_unit $target conversion_plan $plan scale_factor [expr {abs([dict get $plan scale])}] offset_applied 0]
    }
    return $binding
}
proc ::GX::DatasetCurveFit::_validateMeasurementMetadata {result} {
    if {![dict exists $result measurement_binding]} {
        foreach key {measurement_selection measurement_resource measurement_rows_resource training_rows_resource orthogonal_resource} {if {[dict exists $result $key]} {error {Owned measurement data lack their captured binding}}}
        return
    }
    set binding [dict get $result measurement_binding];set selection [dict get $result measurement_selection]
    if {[dict get $binding schema] ne "gxtxt.fit_measurement_binding.v1"||[dict get $binding kind] ni {sigma sigma_xy relative_precision}||[dict get $binding kind] ne [dict get $selection kind]||[dict get $binding nonfinite] ne [dict get $selection nonfinite_policy]||[dict get $binding offset_applied]!=0} {error {Measurement meaning changed after fitting}}
    set odr [expr {[dict get $binding kind] eq "sigma_xy"}]
    set spec [_measurementOptions [dict get $result options]]
    if {[dict exists $binding digitization]} {
        ::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_COMPANION_API_v1
        set captured [dict get $binding digitization]
        set meaning [::GX::CurveDigitizerCompanion::validateUncertaintyBinding [dict get $captured binding]]
        set plan [::GX::StatisticsV1::digitizationFitPlan $meaning [dict get $spec kind] [dict get $binding orientation]]
        if {$meaning ne [dict get $captured meaning]||$plan ne [dict get $captured fit_plan]||[dict get $plan status] ne "value"||[dict get $captured source_identity] ni [dict get $binding source_identities]} {error {Retained fit lost its exact digitization uncertainty binding}}
    }
    foreach field {kind variable_id nonfinite} {if {[dict get $spec $field] ne [dict get $binding $field]} {error {Measurement settings differ from the fitted binding}}}
    set scale [_finite [dict get $binding scale_factor] {Captured measurement scale}];set conversion [dict get $binding conversion_plan]
    if {$scale<=0||$scale!=[dict get $selection scale_factor]||![dict get $conversion affine]||abs([dict get $conversion scale])!=$scale||[dict get $binding input_unit] ne [dict get $binding variable_descriptor unit]||[dict get $binding variable_id] ne [dict get $binding variable_descriptor variable_id]||[dict get $conversion input_unit] ne [dict get $binding input_unit]||[dict get $conversion output_unit] ne [dict get $binding value_unit]} {error {Captured measurement unit transformation changed}}
    foreach field {input_count fit_count omitted_nonfinite_count zero_precision_count} {
        set value [dict get $selection $field]
        if {[catch {_finite $value {Measurement selection count}}]||$value<0||$value!=floor($value)} {error {Measurement selection counts must be nonnegative integers}}
    }
    set n [dict get $selection input_count];set fitted [dict get $selection fit_count]
    set semantics [expr {[dict get $binding kind] in {sigma sigma_xy}?"inverse_variance":"relative"}]
    set training [dict get $result statistical_results training]
    if {$fitted<2||$n!=$fitted+[dict get $selection omitted_nonfinite_count]+[dict get $selection zero_precision_count]||$fitted!=[dict get $training quantities n value]||[dict get $selection weight_semantics] ne $semantics||[dict get $training context weight_semantics] ne $semantics||([dict get $binding kind] in {sigma sigma_xy}&&[dict get $selection zero_precision_count]!=0)} {error {Measurement counts or weight semantics differ from the fitted result}}
    foreach role {training evaluation} {
        set provenance [dict get $result statistical_results $role provenance]
        if {[dict get $provenance measurement_binding] ne $binding||[dict get $provenance measurement_selection] ne $selection} {error {Measurement lineage differs from its CORE statistical source}}
    }
    set stride [expr {$odr?40:32}];set columns {original_measurement converted_measurement effective_weight used_for_fit}
    if {$odr} {
        set independent [dict get $binding independent_measurement];set conversion [dict get $independent conversion_plan]
        set scale [_finite [dict get $independent scale_factor] {Independent sigma scale}]
        if {[dict get $spec independent_variable_id] ne [dict get $binding independent_variable_id]||[dict get $spec independent_variable_id] ne [dict get $independent variable_id]||[dict get $independent variable_id] ne [dict get $independent variable_descriptor variable_id]||[dict get $independent input_unit] ne [dict get $independent variable_descriptor unit]||[dict get $conversion input_unit] ne [dict get $independent input_unit]||[dict get $conversion output_unit] ne [dict get $independent value_unit]||![dict get $conversion affine]||$scale<=0||abs([dict get $conversion scale])!=$scale||$scale!=[dict get $selection independent_scale_factor]||[dict get $independent offset_applied]!=0||[dict get $training context fit_geometry] ne "orthogonal_xy"} {error {Independent-axis uncertainty binding changed}}
        set columns {original_independent_sigma converted_independent_sigma original_response_sigma converted_response_sigma used_for_fit}
        set correction [::GX::interactiveDocumentResourceInfo [dict get $result orthogonal_resource]]
        if {[dict get $correction size_bytes]!=48*$fitted||[dict get $correction metadata row_count]!=$fitted||[dict get $correction metadata format] ne "float64_interleaved_le"||[dict get $correction metadata columns] ne {adjusted_independent adjusted_response independent_correction response_correction normalized_independent_correction normalized_response_correction}} {error {Owned XY corrections changed shape or scientific identities}}
    } elseif {[dict exists $result orthogonal_resource]} {error {An ordinary weighted fit cannot own an XY correction result}}
    foreach {field format count stride} [list measurement_resource float64_interleaved_le $n $stride measurement_rows_resource uint64_le $n 8 training_rows_resource uint64_le $fitted 8] {
        set resource [::GX::interactiveDocumentResourceInfo [dict get $result $field]]
        if {[dict get $resource metadata format] ne $format||[dict get $resource metadata row_count]!=$count||[dict get $resource size_bytes]!=$count*$stride} {error {Owned measurement resource shape changed}}
        if {$field eq "measurement_resource"&&[dict get $resource metadata columns] ne $columns} {error {Canonical measurement column identities changed}}
    }
}
proc ::GX::DatasetCurveFit::_measurementLabels {} {return {none {No measurement weighting} sigma {Response standard uncertainty (sigma)} sigma_xy {Both-axis standard uncertainties (ODR)} relative_precision {Relative measurement precision}}}
proc ::GX::DatasetCurveFit::_measurementChoices {w} {
    variable state
    set choices [dict create {No measurement column} {}]
    if {$state($w,sourceKind) eq "dataset"} {
        set schema [variables $state($w,dataset)]
        foreach id [dict get $schema numeric] {
            set label [dict get $schema labels $id]
            if {[dict exists $choices $label]} {append label " \[$id\]"}
            dict set choices $label $id
        }
    }
    return $choices
}
proc ::GX::DatasetCurveFit::_measurementDetails {w} {
    variable state
    set result $state($w,preview);_validateMeasurementMetadata $result
    set binding [dict get $result measurement_binding];set selected [dict get $result measurement_selection]
    set statistics [dict get $result statistical_results training]
    set text "[dict get [_measurementLabels] [dict get $binding kind]]\nColumn: [dict get $binding variable_id]\nUnits: [dict get $binding input_unit] → [dict get $binding value_unit] (scale only)\nMissing values: [dict get $binding nonfinite]\nFit rows: [dict get $selected fit_count] / [dict get $selected input_count]\nOmitted nonfinite: [dict get $selected omitted_nonfinite_count]; zero precision: [dict get $selected zero_precision_count]\n\n"
    if {[dict get $binding kind] eq "sigma_xy"} {
        set independent [dict get $binding independent_measurement]
        append text "Independent-axis sigma: [dict get $independent variable_id]\nUnits: [dict get $independent input_unit] → [dict get $independent value_unit] (scale only)\nSigned physical corrections and normalized XY distances are retained with original source rows. The source residual panel separately shows functional response deviations at observed coordinates.\n\n"
        append text [::GX::StatisticsV1::solverReport $statistics] "\n\n"
    }
    append text [::GX::StatisticsV1::report $statistics {n dof sse rmse r_squared reduced_chi_squared}]
    if {[dict exists $binding digitization]} {append text "\n\n" [::GX::StatisticsV1::digitizationReport [dict get $binding digitization meaning]] "\n" [dict get $binding digitization fit_plan reason]}
    set r2 [dict get $statistics quantities r_squared]
    if {[dict exists $r2 definition]} {append text "\n\n[dict get $r2 definition]"}
    set dialog $w.measurementDetails;catch {destroy $dialog};toplevel $dialog;wm title $dialog {Training measurement details};wm transient $dialog $w
    text $dialog.text -wrap word -width 80 -height 22 -yscrollcommand [list $dialog.scroll set]
    ttk::scrollbar $dialog.scroll -orient vertical -command [list $dialog.text yview]
    $dialog.text insert end $text;$dialog.text configure -state disabled
    ttk::button $dialog.close -text Close -command [list destroy $dialog];pack $dialog.close -side bottom -pady 6
    pack $dialog.scroll -side right -fill y;pack $dialog.text -side left -fill both -expand 1
}
