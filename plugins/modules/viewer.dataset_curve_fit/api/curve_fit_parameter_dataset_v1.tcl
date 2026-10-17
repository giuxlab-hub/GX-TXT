# Project validated CORE parameter rows through the canonical Dataset writer.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::_parameterDatasetPlan {references} {
    if {[llength $references]<1||[llength $references]>64} {error {Choose one to 64 independently accepted fits}}
    set ids {};set signature {};set definitions {};set columns {};set meanings {};set bindings {};set parameterMap {};set rowIndex 0;set sourceDatasets {}
    foreach field {result_id document_id fit_curve_id source_curve_id source_kind source_identity accepted_name model} {
        dict set definitions $field [dict create dtype string unit 1 display_label [string map {_ { }} $field]]
        dict set columns $field {}
    }
    foreach reference $references {
        set record [_recipeResultRecord $reference];set p [dict get $record provenance]
        set resultId "[dict get $reference document_id]/[dict get $reference fit_curve_id]"
        if {$resultId in $ids} {error {An accepted fit may appear only once in a parameter Dataset}};lappend ids $resultId
        set meaning [dict get $p statistical_results training]
        set parameters [::GX::StatisticsV1::parameterRows $meaning]
        if {[llength $parameters]<1||[llength $parameters]>128} {error {A parameter Dataset requires one to 128 scalar parameters per fit; retained curve knots are available through model export}}
        set current [list [dict get $record model] [dict get $p orientation] [dict get $meaning model id] [::GX::datasetPublicationV2DictDefault [dict get $meaning context] coefficient_space original_physical] [lmap parameter $parameters {list [dict get $parameter id] [dict get $parameter unit]}]]
        if {[dict get $record model] in {components regions formula implicit}} {
            set modelIdentity {};set model [dict get $p numeric_model_state]
            foreach field {kind expression parameter_ids predictor_ids parameter_units expression_grammar compiler_version source_sha256 binding_sha256 schema_version input_contract} {dict set modelIdentity $field [::GX::datasetPublicationV2DictDefault $model $field {}]}
            if {[dict get $record model] in {formula implicit}} {
                foreach field {predictor_units response_unit} {dict set modelIdentity $field [dict get $model formula_declaration recipe $field]}
            }
            if {[dict get $record model] eq "rational"} {dict set modelIdentity rational_recipe [dict get $p options rational_recipe];dict set modelIdentity rational_state_sha256 [dict get $p rational_state_sha256]}
            if {[dict get $record model] eq "implicit"} {dict set modelIdentity implicit_recipe [dict get $p options implicit_recipe];dict set modelIdentity implicit_branch [dict get $p options implicit_branch]}
            lappend current $modelIdentity
        }
        if {[dict get $record model] eq "complex_response"} {lappend current [dict get $p complex_model_state declaration_sha256] [dict get $p options complex_recipe]}
        if {[dict get $record model] eq "registered"} {lappend current [dict get $p registered_model_state source_sha256] [dict get $p registered_model_state binding_sha256]}
        if {$rowIndex&&$current ne $signature} {error {Selected fits have different model, parameter order, units or coefficient-coordinate contracts; publish them separately}}
        set signature $current;incr rowIndex
        dict set meanings fit_$rowIndex $meaning
        set binding [dict create row [expr {$rowIndex-1}] reference $reference accepted_name [dict get $record label] parameter_rows $parameters]
        if {[dict get $record model] eq "rational"} {dict set binding rational_recipe [dict get $p options rational_recipe];dict set binding rational_state_sha256 [dict get $p rational_state_sha256]}
        if {[dict get $record model] eq "implicit"} {dict set binding implicit_recipe [dict get $p options implicit_recipe];dict set binding implicit_branch [dict get $p options implicit_branch]}
        if {[dict get $record model] eq "complex_response"} {dict set binding complex_recipe [dict get $p options complex_recipe];dict set binding complex_data [dict get $p options complex_data];dict set binding complex_binding [dict get $p complex_binding]}
        foreach field {model physical_formula orientation translation numeric_model_state numeric_model_state_sha256 registered_model_state registered_model_state_sha256 source_kind source_dataset_id source_sample_id source_sha256 source_filters source_scientific_fingerprints source_axes selection_descriptor observation_binding} {
            if {[dict exists $p $field]} {dict set binding $field [dict get $p $field]}
        }
        lappend bindings $binding
        set sourceKind [dict get $p source_kind]
        set sourceIdentity [dict get $p [expr {$sourceKind in {sample builtin_sample}?"source_sample_id":"source_dataset_id"}]]
        if {$sourceKind eq "dataset"} {lappend sourceDatasets $sourceIdentity}
        foreach field {result_id document_id fit_curve_id source_curve_id source_kind source_identity accepted_name model} value [list $resultId [dict get $reference document_id] [dict get $record fit_curve_id] [dict get $record source_curve_id] $sourceKind $sourceIdentity [dict get $record label] [dict get $record model]] {dict lappend columns $field $value}
        set index 0
        foreach parameter $parameters {
            set prefix [format p%03d [incr index]];set parameterId [dict get $parameter id];set unit [dict get $parameter unit]
            if {$rowIndex==1} {dict set parameterMap $prefix [dict create parameter_id $parameterId unit $unit order [expr {$index-1}]]}
            foreach {suffix field dtype quantityUnit title} {
                estimate value float64 parameter Estimate
                standard_error standard_error float64 parameter {Standard error}
                ci_lower lower float64 parameter {Confidence interval lower bound}
                ci_upper upper float64 parameter {Confidence interval upper bound}
                confidence confidence float64 1 {Confidence level}
                value_status value_status string 1 {Estimate status}
                se_status se_status string 1 {Standard-error status}
                ci_status ci_status string 1 {Confidence-interval status}
                role role string 1 {Parameter role}
            } {
                set id ${prefix}_$suffix
                if {$rowIndex==1} {
                    dict set definitions $id [dict create dtype $dtype unit [expr {$quantityUnit eq "parameter"?$unit:"1"}] display_label "$parameterId — $title"]
                    dict set columns $id {}
                    dict set parameterMap $prefix fields $field $id
                }
                set value {};if {$dtype eq "float64"} {set value NaN}
                if {[dict exists $parameter $field]} {set value [dict get $parameter $field]}
                dict lappend columns $id $value
            }
        }
    }
    set metadata [::GX::StatisticsV1::publicationMetadata $meanings]
    dict set metadata curve_fit.parameter_dataset [dict create schema gxtxt.fitter_parameter_dataset.v1 version 1 row_semantics independent_accepted_fit coefficient_space [lindex $signature 3] parameter_columns $parameterMap rows $bindings uncertainty_authority STATISTICAL_RESULT_SEMANTICS_API_v1 source_operation parameterRows]
    return [dict create row_count $rowIndex definitions $definitions columns $columns metadata $metadata source_dataset_ids [lsort -unique $sourceDatasets]]
}
proc ::GX::DatasetCurveFit::resultParametersPublish {references datasetId} {
    variable version
    ::GX::datasetPublicationV2ValidateId dataset $datasetId
    set data [_parameterDatasetPlan $references]
    set definition [dict create dataset_id $datasetId contract table.generic storage hdf5 replace_owned 0 display_name $datasetId source_dataset_ids [dict get $data source_dataset_ids] structured_metadata [dict get $data metadata] provenance [dict create producer viewer.dataset_curve_fit producer_version $version operation accepted_parameter_dataset]]
    set plan [::GX::datasetPublicationV2Prepare $::GX::currentSession viewer.dataset_curve_fit $definition]
    set writer {}
    try {
        set writer [::GX::datasetPublicationV2OpenWriter $plan]
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        dict for {id spec} [dict get $data definitions] {::GX::datasetPublicationV2DeclareVariable $writer $id [dict merge $spec {rank 1 dimension_ids row coordinate_role data axis_kind explicit}]}
        ::GX::datasetPublicationV2Append $writer row [dict get $data columns]
        set published [::GX::datasetPublicationV2Finalize $writer];set writer {}
        return $published
    } finally {if {$writer ne {}} {::GX::datasetPublicationV2Abort $writer}}
}
proc ::GX::DatasetCurveFit::_parameterDatasetDialog {w} {
    variable state
    _assertSession $w
    if {![llength $state($w,records)]} {error {Accept a fit before publishing parameter results}}
    if {[llength $state($w,records)]>64} {error {This chooser supports up to 64 accepted fits; the public API can select a bounded subset from a larger Workspace}}
    set fields [dict create dataset_id [dict create type string label {New Dataset ID} required 1]]
    set values [dict create dataset_id fit_parameters];set references {};set index 0
    set chosen [$w.left.viewport.content.accepted.list curselection]
    if {![llength $chosen]} {set chosen [list [expr {[llength $state($w,records)]-1}]]}
    foreach record $state($w,records) {
        set field fit[incr index]
        dict set fields $field [dict create type boolean label "[dict get $record fit_curve_id] · [dict get $record label] · [dict get $record source_curve_id]"]
        dict set values $field [expr {$index-1 in $chosen}]
        dict set references $field [resultReference $state($w,documentId) [dict get $record fit_curve_id]]
    }
    set d $w.parameterDataset
    ::GX::uiFieldFormCreate $d {Publish accepted parameters} $fields $values [list ::GX::DatasetCurveFit::_parameterDatasetApply $w $references] $w
    $d.actions.apply configure -text {Publish parameter Dataset}
}
proc ::GX::DatasetCurveFit::_parameterDatasetApply {w references values} {
    variable state
    _assertSession $w
    set selected {};dict for {field reference} $references {if {[dict get $values $field]} {lappend selected $reference}}
    set result [resultParametersPublish $selected [string trim [dict get $values dataset_id]]]
    set state($w,status) "Published [llength $selected] accepted parameter rows as Dataset [dict get $result dataset_id]."
    destroy $w.parameterDataset
    return $result
}
