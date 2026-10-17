# Model-independent presentation of retained facts. CORE owns all statistical
# interpretation; this report never evaluates a model or recomputes a statistic.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::DatasetCurveFit::resultReport {reference} {
    set record [_recipeResultRecord $reference]
    return [_scientificReport [dict get $record provenance] [dict get $record label] $reference]
}
proc ::GX::DatasetCurveFit::_scientificReport {p label {reference {}}} {
    _validateStatisticsMetadata $p
    set lines [list {GX-TXT scientific fit report} "Name: $label" "Model: [dict get $p model]" "Equation: [::GX::datasetPublicationV2DictDefault $p physical_formula [formula $p]]" "Retained reference: $reference" "Producing framework: [::GX::datasetPublicationV2DictDefault $p producer_framework_version unavailable_not_recorded]" {Interpretation API: STATISTICAL_RESULT_SEMANTICS_API_v1; numerical API: NUMERIC_API_v1; Fitter API: DATASET_CURVE_FIT_API_v1} {} {Parameters and uncertainty} [parameterReport $p]]
    if {[dict exists $p statistical_results]} {
        dict for {role meaning} [dict get $p statistical_results] {
            lappend lines {} "Scientific interpretation: $role"
            # Public report dispatch also supports specialized bootstrap and
            # influence receipts. Show the captured applicable ordinary quantities.
            set quantities {}
            if {[dict exists $meaning quantities]} {
                # Keep standard fit diagnostics visible even when inapplicable.
                # Other scientific quantities are shown only when CORE gives
                # them an applicable status; unrelated module catalogs stay out.
                set standard {n p rank dof edf sse rmse r_squared adjusted_r_squared reduced_chi_squared standard_errors covariance condition_number}
                dict for {name quantity} [dict get $meaning quantities] {
                    if {$name in $standard||[dict get $quantity status] ne "not_applicable"} {lappend quantities $name}
                }
            }
            lappend lines [::GX::StatisticsV1::report $meaning $quantities]
            if {$role eq "training"} {
                lappend lines [::GX::StatisticsV1::solverReport $meaning 1]
                foreach field {model context} {if {[dict exists $meaning $field]} {lappend lines "$field: [dict get $meaning $field]"}}
            }
        }
    } else {lappend lines {Statistical interpretation: unavailable; no captured versioned meaning.}}
    if {[dict exists $p measurement_binding digitization]} {
        lappend lines {} {Digitization uncertainty} [::GX::StatisticsV1::digitizationReport [dict get $p measurement_binding digitization meaning]]
        lappend lines [dict get $p measurement_binding digitization fit_plan reason]
    }
    if {[dict exists $p covariance_binding digitization]} {
        set digitization [dict get $p covariance_binding digitization]
        set meaning [::GX::CurveDigitizerCompanion::validateUncertaintyBinding [dict get $digitization source]]
        lappend lines {} {Digitization uncertainty} [::GX::StatisticsV1::digitizationReport $meaning] [dict get $digitization fit_plan reason]
    }
    lappend lines {} {Source, coordinates and solver inputs}
    foreach field {source_kind source_dataset_id source_sample_id source_curve_id source_axes source_sha256 source_descriptor filters orientation translation polar_frame options domain export_domain training_domain measurement_binding measurement_selection region_selection observation_binding recipe_producers registered_execution} {
        if {[dict exists $p $field]} {lappend lines "$field: [dict get $p $field]"}
    }
    lappend lines {} {Retained model state and exact provenance}
    set retained 0
    foreach field {numeric_model_state numeric_model_state_sha256 registered_model_state registered_model_state_sha256 model_state_json model_state_resource registered_source_resource} {
        if {[dict exists $p $field]} {lappend lines "$field: [dict get $p $field]";set retained 1}
    }
    if {!$retained} {lappend lines {Reconstructible model state: unavailable_not_recorded.}}
    lappend lines {Owned resources retain their original SHA256 identity. The CSV bundle includes external model JSON when present; its metadata sidecar preserves inline model state and resource identities.}
    set receipt [_preprocessingInfo $p]
    lappend lines {} {Preprocessing and exact row identities} "Status: [dict get $receipt status]"
    if {[dict get $receipt status] eq "value"} {
        foreach field {original_count original_count_status filtered_count finite_count selected_count nonfinite_count selection_excluded_count region_count fit_count model_input_count finite_policy duplicate_policy order_policy row_identity_kind model_policy coordinate_transform source_request selection_descriptor source} {
            if {[dict exists $receipt $field]} {lappend lines "$field: [dict get $receipt $field]"}
        }
        lappend lines {Row stages preserve original identities in their actual execution order. No row is renumbered or implicitly averaged.}
        dict for {stage field} [dict get $receipt stages] {
            if {[string match *_resource $field]} {
                set resource [dict get $p $field]
                lappend lines "Stage $stage: $field; rows [dict get $resource metadata row_count]; SHA256 [dict get $resource sha256]"
            } else {lappend lines "Stage $stage: [dict get $p $field]"}
        }
        lappend lines {Excluded IDs are exact set expressions: exact_stage names its saved rows; stage_difference subtracts one saved stage from another; range_difference subtracts a stage from the half-open original ordinal range. Order changes are retained separately in the model stage.}
        dict for {reason spec} [dict get $receipt excluded_ids] {lappend lines "Excluded $reason: $spec"}
        lappend lines {CSV export includes every stage in .preprocessing.csv with exact integer IDs. Public result_preprocessing_rows pages each stage without a bulk control-message list.}
    } else {lappend lines "Reason: [dict get $receipt reason]"}
    lappend lines {} {Output domain} [_outputDomainInfo $p]
    return [join $lines \n]
}
proc ::GX::DatasetCurveFit::_exportScientificReport {record out context} {
    fconfigure $out -encoding utf-8 -translation lf
    puts $out [_scientificReport [dict get $record provenance] [dict get $record label]]
    if {[dict exists $context completed preprocessing]} {puts $out "\nExact row audit: [file tail [dict get $context completed preprocessing destination]]; SHA256 [dict get $context completed preprocessing sha256]"}
}
proc ::GX::DatasetCurveFit::_exportPreprocessingRows {p out context} {
    set receipt [_preprocessingInfo $p]
    fconfigure $out -encoding utf-8 -translation lf
    puts $out stage,row_position,source_row
    dict for {stage field} [dict get $receipt stages] {
        set position 0
        if {[string match *_resource $field]} {
            set reader [::GX::interactiveDocumentResourceOpenReader [dict get $p $field]]
            try {
                while {1} {
                    set page [::GX::interactiveDocumentResourceNext $reader 32768]
                    binary scan [dict get $page bytes] wu* rows
                    foreach row $rows {puts $out "$stage,$position,$row";incr position}
                    if {[dict get $page eof]} break
                }
            } finally {::GX::interactiveDocumentResourceCloseReader $reader}
        } else {foreach row [dict get $p $field] {puts $out "$stage,$position,$row";incr position}}
    }
}
proc ::GX::DatasetCurveFit::_scientificReportDetails {w} {
    variable state
    set p $state($w,preview)
    if {$p eq {}} {error {Preview a fit before opening its scientific report}}
    set p [dict merge $p [_sourceProvenance $w]]
    set content [_scientificReport $p {Current preview}]
    set dialog $w.scientificReport;catch {destroy $dialog}
    toplevel $dialog;wm title $dialog {Scientific fit report};wm transient $dialog $w
    text $dialog.text -wrap word -width 100 -height 30 -yscrollcommand [list $dialog.scroll set]
    ttk::scrollbar $dialog.scroll -command [list $dialog.text yview]
    grid $dialog.text -row 0 -column 0 -sticky nsew;grid $dialog.scroll -row 0 -column 1 -sticky ns
    grid rowconfigure $dialog 0 -weight 1;grid columnconfigure $dialog 0 -weight 1
    $dialog.text insert end $content;$dialog.text configure -state disabled
    bind $dialog <Escape> [list destroy $dialog];focus $dialog.text
}
